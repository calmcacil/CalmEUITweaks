-- Run from the parent directory: lua CalmEUITweaks/tests/SpacerCorners.lua
local count = 0
local function Check(value, message) assert(value, message); count = count + 1 end
local function New(saved, character, anchors)
    local ns, frames, timers, listeners = {}, {}, {}, {}
    local combat, active = false, false
    local applies = {}
    local env = setmetatable({CalmUITweaksDB = saved, CalmUITweaksCharDB = character}, {__index = _G})
    env._G = env
    env.hooksecurefunc = function(object, method, callback)
        local original = object[method]
        object[method] = function(...)
            local results = {original(...)}
            callback(...)
            return unpack(results)
        end
    end
    env.print = function() end
    env.InCombatLockdown = function() return combat end
    env.C_Timer = {After = function(_, callback) timers[#timers + 1] = callback end}
    env.CreateFrame = function()
        local frame = {scripts = {}, events = {}, eventChanges = 0}
        function frame:RegisterEvent(event)
            self.eventChanges = self.eventChanges + 1
            self.events = self.events or {}; self.events[event] = true
        end
        function frame:UnregisterEvent(event)
            self.eventChanges = self.eventChanges + 1
            if self.events then self.events[event] = nil end
        end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(key, callback) self.scripts[key] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    env.UIParent = {GetEffectiveScale = function() return 1 end}
    local function Rect(width, height)
        local rect = {width = width, height = height, scale = 1, hooks = {}}
        function rect:GetWidth() return self.width end
        function rect:GetHeight() return self.height end
        function rect:GetEffectiveScale() return self.scale end
        function rect:HookScript(event, callback) self.hooks[event] = callback end
        function rect:Resize(width, height)
            self.width = width or self.width
            self.height = height or self.height
            if self.hooks.OnSizeChanged then self.hooks.OnSizeChanged(self) end
        end
        return rect
    end
    local player, target, spacer = Rect(200, 50), Rect(180, 40), Rect(24, 24)
    local key = "CalmUITweaks_Spacer1"
    local db = {unlockAnchors = {player = {target = key, side = "LEFT", offsetX = 0, offsetY = 0},
        target = {target = key, side = "RIGHT", offsetX = 0, offsetY = 0}}}
    if anchors then db.unlockAnchors = anchors end
    env.EllesmereUIDB = db
    local eui = {SetFramePoint = function() end, _unlockRegisteredElements = {
        player = {getFrame = function() return player end}, target = {getFrame = function() return target end},
        [key] = {getFrame = function() return spacer end},
    }}
    function eui:RegisterUnlockModeListener(owner, callback) listeners[owner] = callback end
    eui.ReapplyOwnAnchor = function(unit) assert(not combat); applies[#applies + 1] = unit end
    eui.PropagateAnchorChain = function() end
    env.EllesmereUI = eui
    for _, file in ipairs({"core/Bootstrap.lua", "core/Settings.lua", "core/AnchorEvents.lua", "functions/SpacerCorners.lua"}) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        if setfenv then setfenv(chunk, env) else chunk = assert(loadfile("CalmEUITweaks/" .. file, "t", env)) end
        chunk("CalmEUITweaks", ns)
    end
    ns.RequestApply = function(module) timers[#timers + 1] = function() ns.CallModule(module, "ApplySettings") end end
    ns.InitializeSettings()
    ns.db.spacers.spacer1 = true
    ns.CallModule("spacerCorners", "Initialize")
    ns.ready = true
    ns.CallModule("spacerCorners", "ApplySettings")
    local s = {ns = ns, db = db, eui = eui, player = player, target = target, spacer = spacer,
        applies = applies, driver = frames[1]}
    function s:queued() return #timers end
    function s:flush()
        local batch = timers; timers = {}
        for _, callback in ipairs(batch) do callback() end
        assert(not next(ns.errors), ns.errors.spacerCorners)
    end
    function s:apply() ns.CallModule("spacerCorners", "ApplySettings"); assert(not next(ns.errors)) end
    function s:combat(value) combat = value end
    function s:session(value, action)
        active = value
        if listeners.CalmEUITweaks_SpacerCorners then listeners.CalmEUITweaks_SpacerCorners(value, action) end
    end
    function s:tick()
        eui.SetFramePoint(player); eui.SetFramePoint(target); self:flush()
    end
    return s
end
local s = New()
Check(#s.applies == 0 and s.db.unlockAnchors.player.side == "LEFT", "Default leaves native links alone")
local pairsBySide = {
    LEFT = {TOPRIGHT = "TOPLEFT", BOTTOMRIGHT = "BOTTOMLEFT"},
    RIGHT = {TOPLEFT = "TOPRIGHT", BOTTOMLEFT = "BOTTOMRIGHT"},
    TOP = {BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT"},
    BOTTOM = {TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT"},
}
local function Point(cx, cy, w, h, corner)
    return cx + (corner:find("RIGHT") and w / 2 or -w / 2),
        cy + (corner:find("TOP") and h / 2 or -h / 2)
end
local function Touches(state, unit, corner, targetCorner)
    local child = state[unit]
    local cw, ch = child.width * child.scale, child.height * child.scale
    local tw, th = state.spacer.width * state.spacer.scale, state.spacer.height * state.spacer.scale
    local info = state.db.unlockAnchors[unit]
    local cx, cy = info.offsetX, info.offsetY
    if info.side == "LEFT" then cx = cx - (tw + cw) / 2
    elseif info.side == "RIGHT" then cx = cx + (tw + cw) / 2
    elseif info.side == "TOP" then cy = cy + (th + ch) / 2
    elseif info.side == "BOTTOM" then cy = cy - (th + ch) / 2 end
    local x, y = Point(cx, cy, cw, ch, corner)
    local tx, ty = Point(0, 0, tw, th, targetCorner)
    return math.abs(x - tx) < 0.000001 and math.abs(y - ty) < 0.000001
end
for side, choices in pairs(pairsBySide) do
    for corner, targetCorner in pairs(choices) do
        s.db.unlockAnchors.player = {target = "CalmUITweaks_Spacer1", side = side, offsetX = 7, offsetY = -3}
        s.ns.SetSetting("spacerCorners", "player", corner)
        s:apply()
        Check(s.db.unlockAnchors.player.side == side, "Selection preserves " .. side)
        Check(Touches(s, "player", corner, targetCorner), side .. " corners touch: " .. corner)
        for _, other in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
            Check(s.ns.IsSpacerCornerCompatible(side, other) == (choices[other] ~= nil),
                "Only facing corners are available on " .. side)
        end
    end
end
s.db.unlockAnchors.player = {target = "CalmUITweaks_Spacer1", side = "LEFT", offsetX = 0, offsetY = 0}
s.ns.SetSetting("spacerCorners", "player", "TOPRIGHT"); s:apply()
s.ns.SetSetting("spacerCorners", "target", "TOPLEFT")
Check(Touches(s, "player", "TOPRIGHT", "TOPLEFT") and Touches(s, "target", "TOPLEFT", "TOPRIGHT"),
    "Player and Target facing top corners touch independently")
s.player:Resize(240, 70); s:flush()
Check(Touches(s, "player", "TOPRIGHT", "TOPLEFT"), "Both dimensions can change without breaking alignment")
s.spacer:Resize(40, 30); s:flush()
Check(Touches(s, "player", "TOPRIGHT", "TOPLEFT") and Touches(s, "target", "TOPLEFT", "TOPRIGHT"),
    "Spacer resize keeps both facing corner pairs touching")
s.db.unlockAnchors.player.offsetX = -2
s.db.unlockAnchors.player.offsetY = -17
s.player:Resize(nil, 90); s:flush()
Check(s.db.unlockAnchors.player.offsetX == -2 and s.db.unlockAnchors.player.offsetY == -27,
    "Resize retains normal gap and cross-axis nudge")
local retained = New(s.ns.Copy(s.ns.db), s.ns.Copy(s.ns.charDB), s.ns.Copy(s.db.unlockAnchors))
Check(retained.db.unlockAnchors.player.offsetX == -2 and retained.db.unlockAnchors.player.offsetY == -10,
    "Reload preserves nudges and adapts to final frame geometry")
local scaled = New({spacerCorners = {player = "TOPRIGHT"}})
scaled.player.scale = 0.8; scaled.spacer.scale = 1.25; scaled:apply()
Check(Touches(scaled, "player", "TOPRIGHT", "TOPLEFT"), "Frame scales produce touching corners")
local migrated = New({spacerCorners = {player = "TOPRIGHT"}},
    {spacerCorners = {player = {target = "CalmUITweaks_Spacer1", corner = "TOPRIGHT", base = -88}}})
Check(Touches(migrated, "player", "TOPRIGHT", "TOPLEFT"), "Legacy width baseline resets to correct geometry")
s:combat(true)
local before = #s.applies
s.player:Resize(nil, 110); s:flush()
Check(#s.applies == before and s.db.unlockAnchors.player.offsetY == -27, "Combat defers movement and writes")
s:combat(false); s:apply()
Check(s.db.unlockAnchors.player.offsetY == -37, "Combat end reconciles final height")
s:session(true)
local anchorSnapshot = s.ns.Copy(s.db.unlockAnchors)
s.player:Resize(nil, 130); s:tick(); s:flush()
Check(s.db.unlockAnchors.player.offsetY == -47, "Unlock Mode resizing follows alignment")
s.db.unlockAnchors = anchorSnapshot; s.player.height = 110
s:session(false, "exit"); s:flush()
Check(s.db.unlockAnchors.player.offsetY == -37 and s.db.unlockAnchors.player.offsetX == -2,
    "Discard restores the matching baseline and offsets")
s:session(true); s.player:Resize(nil, 120); s:tick(); s:flush()
s:session(false, "save"); s:flush()
Check(s.db.unlockAnchors.player.offsetY == -42, "Save keeps alignment and nudge")
s.ns.SetSetting("spacerCorners", "player", "DEFAULT")
s.player:Resize(nil, 200); s:flush()
Check(s.db.unlockAnchors.player.offsetY == -42, "Default stops maintaining alignment")
s.db.unlockAnchors.target = {target = "power", side = "RIGHT", offsetX = 17, offsetY = 0}; s:apply()
Check(s.db.unlockAnchors.target.offsetX == 17, "Unrelated links remain unchanged")
Check(not s.ns.SetSetting("spacerCorners", "target", "BAD"), "Invalid choices are rejected")
Check(New({spacerCorners = {player = "BAD"}}).ns.db.spacerCorners.player == "DEFAULT", "Invalid saved choices reset")
s.ns.SetSetting("spacerCorners", "player", "TOPLEFT"); s:apply()
Check(s.db.unlockAnchors.player.side == "LEFT" and s.db.unlockAnchors.player.offsetY == -42,
    "Incompatible selection does not change side or offsets")
s.db.unlockAnchors.player = {target = "CalmUITweaks_Spacer1", side = "RIGHT", offsetX = 8, offsetY = 4}; s:apply()
Check(Touches(s, "player", "TOPLEFT", "TOPRIGHT"), "Re-anchor to a compatible side establishes touching corners")
s.ns.db.spacers.spacer1 = false
local previousY = s.db.unlockAnchors.player.offsetY
s.spacer:Resize(nil, 60); s:flush()
Check(s.db.unlockAnchors.player.offsetY == previousY, "Disabled spacers remain unchanged")
local idle = New()
idle:session(true)
Check(not idle.driver.scripts.OnUpdate and next(idle.driver.events) == nil,
    "Default corners have no edit watcher or world/combat subscriptions")
idle.ns.SetSetting("spacerCorners", "player", "TOPRIGHT")
idle.ns.SetSetting("spacerCorners", "player", "DEFAULT")
idle.player:Resize(nil, 90)
Check(idle:queued() == 0, "Retained size hooks are inert after disabling the last managed corner")
local notified = New({spacerCorners = {player = "TOPRIGHT"}})
notified.db.unlockAnchors.player = {target = "CalmUITweaks_Spacer1", side = "LEFT", offsetX = 9, offsetY = 0}
notified.eui.SetFramePoint(notified.player); notified:flush()
Check(Touches(notified, "player", "TOPRIGHT", "TOPLEFT"),
    "Native placement notification aligns a replaced link without polling")
local eventChanges = notified.driver.eventChanges
notified:apply()
Check(notified.driver.eventChanges == eventChanges, "Unchanged corner refresh keeps existing event subscriptions")
print("SpacerCorners: " .. count .. " checks passed")
