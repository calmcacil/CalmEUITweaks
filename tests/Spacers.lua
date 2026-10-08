-- Run from the parent directory: lua CalmEUITweaks/tests/Spacers.lua
local tests = 0
local function fixture(db, charDB, lateListener)
    local ns, frames, registry, links, timers = {}, {}, {}, {}, {}
    local combat, active, listener = false, false, nil
    local registrations, removals = 0, 0
    local env = setmetatable({ CalmUITweaksDB = db, CalmUITweaksCharDB = charDB }, { __index = _G })
    env._G = env
    env.print = function() end
    env.UIParent = {}
    env.InCombatLockdown = function() return combat end
    env.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    env.CreateFrame = function(_, name, parent)
        local frame = { events = {}, scripts = {}, name = name, parent = parent, eventChanges = 0 }
        function frame:RegisterEvent(event) self.eventChanges = self.eventChanges + 1; self.events[event] = true end
        function frame:UnregisterEvent(event) self.eventChanges = self.eventChanges + 1; self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        function frame:EnableMouse(value) self.mouse = value end
        function frame:SetSize(w, h)
            assert(not combat, "geometry changed in combat")
            self.width, self.height = w, h
        end
        function frame:GetWidth() return self.width end
        function frame:GetHeight() return self.height end
        function frame:ClearAllPoints() assert(not combat); self.point = nil end
        function frame:SetPoint(...) assert(not combat); self.point = {...} end
        function frame:Show() self.shown = true end
        frames[#frames + 1] = frame
        return frame
    end
    local eui = {}
    env.EllesmereUI = eui
    function eui:RegisterUnlockElements(elements, folder)
        assert(self == eui and folder == "CalmEUITweaks")
        assert(not combat and not active, "registration during combat/session")
        registrations = registrations + 1
        for _, element in ipairs(elements) do registry[element.key] = element end
    end
    function eui:UnregisterUnlockElement(key)
        assert(not combat and not active, "removal during combat/session")
        registry[key] = nil
        links[key] = nil
        for child, target in pairs(links) do if target == key then links[child] = nil end end
        removals = removals + 1
    end
    function eui:IsUnlockModeActive() return active end
    function eui:RegisterUnlockModeListener(owner, callback)
        assert(owner == "CalmEUITweaks_Spacers")
        listener = callback
    end
    function eui:UnregisterUnlockModeListener(owner)
        assert(owner == "CalmEUITweaks_Spacers")
        listener = nil
    end
    eui.IsUnlockAnchored = function(key) return links[key] ~= nil end
    eui.ReapplyOwnAnchor = function(key)
        local element = registry[key]
        local target = links[key]
        if element and target then
            local frame = element.getFrame(key)
            frame:ClearAllPoints()
            frame:SetPoint("RIGHT", target, "LEFT", 0, 0)
        end
    end
    for _, file in ipairs({ "core/Bootstrap.lua", "core/Settings.lua", "core/AnchorEvents.lua", "functions/Spacers.lua" }) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        if setfenv then setfenv(chunk, env)
        else chunk = assert(loadfile("CalmEUITweaks/" .. file, "t", env)) end
        chunk("CalmEUITweaks", ns)
    end
    ns.RequestApply = function(key) timers[#timers + 1] = function() ns.CallModule(key, "ApplySettings") end end
    ns.InitializeSettings()
    local registerListener = eui.RegisterUnlockModeListener
    if lateListener then eui.RegisterUnlockModeListener = nil end
    ns.CallModule("spacers", "Initialize")
    eui.RegisterUnlockModeListener = registerListener
    ns.ready = true
    ns.CallModule("spacers", "ApplySettings")
    local s = { ns = ns, eui = eui, registry = registry, links = links, frames = frames }
    function s:element(index) return registry["CalmUITweaks_Spacer" .. (index or 1)] end
    function s:combat(value) combat = value end
    function s:session(value) active = value; if listener then listener(value) end end
    function s:fire(event)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event) end
        end
    end
    function s:flush()
        local batch = timers; timers = {}
        for _, callback in ipairs(batch) do callback() end
        assert(not next(ns.errors), ns.errors.spacers)
    end
    function s:counts() return registrations, removals end
    function s:hasListener() return listener ~= nil end
    assert(not next(ns.errors), ns.errors.spacers)
    return s
end
local function test(name, run)
    run()
    tests = tests + 1
    print("PASS " .. name)
end

test("disabled spacers have no idle subscriptions and recover a late close listener", function()
    local idle = fixture()
    assert(next(idle.frames[1].events) == nil)
    local s = fixture({spacers = {spacer1 = true}}, nil, true)
    s:session(true)
    s.ns.SetSetting("spacers", "spacer2", true)
    assert(not s:element(2))
    s:session(false); s:flush()
    assert(s:element(2), "Recovered listener must finish pending settings when editing closes")
    assert(not s.frames[1].events.PLAYER_REGEN_ENABLED, "Combat-end listener is only for pending combat work")
end)

test("default off creates no spacer frames or registrations", function()
    local s = fixture()
    assert(not next(s.registry) and #s.frames == 1)
    assert(s.ns.GetStatus("spacers") == "Disabled")
end)

test("disabling the last spacer releases its native listener", function()
    local s = fixture({spacers = {spacer1 = true}})
    assert(s:hasListener())
    s.ns.SetSetting("spacers", "spacer1", false)
    assert(not s:element() and not s:hasListener(), "Disabled spacers must release the Unlock Mode listener")
    assert(not next(s.frames[1].events), "Disabled spacers must release frame events")
    s.ns.SetSetting("spacers", "spacer1", true)
    assert(s:element() and s:hasListener(), "Re-enabling must register the listener again")
end)
test("four independent switches register unique native elements", function()
    local s = fixture()
    for i = 1, 4 do
        assert(s.ns.SetSetting("spacers", "spacer" .. i, true))
        local element = assert(s:element(i))
        assert(element.label == "Spacer " .. i and element.group == "Calm UI Tweaks")
        local frame = element.getFrame()
        assert(frame.shown and not frame.mouse and frame.parent ~= nil)
        assert(frame.width == 24 and frame.height == 24)
    end
    assert(not s.ns.SetSetting("spacers", "spacer5", true))
    assert(s:counts() == 4)
end)
test("dimensions and positions are shared with a fresh character", function()
    local s = fixture({spacers = {spacer1 = true}})
    local e = s:element()
    e.setWidth(e.key, 36); e.setHeight(e.key, 17)
    e.savePosition(e.key, "CENTER", "CENTER", -260, -120)
    local nextSession = fixture(s.ns.Copy(s.ns.db))
    local nextElement = nextSession:element()
    local w, h = nextElement.getSize()
    assert(w == 36 and h == 17 and nextElement.loadPosition().x == -260)
    assert(nextElement.getFrame().point[4] == -260)
end)
test("native discard callbacks restore size and position", function()
    local s = fixture({spacers = {spacer1 = true}})
    local e = s:element()
    local before, w, h = e.loadPosition(), e.getSize()
    s:session(true)
    e.setWidth(e.key, 100); e.setHeight(e.key, 80)
    e.savePosition(e.key, "CENTER", "CENTER", 42, 53)
    e.setWidth(e.key, w); e.setHeight(e.key, h)
    e.savePosition(e.key, before.point, before.relPoint, before.x, before.y)
    e.applyPosition(e.key)
    s:session(false)
    assert(e.getFrame().width == w and e.getFrame().height == h)
    assert(e.loadPosition().x == before.x and e.getFrame().point[4] == before.x)
end)
test("standalone application preserves EUI anchor authority", function()
    local s = fixture({spacers = {spacer1 = true}})
    local e, powerBar = s:element(), {}
    s.links[e.key] = powerBar
    e.applyPosition(e.key)
    assert(e.getFrame().point[2] == powerBar)
    e.savePosition(e.key, "CENTER", "CENTER", 100, 100)
    assert(e.getFrame().point[2] == powerBar)
end)
test("disable uses native unregister cleanup and re-enable reuses geometry", function()
    local s = fixture({spacers = {spacer1 = true, spacer2 = true}})
    local e, other = s:element(), s:element(2)
    e.setWidth(e.key, 45)
    s.links.player = e.key
    s.ns.SetSetting("spacers", "spacer1", false)
    assert(not s:element() and not s.links.player and s:element(2) == other)
    s.ns.SetSetting("spacers", "spacer1", true)
    assert(s:element() == e and e.getFrame().width == 45)
    local _, removals = s:counts(); assert(removals == 1)
end)
test("early login anchor API works before full Unlock Mode loads", function()
    local s = fixture({spacers = {spacer1 = true}})
    local e, powerBar = s:element(), {}
    s.eui.IsUnlockAnchored = nil
    s.links[e.key] = powerBar
    e.applyPosition(e.key)
    assert(e.getFrame().point[2] == powerBar)
end)
test("late target registration reapplies the spacer anchor", function()
    local s = fixture({spacers = {spacer1 = true}})
    local e, powerBar = s:element(), {}
    s.links[e.key] = powerBar
    s.ns.CallModule("spacers", "OnAddonLoaded", "EllesmereUIUnitFrames"); s:flush()
    assert(e.getFrame().point[2] == powerBar)
    assert(s:counts() == 1)
end)
test("registration and removal defer until combat ends", function()
    local s = fixture()
    s:combat(true)
    s.ns.SetSetting("spacers", "spacer1", true)
    assert(not s:element())
    s:combat(false); s:fire("PLAYER_REGEN_ENABLED")
    assert(s:element())
    s:combat(true); s.ns.SetSetting("spacers", "spacer1", false)
    assert(s:element())
    s:combat(false); s:fire("PLAYER_REGEN_ENABLED")
    assert(not s:element())
end)
test("preference changes defer until native edit session closes", function()
    local s = fixture()
    s:session(true); s.ns.SetSetting("spacers", "spacer3", true)
    assert(not s:element(3))
    s:session(false); s:flush()
    assert(s:element(3))
end)
test("repeat world and addon events do not re-register existing elements", function()
    local s = fixture({spacers = {spacer1 = true}})
    local eventChanges = s.frames[1].eventChanges
    s:fire("PLAYER_ENTERING_WORLD")
    s.ns.CallModule("spacers", "OnAddonLoaded", "AnotherAddon"); s:flush()
    assert(s:counts() == 1)
    assert(s.frames[1].eventChanges == eventChanges, "Unchanged spacer refresh must keep event subscriptions")
end)
test("invalid saved geometry is repaired and callback inputs are validated", function()
    local s = fixture({spacers = {spacer1 = true}}, {spacers = {[1] = {
        width = 0 / 0, height = math.huge, position = {point = "BAD", x = "bad"}}}})
    local e = s:element()
    local w, h = e.getSize(); assert(w == 24 and h == 24)
    e.setWidth(e.key, -5); e.setHeight(e.key, 3000)
    w, h = e.getSize(); assert(w == 1 and h == 2000)
    e.setWidth(e.key, 0 / 0); assert(e.getSize() == 1)
    e.savePosition(e.key, "BAD", "CENTER", 1, 1)
    assert(e.loadPosition().point == "CENTER")
    local pos = e.loadPosition(); pos.x = 999
    assert(e.loadPosition().x ~= 999)
end)
test("missing native API is reported and recovers after addon load", function()
    local s = fixture()
    local register = s.eui.RegisterUnlockElements
    s.eui.RegisterUnlockElements = nil
    s.ns.SetSetting("spacers", "spacer1", true)
    assert(s.ns.GetStatus("spacers"):find("Waiting"))
    s.eui.RegisterUnlockElements = register
    s.ns.CallModule("spacers", "OnAddonLoaded", "EllesmereUI"); s:flush()
    assert(s:element())
end)
test("preference reset disables spacers but preserves account geometry", function()
    local s = fixture({spacers = {spacer1 = true}})
    s:element().setWidth("CalmUITweaks_Spacer1", 64)
    s.ns.ResetSettings()
    assert(not s:element() and s.ns.db.spacerLayouts[1].width == 64)
end)
print("Spacers: " .. tests .. " tests passed")
