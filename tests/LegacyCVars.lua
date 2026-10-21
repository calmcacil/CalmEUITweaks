local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
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
local function Copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function Saved()
    local restore = {}
    for name, value in pairs(applied) do restore[name] = {before = original[name], applied = value} end
    return {gatheringSparkles = {enabled = true, restore = restore}}
end
local function New(saved, current, options)
    options = options or {}
    local ns, frames, timers, writes, messages = {}, {}, {}, {}, {}
    local env = setmetatable({}, {__index = _G})
    env._G, env.CalmUITweaksDB = env, saved or {}
    env.print = function(message) messages[#messages + 1] = message end
    env.geterrorhandler = function() return function() end end
    env.IsLoggedIn = function() return false end
    local s = {ns = ns, cv = current or Copy(applied), combat = options.combat, reject = options.reject,
        throw = options.throw, silent = options.silent, frames = frames, writes = writes, messages = messages,
        env = env}
    env.InCombatLockdown = function() return s.combat == true end
    env.CreateFrame = function()
        local frame = {events = {}, scripts = {}}
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    function s:fire(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    local api = {
        GetCVar = function(name) return s.cv[name] end,
        SetCVar = function(name, value)
            assert(not s.combat, "Legacy restoration must wait through combat")
            if name == s.reject then return false end
            if name == s.throw then error("Console write failed") end
            if name == s.silent then return true end
            s.cv[name] = value
            writes[#writes + 1] = name
            s:fire("CVAR_UPDATE", name)
            return true
        end,
    }
    env.C_CVar = not options.noAPI and api or nil
    env.C_Timer = {After = function(_, callback) timers[#timers + 1] = callback end}
    for _, file in ipairs({"core/Bootstrap.lua", "core/Settings.lua", "core/CVars.lua",
        "core/LegacyCVars.lua", "core/Lifecycle.lua"}) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
    end
    if options.quest then
        local chunk = assert(loadfile("CalmEUITweaks/functions/QuestLootSparkles.lua"))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
    end
    if options.configure then options.configure(ns) end
    function s:flush()
        local turns = 0
        while #timers > 0 do
            turns = turns + 1
            assert(turns <= 2, "Only cleanup and one dependent feature application may be queued")
            local batch = timers
            timers = {}
            for _, callback in ipairs(batch) do callback() end
        end
    end
    function s:restoreAPI() env.C_CVar = api end
    function s:pending() return #timers end
    s:fire("ADDON_LOADED", "CalmEUITweaks")
    Check(#writes == 0, "SavedVariables initialization must not write console settings")
    if options.beforeLogin then options.beforeLogin(s) end
    s:fire("PLAYER_LOGIN")
    s:flush()
    s.driver = frames[options.quest and 3 or 2]
    return s
end

local fresh = New()
Check(fresh.ns.defaults.gatheringSparkles == nil and fresh.ns.db.gatheringSparkles == nil,
    "Fresh settings must not expose the removed feature")
Check(fresh.ns.modules.gatheringSparkles == nil, "Removed gameplay module must not register")
Check(not fresh.ns.SetSetting("gatheringSparkles", "enabled", true), "Removed preference cannot be enabled")
Check(#fresh.writes == 0 and not fresh.driver, "Fresh installs create no cleanup frame or writes")
Check(#fresh.messages == 0, "Fresh installs do not announce a saved-data upgrade")

local upgraded = New(Saved())
for name, value in pairs(original) do Check(upgraded.cv[name] == value, "Restore still-owned " .. name) end
Check(upgraded.ns.db.gatheringSparkles == nil, "Completed migration deletes obsolete settings")
Check(not next(upgraded.driver.events), "Completed migration releases all subscriptions")
Check(#upgraded.messages == 1 and upgraded.messages[1]:find('savedvarsdb updated from "0" to "1"', 1, true),
    "Completed upgrade announces the saved-data version change once")
upgraded:fire("PLAYER_ENTERING_WORLD"); upgraded:flush()
Check(#upgraded.writes == 8 and #upgraded.messages == 1, "Completed cleanup never replays or re-announces")

local reloadedVersion = New({cvarVersion = 1})
Check(#reloadedVersion.messages == 0, "Already-current saved data must not announce on every login")

local emptyUpgrade = New({gatheringSparkles = {enabled = false, restore = {}}})
Check(#emptyUpgrade.messages == 1 and emptyUpgrade.messages[1]:find('"0" to "1"', 1, true),
    "Upgrading existing saved data announces even when there is nothing to restore")

local saved, current = Saved(), Copy(applied)
current.SoftTargetInteractRange = "8"
current.graphicsOutlineMode = "2"
saved.gatheringSparkles.restore.graphicsOutlineMode = {before = "0", applied = "2"}
saved.gatheringSparkles.restore.SoftTargetInteractArc.before = false
local foreign = New(saved, current)
Check(foreign.cv.SoftTargetInteractRange == "8", "Later targeting changes remain local")
Check(foreign.cv.graphicsOutlineMode == "2", "Legacy cleanup cannot acquire quest graphics variables")
Check(foreign.cv.SoftTargetInteractArc == "2", "Malformed restoration records do not write values")
Check(foreign.ns.db.gatheringSparkles == nil, "Foreign and invalid records do not prevent completion")

saved, current = Saved(), Copy(applied)
saved.gatheringSparkles.restore.SoftTargetNameplateInteract.applied = "1"
current.SoftTargetNameplateInteract = "1"
local node = New(saved, current)
Check(node.cv.SoftTargetNameplateInteract == "1" and node.ns.db.gatheringSparkles == nil,
    "Both former dynamic nameplate modes are recognized for cleanup")

local combat = New(Saved(), nil, {combat = true})
Check(#combat.writes == 0 and combat.driver.events.PLAYER_REGEN_ENABLED,
    "Upgrade in combat retains pending restoration")
Check(combat.ns.db.gatheringSparkles.enabled == nil, "Pending migration retains records, not the old toggle")
combat.ns.ResetSettings()
Check(combat.ns.db.gatheringSparkles.restore.SoftTargetInteract ~= nil, "Preference reset preserves pending migration")
local reloaded = New(combat.ns.db, combat.cv, {combat = true})
reloaded.combat = false
reloaded:fire("PLAYER_REGEN_ENABLED"); reloaded:flush()
Check(reloaded.cv.SoftTargetInteract == "0" and reloaded.ns.db.gatheringSparkles == nil,
    "Pending cleanup survives reload and finishes after combat")
Check(not next(reloaded.driver.events), "Combat completion returns to idle")

local unavailable = New(Saved(), nil, {noAPI = true})
Check(#unavailable.writes == 0 and unavailable.ns.db.gatheringSparkles ~= nil,
    "Unavailable console API retains legacy ownership")
unavailable:restoreAPI()
unavailable:fire("VARIABLES_LOADED"); unavailable:flush()
Check(unavailable.ns.db.gatheringSparkles == nil, "Readiness finishes cleanup without enabling any feature")

current = Copy(applied); current.SoftTargetInteractRange = nil
local missing = New(Saved(), current)
Check(#missing.writes == 0, "Unavailable owned variable defers the whole cleanup pass")
missing.cv.SoftTargetInteractRange = "15"
missing:fire("PLAYER_ENTERING_WORLD"); missing:flush()
Check(missing.cv.SoftTargetInteractRange == "10" and missing.ns.db.gatheringSparkles == nil,
    "A later world event retries unavailable variables")

local rejected = New(Saved(), nil, {reject = "SoftTargetInteractRange"})
Check(rejected.ns.errors.legacyCVars ~= nil and rejected.ns.db.gatheringSparkles.restore.SoftTargetInteractRange,
    "Rejected writes remain saved and report through the module boundary")
rejected:fire("CVAR_UPDATE", "unrelated")
Check(rejected:pending() == 0, "Unrelated console events do not retry cleanup")
rejected.reject = nil
rejected:fire("CVAR_UPDATE", "SoftTargetInteractRange"); rejected:flush()
Check(rejected.cv.SoftTargetInteractRange == "10" and rejected.ns.db.gatheringSparkles == nil,
    "Relevant readiness retries a rejected restoration")
Check(rejected.ns.errors.legacyCVars == nil and not next(rejected.driver.events),
    "Successful retry clears errors and subscriptions")

local malformed = New({gatheringSparkles = {enabled = true, restore = {arbitrary = {before = "0", applied = "1"}}}})
Check(malformed.ns.db.gatheringSparkles == nil and #malformed.writes == 0 and not malformed.driver,
    "Invalid legacy records are removed without creating an idle cleanup driver")
Check(fresh.ns.db.cvarVersion == 1, "Fresh installs checkpoint the empty first migration")
Check(upgraded.ns.db.cvarVersion == 1, "Owned cleanup checkpoints only after success")
Check(combat.ns.db.cvarVersion == 1, "Shared saved data retains the completed checkpoint after reload")

local empty = New({cvarVersion = 0}, nil, {combat = true, noAPI = true, beforeLogin = function(s)
    Check(s.ns.db.cvarVersion == 0, "Preparation never advances the checkpoint before login")
end})
Check(empty.ns.db.cvarVersion == 1 and #empty.writes == 0 and not empty.driver,
    "Empty migrations complete without console APIs or combat writes")
local completedData = Saved()
completedData.cvarVersion = 1
local completedLedger = completedData.gatheringSparkles
local completed = New(completedData)
Check(completed.ns.db.gatheringSparkles == completedLedger and #completed.writes == 0 and not completed.driver,
    "Completed migrations do not prepare or replay old steps")
completed.ns.ResetSettings()
Check(completed.ns.db.cvarVersion == 1 and #completed.writes == 0, "Reset cannot replay completed migrations")

local function QuestValues()
    return {
        outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "3",
        OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2",
        RetiredQuestEffect = "1",
    }
end
for _, version in ipairs({false, "1", {}, -1, 0.5, math.huge, 0 / 0, 2}) do
    local savedVersion = Saved()
    savedVersion.cvarVersion = version
    savedVersion.questLootSparkles = {enabled = true, restore = {RetiredQuestEffect = {before = "0", applied = "1"}}}
    local legacy, quest = savedVersion.gatheringSparkles, savedVersion.questLootSparkles.restore
    local blocked = New(savedVersion, QuestValues(), {quest = true})
    Check(#blocked.writes == 0 and blocked.ns.db.gatheringSparkles == legacy
        and blocked.ns.db.questLootSparkles.restore == quest,
        "Unsupported versions preserve both ledgers before any CVar writes or sanitization")
    Check((version ~= version and blocked.ns.db.cvarVersion ~= blocked.ns.db.cvarVersion)
        or blocked.ns.db.cvarVersion == version, "Unsupported raw version remains unchanged")
    Check(not blocked.driver and not next(blocked.frames[2].events),
        "Unsupported versions cannot spin readiness or active feature events")
    blocked.ns.ResetSettings()
    Check(#blocked.writes == 0 and blocked.ns.db.gatheringSparkles == legacy
        and blocked.ns.db.questLootSparkles.restore == quest,
        "Reset preserves unknown-version restoration records")
    Check(blocked.ns.GetStatus("questLootSparkles"):find("version", 1, true),
        "Active features explain the version barrier")
end

for _, failure in ipairs({"throw", "silent"}) do
    local failedWrite = New(Saved(), nil, {[failure] = "SoftTargetInteractRange"})
    Check(failedWrite.ns.db.cvarVersion == nil and failedWrite.ns.errors.legacyCVars
        and failedWrite.ns.db.gatheringSparkles.restore.SoftTargetInteractRange.before == "10",
        "A " .. failure .. " write cannot advance the checkpoint or erase pending ownership")
    failedWrite[failure] = nil
    failedWrite:fire("PLAYER_ENTERING_WORLD"); failedWrite:flush()
    Check(failedWrite.ns.db.cvarVersion == 1 and failedWrite.cv.SoftTargetInteractRange == "10"
        and failedWrite.ns.errors.legacyCVars == nil, "Verified retry completes the failed migration")
end

local function AddQuestMigration(ns)
    ns.cvarMigrations[2] = {
        settingsKey = "questLootSparkles",
        values = {{"graphicsOutlineMode", "3"}, {"RetiredQuestEffect", "1"}},
    }
end
local function QuestSaved()
    local savedVersion = Saved()
    savedVersion.questLootSparkles = {enabled = true, restore = {
        graphicsOutlineMode = {before = "2", applied = "3"},
        RetiredQuestEffect = {before = "0", applied = "1"},
    }}
    return savedVersion
end
local currentQuest = QuestValues()
for name, value in pairs(applied) do currentQuest[name] = value end
local partial = New(QuestSaved(), currentQuest, {quest = true, configure = AddQuestMigration,
    reject = "RetiredQuestEffect", beforeLogin = function(s)
        Check(s.ns.db.questLootSparkles.restore.RetiredQuestEffect ~= nil,
            "Latest feature validation cannot discard historical ownership before migration")
    end})
Check(partial.ns.db.cvarVersion == 1 and partial.ns.db.gatheringSparkles == nil,
    "Each successful step checkpoints before a later failure")
Check(partial.cv.graphicsOutlineMode == "2" and partial.cv.RetiredQuestEffect == "1",
    "Failed historical cleanup blocks the latest feature policy")
Check(partial.ns.db.questLootSparkles.restore.RetiredQuestEffect ~= nil,
    "Failed historical writes retain their original baseline")
local resumed = New(partial.ns.db, partial.cv, {quest = true, configure = AddQuestMigration})
Check(resumed.ns.db.cvarVersion == 2 and resumed.cv.RetiredQuestEffect == "0"
    and resumed.cv.graphicsOutlineMode == "0", "Reload completes remaining cleanup before latest quest application")
Check(resumed.ns.db.questLootSparkles.restore.graphicsOutlineMode.before == "2",
    "New policy acquires the original baseline, not the previous owned mode")
for _, name in ipairs(resumed.writes) do
    Check(not applied[name], "Reload must not replay an already-completed targeting migration")
end
local writes = #resumed.writes
resumed:fire("PLAYER_ENTERING_WORLD"); resumed:flush()
Check(#resumed.writes == writes, "Ready lifecycle events do not repeat completed cleanup or unchanged writes")
resumed.ns.SetSetting("questLootSparkles", "enabled", false)
Check(resumed.cv.graphicsOutlineMode == "2", "Disabling the new policy restores the pre-migration baseline")

local resetValues = QuestValues()
for name, value in pairs(applied) do resetValues[name] = value end
local reset = New(QuestSaved(), resetValues, {quest = true, configure = AddQuestMigration,
    reject = "RetiredQuestEffect"})
reset.ns.ResetSettings()
Check(reset.ns.db.cvarVersion == 1 and not reset.ns.db.questLootSparkles.enabled
    and reset.ns.db.questLootSparkles.restore.RetiredQuestEffect ~= nil,
    "Reset retains a pending active migration and its checkpoint but disables the feature")
reset.reject = nil
reset:fire("PLAYER_ENTERING_WORLD"); reset:flush()
Check(reset.ns.db.cvarVersion == 2 and reset.cv.graphicsOutlineMode == "2"
    and not reset.ns.db.questLootSparkles.enabled, "Cleanup completion cannot resurrect pre-reset preferences")
Check(not next(reset.ns.db.questLootSparkles.restore), "Disabled current policy acquires no new ownership")

local firstValues = QuestValues()
for name, value in pairs(applied) do firstValues[name] = value end
local firstFailure = New(QuestSaved(), firstValues, {quest = true, configure = AddQuestMigration,
    reject = "SoftTargetInteractRange"})
Check(firstFailure.ns.db.cvarVersion == nil and firstFailure.ns.db.questLootSparkles.restore.RetiredQuestEffect,
    "A failed first step cannot run or checkpoint later steps")
print("LegacyCVars: " .. checks .. " checks passed")
