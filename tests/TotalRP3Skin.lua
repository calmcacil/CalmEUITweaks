local root = "CalmEUITweaks/"
local checks, tests = 0, 0

local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function Contains(value, text)
    Check(type(value) == "string" and value:find(text, 1, true),
        "Expected '" .. tostring(value) .. "' to contain '" .. text .. "'")
end

local function Test(name, callback)
    callback()
    tests = tests + 1
    print("PASS Total RP 3 skin: " .. name)
end

local function Fixture(options)
    options = options or {}
    local s = {
        ns = {}, frames = {}, timers = {}, errors = {}, registrations = 0,
        applications = 0, hookCalls = 0, surfaceHooks = 0, refreshes = 0,
        trpLoaded = options.loaded ~= false, euiEnabled = options.euiEnabled ~= false,
        combat = options.combat == true, activeEdit = options.editing == true,
        editSession = options.editing == true, summary = { applied = 4 },
        registrationFailure = options.registrationFailure == true,
    }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    s.env = env
    env.CalmUITweaksDB = options.blocked and {
        calm_forever = true, schemaVersion = 999,
        totalRP3Skin = { enabled = true },
    } or {
        calm_forever = true, schemaVersion = 1,
        totalRP3Skin = { enabled = options.enabled == true, future = "preserved" },
    }
    env.IsLoggedIn = function() return options.lateLogin == true end
    env.InCombatLockdown = function() return s.combat end
    env.geterrorhandler = function()
        return function(err) s.errors[#s.errors + 1] = tostring(err) end
    end
    env.print = function() end
    env.C_AddOns = { IsAddOnLoaded = function(name)
        Check(name == "totalRP3", "Only TRP3 dependency readiness may be queried")
        if s.singleLoadFlag then return s.trpLoaded end
        return s.trpLoaded or s.trpLoading, s.trpLoaded
    end }
    env.C_Timer = { After = function(delay, callback)
        Check(delay == 0, "Only the shared bounded coalescer may schedule work")
        s.timers[#s.timers + 1] = callback
    end }
    if options.trpCallbacks then
        env.TRP3_Addon = {
            RegisterCallback = function(owner, event, callback)
                Check(event == "PAGE_OPENED", "Only relevant TRP3 navigation may be subscribed")
                s.pageOwner, s.pageCallback = owner, callback
                s.pageRegistrations = (s.pageRegistrations or 0) + 1
            end,
            UnregisterCallback = function(owner, event)
                Check(owner == s.pageOwner and event == "PAGE_OPENED", "Only owned TRP3 callback is removed")
                s.pageCallback = nil
            end,
        }
    end
    env.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(script, callback)
            Check(script == "OnEvent", "Skinning must not install OnUpdate")
            self.callback = callback
        end
        s.frames[#s.frames + 1] = frame
        return frame
    end
    local skin = {}
    s.skin = skin
    skin.IsEnabled = function(...)
        Check(select("#", ...) == 0, "S.IsEnabled is a function call")
        return s.euiEnabled
    end
    skin.OnLooksChanged = function(callback, ...)
        Check(select("#", ...) == 0 and type(callback) == "function", "S.OnLooksChanged signature")
        s.looksCallback = callback
    end
    local eui = {}
    s.eui, env.EllesmereUI = eui, eui
    function s:installSkinAPI()
        eui.RegisterSkin = function(name, callback, ...)
            Check(name == "CalmEUITweaks" and select("#", ...) == 0,
                "RegisterSkin must use the folder name and a function call")
            self.registrations = self.registrations + 1
            if self.registrationFailure then error("skin registration failed") end
            self.skinCallback = callback
            if self.euiEnabled and not self.delayCallback then callback(self.skin) end
            -- EUI documents no registration return value.
        end
    end
    s.delayCallback = options.delayCallback
    if not options.missingAPI then s:installSkinAPI() end
    function eui:IsUnlockModeActive()
        Check(self == eui, "Unlock Mode query must use a method call")
        return s.activeEdit
    end
    function eui:RegisterUnlockModeListener(owner, callback)
        Check(self == eui and owner == "CalmEUITweaks_TotalRP3Skin", "Unlock listener owner")
        s.listener = callback
        if s.editSession then callback(true) end
    end
    function eui:UnregisterUnlockModeListener(owner)
        Check(self == eui and owner == "CalmEUITweaks_TotalRP3Skin", "Unlock listener removal")
        s.listener = nil
    end
    s.ns.TotalRP3SkinFrames = {
        ClearPending = function() s.pendingClears = (s.pendingClears or 0) + 1 end,
        PageOpened = function(page, context)
            s.pageVisits = (s.pageVisits or 0) + 1
            s.lastPage, s.lastContext = page, context
        end,
        InstallHooks = function(supplied, allowed, report)
            Check(supplied == skin and type(allowed) == "function" and type(report) == "function",
                "Surface hooks need the supplied API and guarded callbacks")
            s.hookCalls = s.hookCalls + 1
            if not s.allowed then s.surfaceHooks = s.surfaceHooks + 1 end
            s.allowed, s.report = allowed, report
        end,
        Apply = function(supplied, allowed, report)
            Check(supplied == skin and allowed(), "Surface application must be allowed")
            Check(not s.combat and not s.editSession, "No surface writes in combat or active editing")
            s.applications = s.applications + 1
            if s.surfaceFailure then report("main window", "surface failed")
            elseif s.surfaceRecovery then report("main window") end
            if s.otherSurfaceFailure then report("toolbar", "other failure")
            elseif s.otherSurfaceRecovery then report("toolbar") end
            return s.summary
        end,
    }
    for _, path in ipairs({
        "core/Bootstrap.lua", "core/Settings.lua", "core/CVars.lua", "core/Migrations.lua",
        "core/Lifecycle.lua", "functions/TotalRP3Skin.lua",
    }) do
        local chunk = assert(loadfile(root .. path))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", s.ns)
    end
    s.ns.RefreshOptions = function() s.refreshes = s.refreshes + 1 end
    function s:fire(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] then frame.callback(frame, event, ...) end
        end
    end
    function s:flush()
        local batches = 0
        while #self.timers > 0 do
            batches = batches + 1
            Check(batches < 8, "Deferred skin work must terminate without polling")
            local batch = self.timers
            self.timers = {}
            for _, callback in ipairs(batch) do callback() end
        end
    end
    function s:set(value)
        local ok, reason = self.ns.SetSetting("totalRP3Skin", "enabled", value)
        Check(ok, reason)
    end
    function s:status() return self.ns.GetStatus("totalRP3Skin") end
    function s:watchingCombat()
        for _, frame in ipairs(self.frames) do
            if frame.events.PLAYER_REGEN_ENABLED then return true end
        end
        return false
    end
    function s:session(value)
        self.activeEdit, self.editSession = value, value
        if self.listener then self.listener(value) end
    end
    function s:load(name)
        self:fire("ADDON_LOADED", name)
        self:flush()
    end
    s:fire("ADDON_LOADED", "CalmEUITweaks")
    if not options.noLogin and not options.lateLogin then s:fire("PLAYER_LOGIN") end
    s:flush()
    return s
end

Test("default off has no skin registrations or feature subscriptions", function()
    local s = Fixture()
    Check(s.ns.GetSettings("totalRP3Skin").enabled == false, "Skin defaults off")
    Check(s:status() == "Disabled", "Off status")
    Check(s.registrations == 0 and s.applications == 0 and not s.listener, "Default off must be inert")
    Check(not s:watchingCombat() and #s.timers == 0, "Default off has no deferred work")
    s:load("totalRP3")
    Check(s.registrations == 0, "Dependency load must not activate default-off skin")
end)

Test("initial activation accepts EUI's absent registration result", function()
    local s = Fixture({ enabled = true })
    Check(s.registrations == 1 and s.applications >= 1, "The supplied callback activates styling")
    Check(s:status():find("Active", 1, true), "Successful skin status")
    Check(#s.errors == 0 and not s:watchingCombat(), "Successful setup leaves no error or combat wait")
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.registrations == 1 and s.surfaceHooks == 1, "Repeated application delegates idempotent hook ownership")
    Check(#s.timers == 0, "Active skin does not poll")
end)

Test("late TRP3 and EUI readiness recover through relevant addon events", function()
    for _, missing in ipairs({ "trp", "api" }) do
        local s = Fixture({ enabled = true, loaded = missing ~= "trp", missingAPI = missing == "api" })
        Check(s.registrations == 0 and s.applications == 0, "Missing dependency must wait")
        Contains(s:status(), "Waiting")
        s:load("UnrelatedAddon")
        Check(s.registrations == 0 and #s.timers == 0, "Unrelated addon loads do not schedule skin work")
        if missing == "trp" then s.trpLoaded = true; s:load("totalRP3")
        else s:installSkinAPI(); s:load("EllesmereUIBlizzardSkin") end
        Check(s.registrations == 1 and s.applications >= 1, "Late dependency readiness must recover")
    end
    local s = Fixture({ enabled = true, lateLogin = true })
    Check(s.ns.ready and s.applications >= 1, "Post-login addon initialization must activate")
end)

Test("loads in progress do not count as completed dependencies", function()
    local s = Fixture({ enabled = true, loaded = false })
    s.trpLoading = true
    s:load("totalRP3")
    Check(s.registrations == 0, "The completed-load flag takes precedence")
    s.singleLoadFlag, s.trpLoaded = true, true
    s:load("totalRP3")
    Check(s.registrations == 1, "Clients reporting one load flag remain supported")
end)

Test("suppressed or delayed EUI callback is reported without guessing opt-out", function()
    for _, settings in ipairs({ { enabled = true, euiEnabled = false }, { enabled = true, delayCallback = true } }) do
        local s = Fixture(settings)
        Check(s.registrations == 1 and s.applications == 0, "No callback means no styling")
        Contains(s:status(), "Waiting for EUI skin callback")
        Check(not s:watchingCombat() and not s.listener and #s.errors == 0, "Waiting must be idle and non-error")
        s.euiEnabled = true
        s.skinCallback(s.skin)
        s:flush()
        Check(s.applications >= 1 and s.registrations == 1, "A later supplied callback activates once")
        s.euiEnabled = false
        s.looksCallback()
        Contains(s:status(), "Disabled in EUI")
        Check(not s.listener and not s:watchingCombat() and not s.allowed(), "EUI opt-out releases waits and guards hooks")
    end
end)

Test("registration exception can recover on later provider readiness", function()
    local s = Fixture({ enabled = true, registrationFailure = true })
    Check(s.registrations == 1 and s.applications == 0, "A rejected boundary cannot reach surfaces")
    Contains(s:status(), "skin registration failed")
    s.registrationFailure, s.surfaceRecovery = false, true
    s:load("EllesmereUIBlizzardSkin")
    Check(s.registrations == 2 and s.applications >= 1, "A failed registration must not commit its checkpoint")
    Check(s.ns.errors.totalRP3Skin == nil, "Successful surface initialization recovers registration errors")
    s:load("EllesmereUIBlizzardSkin")
    Check(s.registrations == 2, "Successful registration remains once per session")
end)

Test("EUI reenable resumes work cancelled before the first surface application", function()
    local s = Fixture({ enabled = true, combat = true })
    Check(s.applications == 0 and s:watchingCombat(), "First styling is pending combat")
    s.euiEnabled = false
    s.looksCallback()
    Check(not s:watchingCombat() and not s.listener, "EUI opt-out cancels the pending wait")
    s.combat = false
    s.euiEnabled = true
    s.looksCallback()
    s:flush()
    Check(s.applications >= 1 and s.registrations == 1, "EUI reenable resumes without another dependency event")
    s.looksCallback()
    Check(#s.timers == 0, "Ordinary theme notifications do not schedule full surface passes")
end)

Test("changes after login require reload and disable immediately guards hooks", function()
    local s = Fixture()
    s:set(true)
    Contains(s:status(), "Reload required")
    Check(s.registrations == 0 and s.applications == 0, "Enabling after login waits for reload")
    s:set(false)
    Check(s:status() == "Disabled", "Cancelling a pending enable restores disabled state")
    s = Fixture({ enabled = true })
    local before = s.applications
    s:set(false)
    Contains(s:status(), "Reload required")
    Check(not s.allowed() and not s.listener and not s:watchingCombat(), "Disable makes retained hooks inert")
    s:load("totalRP3")
    Check(s.applications == before, "Later readiness must not skin after disable")
    s:set(true)
    Check(s.applications > before and s.registrations == 1, "Restoring the session preference reuses registration")
end)

Test("combat deferral resumes latest settings and releases combat events", function()
    local s = Fixture({ enabled = true, combat = true })
    Check(s.applications == 0 and s:watchingCombat(), "Combat must defer initial surface writes")
    Contains(s:status(), "Waiting for combat")
    s.combat = false
    s:fire("PLAYER_REGEN_ENABLED")
    s:flush()
    Check(s.applications >= 1 and not s:watchingCombat(), "Combat end resumes and unregisters")
    s.combat = true
    Check(not s.allowed() and s:watchingCombat(), "Dynamic surface writes use the same combat guard")
    local before = s.applications
    s:set(false)
    s.combat = false
    s:fire("PLAYER_REGEN_ENABLED")
    s:flush()
    Check(s.applications == before and not s:watchingCombat(), "Disable cancels pending combat styling")
end)

Test("Unlock Mode session remains protected when its visible editor is suspended", function()
    local s = Fixture({ enabled = true, editing = true })
    Check(s.applications == 0 and s.listener, "Editing defers setup through native listener")
    Contains(s:status(), "Waiting for EUI Unlock Mode")
    s.activeEdit = false
    s.combat = true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    s.combat = false
    s:fire("PLAYER_REGEN_ENABLED")
    s:flush()
    Check(s.applications == 0, "A combat-suspended session is still editing")
    s:session(false)
    s:flush()
    Check(s.applications >= 1 and not s:watchingCombat(), "Closing the session resumes skinning")
    s:session(true)
    Check(not s.allowed(), "Dynamic writes defer during later editing")
    local before = s.applications
    s:set(false)
    s:session(false)
    s:flush()
    Check(s.applications == before and not s.listener, "Disable while editing cancels pending styling")
end)

Test("surface status distinguishes missing frames, conflicts and partial coverage", function()
    local s = Fixture({ enabled = true })
    s.summary = { applied = 0 }
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Contains(s:status(), "Waiting for supported")
    s.summary = { applied = 2, unsupported = "toolbar widget changed" }
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Contains(s:status(), "Partial coverage: toolbar widget changed")
    s.summary = { applied = 2, conflict = "another TRP3 skin" }
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Contains(s:status(), "Conflict: another TRP3 skin")
end)

Test("TRP3 navigation callbacks retain context and detach on disable", function()
    local s = Fixture({ enabled = true, trpCallbacks = true })
    Check(s.pageRegistrations == 1 and s.pageCallback, "Ready skin subscribes once to navigation")
    local context = { profile = "unchanged" }
    s.pageCallback(s.pageOwner, "main_config_toolbar", context)
    Check(s.lastPage == "main_config_toolbar" and s.lastContext == context,
        "TRP3 callback context passes through without rewriting data")
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.pageRegistrations == 1, "Repeated application cannot duplicate navigation callbacks")
    local retained = s.pageCallback
    local visits = s.pageVisits
    s:set(false)
    Check(not s.pageCallback and s.pendingClears > 0, "Disable removes callbacks and queued surface work")
    retained(s.pageOwner, "main_config_toolbar", context)
    Check(s.pageVisits == visits, "An already-dispatched callback cannot bypass disable")
    s:set(true)
    Check(s.pageRegistrations == 2 and s.pageCallback, "Reenable attaches one replacement callback")
end)

Test("surface errors are isolated, deduplicated and clear only after all recover", function()
    local s = Fixture({ enabled = true })
    s.surfaceFailure = true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Contains(s:status(), "main window: surface failed")
    local count, applications = #s.errors, s.applications
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(#s.errors == count and s.applications > applications, "Repeated error does not spam or stop safe surfaces")
    s.otherSurfaceFailure = true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    s.surfaceFailure, s.surfaceRecovery = false, true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.ns.errors.totalRP3Skin ~= nil, "One healthy surface cannot clear another surface failure")
    s.otherSurfaceFailure, s.otherSurfaceRecovery = false, true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.ns.errors.totalRP3Skin == nil, "All recovered surfaces release the error")
    s.surfaceFailure = true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(#s.errors > count, "A later recurrence is reported again")
    s:set(false)
    Check(s.ns.errors.totalRP3Skin == nil, "Disable releases feature errors as well as pending activity")
    Contains(s:status(), "Reload required")
end)

Test("EUI opt-out clears stale errors before surface failure identities are discarded", function()
    local s = Fixture({ enabled = true })
    s.surfaceFailure = true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.ns.errors.totalRP3Skin ~= nil, "A failing surface establishes an owned error")
    s.euiEnabled = false
    s.looksCallback()
    Check(s.ns.errors.totalRP3Skin == nil, "EUI opt-out releases the owned error")
    Contains(s:status(), "Disabled in EUI")
    s.surfaceFailure = false
    s.euiEnabled = true
    s.looksCallback()
    s:flush()
    Check(s.ns.errors.totalRP3Skin == nil, "Reenabled surfaces cannot retain a discarded failure identity")
    Contains(s:status(), "Active")
    s.surfaceFailure = true
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.ns.errors.totalRP3Skin ~= nil, "Reenable does not suppress a new real failure")
    s.euiEnabled = false
    s.ns.CallModule("totalRP3Skin", "ApplySettings")
    Check(s.ns.errors.totalRP3Skin == nil, "Applying a provider opt-out also clears errors without a theme event")
end)

Test("saved-data readiness delays feature initialization and reset preserves unknown fields", function()
    local s = Fixture({ enabled = true, noLogin = true })
    Check(not s.ns.ready and s.registrations == 0, "Before login the skin cannot register")
    s:fire("PLAYER_LOGIN")
    s:flush()
    Check(s.applications >= 1, "Normal readiness activates skin")
    local ok = s.ns.ResetSettings()
    Check(ok and not s.ns.db.totalRP3Skin.enabled, "Reset returns skin to opt-out")
    Check(s.ns.db.totalRP3Skin.future == "preserved", "Reset preserves unknown nested data")
    Check(not s.allowed() and not s.listener and not s:watchingCombat(), "Reset tears down owned activity")
end)

Test("blocked saved data prevents feature initialization and all styling", function()
    local s = Fixture({ enabled = true, blocked = true })
    Check(not s.ns.ready and not s.ns.initialized and s.ns.settingsError,
        "Unsupported schema must block startup before feature initialization")
    Check(s.registrations == 0 and s.applications == 0 and not s.listener,
        "Blocked schema must not register skins or callbacks")
    local ok = s.ns.SetSetting("totalRP3Skin", "enabled", false)
    Check(ok == false and s.env.CalmUITweaksDB.totalRP3Skin.enabled == true,
        "Blocked data cannot be edited by the feature")
    s:load("totalRP3")
    Check(s.registrations == 0 and #s.timers == 0, "Late dependencies do not bypass blocked startup")
end)

Test("incompatible callback payload fails at the API boundary", function()
    for _, payload in ipairs({ false, {}, { IsEnabled = false } }) do
        local s = Fixture({ enabled = true, delayCallback = true })
        s.skinCallback(payload)
        s:flush()
        Contains(s:status(), "incompatible skinning API")
        Check(s.applications == 0 and #s.errors == 1, "Invalid API must not reach a surface")
        s.skinCallback(payload)
        Check(#s.errors == 1, "Repeated incompatible API report must not flood errors")
    end
end)

print("PASS: Total RP 3 skin lifecycle (" .. tests .. " scenarios, " .. checks .. " assertions)")
