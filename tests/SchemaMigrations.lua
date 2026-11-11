-- Exercise raw SavedVariables migration through the real startup lifecycle.
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end
local function Same(actual, expected)
    if type(actual) ~= type(expected) then return false end
    if type(expected) ~= "table" then
        return actual == expected or (type(expected) == "number" and actual ~= actual and expected ~= expected)
    end
    for key, value in pairs(expected) do if not Same(actual[key], value) then return false end end
    for key in pairs(actual) do if expected[key] == nil then return false end end
    return true
end
local original = {
    SoftTargetInteract = "0", SoftTargetInteractRange = "10", SoftTargetInteractArc = "0",
    SoftTargetInteractOnlyInRange = "1", SoftTargetIconInteract = "0", SoftTargetIconGameObject = "0",
    SoftTargetLowPriorityIcons = "0", SoftTargetNameplateInteract = "1",
}
local applied = {
    SoftTargetInteract = "3", SoftTargetInteractRange = "15", SoftTargetInteractArc = "2",
    SoftTargetInteractOnlyInRange = "0", SoftTargetIconInteract = "1", SoftTargetIconGameObject = "1",
    SoftTargetLowPriorityIcons = "1", SoftTargetNameplateInteract = "0",
}
local function Legacy()
    local restore = {}
    for name, value in pairs(applied) do restore[name] = {before = original[name], applied = value} end
    return {version = 1, cvarVersion = 0, gatheringSparkles = {enabled = true, restore = restore},
        anchorGap = {enabled = false, pixels = 7, top = 3}, keep = {nested = "preserved"}}
end
local function New(account, character, current, options)
    options = options or {}
    local ns, frames, timers = {}, {}, {}
    local env = setmetatable({}, {__index = _G})
    env._G, env.CalmUITweaksDB, env.CalmUITweaksCharDB = env, account, character
    local s = {ns = ns, env = env, cv = current or Copy(applied), frames = frames,
        writes = {}, reads = 0, messages = {}, errors = {}, combat = options.combat,
        loggedIn = options.loggedIn, reject = options.reject, throw = options.throw, silent = options.silent,
        readThrow = options.readThrow, readbackMissing = options.readbackMissing, changed = {},
        feature = {initialized = 0, login = 0, applied = 0, addons = 0}}
    env.print = function(message) s.messages[#s.messages + 1] = message end
    env.geterrorhandler = function() return function(err) s.errors[#s.errors + 1] = tostring(err) end end
    env.InCombatLockdown = function() return s.combat == true end
    env.IsLoggedIn = function() return s.loggedIn == true end
    local function UnexpectedNativeWrite() error("Conversion must not edit macros or chat history") end
    for _, name in ipairs({"CreateMacro", "EditMacro", "DeleteMacro", "FCF_Close", "FCF_OpenNewWindow",
        "FCF_SetWindowName", "ChatFrame_AddMessageGroup", "ChatFrame_RemoveMessageGroup"}) do
        env[name] = UnexpectedNativeWrite
    end
    env.C_Timer = {After = function(_, callback) timers[#timers + 1] = callback end}
    env.CreateFrame = function()
        local frame = {events = {}, scripts = {}}
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    function s:event(event, ...)
        local listeners = {}
        for _, frame in ipairs(frames) do if frame.events[event] then listeners[#listeners + 1] = frame end end
        for _, frame in ipairs(listeners) do frame.scripts.OnEvent(frame, event, ...) end
    end
    function s:flush()
        local turns = 0
        while #timers > 0 do
            turns = turns + 1
            assert(turns <= 4, "Schema readiness must settle without polling")
            local batch = timers
            timers = {}
            for _, callback in ipairs(batch) do callback() end
        end
    end
    function s:initialize() self:event("ADDON_LOADED", "CalmEUITweaks"); self:flush(); return self end
    function s:login() self.loggedIn = true; self:event("PLAYER_LOGIN"); self:flush(); return self end
    function s:hasEvent(event)
        for _, frame in ipairs(frames) do if frame.events[event] then return true end end
        return false
    end
    function s:idle()
        return not self:hasEvent("VARIABLES_LOADED") and not self:hasEvent("PLAYER_ENTERING_WORLD")
            and not self:hasEvent("PLAYER_REGEN_ENABLED") and not self:hasEvent("CVAR_UPDATE") and #timers == 0
    end
    function s:notices()
        local result = {}
        for _, message in ipairs(self.messages) do
            if message:find("savedvarsdb", 1, true) then result[#result + 1] = message end
        end
        return result
    end
    local api = {
        GetCVar = function(name)
            s.reads = s.reads + 1
            if s.readThrow == name then error("Native read failed") end
            if s.readbackMissing == name and s.changed[name] then return nil end
            return s.cv[name]
        end,
        SetCVar = function(name, value)
            assert(ns.loggedIn and not s.combat, "Native migration writes require login and no combat")
            if s.reject == name then return false end
            if s.throw == name then error("Rejected native restore") end
            if s.silent == name then return true end
            s.cv[name], s.changed[name] = value, true
            s.writes[#s.writes + 1] = name
            s:event("CVAR_UPDATE", name)
            return true
        end,
    }
    env.C_CVar = not options.noAPI and api or nil
    function s:restoreAPI() env.C_CVar = api end
    for _, file in ipairs({"core/Bootstrap.lua", "core/Settings.lua", "core/CVars.lua",
        "core/Migrations.lua", "core/Lifecycle.lua"}) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
    end
    for _, feature in ipairs({{"quest", "QuestLootSparkles"}, {"cursor", "CursorWashedOut"}}) do
        if options[feature[1]] then
            local chunk = assert(loadfile("CalmEUITweaks/functions/" .. feature[2] .. ".lua"))
            setfenv(chunk, env)
            chunk("CalmEUITweaks", ns)
        end
    end
    ns.RegisterModule("probe", {
        Initialize = function()
            assert(ns.db and ns.charDB and ns.SavedVariablesReady(), "Features must see normalized ready stores")
            s.feature.initialized = s.feature.initialized + 1
        end,
        OnLogin = function()
            assert(ns.ready and ns.loggedIn, "Login callback requires complete startup")
            s.feature.login = s.feature.login + 1
        end,
        ApplySettings = function() s.feature.applied = s.feature.applied + 1 end,
        OnAddonLoaded = function() s.feature.addons = s.feature.addons + 1 end,
    })
    if options.configure then options.configure(ns) end
    return s
end

local fresh = New(nil, nil, nil, {combat = true, noAPI = true}):initialize()
Check(fresh.ns.db.calm_forever == true and fresh.ns.db.schemaVersion == 1,
    "Fresh data initializes directly at the current lineage baseline")
Check(fresh.reads == 0 and #fresh.writes == 0 and fresh:idle(), "Fresh startup needs no native APIs or migration events")
for key, defaults in pairs(fresh.ns.defaults) do
    for field, value in pairs(defaults) do
        if type(value) == "boolean" then Check(fresh.ns.db[key][field] == false, "Fresh preferences are opt in") end
    end
end
fresh:login()
Check(#fresh:notices() == 0 and fresh.feature.initialized == 1 and fresh.feature.login == 1,
    "Fresh startup is silent and initializes once")
local empty = New({}, {}):initialize():login()
Check(empty.ns.SavedVariablesReady() and #empty:notices() == 0, "Empty stores also initialize fresh")
local late = New(nil, nil, nil, {loggedIn = true}):initialize()
Check(late.feature.initialized == 1 and late.feature.login == 1 and late.feature.applied == 1,
    "Loading fresh after login starts once")
for _, version in ipairs({0, 1, 2, 3, 4}) do
    for _, cvar in ipairs({false, 0, 1}) do
        local account = Legacy()
        account.schemaVersion, account.cvarVersion = version, cvar or nil
        account.questLootSparkles = {enabled = true, restore = {graphicsOutlineMode = {before = "2", applied = "0"}}}
        local character = {version = 1, spacers = {[1] = {width = 50}}, chat = {appliedSavedAt = 7}}
        local accountBefore, characterBefore = Copy(account), Copy(character)
        local old = New(account, character):initialize():login()
        Check(not old.ns.SavedVariablesReady() and not old.ns.db and not old.ns.charDB,
            "Pre-beta checkpoints require explicit recovery")
        Check(Same(account, accountBefore) and Same(character, characterBefore), "Rejected old stores remain unchanged")
        Check(old.reads == 0 and #old.writes == 0 and old.feature.initialized == 0
            and #old:notices() == 0 and old:idle(), "Unsupported saves cannot restore CVars or start features")
        old:event("PLAYER_ENTERING_WORLD"); old:event("PLAYER_REGEN_ENABLED"); old:flush()
        Check(old.reads == 0 and Same(account, accountBefore), "Old data is not retried by readiness events")
    end
end
local unmarked = New({mageMacro = {enabled = true}}):initialize():login()
Check(not unmarked.ns.SavedVariablesReady(), "Nonempty unversioned data cannot masquerade as fresh")
local account = {calm_forever = true, schemaVersion = 1,
    mageMacro = {enabled = true, name = "Custom", ownedMacros = {Keep = {body = "owned"}}, extra = true},
    chat = {autoApply = true, default = {savedAt = 7}}, spacerLayouts = {[1] = {width = 40}}, unknown = true,
    cursorWashedOut = {enabled = true, restore = {HardwareCursor = {before = "1", applied = "0"}}}}
local character = {version = 1, spacers = {[1] = {width = 99}, [2] = {width = 25}},
    spacerCorners = {old = true}, chat = {appliedSavedAt = 7}, mageMacro = {ownedMacros = {Keep = true}}}
local before, charBefore = Copy(account), Copy(character)
local current = New(account, character):initialize():login()
Check(current.ns.db == account and current.ns.charDB == character and current.ns.db.mageMacro.enabled
    and current.ns.db.mageMacro.name == "Custom" and current.ns.db.mageMacro.extra,
    "Current schema preserves root identity and enabled choices")
Check(Same(account.chat, before.chat) and Same(account.cursorWashedOut, before.cursorWashedOut)
    and account.unknown and account.mageMacro.ownedMacros.Keep.body == "owned",
    "Current saved content and restore ledgers survive startup")
Check(account.spacerLayouts[1].width == 40 and account.spacerLayouts[2] == nil
    and Same(character.spacers, charBefore.spacers) and Same(character.spacerCorners, charBefore.spacerCorners),
    "Old character layouts remain inert without imports or pruning")
Check(current.reads == 0 and #current.writes == 0 and #current:notices() == 0 and current:idle(),
    "Current startup does not replay native migration cleanup")
local reload = New(account, character):initialize():login()
Check(reload.ns.db.mageMacro.enabled and reload.ns.db.chat.autoApply and #reload:notices() == 0,
    "Current choices persist after reload")
Check(current.ns.ResetSettings() and not account.mageMacro.enabled and account.mageMacro.name == "FoodWater"
    and account.mageMacro.ownedMacros.Keep and account.chat.default.savedAt == 7
    and account.spacerLayouts[1].width == 40 and account.unknown and account.calm_forever and account.schemaVersion == 1,
    "Normal reset retains ownership, content and metadata")
local freshCharacter = New(nil, Copy(character)):initialize():login()
Check(next(freshCharacter.ns.db.spacerLayouts) == nil and freshCharacter.ns.charDB.spacers[2].width == 25,
    "An empty account cannot import offline character geometry")
local failedAccount, failedCharacter = {}, {version = 1, keep = true}
local failed = New(failedAccount, failedCharacter, nil, {configure = function(ns)
    ns.NormalizeSettings = function(candidate, candidateChar)
        candidate.partial, candidateChar.partial = true, true
        error("Normalization failed")
    end
end}):initialize():login()
Check(next(failedAccount) == nil and failedCharacter.partial == nil and not failed.ns.db
    and failed.feature.initialized == 0, "Failed fresh normalization cannot publish partial stores")

local cases = {
    {account = false}, {account = "bad"}, {account = 7},
    {character = false}, {character = "bad"}, {character = 7},
    {account = {schemaVersion = 5}}, {account = {schemaVersion = "2"}},
    {account = {schemaVersion = false}}, {account = {schemaVersion = -1}},
    {account = {schemaVersion = 0.5}}, {account = {schemaVersion = math.huge}},
    {account = {schemaVersion = 0 / 0}}, {account = {schemaVersion = {}}},
    {account = {cvarVersion = 2}}, {account = {cvarVersion = "1"}},
    {account = {schemaVersion = 2, cvarVersion = 2}}, {account = {schemaVersion = 0, cvarVersion = 1}},
    {account = {version = 2}}, {account = {version = "1"}}, {account = {version = 0}},
    {character = {version = 2}}, {character = {version = false}}, {character = {version = "1"}},
    {character = {schemaVersion = 0}}, {character = {schemaVersion = 1}},
    {account = {calm_forever = false}}, {account = {calm_forever = "true"}},
    {account = {calm_forever = {}}}, {account = {calm_forever = 1}},
    {account = {calm_forever = true}}, {account = {calm_forever = true, schemaVersion = 0}},
    {account = {calm_forever = true, schemaVersion = 2}},
    {account = {calm_forever = true, schemaVersion = "1"}},
    {account = {calm_forever = true, schemaVersion = false}},
    {account = {calm_forever = true, schemaVersion = -1}},
    {account = {calm_forever = true, schemaVersion = 1.5}},
    {account = {calm_forever = true, schemaVersion = math.huge}},
    {account = {calm_forever = true, schemaVersion = 0 / 0}},
    {account = {calm_forever = true, schemaVersion = {}}},
    {account = {calm_forever = true, schemaVersion = 1, version = 1}},
    {account = {calm_forever = true, schemaVersion = 1, cvarVersion = 0}},
    {account = {calm_forever = true, schemaVersion = 1, cvarVersion = 1}},
}
for _, case in ipairs(cases) do
    local account, character = case.account, case.character
    local accountBefore, characterBefore = Copy(account), Copy(character)
    local s = New(account, character):initialize():login()
    Check(Same(s.env.CalmUITweaksDB, accountBefore) and Same(s.env.CalmUITweaksCharDB, characterBefore),
        "Unsupported metadata/root cannot alter either store, including an absent opposite store")
    Check(not s.ns.db and not s.ns.charDB and not s.ns.ready and s.ns.settingsError,
        "Unsupported stores remain unexposed with an explicit startup error")
    local ready, reason = s.ns.SavedVariablesReady()
    Check(not ready and type(reason) == "string" and reason ~= "", "Readiness reports the blocked reason")
    Check(s.feature.initialized == 0 and s.feature.login == 0 and s.feature.applied == 0,
        "Unknown schemas cannot initialize or activate features")
    local set, setReason = s.ns.SetSetting("mageMacro", "enabled", false)
    local reset, resetReason = s.ns.ResetSettings()
    Check(not set and type(setReason) == "string" and not reset and type(resetReason) == "string",
        "Blocked setting/reset operations reject explicitly")
    Check(Same(s.env.CalmUITweaksDB, accountBefore) and Same(s.env.CalmUITweaksCharDB, characterBefore),
        "Rejected mutations preserve raw saved data")
    Check(#s.writes == 0 and s.reads == 0 and #s:notices() == 0 and s:idle(),
        "Unsupported versions do not touch native CVars, announce success, or retry indefinitely")
end

for _, mode in ipairs({"false", "throw", "nonboolean"}) do
    local fail = true
    local account = {calm_forever = true, schemaVersion = 1, keep = {value = "old"}, mageMacro = {enabled = true}}
    local before = Copy(account)
    local s = New(account, {version = 1}, nil, {configure = function(ns)
        ns.SCHEMA_VERSION = 2
        ns.schemaMigrations[2] = {migrate = function(candidate)
            assert(candidate ~= account and candidate.keep ~= account.keep, "Data steps must use an isolated candidate")
            candidate.keep.value = "new"
            candidate.added = true
            if fail then
                if mode == "throw" then error("Data migration failed after staging") end
                return mode == "nonboolean" and 1 or false
            end
            return true
        end}
    end}):initialize():login()
    Check(Same(account, before) and not s.ns.db and s.feature.initialized == 0,
        "A " .. mode .. " data result discards staged changes and cannot initialize features")
    Check(#s:notices() == 0 and #s.writes == 0, "Failed data steps cannot announce success or mutate native settings")
    fail = false
    s.ns.ResumeStartup(); s:flush()
    Check(s.ns.db == account and account.calm_forever == true and account.schemaVersion == 2
        and account.keep.value == "new" and account.added,
        "Literal true commits data into the original root and checkpoints the step")
    Check(account.mageMacro.enabled and s.feature.initialized == 1 and s.feature.login == 1
        and s.feature.applied == 1 and #s:notices() == 1, "Committed data preserves preferences and resumes startup once")
end

local stepTwoRuns = 0
local checkpointData = {calm_forever = true, schemaVersion = 1, keep = true}
local function TwoSteps(ns)
    ns.SCHEMA_VERSION = 3
    ns.schemaMigrations[2] = {migrate = function(candidate)
        stepTwoRuns = stepTwoRuns + 1
        candidate.second = true
        return true
    end}
    ns.schemaMigrations[3] = {migrate = function(candidate) candidate.third = true; return false end}
end
local partial = New(checkpointData, nil, nil, {configure = TwoSteps}):initialize():login()
Check(checkpointData.schemaVersion == 2 and checkpointData.second and checkpointData.third == nil
    and stepTwoRuns == 1 and not partial.ns.db, "Each completed data step checkpoints before later failure")
local resumed = New(checkpointData, partial.env.CalmUITweaksCharDB, nil, {configure = function(ns)
    TwoSteps(ns)
    ns.schemaMigrations[3].migrate = function(candidate) candidate.third = true; return true end
end}):initialize():login()
Check(resumed.ns.db.schemaVersion == 3 and resumed.ns.db.third and stepTwoRuns == 1,
    "Reload resumes from the checkpoint without replaying an earlier step")
Check(#resumed:notices() == 1 and resumed:notices()[1]:find('"2" to "3"', 1, true),
    "Reload completion reports this session's actual starting checkpoint")

local incomplete = New({calm_forever = true, schemaVersion = 1}, nil, nil, {configure = function(ns)
    ns.SCHEMA_VERSION = 2
    ns.schemaMigrations[2] = nil
end}):initialize():login()
Check(incomplete.env.CalmUITweaksDB.schemaVersion == 1 and not incomplete.ns.db and #incomplete:notices() == 0,
    "A missing required migration is never treated as completed")

for _, chosen in ipairs({false, "User Name"}) do
    local renameData = {calm_forever = true, schemaVersion = 1, oldMacroName = "Imported Food",
        mageMacro = chosen and {name = chosen} or nil}
    local renamed = New(renameData, nil, nil, {configure = function(ns)
        ns.SCHEMA_VERSION = 2
        ns.schemaMigrations[2] = {migrate = function(candidate)
            candidate.mageMacro = candidate.mageMacro or {}
            if candidate.mageMacro.name == nil then candidate.mageMacro.name = candidate.oldMacroName end
            candidate.oldMacroName = nil
            return true
        end}
    end}):initialize():login()
    Check(renamed.ns.db.mageMacro.name == (chosen or "Imported Food") and renameData.oldMacroName == nil,
        "General data renames inspect missing destinations before defaults while retaining user choices")
    Check(renameData.schemaVersion == 2 and #renamed.writes == 0 and renamed.reads == 0,
        "Data-only schema changes neither require nor write console variables")
end

local historicalQuest = {calm_forever = true, schemaVersion = 1, questLootSparkles = {enabled = true, restore = {
    graphicsOutlineMode = {before = "2", applied = "3"}, RetiredQuestEffect = {before = "0", applied = "1"},
}}}
local historicalValues = {outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "3",
    OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2", RetiredQuestEffect = "1"}
local function AddHistoricalQuestStep(ns)
    ns.SCHEMA_VERSION = 2
    ns.schemaMigrations[2] = {settingsKey = "questLootSparkles",
        values = {{"graphicsOutlineMode", "3"}, {"RetiredQuestEffect", "1"}}}
end
local historical = New(historicalQuest, nil, historicalValues,
    {quest = true, configure = AddHistoricalQuestStep, reject = "RetiredQuestEffect"}):initialize()
Check(not historical.ns.db and historicalQuest.questLootSparkles.restore.RetiredQuestEffect.before == "0",
    "Current quest initialization cannot erase old names before historical cleanup")
historical:login()
Check(historicalQuest.schemaVersion == 1 and historical.cv.graphicsOutlineMode == "2"
    and historical.cv.RetiredQuestEffect == "1" and historical.feature.initialized == 0,
    "An active-feature CVar migration retains its checkpoint and blocks latest policy on partial failure")
local historicalResume = New(historicalQuest, historical.env.CalmUITweaksCharDB, historical.cv,
    {quest = true, configure = AddHistoricalQuestStep}):initialize():login()
Check(historicalResume.ns.db.schemaVersion == 2 and historicalResume.cv.RetiredQuestEffect == "0"
    and historicalResume.cv.graphicsOutlineMode == "0", "Reload finishes historical cleanup before applying latest quest values")
Check(historicalResume.ns.db.questLootSparkles.restore.graphicsOutlineMode.before == "2",
    "Latest policy owns the original pre-migration baseline instead of the old applied mode")
historicalResume.ns.SetSetting("questLootSparkles", "enabled", false)
Check(historicalResume.cv.graphicsOutlineMode == "2", "Disabling after schema migration restores the original graphics baseline")
local function CursorStep(ns)
    ns.SCHEMA_VERSION = 2
    ns.schemaMigrations[2] = {settingsKey = "cursorWashedOut", values = {{"HardwareCursor", "0"}}}
end
local deferredAccount = {calm_forever = true, schemaVersion = 1,
    cursorWashedOut = {enabled = false, restore = {HardwareCursor = {before = "1", applied = "0"}}}}
local deferred = New(deferredAccount, nil, {HardwareCursor = "0"},
    {configure = CursorStep, noAPI = true, combat = true}):initialize():login()
Check(deferred.ns.settingsPending and deferredAccount.schemaVersion == 1 and not deferred.ns.db,
    "Future native upgrades wait for API readiness and combat without checkpointing")
deferred:restoreAPI()
deferred:event("CVAR_UPDATE", "unrelated"); deferred:flush()
Check(deferred.reads == 0, "Unrelated CVar events cannot retry pending cleanup")
deferred:event("CVAR_UPDATE", "HardwareCursor"); deferred:flush()
Check(deferred:hasEvent("PLAYER_REGEN_ENABLED") and #deferred.writes == 0,
    "Future native cleanup defers protected writes through combat")
deferred.combat = false
deferred:event("PLAYER_REGEN_ENABLED"); deferred:flush()
Check(deferred.ns.SavedVariablesReady() and deferredAccount.schemaVersion == 2
    and deferred.cv.HardwareCursor == "1" and deferred:idle() and deferred.feature.initialized == 1,
    "Future native cleanup resumes once and releases readiness subscriptions")
local function TwoNativeValues(ns)
    ns.SCHEMA_VERSION = 2
    ns.schemaMigrations[2] = {settingsKey = "questLootSparkles",
        values = {{"graphicsOutlineMode", "0"}, {"HardwareCursor", "0"}}}
end
local nativeAccount = {calm_forever = true, schemaVersion = 1, questLootSparkles = {enabled = false, restore = {
    graphicsOutlineMode = {before = "2", applied = "0"}, HardwareCursor = {before = "1", applied = "0"},
}}}
local native = New(nativeAccount, nil, {graphicsOutlineMode = "0", HardwareCursor = "0"},
    {configure = TwoNativeValues, reject = "HardwareCursor"}):initialize():login()
Check(nativeAccount.schemaVersion == 1 and not native.ns.db and native.cv.graphicsOutlineMode == "2"
    and nativeAccount.questLootSparkles.restore.HardwareCursor ~= nil,
    "Partial future native restoration retains unfinished ownership and the old checkpoint")
local nativeReload = New(nativeAccount, native.env.CalmUITweaksCharDB, native.cv,
    {configure = TwoNativeValues}):initialize():login()
Check(nativeReload.ns.SavedVariablesReady() and nativeAccount.schemaVersion == 2
    and nativeReload.cv.HardwareCursor == "1" and nativeReload.cv.graphicsOutlineMode == "2"
    and nativeReload:idle(), "Reload completes native restoration without losing the earlier baseline")
local externalAccount = {calm_forever = true, schemaVersion = 1,
    cursorWashedOut = {enabled = false, restore = {HardwareCursor = {before = "1", applied = "0"}}}}
local external = New(externalAccount, nil, {HardwareCursor = "external"},
    {configure = CursorStep}):initialize():login()
Check(external.ns.SavedVariablesReady() and external.cv.HardwareCursor == "external" and #external.writes == 0,
    "Future cleanup preserves later external CVar writes")

print("SchemaMigrations: " .. checks .. " checks passed")
