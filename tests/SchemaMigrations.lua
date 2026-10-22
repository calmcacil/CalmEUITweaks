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
Check(fresh.ns.db.calm_forever == true and fresh.ns.db.schemaVersion == 1
    and fresh.ns.db.version == nil and fresh.ns.db.cvarVersion == nil,
    "Fresh data reaches the Calm Forever baseline without legacy metadata")
Check(fresh.ns.SCHEMA_VERSION == 1 and fresh.ns.LEGACY_SCHEMA_VERSION == 4,
    "Current and historical schema targets remain separate")
Check(fresh.ns.defaults.schemaVersion == nil and fresh.ns.defaults.calm_forever == nil,
    "Lineage and schema checkpoints must remain outside preference defaults")
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
    {schemaVersion = 1}, {schemaVersion = 2}, {schemaVersion = 3}, {schemaVersion = 4},
    {schemaVersion = 4, version = 1}, {schemaVersion = 4, cvarVersion = 1},
    {schemaVersion = 4, version = 1, cvarVersion = 1}}) do
    local account = Copy(checkpoint)
    account.lfgLeaderLocation = { enabled = true }
    local s = New(account, {version = 1}):initialize()
    Check(s.ns.db == account and account.calm_forever == true and account.schemaVersion == 1,
        "Recognized legacy checkpoints convert in the original root")
    Check(account.lfgLeaderLocation.enabled == false, "Every legacy checkpoint resets opt-in preferences")
    Check(account.cvarVersion == nil and account.version == nil,
        "General adoption removes known old markers")
    Check(#s:notices() == 0, "Upgrade notices wait until login")
    s:login()
    local notices = s:notices()
    Check(#notices == 1 and notices[1]:find("calm_forever", 1, true)
        and notices[1]:lower():find("reset", 1, true),
        "Every converted existing account announces the lineage baseline and preference reset")
    s.ns.ResetSettings(); s:event("PLAYER_ENTERING_WORLD"); s:flush()
    Check(#s:notices() == #notices and account.calm_forever == true and account.schemaVersion == 1,
        "Reset and later events cannot replay notices or conversion")
    local convertedReload = New(account, s.env.CalmUITweaksCharDB):initialize():login()
    Check(convertedReload.ns.db == account and convertedReload.ns.SavedVariablesReady()
        and #convertedReload:notices() == 0, "Every accepted legacy metadata combination produces reloadable marked data")
end

local adopted = Legacy()
local cursorUpgrade = New({schemaVersion = 2}):initialize()
Check(cursorUpgrade.ns.db.calm_forever == true and cursorUpgrade.ns.db.schemaVersion == 1
    and cursorUpgrade.ns.db.cursorWashedOut.enabled == false and #cursorUpgrade.writes == 0,
    "Legacy schema 2 converts to a default-off cursor fix without native writes")
local cursorRecord = {enabled = true, restore = {HardwareCursor = {before = "1", applied = "0"}}, keep = true}
local cursorExisting = New({schemaVersion = 2, cursorWashedOut = Copy(cursorRecord)}, nil,
    {HardwareCursor = "0"}):initialize()
Check(cursorExisting.ns.settingsPending and cursorExisting.env.CalmUITweaksDB.calm_forever == nil,
    "An active historical cursor ledger delays baseline completion until login")
cursorExisting:login()
Check(cursorExisting.ns.db.cursorWashedOut.enabled == false and cursorExisting.ns.db.cursorWashedOut.keep
    and cursorExisting.cv.HardwareCursor == "1", "Baseline restores the old cursor and retains unknown fields")
adopted.cvarVersion = 1
local noReplay = New(adopted, {version = 1}):initialize():login()
Check(#noReplay.writes == 0 and adopted.gatheringSparkles == nil,
    "Shipped CVar checkpoint 1 skips historical native cleanup and prunes its stale ledger")
Check(adopted.calm_forever == true and adopted.schemaVersion == 1 and adopted.anchorGap == nil,
    "Legacy cleanup drops retired anchor gap preferences before conversion")

local gapOnlyData = Legacy()
gapOnlyData.cvarVersion = 1
local gapOnly = New(nil, nil)
Check(gapOnly.ns.legacySchemaMigrations[2].migrate(gapOnlyData) == true
    and gapOnlyData.anchorGap.top == 3 and gapOnlyData.anchorGap.bottom == 7
    and gapOnlyData.anchorGap.left == 7 and gapOnlyData.anchorGap.right == 7
    and gapOnlyData.anchorGap.pixels == nil and not gapOnlyData.anchorGap.enabled,
    "The shipped shared-gap conversion remains directly usable on a candidate")

local retired = {schemaVersion = 3, mageMacro = {enabled = false},
    chat = {autoApply = true, default = {export = "saved", savedAt = 7}},
    spacerLayouts = {[1] = {width = 40}},
    whatsTraining = {enabled = true}, anchorGap = {enabled = true},
    spacerCorners = {player = "TOPLEFT"}, unknown = {keep = true}}
local retiredChar = {version = 1, mageMacro = {}, chat = {appliedSavedAt = 7},
    spacerCorners = {player = {base = 1}}, spacers = {[1] = {width = 10}}, unknown = true}
local pruned = New(retired, retiredChar):initialize():login()
Check(pruned.ns.db.calm_forever == true and pruned.ns.db.schemaVersion == 1 and pruned.ns.db.mageMacro.enabled == false
    and pruned.ns.db.whatsTraining == nil and pruned.ns.db.anchorGap == nil
    and pruned.ns.db.spacerCorners == nil and pruned.ns.db.unknown.keep == true,
    "Schema 4 removes retired account roots and preserves unrecognized keys")
Check(pruned.ns.db.chat.autoApply == false and pruned.ns.db.chat.default.savedAt == 7
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
Check(pending.ns.db.calm_forever == true and pending.ns.db.schemaVersion == 1 and pending.ns.db.gatheringSparkles == nil
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
Check(unavailable.ns.db.schemaVersion == 1 and unavailable.feature.login == 1, "API readiness resumes startup")
local missingValues = Copy(applied); missingValues.SoftTargetInteractRange = nil
local missing = New(Legacy(), nil, missingValues):initialize():login()
Check(#missing.writes == 0 and missing.ns.settingsPending, "Missing owned CVar prevents partial cleanup")
missing.cv.SoftTargetInteractRange = "15"
missing:event("PLAYER_ENTERING_WORLD"); missing:flush()
Check(missing.cv.SoftTargetInteractRange == "10" and missing.ns.db.schemaVersion == 1,
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
    Check(resumed.ns.db.calm_forever == true and resumed.ns.db.schemaVersion == 1 and resumed.cv.SoftTargetInteractRange == "10",
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
Check(node.ns.db.calm_forever == true and node.ns.db.schemaVersion == 1 and node.cv.SoftTargetNameplateInteract == "1",
    "Historical cleanup recognizes both nameplate modes")

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

local questAccount, questValues = Legacy(), Copy(applied)
questAccount.questLootSparkles = {enabled = true, restore = {}}
for name, value in pairs({outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2",
    OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2"}) do questValues[name] = value end
local quest = New(questAccount, nil, questValues, {quest = true, reject = "SoftTargetInteractRange"}):initialize():login()
Check(quest.cv.graphicsOutlineMode == "2" and quest.feature.initialized == 0,
    "Quest graphics cannot apply before the whole account schema is ready")
quest.reject = nil; quest:event("PLAYER_ENTERING_WORLD"); quest:flush()
Check(quest.ns.db.calm_forever == true and quest.ns.db.schemaVersion == 1 and quest.cv.graphicsOutlineMode == "2"
    and not quest.ns.db.questLootSparkles.enabled, "Conversion does not apply a previously enabled quest preference")
Check(quest.ns.SetSetting("questLootSparkles", "enabled", true) and quest.cv.graphicsOutlineMode == "0",
    "A user can explicitly opt in after conversion")
Check(quest.ns.ResetSettings() and quest.ns.db.schemaVersion == 1 and not quest.ns.db.questLootSparkles.enabled
    and quest.cv.graphicsOutlineMode == "2", "Ready reset preserves checkpoint and restores owned quest settings")

local accountLayouts = {calm_forever = true, schemaVersion = 1, spacerLayouts = {[1] = {width = 40, height = 10}}}
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
local booleanPreferences = {
    {"mageMacro", "enabled"}, {"druidRebirthMacro", "enabled"}, {"druidThornsMacro", "enabled"},
    {"generalFoodWaterMacro", "enabled"}, {"simpleItemLevel", "enabled"},
    {"simpleItemLevel", "inventory"}, {"simpleItemLevel", "reagent"}, {"simpleItemLevel", "bank"},
    {"questLootSparkles", "enabled"}, {"cursorWashedOut", "enabled"}, {"lfgLeaderLocation", "enabled"},
    {"chat", "autoApply"}, {"spacers", "spacer1"}, {"spacers", "spacer2"},
    {"spacers", "spacer3"}, {"spacers", "spacer4"},
}
local macroNames = {mageMacro = "FoodWater", druidRebirthMacro = "Rebirth",
    druidThornsMacro = "Thorns", generalFoodWaterMacro = "Food and Water"}
local function AllDisabled(account, context)
    for _, entry in ipairs(booleanPreferences) do
        Check(account[entry[1]][entry[2]] == false, context .. ": " .. entry[1] .. "." .. entry[2] .. " is false")
    end
    for key, name in pairs(macroNames) do Check(account[key].name == name, context .. ": default " .. key .. " name") end
end
local function Preferences()
    local account = {schemaVersion = 4, unknown = {nested = {keep = true}},
        provider = {enabled = true, name = "Provider", ownedMacros = {External = {lastGeneratedBody = "provider"}}},
        chat = {autoApply = true, default = {export = "chat-data", savedAt = 77}, future = {keep = true}},
        spacerLayouts = {[1] = {width = 40, height = 12, point = "CENTER", x = 9, provider = true}}}
    for _, entry in ipairs(booleanPreferences) do
        account[entry[1]] = account[entry[1]] or {future = {keep = true}}
        account[entry[1]][entry[2]] = true
    end
    account.questLootSparkles.restore, account.cursorWashedOut.restore = {}, {}
    for key in pairs(macroNames) do
        account[key].name = "Custom Name"
        account[key].ownedMacros = {Keep = {lastGeneratedBody = "account-body", unknown = true}}
    end
    return account
end
local function CharacterData()
    return {version = 1, mageMacro = {ownedMacros = {Keep = {lastGeneratedBody = "character-body"}}},
        druidRebirthMacro = {ownedMacros = {Rebirth = {lastGeneratedBody = "rebirth-body"}}},
        provider = {ownedMacros = {Custom = {lastGeneratedBody = "custom-body"}}, unknown = true},
        chat = {appliedSavedAt = 77, appliedExport = "receipt", future = {keep = true}},
        spacers = {[1] = {width = 99}, [2] = {width = 25, height = 15}},
        spacerCorners = {old = true}, unknown = {nested = true}}
end
AllDisabled(fresh.ns.db, "Fresh baseline")
local expectedFresh = Copy(fresh.ns.defaults)
expectedFresh.calm_forever, expectedFresh.schemaVersion = true, 1
Check(Same(fresh.ns.db, expectedFresh), "Fresh data contains only preference defaults and completed lineage metadata")
for _, entry in ipairs(booleanPreferences) do
    Check(fresh.ns.defaults[entry[1]][entry[2]] == false, "Every declared boolean default is opt-in")
end
local emptyAccount, emptyCharacter = {}, {}
local empty = New(emptyAccount, emptyCharacter, nil, {noAPI = true}):initialize():login()
Check(empty.ns.db == emptyAccount and empty.ns.charDB == emptyCharacter and emptyAccount.calm_forever == true
    and #empty:notices() == 0 and empty.reads == 0, "Empty roots convert in place without a fresh-install notice")

local preservedAccount, preservedCharacter = Preferences(), CharacterData()
local preservedBefore, charBefore = Copy(preservedAccount), Copy(preservedCharacter)
local preserved = New(preservedAccount, preservedCharacter, nil, {noAPI = true}):initialize():login()
AllDisabled(preservedAccount, "Converted baseline")
Check(preserved.ns.db == preservedAccount and preserved.ns.charDB == preservedCharacter,
    "Conversion preserves both original root identities")
for key in pairs(macroNames) do
    Check(Same(preservedAccount[key].ownedMacros, preservedBefore[key].ownedMacros)
        and Same(preservedAccount[key].future, preservedBefore[key].future), "Conversion preserves nested ownership and unknowns: " .. key)
end
for _, entry in ipairs(booleanPreferences) do
    Check(Same(preservedAccount[entry[1]].future, preservedBefore[entry[1]].future), "Live nested unknowns survive: " .. entry[1])
end
Check(Same(preservedAccount.provider, preservedBefore.provider) and Same(preservedAccount.unknown, preservedBefore.unknown)
    and Same(preservedAccount.chat.default, preservedBefore.chat.default), "Provider roots, saved chat and unknown roots survive conversion")
Check(Same(preservedCharacter.mageMacro, charBefore.mageMacro) and Same(preservedCharacter.druidRebirthMacro, charBefore.druidRebirthMacro)
    and Same(preservedCharacter.provider, charBefore.provider) and Same(preservedCharacter.chat, charBefore.chat)
    and Same(preservedCharacter.unknown, charBefore.unknown), "Character ownership, receipts and unknowns survive conversion")
Check(preservedAccount.spacerLayouts[1].width == 40 and preservedAccount.spacerLayouts[2].width == 25
    and preservedCharacter.spacers == nil and preservedCharacter.spacerCorners == nil,
    "Baseline stages account-wins geometry import before retiring character sources")

local nestedRoots = {}
for key, value in pairs(preservedAccount) do if type(value) == "table" then nestedRoots[key] = value end end
for _, entry in ipairs(booleanPreferences) do preservedAccount[entry[1]][entry[2]] = true end
for key in pairs(macroNames) do preservedAccount[key].name = "Changed Name" end
local normalizedChar = Copy(preservedCharacter)
Check(preserved.ns.ResetSettings() == true, "Normal reset succeeds after conversion")
AllDisabled(preservedAccount, "Normal reset")
for key, value in pairs(nestedRoots) do Check(preservedAccount[key] == value, "Normal reset preserves live table identity: " .. key) end
Check(Same(preservedCharacter, normalizedChar) and preservedAccount.calm_forever == true and preservedAccount.schemaVersion == 1,
    "Normal reset preserves character records and completed lineage metadata")
Check(Same(preservedAccount.provider, preservedBefore.provider) and Same(preservedAccount.chat.default, preservedBefore.chat.default)
    and preservedAccount.spacerLayouts[2].width == 25, "Normal reset preserves provider data, saved chat and imported geometry")

local pure = Preferences()
local pureRoots = {chat = pure.chat, mageMacro = pure.mageMacro, spacerLayouts = pure.spacerLayouts}
local pureHarness = New(nil, nil)
Check(pureHarness.ns.ResetPreferences(pure) == true, "Pure reset helper returns literal true")
AllDisabled(pure, "Pure reset")
Check(pure.chat == pureRoots.chat and pure.mageMacro == pureRoots.mageMacro and pure.spacerLayouts == pureRoots.spacerLayouts
    and pureHarness.reads == 0 and #pureHarness.writes == 0 and pureHarness.feature.initialized == 0,
    "Pure reset preserves valid nested tables without native or lifecycle effects")
local malformedPreferences = {schemaVersion = 4, mageMacro = false, simpleItemLevel = "bad", spacers = 3,
    chat = {autoApply = "bad", default = {export = "keep"}}, spacerLayouts = {[3] = {width = 80}}}
Check(pureHarness.ns.ResetPreferences(malformedPreferences) == true, "Pure reset repairs malformed known preference tables")
AllDisabled(malformedPreferences, "Repaired reset")
Check(malformedPreferences.chat.default.export == "keep" and malformedPreferences.spacerLayouts[3].width == 80
    and malformedPreferences.schemaVersion == 4 and malformedPreferences.calm_forever == nil,
    "Pure reset repairs preferences without stamping metadata or erasing empty-default contents")

preserved.ns.SetSetting("mageMacro", "enabled", true)
preserved.ns.SetSetting("mageMacro", "name", "My Food")
preserved.ns.SetSetting("simpleItemLevel", "inventory", true)
preserved.ns.SetSetting("lfgLeaderLocation", "enabled", true)
local afterChoice = Copy(preservedAccount)
local reload = New(preservedAccount, preservedCharacter, nil, {configure = function(ns)
    ns.ResetPreferences = function() error("Marked current data must never repeat baseline reset") end
end}):initialize():login()
Check(Same(preservedAccount, afterChoice) and reload.feature.initialized == 1 and #reload:notices() == 0
    and reload.reads == 0 and #reload.writes == 0, "Marked reload retains choices and never repeats conversion")
local offlineCharacter = CharacterData()
offlineCharacter.spacers[2].width, offlineCharacter.spacers[3] = 111, {width = 66}
local alt = New(preservedAccount, offlineCharacter, nil, {configure = function(ns)
    ns.ResetPreferences = function() error("An alternate character must not reset an already converted account") end
end}):initialize():login()
Check(alt.ns.charDB == offlineCharacter and preservedAccount.mageMacro.enabled and preservedAccount.mageMacro.name == "My Food"
    and preservedAccount.simpleItemLevel.inventory and preservedAccount.lfgLeaderLocation.enabled and #alt:notices() == 0,
    "An alternate character retains account opt-in choices without a second reset or notice")
Check(preservedAccount.spacerLayouts[2].width == 25 and preservedAccount.spacerLayouts[3].width == 66
    and offlineCharacter.spacers == nil, "A later character lazily seeds only still-missing geometry")

-- These snapshots match the actual feature definitions, not the narrower retired targeting policy.
local activeApplied = {outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0", OutlineEngineMode = "0",
    raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0", HardwareCursor = "0"}
local activeBefore = {outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2", OutlineEngineMode = "2",
    raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2", HardwareCursor = "1"}
local activeNames = {"outlineModeShowLootEffectWhenDisabled", "graphicsOutlineMode", "OutlineEngineMode",
    "raidGraphicsOutlineMode", "RAIDOutlineEngineMode", "HardwareCursor"}
local function ActiveAccount()
    local account = Preferences()
    account.questLootSparkles.restore, account.cursorWashedOut.restore = {}, {}
    for _, name in ipairs(activeNames) do
        local owner = name == "HardwareCursor" and account.cursorWashedOut or account.questLootSparkles
        owner.restore[name] = {before = activeBefore[name], applied = activeApplied[name]}
    end
    return account
end
local function Restored(s, context)
    Check(s.ns.db and s.ns.db.calm_forever == true and s.ns.db.schemaVersion == 1, context .. ": commits baseline")
    for _, name in ipairs(activeNames) do Check(s.cv[name] == activeBefore[name], context .. ": restores " .. name) end
    Check(next(s.ns.db.questLootSparkles.restore) == nil and next(s.ns.db.cursorWashedOut.restore) == nil,
        context .. ": consumes completed ownership ledgers")
    AllDisabled(s.ns.db, context)
    Check(s:idle() and s.feature.initialized == 1 and s.feature.login == 1 and s.feature.applied == 1,
        context .. ": starts once and releases pending events")
end
local fullAccount, fullCharacter = ActiveAccount(), CharacterData()
local full = New(fullAccount, fullCharacter, Copy(activeApplied), {combat = true, quest = true, cursor = true}):initialize()
Check(fullAccount.calm_forever == nil and fullAccount.schemaVersion == 4 and fullAccount.mageMacro.enabled
    and fullAccount.questLootSparkles.enabled and fullCharacter.spacers ~= nil and not full.ns.db,
    "Pending baseline does not publish reset preferences, geometry imports or marker")
Check(#full.writes == 0 and full.reads == 0 and not full.ns.SetSetting("mageMacro", "enabled", false)
    and not full.ns.ResetSettings(), "Pending baseline blocks edits and native reads before login")
full:login()
Check(full:hasEvent("PLAYER_REGEN_ENABLED") and full.reads == 0 and #full.writes == 0,
    "Active baseline waits through combat without native reads")
full.combat = false; full:event("PLAYER_REGEN_ENABLED"); full:flush()
Restored(full, "Full baseline")
Check(full.ns.db == fullAccount and full.ns.charDB == fullCharacter and #full.writes == 6
    and #full:notices() == 1, "Full baseline keeps root identities, restores each CVar once and announces once")
local writesBefore = #full.writes
full:event("PLAYER_ENTERING_WORLD"); full:event("CVAR_UPDATE", "HardwareCursor"); full:flush()
Check(#full.writes == writesBefore and #full:notices() == 1, "Finished native baseline never replays on readiness events")

local combinedAccount, combinedValues = ActiveAccount(), Copy(activeApplied)
local historicalData = Legacy()
combinedAccount.schemaVersion = nil
combinedAccount.version, combinedAccount.cvarVersion = 1, 0
combinedAccount.gatheringSparkles = historicalData.gatheringSparkles
for name, value in pairs(applied) do combinedValues[name] = value end
local combined = New(combinedAccount, nil, combinedValues):initialize():login()
Restored(combined, "Legacy then baseline")
for name, value in pairs(original) do Check(combined.cv[name] == value, "Legacy cleanup still restores " .. name) end
Check(#combined.writes == 14 and combined.writes[1] == "SoftTargetInteract"
    and combined.writes[9] == "outlineModeShowLootEffectWhenDisabled" and combined.writes[14] == "HardwareCursor",
    "Legacy targeting cleanup precedes quest and cursor baseline cleanup")

for _, failure in ipairs({"reject", "throw", "silent", "readThrow", "readbackMissing"}) do
    for _, name in ipairs(activeNames) do
        local account, character = ActiveAccount(), CharacterData()
        local failed = New(account, character, Copy(activeApplied), {[failure] = name}):initialize():login()
        local owner = name == "HardwareCursor" and account.cursorWashedOut or account.questLootSparkles
        Check(account.calm_forever == nil and account.schemaVersion == 4 and not failed.ns.db
            and account.mageMacro.enabled and account.mageMacro.name == "Custom Name"
            and account.questLootSparkles.enabled and account.cursorWashedOut.enabled,
            failure .. " at " .. name .. " cannot commit reset preferences or lineage")
        Check(owner.restore[name] and owner.restore[name].before == activeBefore[name]
            and character.spacers ~= nil and #failed:notices() == 0 and failed.feature.initialized == 0,
            failure .. " at " .. name .. " retains unfinished ownership and character data")
        local nativeProgress = Copy(failed.cv)
        local alternate = CharacterData()
        local resumedActive = New(account, alternate, failed.cv, {quest = true, cursor = true}):initialize():login()
        Restored(resumedActive, failure .. " reload at " .. name)
        Check(resumedActive.ns.db == account and resumedActive.ns.charDB == alternate,
            "Native failure can resume on another character without replacing either root")
        for _, written in ipairs(resumedActive.writes) do
            Check(nativeProgress[written] == activeApplied[written], "Reload does not rewrite already restored " .. written)
        end
    end
end

for _, ownerKey in ipairs({"questLootSparkles", "cursorWashedOut"}) do
    for _, unavailableAPI in ipairs({"noAPI", "GetCVar", "SetCVar"}) do
        local account = ActiveAccount()
        account[ownerKey == "questLootSparkles" and "cursorWashedOut" or "questLootSparkles"].restore = {}
        local s = New(account, nil, Copy(activeApplied), {noAPI = unavailableAPI == "noAPI"}):initialize()
        local savedAPI = s.env.C_CVar
        if unavailableAPI ~= "noAPI" then
            local availableMethod = unavailableAPI == "GetCVar" and "SetCVar" or "GetCVar"
            s.env.C_CVar = {[availableMethod] = savedAPI[availableMethod]}
        end
        s:login()
        Check(account.calm_forever == nil and account[ownerKey].enabled and s.ns.settingsPending
            and s.reads == 0 and #s.writes == 0, "Missing " .. unavailableAPI .. " preserves pending " .. ownerKey)
        s:restoreAPI(); s:event("VARIABLES_LOADED"); s:flush()
        Check(s.ns.db and account.calm_forever == true and not account[ownerKey].enabled and s:idle(),
            "Native API readiness completes " .. ownerKey .. " baseline")
    end
end
for _, name in ipairs(activeNames) do
    local account, values = ActiveAccount(), Copy(activeApplied)
    values[name] = nil
    local s = New(account, nil, values):initialize():login()
    Check(not s.ns.db and account.calm_forever == nil and account.mageMacro.enabled,
        "Missing native value preserves baseline preferences: " .. name)
    values[name] = activeApplied[name]
    s:event("PLAYER_ENTERING_WORLD"); s:flush()
    Restored(s, "Native value readiness " .. name)
end
local externalAccount, externalValues = ActiveAccount(), Copy(activeApplied)
externalValues.graphicsOutlineMode, externalValues.HardwareCursor = "3", "external"
local external = New(externalAccount, nil, externalValues):initialize():login()
Check(external.ns.db.calm_forever == true and external.cv.graphicsOutlineMode == "3" and external.cv.HardwareCursor == "external",
    "Baseline preserves external quest graphics and cursor writes")
for _, name in ipairs(external.writes) do Check(name ~= "graphicsOutlineMode" and name ~= "HardwareCursor", "External values are never overwritten") end
local invalidLedger = {schemaVersion = 4, questLootSparkles = {enabled = true, restore = {
    graphicsOutlineMode = {before = 2, applied = "0"}, OutlineEngineMode = {before = "2", applied = "3"},
    UnknownCVar = {before = "0", applied = "1"}}},
    cursorWashedOut = {enabled = true, restore = {HardwareCursor = {before = "1", applied = "1"}}}}
local invalidOwned = New(invalidLedger, nil, nil, {noAPI = true}):initialize():login()
Check(invalidOwned.ns.db.calm_forever == true and invalidOwned.reads == 0 and #invalidOwned.writes == 0
    and next(invalidLedger.questLootSparkles.restore) == nil and next(invalidLedger.cursorWashedOut.restore) == nil,
    "Malformed baselines, unrecognized applied values and arbitrary CVars are pruned without native reads")

for _, mode in ipairs({"false", "nil", "nonboolean", "throw"}) do
    local account, character = Preferences(), CharacterData()
    local accountBefore, characterBefore = Copy(account), Copy(character)
    local fail = true
    local s = New(account, character, nil, {configure = function(ns)
        local reset = ns.ResetPreferences
        ns.ResetPreferences = function(candidate)
            Check(candidate ~= account and candidate.mageMacro ~= account.mageMacro,
                "Baseline reset receives an isolated account candidate")
            reset(candidate)
            candidate.unknown.nested.keep, candidate.tentative = false, true
            if fail then
                if mode == "throw" then error("Baseline reset failed after staging") end
                if mode == "nil" then return nil end
                return mode == "nonboolean" and 1 or false
            end
            return true
        end
    end}):initialize():login()
    Check(Same(account, accountBefore) and Same(character, characterBefore) and account.calm_forever == nil
        and not s.ns.db and not s.ns.charDB and #s:notices() == 0 and s.feature.initialized == 0,
        "A baseline " .. mode .. " result discards all tentative reset data and stamps nothing")
    fail = false; s.ns.ResumeStartup(); s:flush()
    Check(s.ns.db == account and s.ns.charDB == character and account.calm_forever == true
        and account.schemaVersion == 1 and account.tentative and #s:notices() == 1,
        "Baseline retry commits only a literal true result into the original roots")
    AllDisabled(account, "Successful reset retry")
end
local normalizeAccount, normalizeChar = ActiveAccount(), CharacterData()
local normalizeCharBefore = Copy(normalizeChar)
local normalizeFail = true
local normalize = New(normalizeAccount, normalizeChar, Copy(activeApplied), {configure = function(ns)
    local normalizeSettings = ns.NormalizeSettings
    ns.NormalizeSettings = function(account, character)
        if normalizeFail then
            Check(account ~= normalizeAccount and character ~= normalizeChar
                and character.spacers ~= normalizeChar.spacers, "Normalization receives copies of both roots")
            normalizeSettings(account, character)
            account.unknown.nested.keep = false
            character.chat.appliedSavedAt = 999
            error("Normalization failed after staging both roots")
        end
        return normalizeSettings(account, character)
    end
end}):initialize():login()
Check(normalizeAccount.calm_forever == nil and normalizeAccount.schemaVersion == 4 and normalizeAccount.mageMacro.enabled
    and normalizeAccount.unknown.nested.keep and Same(normalizeChar, normalizeCharBefore) and not normalize.ns.db
    and #normalize:notices() == 0, "Normalization failure cannot publish reset preferences, character imports or marker")
for _, name in ipairs(activeNames) do Check(normalize.cv[name] == activeBefore[name], "Native progress survives pure-data failure: " .. name) end
Check(next(normalizeAccount.questLootSparkles.restore) == nil and next(normalizeAccount.cursorWashedOut.restore) == nil,
    "Already completed native restoration remains durable after normalization failure")
normalizeFail = false; normalize.ns.ResumeStartup(); normalize:flush()
Restored(normalize, "Normalization retry")
Check(#normalize.writes == 6 and normalize.ns.db == normalizeAccount and normalize.ns.charDB == normalizeChar
    and normalizeChar.chat.appliedSavedAt == normalizeCharBefore.chat.appliedSavedAt,
    "Normalization retry does not repeat native writes or leak staged character changes")

-- Reject the opposite root before even preparing an otherwise valid active ledger.
for _, marked in ipairs({false, true}) do
    local account = ActiveAccount()
    if marked then account.calm_forever, account.schemaVersion = true, 1 end
    local before = Copy(account)
    local invalidCharacter = {version = 2, keep = {unchanged = true}}
    local s = New(account, invalidCharacter, Copy(activeApplied)):initialize():login()
    Check(Same(account, before) and Same(invalidCharacter, {version = 2, keep = {unchanged = true}})
        and s.env.CalmUITweaksDB == account and s.env.CalmUITweaksCharDB == invalidCharacter,
        "Invalid opposite character metadata cannot mutate a valid " .. (marked and "marked" or "legacy") .. " account")
    Check(s.reads == 0 and #s.writes == 0 and s.feature.initialized == 0 and #s:notices() == 0,
        "Opposite-root preflight blocks all native reads and startup")
end
local invalidAccount, validCharacter = {calm_forever = false}, CharacterData()
local validCharacterBefore = Copy(validCharacter)
local opposite = New(invalidAccount, validCharacter):initialize():login()
Check(Same(validCharacter, validCharacterBefore) and opposite.env.CalmUITweaksCharDB == validCharacter
    and opposite.reads == 0 and not opposite.ns.charDB, "Invalid account cannot normalize or retire valid character data")
local legacyFailure = Legacy()
legacyFailure.cvarVersion, legacyFailure.mageMacro = 1, {enabled = true, name = "Keep Until Done"}
local legacyFailed = New(legacyFailure, nil, nil, {configure = function(ns)
    ns.ResetPreferences = function(candidate)
        candidate.mageMacro.enabled = false
        return false
    end
end}):initialize():login()
Check(legacyFailure.calm_forever == nil and legacyFailure.schemaVersion == 4 and legacyFailure.anchorGap == nil
    and legacyFailure.version == nil and legacyFailure.cvarVersion == nil and legacyFailure.mageMacro.enabled
    and legacyFailure.mageMacro.name == "Keep Until Done" and #legacyFailed:notices() == 0,
    "Failed baseline preserves legacy checkpoints and cleanup without committing preference reset")
local legacyRetried = New(legacyFailure, legacyFailed.env.CalmUITweaksCharDB):initialize():login()
Check(legacyRetried.ns.db.calm_forever == true and legacyRetried.ns.db.schemaVersion == 1
    and not legacyFailure.mageMacro.enabled and legacyFailure.mageMacro.name == "FoodWater",
    "Reload resumes baseline after the last durable legacy checkpoint")
local eventAccount = ActiveAccount()
local eventRetry = New(eventAccount, nil, Copy(activeApplied), {reject = "graphicsOutlineMode"}):initialize():login()
local readsBefore = eventRetry.reads
eventRetry.reject = nil
eventRetry:event("CVAR_UPDATE", "unrelatedCVar"); eventRetry:flush()
Check(eventRetry.reads == readsBefore and eventAccount.calm_forever == nil,
    "Pending migration ignores unrelated CVar events")
eventRetry:event("CVAR_UPDATE", "GRAPHICSOUTLINEMODE"); eventRetry:flush()
Restored(eventRetry, "Relevant CVar readiness")
Check(full.ns.SetSetting("questLootSparkles", "enabled", true)
    and full.ns.SetSetting("cursorWashedOut", "enabled", true), "Both native features can opt in after conversion")
for _, name in ipairs(activeNames) do Check(full.cv[name] == activeApplied[name], "Opt-in applies " .. name) end
Check(full.ns.ResetSettings() and fullAccount.calm_forever == true and fullAccount.schemaVersion == 1,
    "Normal native reset preserves lineage metadata")
for _, name in ipairs(activeNames) do Check(full.cv[name] == activeBefore[name], "Normal reset restores " .. name) end
print("SchemaMigrations: " .. checks .. " checks passed")
