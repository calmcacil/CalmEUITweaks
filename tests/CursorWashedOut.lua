local checks = 0
local function Check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local function New(saved, current)
    local ns, frames, timers, errors, writes = {}, {}, {}, {}, {}
    local combat = false
    local cv = current or { HardwareCursor = "1" }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.CalmUITweaksDB = saved or {}
    if saved then saved.calm_forever, saved.schemaVersion = true, 1 end
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
        "functions/CursorWashedOut.lua" }) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
    end
    s.driver = frames[2]
    function s:flush()
        local turns = 0
        while #timers > 0 do
            turns = turns + 1
            assert(turns < 10, "Cursor callbacks must settle")
            local batch = timers
            timers = {}
            for _, callback in ipairs(batch) do callback() end
        end
    end
    function s:pending() return #timers end
    function s:combat(value) combat = value end
    function s:enable(value) ns.SetSetting("cursorWashedOut", "enabled", value) end
    s:fire("ADDON_LOADED", "CalmEUITweaks")
    s:fire("PLAYER_LOGIN")
    s:flush()
    return s
end

local off = New()
Check(not off.ns.db.cursorWashedOut.enabled and #off.writes == 0 and not next(off.driver.events),
    "Default-off cursor fix must not change the native preference or subscribe")
off:enable(true)
Check(off.cv.HardwareCursor == "0" and #off.writes == 1 and off:pending() == 0,
    "Enable must disable only the hardware cursor without reacting to its own write")
off:fire("CVAR_UPDATE", "unrelated")
Check(off:pending() == 0, "Unrelated CVar changes must not schedule cursor work")
off.ns.CallModule("cursorWashedOut", "ApplySettings")
Check(#off.writes == 1 and not off.driver.events.PLAYER_REGEN_ENABLED,
    "Unchanged state must not write again or listen for combat end")
off:enable(false)
Check(off.cv.HardwareCursor == "1" and not next(off.driver.events),
    "Disable must restore the owned value and release subscriptions")

local enabled = New({ cursorWashedOut = { enabled = true } })
local reloaded = New(enabled.ns.db, enabled.cv)
reloaded:enable(false)
Check(reloaded.cv.HardwareCursor == "1", "Restoration ownership must survive reload")
local inherited = New(nil, { HardwareCursor = "0" })
inherited:enable(true)
inherited:enable(false)
Check(#inherited.writes == 0 and inherited.cv.HardwareCursor == "0",
    "A preexisting workaround must remain untouched on enable and disable")
local external = New({ cursorWashedOut = { enabled = true } })
external.cv.HardwareCursor = "1"
local count = #external.writes
external:enable(false)
Check(external.cv.HardwareCursor == "1" and #external.writes == count,
    "Disable must preserve later external writes")

local deferred = New()
deferred:combat(true)
deferred:enable(true)
Check(#deferred.writes == 0 and deferred.driver.events.PLAYER_REGEN_ENABLED,
    "Enable in combat must wait")
deferred:enable(false)
Check(not next(deferred.driver.events), "Cancelling deferred enable must release listeners")
deferred:combat(false)
deferred:enable(true)
deferred:combat(true)
deferred.ns.ResetSettings()
Check(deferred.cv.HardwareCursor == "0" and deferred.ns.db.cursorWashedOut.restore.HardwareCursor,
    "Reset must retain ownership until deferred restoration completes")
deferred:combat(false)
deferred:fire("PLAYER_REGEN_ENABLED")
deferred:flush()
Check(deferred.cv.HardwareCursor == "1" and not next(deferred.driver.events),
    "Combat end must complete reset restoration and release listeners")

local refresh = New({ cursorWashedOut = { enabled = true } })
refresh.cv.HardwareCursor = "1"
refresh:fire("CVAR_UPDATE", "HARDWARECURSOR")
refresh:fire("CVAR_UPDATE", "HardwareCursor")
Check(refresh:pending() == 1, "Relevant external changes must coalesce")
refresh:flush()
Check(refresh.cv.HardwareCursor == "0", "Enabled fix must reapply after external changes")
refresh:fire("PLAYER_ENTERING_WORLD")
refresh:enable(false)
count = #refresh.writes
refresh:flush()
Check(#refresh.writes == count and not next(refresh.driver.events),
    "Queued callbacks cannot reenable a disabled fix")

local missing = New(nil, {})
missing:enable(true)
Check(#missing.writes == 0 and missing.ns.GetStatus("cursorWashedOut"):find("HardwareCursor"),
    "Unsupported CVar must wait without writing")
missing.cv.HardwareCursor = "1"
missing:fire("VARIABLES_LOADED")
missing:flush()
Check(missing.cv.HardwareCursor == "0", "Variable readiness must recover the fix")
missing.env.C_CVar = nil
missing:enable(false)
Check(missing.ns.db.cursorWashedOut.restore.HardwareCursor and
    missing.ns.GetStatus("cursorWashedOut"):find("Waiting"), "Missing APIs must retain restoration")

local failed = New()
failed.reject = "HardwareCursor"
failed:enable(true)
Check(failed.ns.errors.cursorWashedOut ~= nil, "Rejected writes must report through the module boundary")
failed.reject = nil
failed:fire("PLAYER_ENTERING_WORLD")
failed:flush()
Check(not failed.ns.errors.cursorWashedOut and failed.cv.HardwareCursor == "0",
    "Readiness must recover a rejected write")
failed.throw = "HardwareCursor"
failed.ns.ResetSettings()
Check(failed.ns.errors.cursorWashedOut and failed.ns.db.cursorWashedOut.restore.HardwareCursor,
    "Failed reset restoration must retain ownership")
failed.throw = nil
failed:fire("PLAYER_ENTERING_WORLD")
failed:flush()
Check(failed.cv.HardwareCursor == "1" and not next(failed.driver.events),
    "Later readiness must finish failed restoration")

local malformed = New({ cursorWashedOut = { restore = {
    arbitrary = { before = "1", applied = "0" },
    HardwareCursor = { before = false, applied = "0" },
} } })
Check(#malformed.writes == 0 and not next(malformed.ns.db.cursorWashedOut.restore),
    "Malformed ownership cannot write native settings")

print("CursorWashedOut: " .. checks .. " checks passed")

