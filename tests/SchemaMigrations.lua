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
        feature = {initialized = 0, login = 0, applied = 0, addons = 0}}
    env.print = function(message) s.messages[#s.messages + 1] = message end
    env.geterrorhandler = function() return function(err) s.errors[#s.errors + 1] = tostring(err) end end
    env.InCombatLockdown = function() return s.combat == true end
    env.IsLoggedIn = function() return s.loggedIn == true end
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
            if message:find("savedvarsdb updated", 1, true) then result[#result + 1] = message end
        end
        return result
    end
    local api = {
        GetCVar = function(name) s.reads = s.reads + 1; return s.cv[name] end,
        SetCVar = function(name, value)
            assert(ns.loggedIn and not s.combat, "Native migration writes require login and no combat")
            if s.reject == name then return false end
            if s.throw == name then error("Rejected native restore") end
            if s.silent == name then return true end
            s.cv[name] = value
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
    if options.quest then
        local chunk = assert(loadfile("CalmEUITweaks/functions/QuestLootSparkles.lua"))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
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
Check(fresh.ns.db.schemaVersion == 4 and fresh.ns.db.version == nil and fresh.ns.db.cvarVersion == nil,
    "Fresh data reaches the canonical target without legacy metadata")
Check(fresh.ns.defaults.schemaVersion == nil, "Schema checkpoints must remain outside preference defaults")
Check(fresh.feature.initialized == 1 and fresh.feature.login == 0 and fresh.feature.applied == 0,
    "Pure fresh startup initializes at ADDON_LOADED but waits for login to apply features")
Check(#fresh.writes == 0 and fresh.reads == 0 and fresh:idle(), "Empty cleanup needs no native APIs or retry events")
fresh:login()
Check(fresh.feature.login == 1 and fresh.feature.applied == 1 and #fresh:notices() == 0,
    "Fresh login completes once without an upgrade announcement")
fresh:initialize():login()
Check(fresh.feature.initialized == 1 and fresh.feature.login == 1 and fresh.feature.applied == 1,
    "Repeated startup events cannot repeat feature callbacks")

for _, checkpoint in ipairs({{}, {cvarVersion = 0}, {cvarVersion = 1}, {schemaVersion = 0},
    {schemaVersion = 1}, {schemaVersion = 2}, {schemaVersion = 3}, {schemaVersion = 4}}) do
    local account = Copy(checkpoint)
    account.lfgLeaderLocation = { enabled = true }
    local initial = account.schemaVersion or account.cvarVersion or 0
    local s = New(account, {version = 1}):initialize()
    Check(s.ns.db == account and account.schemaVersion == 4, "Recognized checkpoints upgrade in the original root")
    Check(account.cvarVersion == nil and account.version == nil,
        "General adoption removes known old markers")
    Check(#s:notices() == 0, "Upgrade notices wait until login")
    s:login()
    local notices = s:notices()
    Check((initial == 4 and #notices == 0) or (#notices == 1
        and notices[1]:find('"' .. initial .. '" to "4"', 1, true)),
        "Existing data announces only an actual completed version advance")
    s.ns.ResetSettings(); s:event("PLAYER_ENTERING_WORLD"); s:flush()
    Check(#s:notices() == #notices and account.schemaVersion == 4, "Reset and later events cannot replay notices or migrations")
end

local adopted = Legacy()
local cursorUpgrade = New({schemaVersion = 2}):initialize()
Check(cursorUpgrade.ns.db.schemaVersion == 4 and cursorUpgrade.ns.db.cursorWashedOut.enabled == false
    and #cursorUpgrade.writes == 0, "Schema 2 upgrade adds a default-off cursor fix without native writes")
local cursorRecord = {enabled = true, restore = {HardwareCursor = {before = "1", applied = "0"}}, keep = true}
local cursorExisting = New({schemaVersion = 2, cursorWashedOut = Copy(cursorRecord)}):initialize()
Check(Same(cursorExisting.ns.db.cursorWashedOut, cursorRecord),
    "Cursor migration preserves existing preferences, ownership and unknown fields")
adopted.cvarVersion = 1
local noReplay = New(adopted, {version = 1}):initialize():login()
Check(#noReplay.writes == 0 and adopted.gatheringSparkles == nil,
    "Shipped CVar checkpoint 1 skips historical native cleanup and prunes its stale ledger")
Check(adopted.schemaVersion == 4 and adopted.anchorGap == nil,
    "Schema 4 drops retired anchor gap preferences")

local gapOnlyData = Legacy()
gapOnlyData.cvarVersion = 1
local gapOnly = New(gapOnlyData, {version = 1}, nil, {configure = function(ns)
    ns.SCHEMA_VERSION = 2
end}):initialize()
Check(gapOnlyData.anchorGap.top == 3 and gapOnlyData.anchorGap.bottom == 7
    and gapOnlyData.anchorGap.left == 7 and gapOnlyData.anchorGap.right == 7
    and gapOnlyData.anchorGap.pixels == nil and not gapOnlyData.anchorGap.enabled,
    "Historical shared-gap conversion still runs before later cleanup")

local retired = {schemaVersion = 3, mageMacro = {enabled = false},
    chat = {autoApply = true, default = {export = "saved", savedAt = 7}},
    spacerLayouts = {[1] = {width = 40}},
    whatsTraining = {enabled = true}, anchorGap = {enabled = true},
    spacerCorners = {player = "TOPLEFT"}, unknown = {keep = true}}
local retiredChar = {version = 1, mageMacro = {}, chat = {appliedSavedAt = 7},
    spacerCorners = {player = {base = 1}}, spacers = {[1] = {width = 10}}, unknown = true}
local pruned = New(retired, retiredChar):initialize():login()
Check(pruned.ns.db.schemaVersion == 4 and pruned.ns.db.mageMacro.enabled == false
    and pruned.ns.db.whatsTraining == nil and pruned.ns.db.anchorGap == nil
    and pruned.ns.db.spacerCorners == nil and pruned.ns.db.unknown.keep == true,
    "Schema 4 removes retired account roots and preserves unrecognized keys")
Check(pruned.ns.db.chat.autoApply and pruned.ns.db.chat.default.savedAt == 7
    and pruned.ns.db.spacerLayouts[1].width == 40,
    "Schema 4 keeps the chat default and spacer geometry")
Check(retiredChar.spacerCorners == nil and retiredChar.spacers == nil
    and retiredChar.unknown == true and retiredChar.chat.appliedSavedAt == 7,
    "Character cleanup removes retired roots without touching other keys")

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

local pending = New(Legacy(), {version = 1}, nil, {combat = true}):initialize()
Check(not pending.ns.db and not pending.ns.initialized and pending.ns.settingsPending,
    "Owned native cleanup gates normalization and feature initialization")
Check(pending.env.CalmUITweaksDB.anchorGap.pixels == 7
    and pending.env.CalmUITweaksDB.anchorGap.right == nil,
    "Later data steps and defaults cannot obscure missing fields while cleanup waits")
Check(#pending.writes == 0 and pending.feature.initialized == 0 and #pending:notices() == 0,
    "Before login, owned cleanup cannot write or start features")
local pendingBefore = Copy(pending.env.CalmUITweaksDB)
Check(not pending.ns.SetSetting("mageMacro", "enabled", false) and not pending.ns.ResetSettings(),
    "Pending data cannot be edited or reset")
Check(Same(pending.env.CalmUITweaksDB, pendingBefore), "Pending rejection retains ownership and raw preferences")
pending:event("ADDON_LOADED", "EllesmereUIBags")
Check(pending.feature.addons == 0, "Pending feature modules receive no late-addon callbacks")
pending:login()
Check(pending:hasEvent("PLAYER_REGEN_ENABLED") and #pending.writes == 0,
    "Login during combat retains the upgrade and arms combat-end readiness")
pending.combat = false
pending:event("PLAYER_REGEN_ENABLED"); pending:flush()
for name, value in pairs(original) do Check(pending.cv[name] == value, "Historical cleanup restores " .. name) end
Check(pending.ns.db.schemaVersion == 4 and pending.ns.db.gatheringSparkles == nil
    and pending.ns.db.anchorGap == nil, "Cleanup completion allows ordered data adoption and defaults")
Check(pending.feature.initialized == 1 and pending.feature.login == 1 and pending.feature.applied == 1,
    "Deferred readiness resumes each feature lifecycle callback exactly once")
Check(#pending:notices() == 1 and pending:idle(), "Successful pending upgrade announces once and releases listeners")
local writeCount = #pending.writes
pending:event("CVAR_UPDATE", "SoftTargetInteractRange"); pending:event("PLAYER_ENTERING_WORLD")
pending.ns.RequestApply("migrations"); pending:flush()
Check(#pending.writes == writeCount and pending.feature.applied == 1 and #pending:notices() == 1,
    "Stale migration requests cannot replay cleanup, startup, or notifications")

local unavailable = New(Legacy(), nil, nil, {noAPI = true}):initialize():login()
Check(unavailable.ns.settingsPending and not unavailable.ns.db and #unavailable.writes == 0,
    "Missing CVar APIs preserve a pending raw upgrade")
unavailable:restoreAPI(); unavailable:event("VARIABLES_LOADED"); unavailable:flush()
Check(unavailable.ns.db.schemaVersion == 4 and unavailable.feature.login == 1, "API readiness resumes startup")
local missingValues = Copy(applied); missingValues.SoftTargetInteractRange = nil
local missing = New(Legacy(), nil, missingValues):initialize():login()
Check(#missing.writes == 0 and missing.ns.settingsPending, "Missing owned CVar prevents partial cleanup")
missing.cv.SoftTargetInteractRange = "15"
missing:event("PLAYER_ENTERING_WORLD"); missing:flush()
Check(missing.cv.SoftTargetInteractRange == "10" and missing.ns.db.schemaVersion == 4,
    "A later world readiness event completes missing CVar cleanup")

for _, failure in ipairs({"reject", "throw", "silent"}) do
    local failed = New(Legacy(), nil, nil, {[failure] = "SoftTargetInteractRange"}):initialize():login()
    local raw = failed.env.CalmUITweaksDB
    Check(not failed.ns.db and (raw.schemaVersion == nil or raw.schemaVersion == 0)
        and raw.gatheringSparkles.restore.SoftTargetInteractRange.before == "10",
        "A " .. failure .. " native write cannot checkpoint or lose remaining ownership")
    Check(raw.anchorGap.pixels == 7 and raw.anchorGap.right == nil and #failed:notices() == 0,
        "Native failure cannot run later transformations or announce completion")
    local resumed = New(raw, failed.env.CalmUITweaksCharDB, failed.cv):initialize():login()
    Check(resumed.ns.db.schemaVersion == 4 and resumed.cv.SoftTargetInteractRange == "10",
        "Reload retries the unfinished native cleanup")
    for _, name in ipairs(resumed.writes) do
        Check(name ~= "SoftTargetInteract", "Reload does not rewrite already-restored native values")
    end
end

local foreignValues = Copy(applied)
foreignValues.SoftTargetInteractRange, foreignValues.graphicsOutlineMode = "8", "2"
local foreignSaved = Legacy()
foreignSaved.gatheringSparkles.restore.graphicsOutlineMode = {before = "0", applied = "2"}
local foreign = New(foreignSaved, nil, foreignValues):initialize():login()
Check(foreign.cv.SoftTargetInteractRange == "8" and foreign.cv.graphicsOutlineMode == "2",
    "Migration preserves later external values and rejects arbitrary CVar ownership")
local oldMode = Legacy()
oldMode.gatheringSparkles.restore.SoftTargetNameplateInteract.applied = "1"
local nodeValues = Copy(applied); nodeValues.SoftTargetNameplateInteract = "1"
local node = New(oldMode, nil, nodeValues):initialize():login()
Check(node.ns.db.schemaVersion == 4 and node.cv.SoftTargetNameplateInteract == "1",
    "Historical cleanup recognizes both nameplate modes")

for _, mode in ipairs({"false", "throw", "nonboolean"}) do
    local fail = true
    local account = {schemaVersion = 2, keep = {value = "old"}, mageMacro = {enabled = false}}
    local before = Copy(account)
    local s = New(account, {version = 1}, nil, {configure = function(ns)
        ns.SCHEMA_VERSION = 3
        ns.schemaMigrations[3] = {migrate = function(candidate)
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
    Check(s.ns.db == account and account.schemaVersion == 3 and account.keep.value == "new" and account.added,
        "Literal true commits data into the original root and checkpoints the step")
    Check(not account.mageMacro.enabled and s.feature.initialized == 1 and s.feature.login == 1
        and s.feature.applied == 1 and #s:notices() == 1, "Committed data preserves preferences and resumes startup once")
end

local stepThreeRuns = 0
local checkpointData = {schemaVersion = 2, keep = true}
local function TwoSteps(ns)
    ns.SCHEMA_VERSION = 4
    ns.schemaMigrations[3] = {migrate = function(candidate)
        stepThreeRuns = stepThreeRuns + 1
        candidate.third = true
        return true
    end}
    ns.schemaMigrations[4] = {migrate = function(candidate) candidate.fourth = true; return false end}
end
local partial = New(checkpointData, nil, nil, {configure = TwoSteps}):initialize():login()
Check(checkpointData.schemaVersion == 3 and checkpointData.third and checkpointData.fourth == nil
    and stepThreeRuns == 1 and not partial.ns.db, "Each completed data step checkpoints before later failure")
local resumed = New(checkpointData, partial.env.CalmUITweaksCharDB, nil, {configure = function(ns)
    TwoSteps(ns)
    ns.schemaMigrations[4].migrate = function(candidate) candidate.fourth = true; return true end
end}):initialize():login()
Check(resumed.ns.db.schemaVersion == 4 and resumed.ns.db.fourth and stepThreeRuns == 1,
    "Reload resumes from the checkpoint without replaying an earlier step")
Check(#resumed:notices() == 1 and resumed:notices()[1]:find('"3" to "4"', 1, true),
    "Reload completion reports this session's actual starting checkpoint")

local incomplete = New({schemaVersion = 2}, nil, nil, {configure = function(ns)
    ns.SCHEMA_VERSION = 3
    ns.schemaMigrations[3] = nil
end}):initialize():login()
Check(incomplete.env.CalmUITweaksDB.schemaVersion == 2 and not incomplete.ns.db and #incomplete:notices() == 0,
    "A missing required migration is never treated as completed")

local questAccount, questValues = Legacy(), Copy(applied)
questAccount.questLootSparkles = {enabled = true, restore = {}}
for name, value in pairs({outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2",
    OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2"}) do questValues[name] = value end
local quest = New(questAccount, nil, questValues, {quest = true, reject = "SoftTargetInteractRange"}):initialize():login()
Check(quest.cv.graphicsOutlineMode == "2" and quest.feature.initialized == 0,
    "Quest graphics cannot apply before the whole account schema is ready")
quest.reject = nil; quest:event("PLAYER_ENTERING_WORLD"); quest:flush()
Check(quest.ns.db.schemaVersion == 4 and quest.cv.graphicsOutlineMode == "0",
    "Quest uses its latest preference after schema readiness")
Check(quest.ns.ResetSettings() and quest.ns.db.schemaVersion == 4 and not quest.ns.db.questLootSparkles.enabled
    and quest.cv.graphicsOutlineMode == "2", "Ready reset preserves checkpoint and restores owned quest settings")

local accountLayouts = {schemaVersion = 2, spacerLayouts = {[1] = {width = 40, height = 10}}}
local oldCharacter = {version = 1, spacers = {[1] = {width = 99}, [2] = {width = 25, height = 12}},
    mageMacro = {ownedMacros = {Keep = {lastGeneratedBody = "owned"}}}, chat = {appliedSavedAt = 123}}
local geometry = oldCharacter.spacers[2]
local character = New(accountLayouts, oldCharacter):initialize():login()
Check(character.ns.db.spacerLayouts[1].width == 40 and character.ns.db.spacerLayouts[2].width == 25,
    "A later character seeds missing layouts even when the account schema is already current")
Check(character.ns.db.spacerLayouts[2] ~= geometry and oldCharacter.spacers == nil,
    "Character import copies geometry and removes only its migrated source")
Check(oldCharacter.mageMacro.ownedMacros.Keep.lastGeneratedBody == "owned" and oldCharacter.chat.appliedSavedAt == 123,
    "Character import preserves macro ownership and chat receipts")
local late = New({cvarVersion = 1, keep = true}, {version = 1}, nil, {loggedIn = true}):initialize()
Check(late.feature.initialized == 1 and late.feature.login == 1 and late.feature.applied == 1
    and #late:notices() == 1, "An addon loaded after login migrates and starts once")
for _, chosen in ipairs({false, "User Name"}) do
    local renameData = {schemaVersion = 2, oldMacroName = "Imported Food",
        mageMacro = chosen and {name = chosen} or nil}
    local renamed = New(renameData, nil, nil, {configure = function(ns)
        ns.SCHEMA_VERSION = 3
        ns.schemaMigrations[3] = {migrate = function(candidate)
            candidate.mageMacro = candidate.mageMacro or {}
            if candidate.mageMacro.name == nil then candidate.mageMacro.name = candidate.oldMacroName end
            candidate.oldMacroName = nil
            return true
        end}
    end}):initialize():login()
    Check(renamed.ns.db.mageMacro.name == (chosen or "Imported Food") and renameData.oldMacroName == nil,
        "General data renames inspect missing destinations before defaults while retaining user choices")
    Check(renameData.schemaVersion == 3 and #renamed.writes == 0 and renamed.reads == 0,
        "Data-only schema changes neither require nor write console variables")
end

local historicalQuest = {schemaVersion = 2, questLootSparkles = {enabled = true, restore = {
    graphicsOutlineMode = {before = "2", applied = "3"}, RetiredQuestEffect = {before = "0", applied = "1"},
}}}
local historicalValues = {outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "3",
    OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2", RetiredQuestEffect = "1"}
local function AddHistoricalQuestStep(ns)
    ns.SCHEMA_VERSION = 3
    ns.schemaMigrations[3] = {settingsKey = "questLootSparkles",
        values = {{"graphicsOutlineMode", "3"}, {"RetiredQuestEffect", "1"}}}
end
local historical = New(historicalQuest, nil, historicalValues,
    {quest = true, configure = AddHistoricalQuestStep, reject = "RetiredQuestEffect"}):initialize()
Check(not historical.ns.db and historicalQuest.questLootSparkles.restore.RetiredQuestEffect.before == "0",
    "Current quest initialization cannot erase old names before historical cleanup")
historical:login()
Check(historicalQuest.schemaVersion == 2 and historical.cv.graphicsOutlineMode == "2"
    and historical.cv.RetiredQuestEffect == "1" and historical.feature.initialized == 0,
    "An active-feature CVar migration retains its checkpoint and blocks latest policy on partial failure")
local historicalResume = New(historicalQuest, historical.env.CalmUITweaksCharDB, historical.cv,
    {quest = true, configure = AddHistoricalQuestStep}):initialize():login()
Check(historicalResume.ns.db.schemaVersion == 3 and historicalResume.cv.RetiredQuestEffect == "0"
    and historicalResume.cv.graphicsOutlineMode == "0", "Reload finishes historical cleanup before applying latest quest values")
Check(historicalResume.ns.db.questLootSparkles.restore.graphicsOutlineMode.before == "2",
    "Latest policy owns the original pre-migration baseline instead of the old applied mode")
historicalResume.ns.SetSetting("questLootSparkles", "enabled", false)
Check(historicalResume.cv.graphicsOutlineMode == "2", "Disabling after schema migration restores the original graphics baseline")
print("SchemaMigrations: " .. checks .. " checks passed")
