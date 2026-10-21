local root = "CalmEUITweaks/"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function Sandbox(enabled, late)
    local s = { ns = {}, frames = {}, timers = {}, rows = {}, leaders = {}, errors = {}, queries = 0, hooks = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.CalmUITweaksDB = { lfgLeaderLocation = { enabled = enabled } }
    env.InCombatLockdown = function() return s.combat end
    env.IsLoggedIn = function() return false end
    env.geterrorhandler = function() return function(err) s.errors[#s.errors + 1] = err end end
    env.print = function() end
    env.C_Timer = { After = function(_, callback) s.timers[#s.timers + 1] = callback end }
    env.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, callback) self.callback = callback end
        s.frames[#s.frames + 1] = frame
        return frame
    end
    env.hooksecurefunc = function(name, callback)
        s.hooks = s.hooks + 1
        local native = env[name]
        env[name] = function(entry) native(entry); callback(entry) end
    end
    function s:installUI()
        env.C_LFGList = { GetSearchResultLeaderInfo = function(id)
            self.queries = self.queries + 1
            if self.fail then error("leader query failed") end
            return self.leaders[id]
        end }
        env.LFGBrowseSearchEntry_Update = function(entry) entry.nativeUpdates = (entry.nativeUpdates or 0) + 1 end
        env.LFGBrowseFrame = { ScrollBox = { ForEachFrame = function(_, callback)
            for _, row in ipairs(self.rows) do callback(row) end
        end } }
    end
    function s:row(id)
        local activity = { font = "EUI face", size = 13, flags = "OUTLINE", right = 150, height = 15 }
        function activity:GetFontObject() return "NativeFontObject" end
        function activity:GetFont() return self.font, self.size, self.flags end
        function activity:GetShadowColor() return 0, 0, 0, 0.5 end
        function activity:GetShadowOffset() return 1, -1 end
        function activity:GetTextColor() return 0.4, 0.6, 0.8, 0.7 end
        function activity:GetHeight() return self.height end
        function activity:GetRight() return self.right end
        local row = { resultID = id, ActivityName = activity, DataDisplay = {}, labels = {}, shown = true }
        function row.DataDisplay:GetLeft() return 350 end
        function row:IsShown() return self.shown end
        function row:CreateFontString()
            local label = { points = {} }
            function label:Hide() self.shown = false end
            function label:Show() self.shown = true end
            function label:SetJustifyH(value) self.justify = value end
            function label:SetWordWrap(value) self.wrap = value end
            function label:SetPoint(...) self.points[#self.points + 1] = { ... } end
            function label:SetFontObject(value) self.fontObject = value end
            function label:SetFont(...) self.font = { ... } end
            function label:SetShadowColor(...) self.shadow = { ... } end
            function label:SetShadowOffset(...) self.shadowOffset = { ... } end
            function label:SetTextColor(...) self.color = { ... } end
            function label:SetHeight(value) self.height = value end
            function label:SetText(value) self.text = value end
            self.labels[#self.labels + 1] = label
            return label
        end
        self.rows[#self.rows + 1] = row
        return row
    end
    function s:event(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] then frame.callback(frame, event, ...) end
        end
    end
    function s:flush()
        local pending = self.timers
        self.timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
    function s:update(row) env.LFGBrowseSearchEntry_Update(row) end
    function s:enable(value) self.ns.SetSetting("lfgLeaderLocation", "enabled", value) end
    function s:watchingCombat() return self.frames[2].events.PLAYER_REGEN_ENABLED end
    if not late then s:installUI() end
    for _, path in ipairs({ "core/Bootstrap.lua", "core/Settings.lua", "core/CVars.lua", "core/Migrations.lua", "core/Lifecycle.lua", "functions/LFGLeaderLocation.lua" }) do
        local chunk = assert(loadfile(root .. path))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", s.ns)
    end
    s:event("ADDON_LOADED", "CalmEUITweaks")
    s:event("PLAYER_LOGIN")
    return s
end

local s = Sandbox(false)
local row = s:row(10)
s.leaders[10] = { areaName = "Searing Gorge" }
s:update(row)
Check(s.hooks == 0 and s.queries == 0 and #row.labels == 0, "Default-off must leave the LFG UI idle")
Check(s.ns.GetStatus("lfgLeaderLocation") == "Disabled", "Disabled status missing")
s:enable(true)
local label = row.labels[1]
Check(label and label.shown and label.text == "Searing Gorge", "Opt-in must refresh already-visible rows")
Check(label.fontObject == "NativeFontObject" and label.font[1] == "EUI face"
    and label.font[2] == 13 and label.font[3] == "OUTLINE", "Labels must inherit the skinned row font")
Check(label.color[1] == 0.45 and label.color[2] == 0.8 and label.color[3] == 1
    and label.color[4] == 0.7 and label.shadow[4] == 0.5
    and label.shadowOffset[2] == -1, "Locations must use soft blue while retaining native opacity and shadow")
Check(not label.wrap and label.justify == "LEFT" and label.height == 15, "Labels must fit one native row line")
Check(label.points[1][2] == row.ActivityName and label.points[2][2] == row.DataDisplay,
    "Labels must use the gap between activity and group data")
Check(row.nativeUpdates == 1, "Refreshing labels must not rerun native list updates")
s.leaders[11] = { areaName = "Stormwind City" }
row.resultID = 11
row.ActivityName.font, row.ActivityName.size = "Changed EUI face", 14
s:update(row)
Check(#row.labels == 1 and label.text == "Stormwind City" and label.font[1] == "Changed EUI face",
    "Recycled rows must reuse labels and sample the current theme")
s.leaders[11] = nil
s:update(row)
Check(not label.shown, "Missing leader information must hide the prior zone")
for _, area in ipairs({ "", "   ", false, 5 }) do
    s.leaders[11] = { areaName = area }
    s:update(row)
    Check(not label.shown, "Unavailable or malformed zones must stay hidden")
end
s.leaders[11] = { areaName = "Stormwind City" }
row.ActivityName.right = 340
s:update(row)
Check(not label.shown, "Rows without space must not overlap native group data")
row.ActivityName.right = 150
row.shown = false
local queries = s.queries
s:update(row)
Check(not label.shown and s.queries == queries, "Hidden or removed results must not query or show zones")
row.shown = true
s:update(row)
Check(label.shown, "Normal native result updates must recover labels")
s:enable(false)
Check(not label.shown and not s:watchingCombat(), "Disable must immediately release labels and subscriptions")
queries = s.queries
s:update(row)
Check(s.queries == queries and not label.shown, "Installed hooks must remain inert while disabled")
s:enable(true)
Check(s.hooks == 1 and label.shown, "Re-enabling must reuse the hook and refresh rows")
s.ns.ResetSettings()
Check(not label.shown and not s.ns.db.lfgLeaderLocation.enabled, "Reset must restore opt-in to off")

s = Sandbox(true, true)
row = s:row(20)
s.leaders[20] = { areaName = "Dun Morogh" }
Check(s.ns.GetStatus("lfgLeaderLocation"):find("Waiting"), "Missing native UI must leave the feature waiting")
s:event("ADDON_LOADED", "UnrelatedAddon")
Check(#s.timers == 0, "Unrelated addon loads must not schedule LFG work")
s:installUI()
s:event("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
s:event("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
Check(#s.timers == 1, "Late UI readiness must coalesce refreshes")
s:flush()
Check(row.labels[1].shown and s.hooks == 1, "Late native UI loading must recover without reload")
local divider = { IsShown = function() return true end }
s.ns.CallModule("lfgLeaderLocation", "UpdateEntry", divider)
Check(#s.errors == 0, "Native section dividers must be skipped")
s.combat = true
s:update(row)
Check(not row.labels[1].shown and s:watchingCombat(), "Combat updates must hide stale zones and defer work")
local combatRow = s:row(20)
s:update(combatRow)
Check(#combatRow.labels == 0, "Combat must not create row decorations")
s:event("PLAYER_REGEN_ENABLED")
s.combat = false
s:flush()
Check(row.labels[1].shown and combatRow.labels[1].shown and not s:watchingCombat(),
    "Combat end must refresh visible rows and release its listener")
s.fail = true
s:update(row)
Check(#s.errors == 1 and not row.labels[1].shown and s.ns.errors.lfgLeaderLocation,
    "Native callback failures must reach shared reporting without stale labels")
s:update(row)
Check(#s.errors == 1, "Repeated native failures must not spam")
s.fail = false
s:update(row)
Check(row.labels[1].shown and not s.ns.errors.lfgLeaderLocation, "Successful native updates must clear errors")
s.combat = true
s:update(row)
s:enable(false)
s:event("PLAYER_REGEN_ENABLED")
s:flush()
Check(not s:watchingCombat() and not row.labels[1].shown, "Disable in combat must cancel deferred display work")
Check(#s.timers == 0, "Idle feature must not poll")
print("PASS: LFG leader location (" .. checks .. " assertions)")
