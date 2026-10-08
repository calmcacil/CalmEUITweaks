-- Run from the parent directory: lua CalmEUITweaks/tests/AnchorGap.lua
local count = 0
local function Check(value, message)
    assert(value, message)
    count = count + 1
end
local function New(settings, anchors, lazy)
    local ns, frames, active, combat, timers = {}, {}, false, false, {}
    local applied, propagated, errors = {}, {}, {}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.hooksecurefunc = function(object, method, callback)
        local original = object[method]
        object[method] = function(...)
            local results = {original(...)}
            callback(...)
            return unpack(results)
        end
    end
    env.CalmUITweaksDB = {anchorGap = settings or {}}
    env.EllesmereUIDB = {unlockAnchors = anchors or {}}
    env.InCombatLockdown = function() return combat end
    env.print = function() end
    env.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    env.CreateFrame = function()
        local frame = {scripts = {}}
        function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
        function frame:UnregisterEvent(event) if self.events then self.events[event] = nil end end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(key, callback) self.scripts[key] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    env.C_Timer = {After = function(_, fn) timers[#timers + 1] = fn end}
    local eui = {_unlockRegisteredElements = {}, SetFramePoint = function() end, PP = {FromPixels = function(pixels) return pixels * 0.75 end}}
    function eui:RegisterUnlockElements(elements)
        for _, element in ipairs(elements) do self._unlockRegisteredElements[element.key] = element end
    end
    local listener
    function eui:RegisterUnlockModeListener(owner, callback)
        assert(owner == "CalmEUITweaks_AnchorGap")
        listener = callback
        if active then callback(true) end
    end
    function eui:IsUnlockModeActive() return active end
    eui.ReapplyUnlockAnchor = function(key) applied[#applied + 1] = key end
    eui.PropagateAnchorChain = function(key) propagated[#propagated + 1] = key end
    local reapply = eui.ReapplyUnlockAnchor
    if lazy then eui.ReapplyUnlockAnchor = nil end
    env.EllesmereUI = eui
    for _, file in ipairs({"core/Bootstrap.lua", "core/Settings.lua", "core/AnchorEvents.lua", "functions/AnchorGap.lua"}) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        if setfenv then setfenv(chunk, env) else chunk = assert(loadfile("CalmEUITweaks/" .. file, "t", env)) end
        chunk("CalmEUITweaks", ns)
    end
    ns.RequestApply = function(key) ns.CallModule(key, "ApplySettings") end
    ns.InitializeSettings()
    ns.CallModule("anchorGap", "Initialize")
    ns.ready = true
    ns.CallModule("anchorGap", "ApplySettings")
    local s = {ns = ns, env = env, db = env.EllesmereUIDB, eui = eui, applied = applied,
        propagated = propagated, errors = errors, driver = frames[1]}
    function s:open() active = true; if listener then listener(true) end end
    function s:close() active = false; if listener then listener(false) end end
    function s:place(key)
            local element = eui._unlockRegisteredElements[key]
            if not element then
                local frame = {}
                element = {key = key, getFrame = function() return frame end}
                eui:RegisterUnlockElements({element})
            end
            eui.SetFramePoint(element.getFrame())
    end
    function s:flush()
        local turns = 0
        while #timers > 0 do
            turns = turns + 1; assert(turns < 20, "Anchor notifications must settle")
            local batch = timers; timers = {}
            for _, fn in ipairs(batch) do fn() end
        end
    end
    function s:tick()
        for key in pairs(self.db.unlockAnchors) do self:place(key) end
        self:flush()
    end
    function s:combat(value) combat = value end
    function s:loadEngine() eui.ReapplyUnlockAnchor = reapply end
    return s
end
local function Link(side, target, x, y)
    return {side = side, target = target or "power", offsetX = x, offsetY = y}
end

local disabled = New()
disabled:open()
disabled.db.unlockAnchors.bar = Link("TOP")
disabled:tick()
Check(not disabled.driver.scripts.OnUpdate and #disabled.applied == 0,
    "Defaults off and never runs an edit-mode watcher")

local old = Link("TOP", "power", 0, 0)
local s = New({enabled = true}, {old = old})
s:open(); s:tick()
Check(old.offsetY == 0 and #s.applied == 0, "Existing flush links are not changed")
for _, side in ipairs({"LEFT", "RIGHT", "TOP", "BOTTOM"}) do s.db.unlockAnchors[side] = Link(side) end
s:tick()
Check(s.db.unlockAnchors.LEFT.offsetX == -1.5 and s.db.unlockAnchors.RIGHT.offsetX == 1.5
    and s.db.unlockAnchors.TOP.offsetY == 1.5 and s.db.unlockAnchors.BOTTOM.offsetY == -1.5,
    "All four edge directions get outward gaps using physical pixel conversion")
Check(#s.applied == 4 and #s.propagated == 4, "Native anchor reapply and child propagation run once per changed link")
s:tick(); s:tick()
Check(#s.applied == 4, "Repeated edit updates do not accumulate gaps")
s.db.unlockAnchors.TOP.offsetY = 7
s:tick()
Check(s.db.unlockAnchors.TOP.offsetY == 7, "Manual nudges after automatic placement remain authoritative")
s.db.unlockAnchors.TOP = Link("TOP")
s:tick()
Check(s.db.unlockAnchors.TOP.offsetY == 1.5, "Re-anchoring creates a fresh default rather than accumulating an old gap")
s.db.unlockAnchors.cross = Link("RIGHT", "power", 0, 12)
s.db.unlockAnchors.manual = Link("BOTTOM", "power", 0, -5)
s:tick()
Check(s.db.unlockAnchors.cross.offsetX == 1.5 and s.db.unlockAnchors.cross.offsetY == 12,
    "Cross-axis alignment is preserved when adding the default gap")
Check(s.db.unlockAnchors.manual.offsetY == -5, "Nonzero edge offsets are never overwritten")
s.db.unlockAnchors.lateLoad = Link("TOP")
s.ns.CallModule("anchorGap", "OnAddonLoaded", "AnotherAddon")
s:tick()
Check(s.db.unlockAnchors.lateLoad.offsetY == 1.5,
    "Unrelated addon loads do not swallow a newly created anchor before the next edit update")

-- EUI corner picks are cardinal links with an alignment offset, not diagonal sides.
local corners = New({enabled = true})
corners:open()
for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
    for _, alignment in ipairs({-88, 88}) do
        local horizontal = side == "LEFT" or side == "RIGHT"
        local key = side .. tostring(alignment)
        local info = Link(side, "power", horizontal and 0 or alignment, horizontal and alignment or 0)
        info.edgeOffX, info.edgeOffY = info.offsetX, info.offsetY
        corners.db.unlockAnchors[key] = info
        corners:tick()
        local outward = (side == "LEFT" or side == "BOTTOM") and -1.5 or 1.5
        Check((horizontal and info.offsetY or info.offsetX) == alignment,
            side .. " corner keeps aligned edges")
        Check((horizontal and info.offsetX or info.offsetY) == outward,
            side .. " corner gets only the outward two-pixel gap")
        Check((horizontal and info.edgeOffY or info.edgeOffX) == alignment,
            side .. " corner keeps the alignment growth pin unchanged")
        corners:tick()
        Check((horizontal and info.offsetX or info.offsetY) == outward,
            side .. " corner gap never accumulates")
    end
end

corners.db.unlockAnchors.horizontalBar = Link("TOP", "power", -88, 0)
local horizontalBar = corners.db.unlockAnchors.horizontalBar
horizontalBar.refFor, horizontalBar.refX = "RIGHT", "LEFT"
horizontalBar.edgeOffX, horizontalBar.edgeOffY = 0, 9
corners:tick()
Check(horizontalBar.offsetY == 1.5 and horizontalBar.offsetX == -88
    and horizontalBar.edgeOffX == 0 and horizontalBar.edgeOffY == 9,
    "Horizontal corner preserves alignment pin and ignores stale inactive vertical pin")
corners.db.unlockAnchors.verticalBar = Link("LEFT", "power", 0, 35)
local verticalBar = corners.db.unlockAnchors.verticalBar
verticalBar.refFor, verticalBar.refY = "DOWN", "TOP"
verticalBar.edgeOffX, verticalBar.edgeOffY = 9, 0
corners:tick()
Check(verticalBar.offsetX == -1.5 and verticalBar.offsetY == 35
    and verticalBar.edgeOffY == 0 and verticalBar.edgeOffX == 9,
    "Vertical corner preserves alignment pin and ignores stale inactive horizontal pin")

local appliedBefore = #s.applied
s.db.unlockAnchors.center = Link("CENTER")
s.db.unlockAnchors.corner = Link("TOPLEFT")
s.db.unlockAnchors.screen = Link("TOP", "SCREEN_TOP")
s.db.unlockAnchors.SCREEN_LEFT = Link("LEFT")
s.db.unlockAnchors.spacerTarget = Link("RIGHT", "CalmUITweaks_Spacer1")
s.db.unlockAnchors.CalmUITweaks_Spacer2 = Link("BOTTOM")
s:tick()
Check(#s.applied == appliedBefore, "Center, corner, screen-edge and spacer links are excluded")

s.db.unlockAnchors.pin = Link("LEFT")
s.db.unlockAnchors.pin.edgeOffX = -200
s.db.unlockAnchors.pin.refFor = "LEFT"
s:tick()
Check(s.db.unlockAnchors.pin.offsetX == -1.5 and s.db.unlockAnchors.pin.edgeOffX == -201.5
    and s.db.unlockAnchors.pin.refFor == "LEFT", "Native growth pin is shifted with its offset")

s:combat(true)
s.db.unlockAnchors.combat = Link("TOP")
appliedBefore = #s.applied
s:tick()
Check(#s.applied == appliedBefore and s.db.unlockAnchors.combat.offsetY == nil, "No anchor writes or reapply in combat")
s:combat(false); s:tick()
Check(s.db.unlockAnchors.combat.offsetY == 1.5, "A new link queued during combat is processed on editing resume")

s:close()
appliedBefore = #s.applied
s.db.unlockAnchors.outside = Link("TOP")
s:tick()
Check(not s.driver.scripts.OnUpdate and #s.applied == appliedBefore, "Watcher is removed outside edit mode")
s:open(); s:tick()
Check(s.db.unlockAnchors.outside.offsetY == nil, "Links that predate a new edit session remain untouched")

s.ns.SetSetting("anchorGap", "top", 1)
s.db.unlockAnchors.one = Link("TOP"); s:tick()
Check(s.db.unlockAnchors.one.offsetY == 0.75, "The one-pixel preference is converted using EUI scale")
Check(s.db.unlockAnchors.RIGHT.offsetX == 1.5, "Changing defaults does not resize existing gaps")
s.ns.SetSetting("anchorGap", "enabled", false)
Check(not s.driver.scripts.OnUpdate and s.db.unlockAnchors.one.offsetY == 0.75,
    "Disabling stops automatic offsets but preserves saved native gaps")

local lazy = New({enabled = true}, nil, true)
lazy:loadEngine(); lazy:open()
lazy.db.unlockAnchors.bar = Link("TOP"); lazy:tick()
Check(lazy.db.unlockAnchors.bar.offsetY == 1.5, "Listener is installed before EUI's full anchor engine loads")

local replace = New({enabled = true})
replace:open()
replace.db.unlockAnchors = {imported = Link("TOP")}
replace:tick()
Check(replace.db.unlockAnchors.imported.offsetY == nil, "Replacing the native anchor store is treated as a layout load")
replace.db.unlockAnchors.new = Link("TOP"); replace:tick()
Check(replace.db.unlockAnchors.new.offsetY == 1.5, "Fresh links still work after a native layout store switch")

-- Native Discard restores its anchor snapshot before the close listener runs.
replace.db.unlockAnchors.new = nil
replace:close(); replace:tick()
Check(replace.db.unlockAnchors.new == nil, "Discarded links are not recreated by the watcher")
local repaired = New({enabled = true, pixels = 0/0})
Check(repaired.ns.db.anchorGap.top == 2 and repaired.ns.db.anchorGap.pixels == nil,
    "Malformed legacy gap values reset to the side defaults")
for _, value in ipairs({-1, 11, 1.5, math.huge, 0/0}) do
    Check(not repaired.ns.SetSetting("anchorGap", "top", value), "Invalid gap preference rejected")
end
Check(not next(s.ns.errors) and not next(lazy.ns.errors), "Normal edit operations raise no module errors")
local migrated = New({enabled = true, pixels = 4})
Check(migrated.ns.db.anchorGap.enabled and migrated.ns.db.anchorGap.top == 4
    and migrated.ns.db.anchorGap.bottom == 4 and migrated.ns.db.anchorGap.left == 4
    and migrated.ns.db.anchorGap.right == 4 and migrated.ns.db.anchorGap.pixels == nil,
    "Old shared preference migrates into all four sides and retains the enable switch")
local partial = New({pixels = 4, top = 0, right = 7})
Check(partial.ns.db.anchorGap.top == 0 and partial.ns.db.anchorGap.right == 7
    and partial.ns.db.anchorGap.left == 4 and partial.ns.db.anchorGap.bottom == 4,
    "Migration fills missing sides without replacing existing side values or zero")
local invalidSides = New({top = math.huge, bottom = -1, left = 1.5, right = 0/0})
Check(invalidSides.ns.db.anchorGap.top == 2 and invalidSides.ns.db.anchorGap.bottom == 2
    and invalidSides.ns.db.anchorGap.left == 2 and invalidSides.ns.db.anchorGap.right == 2,
    "Malformed saved side values each reset to the default")

local sides = New({enabled = true, top = 3, bottom = 0, left = 1, right = 2})
sides:open()
for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
    sides.db.unlockAnchors[side] = Link(side, "power", 0, 0)
end
sides:tick()
Check(sides.db.unlockAnchors.TOP.offsetY == 2.25 and sides.db.unlockAnchors.LEFT.offsetX == -0.75
    and sides.db.unlockAnchors.RIGHT.offsetX == 1.5 and sides.db.unlockAnchors.BOTTOM.offsetY == 0,
    "Asymmetric defaults select the correct target side, including flush zero spacing")
Check(#sides.applied == 3, "A zero gap does not reapply the frame or block other sides")
sides.ns.SetSetting("anchorGap", "bottom", 5)
sides:tick()
Check(sides.db.unlockAnchors.BOTTOM.offsetY == 0 and #sides.applied == 3,
    "Zero-spacing links are marked observed and never moved when the default changes")
sides.db.unlockAnchors.newBottom = Link("BOTTOM", "power", 0, 0)
sides:tick()
Check(sides.db.unlockAnchors.newBottom.offsetY == -3.75,
    "New links use the updated side default while old links remain flush")
for _, side in ipairs({"top", "bottom", "left", "right"}) do
    Check(sides.ns.SetSetting("anchorGap", side, 0), "Each side permits zero spacing")
    Check(sides.ns.SetSetting("anchorGap", side, 10), "Each side permits the maximum spacing")
end
Check(not sides.ns.SetSetting("anchorGap", "pixels", 3), "Retired shared-gap setting is no longer writable")
sides.ns.ResetSettings()
Check(not sides.ns.db.anchorGap.enabled and sides.ns.db.anchorGap.top == 2
    and sides.ns.db.anchorGap.bottom == 2 and sides.ns.db.anchorGap.left == 2
    and sides.ns.db.anchorGap.right == 2 and sides.db.unlockAnchors.newBottom.offsetY == -3.75,
    "Reset restores side defaults and disables automation while preserving existing offsets")
print("AnchorGap: " .. count .. " checks passed")
local notified = New({enabled = true})
notified:open()
notified.db.unlockAnchors.changed = Link("TOP")
notified.db.unlockAnchors.untouched = Link("TOP")
notified:place("changed"); notified:flush()
Check(notified.db.unlockAnchors.changed.offsetY == 1.5
    and notified.db.unlockAnchors.untouched.offsetY == nil,
    "Native placement processes only the notified link, without a store scan")
Check(not notified.driver.scripts.OnUpdate and next(notified.driver.events) == nil,
    "Active gap editing has no update callback or idle game-event subscriptions")
notified.db.unlockAnchors.cancelled = Link("BOTTOM")
notified:place("cancelled"); notified:close(); notified:flush()
Check(notified.db.unlockAnchors.cancelled.offsetY == nil,
    "Closing editing cancels deferred link mutation")
