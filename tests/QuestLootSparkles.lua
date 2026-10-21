local checks = 0
local function Check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local names = {
    "outlineModeShowLootEffectWhenDisabled", "graphicsOutlineMode", "OutlineEngineMode",
    "raidGraphicsOutlineMode", "RAIDOutlineEngineMode",
}
local function New(saved, current)
    local ns, frames, timers, errors, writes = {}, {}, {}, {}, {}
    local combat = false
    local cv = current or {
        outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "1",
        OutlineEngineMode = "1", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2",
    }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.CalmUITweaksDB = saved or {}
    env.print = function() end
    env.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    env.InCombatLockdown = function() return combat end
    env.IsLoggedIn = function() return false end
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(key, callback) self.scripts[key] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    local s = { ns = ns, env = env, cv = cv, writes = writes, errors = errors }
    function s:fire(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    env.C_CVar = {
        GetCVar = function(name) return cv[name] end,
        SetCVar = function(name, value)
            if s.reject == name then return false end
            if s.throw == name then error("native setter failure") end
            writes[#writes + 1] = { name, value }
            cv[name] = value
            s:fire("CVAR_UPDATE", name, value)
            return true
        end,
    }
    env.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    for _, file in ipairs({ "core/Bootstrap.lua", "core/Settings.lua", "core/CVars.lua", "core/Migrations.lua", "core/Lifecycle.lua",
        "functions/QuestLootSparkles.lua" }) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
    end
    s.driver = frames[2]
    function s:flush()
        local turns = 0
        while #timers > 0 do
            turns = turns + 1
            assert(turns < 10, "Sparkle callbacks must settle")
            local batch = timers
            timers = {}
            for _, callback in ipairs(batch) do callback() end
        end
    end
    function s:pending() return #timers end
    function s:combat(value) combat = value end
    function s:enable(value) ns.SetSetting("questLootSparkles", "enabled", value) end
    s:fire("ADDON_LOADED", "CalmEUITweaks")
    s:fire("PLAYER_LOGIN")
    s:flush()
    return s
end

local off = New()
Check(off.ns.db.questLootSparkles.enabled == false, "Quest sparkles must default off")
Check(#off.writes == 0 and not next(off.driver.events), "Disabled feature must be idle")
off:fire("CVAR_UPDATE", "graphicsQuality")
Check(off:pending() == 0, "Disabled feature must not schedule graphics work")

off:enable(true)
for index, name in ipairs(names) do
    Check(off.cv[name] == (index == 1 and "1" or "0"), "Enable must apply native sparkle settings")
end
Check(#off.writes == 5 and off:pending() == 0, "Own CVAR_UPDATE events must not schedule more work")
Check(not off.driver.events.PLAYER_REGEN_ENABLED, "Combat listener must be absent without pending work")
off.ns.CallModule("questLootSparkles", "ApplySettings")
Check(#off.writes == 5, "Unchanged graphics values must not be written again")
off:fire("CVAR_UPDATE", "unrelated")
Check(off:pending() == 0, "Unrelated graphics events must not schedule work")
off.cv.graphicsOutlineMode = "2"
off:fire("CVAR_UPDATE", "GRAPHICSQUALITY")
off:fire("CVAR_UPDATE", "graphicsOutlineMode")
Check(off:pending() == 1, "Graphics changes must coalesce")
off:flush()
Check(off.cv.graphicsOutlineMode == "0", "Graphics presets must reapply the sparkle mode")
off:enable(false)
Check(off.cv.graphicsOutlineMode == "2", "Disable must restore the latest external preference")
Check(off.cv.OutlineEngineMode == "1" and off.cv.RAIDOutlineEngineMode == "2",
    "Disable must restore saved values rather than forcing High outlines")
Check(off.cv.outlineModeShowLootEffectWhenDisabled == "0", "Disable must restore native sparkle preference")
Check(not next(off.driver.events) and not next(off.ns.db.questLootSparkles.restore),
    "Disable must release subscriptions and completed ownership")

local enabled = New({ questLootSparkles = { enabled = true } })
local reloaded = New(enabled.ns.db, enabled.cv)
reloaded:enable(false)
Check(reloaded.cv.graphicsOutlineMode == "1" and reloaded.cv.outlineModeShowLootEffectWhenDisabled == "0",
    "Restoration ownership must survive reload and character switches")

local external = New({ questLootSparkles = { enabled = true } })
external.cv.OutlineEngineMode = "2"
external:enable(false)
Check(external.cv.OutlineEngineMode == "2", "Disable must preserve later external writes")

local deferred = New()
deferred:combat(true)
deferred:enable(true)
Check(#deferred.writes == 0 and deferred.driver.events.PLAYER_REGEN_ENABLED,
    "Enabling in combat must defer writes")
deferred:enable(false)
Check(not next(deferred.driver.events), "Cancelling an unstarted enable must release combat listener")
deferred:combat(false)
deferred:enable(true)
deferred:combat(true)
deferred.ns.ResetSettings()
Check(deferred.driver.events.PLAYER_REGEN_ENABLED and deferred.cv.graphicsOutlineMode == "0",
    "Reset in combat must retain pending restoration")
deferred:combat(false)
deferred:fire("PLAYER_REGEN_ENABLED")
deferred:flush()
Check(deferred.cv.graphicsOutlineMode == "1" and not next(deferred.driver.events),
    "Combat end must finish reset restoration and release listener")

local queued = New({ questLootSparkles = { enabled = true } })
queued:fire("PLAYER_ENTERING_WORLD")
queued:enable(false)
local writeCount = #queued.writes
queued:flush()
Check(#queued.writes == writeCount and not queued.ns.db.questLootSparkles.enabled,
    "A queued enabled refresh must not reenable a disabled feature")

local unavailable = New()
unavailable.env.C_CVar = nil
unavailable:enable(true)
Check(#unavailable.writes == 0 and unavailable.ns.GetStatus("questLootSparkles"):find("Waiting"),
    "Missing native API must wait without errors")
local missing = New()
missing.cv.RAIDOutlineEngineMode = nil
missing:enable(true)
Check(#missing.writes == 0 and missing.ns.GetStatus("questLootSparkles"):find("RAIDOutlineEngineMode"),
    "Missing graphics variable must not leave a partial enable")
missing.cv.RAIDOutlineEngineMode = "2"
missing:fire("VARIABLES_LOADED")
missing:flush()
Check(#missing.writes == 5, "Readiness event must recover missing graphics variables")

local failed = New()
failed.reject = "OutlineEngineMode"
failed:enable(true)
Check(failed.ns.errors.questLootSparkles ~= nil, "Rejected native writes must report an error")
failed.reject = nil
failed:fire("CVAR_UPDATE", "graphicsQuality")
failed:flush()
Check(failed.ns.errors.questLootSparkles == nil and failed.cv.OutlineEngineMode == "0",
    "Reported write failure must recover on a later graphics change")
failed.throw = "OutlineEngineMode"
failed:enable(false)
Check(failed.ns.errors.questLootSparkles ~= nil and failed.ns.db.questLootSparkles.restore.OutlineEngineMode,
    "Failed restoration must retain ownership for retry")
failed.throw = nil
failed.ns.CallModule("questLootSparkles", "ApplySettings")
Check(failed.ns.errors.questLootSparkles == nil and failed.cv.OutlineEngineMode == "1",
    "Restoration retry must recover a thrown native error")

local inherited = New({}, {
    outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0",
    OutlineEngineMode = "0", raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0",
})
inherited:enable(true)
inherited:enable(false)
Check(#inherited.writes == 0, "Already configured values must not acquire restoration ownership")
local restoreMissing = New({ questLootSparkles = { enabled = true } })
restoreMissing.cv.OutlineEngineMode = nil
restoreMissing:enable(false)
Check(restoreMissing.ns.db.questLootSparkles.restore.OutlineEngineMode ~= nil,
    "Temporarily unavailable variables must retain pending restoration")
restoreMissing.cv.OutlineEngineMode = "0"
restoreMissing:fire("PLAYER_ENTERING_WORLD")
restoreMissing:flush()
Check(restoreMissing.cv.OutlineEngineMode == "1" and not next(restoreMissing.driver.events),
    "Pending restoration must recover when native graphics settings become ready")
local malformed = New({ questLootSparkles = { restore = {
    arbitrary = { before = "1", applied = "0" },
    graphicsOutlineMode = { before = false, applied = "0" },
    OutlineEngineMode = { before = "2", applied = "2" },
} } })
Check(#malformed.writes == 0 and not next(malformed.ns.db.questLootSparkles.restore),
    "Invalid saved ownership must not write arbitrary variables")

print("QuestLootSparkles: " .. checks .. " checks passed")
