local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function New(saved, current)
    local ns, frames, textures, groups, timers, errors, writes = {}, {}, {}, {}, {}, {}, {}
    local combat, target = false, nil
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.CalmUITweaksDB = saved or {}
    env.print = function() end
    env.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    env.InCombatLockdown = function() return combat end
    env.IsLoggedIn = function() return false end
    local function Texture()
        local texture = {}
        function texture:Hide() self.hidden = true end
        function texture:SetTexture(value) self.texture = value end
        function texture:GetTexture() return self.texture end
        function texture:GetAtlas() return self.atlas end
        function texture:SetBlendMode(value) self.blend = value end
        function texture:SetSize(width, height) self.width, self.height = width, height end
        function texture:SetPoint(...) self.point = { ... } end
        function texture:SetVertexColor(...) self.color = { ... } end
        function texture:SetAlpha(value) self.alpha = value end
        function texture:CreateAnimationGroup()
            local group = { animations = {}, plays = 0, stops = 0 }
            function group:SetLooping(value) self.loop = value end
            function group:Play() self.playing = true; self.plays = self.plays + 1 end
            function group:Stop() self.playing = false; self.stops = self.stops + 1 end
            function group:CreateAnimation(kind)
                local animation = { kind = kind }
                function animation:SetOrder(value) self.order = value end
                function animation:SetDuration(value) self.duration = value end
                function animation:SetStartDelay(value) self.delay = value end
                function animation:SetFromAlpha(value) self.from = value end
                function animation:SetToAlpha(value) self.to = value end
                group.animations[#group.animations + 1] = animation
                return animation
            end
            groups[#groups + 1] = group
            return group
        end
        textures[#textures + 1] = texture
        return texture
    end
    env.UIParent = { CreateTexture = Texture }
    env.CreateFrame = function(_, _, parent)
        local frame = { events = {}, scripts = {}, parent = parent, shown = false }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:SetSize() end
        function frame:SetFrameStrata() end
        function frame:EnableMouse(value) self.mouse = value end
        function frame:CreateTexture() return Texture() end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:ClearAllPoints() self.point = nil end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        frames[#frames + 1] = frame
        return frame
    end
    local cv = current or {
        SoftTargetInteract = "0", SoftTargetInteractRange = "10", SoftTargetInteractArc = "0",
        SoftTargetInteractOnlyInRange = "1", SoftTargetIconInteract = "0", SoftTargetIconGameObject = "0",
        SoftTargetLowPriorityIcons = "0", SoftTargetNameplateInteract = "1",
        outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2",
        OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2",
    }
    local s = { ns = ns, env = env, cv = cv, writes = writes, errors = errors,
        frames = frames, textures = textures, groups = groups }
    function s:fire(event, ...)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    env.C_CVar = {
        GetCVar = function(name) return cv[name] end,
        SetCVar = function(name, value)
            if name == s.reject then return false end
            writes[#writes + 1] = { name, value }
            cv[name] = value
            s:fire("CVAR_UPDATE", name, value)
            return true
        end,
    }
    env.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    env.UnitIsGameObject = function(unit)
        return target ~= nil and target.object ~= false and (unit == "softinteract" or unit == target.unit)
    end
    env.UnitIsUnit = function(unit, other)
        assert(other == "softinteract")
        return target ~= nil and unit == target.unit
    end
    env.SetUnitCursorTexture = function(texture, unit, _, lowPriority)
        assert(unit == "softinteract" and lowPriority == true)
        texture.texture, texture.atlas = target and target.cursor, target and target.atlas
        return target ~= nil
    end
    env.GetFileIDFromPath = function(path)
        return ({ Mine = 11, UnableMine = 12, GatherHerbs = 13, UnableGatherHerbs = 14 })[path:match("([^\\]+)$")]
    end
    env.C_NamePlate = { GetNamePlateForUnit = function(unit)
        if target and (unit == target.unit or (unit == "softinteract" and not s.fallback)) then
            return target.plate
        end
    end }
    for _, file in ipairs({ "core/Bootstrap.lua", "core/Settings.lua", "core/CVars.lua", "core/Lifecycle.lua",
        "functions/QuestLootSparkles.lua", "functions/GatheringSparkles.lua" }) do
        local chunk = assert(loadfile("CalmEUITweaks/" .. file))
        setfenv(chunk, env)
        chunk("CalmEUITweaks", ns)
    end
    s.driver = frames[3]
    function s:flush()
        local turns = 0
        while #timers > 0 do
            turns = turns + 1
            assert(turns < 10, "Gathering updates must settle without polling")
            local batch = timers
            timers = {}
            for _, callback in ipairs(batch) do callback() end
        end
    end
    function s:pending() return #timers end
    function s:combat(value) combat = value end
    function s:enable(value) ns.SetSetting("gatheringSparkles", "enabled", value) end
    function s:target(value)
        target = value
        if value and value.plate then value.plate.unit = value.unit end
        self:fire("PLAYER_SOFT_INTERACT_CHANGED")
        self:flush()
    end
    function s:plate()
        return { IsShown = function() return true end, IsForbidden = function() return false end,
            GetUnit = function(self) return self.unit end }
    end
    function s:sparkle() return frames[4] end
    s:fire("ADDON_LOADED", "CalmEUITweaks")
    s:fire("PLAYER_LOGIN")
    s:flush()
    return s
end

local s = New()
Check(not s.ns.db.gatheringSparkles.enabled and #s.writes == 0 and #s.textures == 0,
    "Default off must create no visuals or change console settings")
Check(not next(s.driver.events), "Default off must have no subscriptions")
s:enable(true)
Check(s.cv.SoftTargetInteract == "3" and s.cv.SoftTargetInteractRange == "15",
    "Enable must configure nearest interaction targeting")
Check(s.cv.SoftTargetNameplateInteract == "0" and not s:sparkle(),
    "No gathering target must have no effect or interaction nameplate")
Check(s.cv.graphicsOutlineMode == "2", "Gathering toggle must leave quest graphics settings alone")
local plate = s:plate()
s:target({ cursor = 11, plate = plate, unit = "nameplate1" })
Check(s.cv.SoftTargetNameplateInteract == "1" and s:sparkle().shown, "Mining target must show sparkles")
Check(s:sparkle().point[2] == plate and s:sparkle().mouse == false, "Sparkles must anchor to the node and ignore clicks")
Check(#s.groups == 5 and s:pending() == 0, "Native animation must not queue gameplay timers")
s:fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
Check(not s:sparkle().shown, "A plate already present at enable must hide on removal without an add event")
s:target({ cursor = 11, plate = plate, unit = "nameplate1" })
for _, group in ipairs(s.groups) do
    Check(group.playing and group.loop == "REPEAT" and #group.animations == 2,
        "Each glint must use native fade animations")
end
local playCount = s.groups[1].plays
s:fire("NAME_PLATE_UNIT_ADDED", "unrelatedNPC")
s:fire("NAME_PLATE_UNIT_REMOVED", "unrelatedNPC")
Check(s:pending() == 0 and s.groups[1].plays == playCount, "Unrelated NPC plates must not refresh or restart sparkles")
s:fire("CVAR_UPDATE", "unrelated")
Check(s:pending() == 0, "Unrelated console changes must schedule no work")
s:target({ cursor = 14, plate = plate, unit = "nameplate2" })
Check(s:sparkle().shown, "Unable herb cursor must still sparkle with the fixed appearance")
s:target({ cursor = "Interface\\Cursor\\GatherHerbs", plate = plate, unit = "nameplate2" })
Check(s:sparkle().shown, "Path-based gathering cursors must work")
s:target({ atlas = "Cursor_Crosshair_UnableMine_64", plate = plate, unit = "nameplate2" })
Check(s:sparkle().shown, "Atlas-based gathering cursors must work")
s:target({ cursor = 11, object = false, plate = plate, unit = "nameplateNPC" })
Check(not s:sparkle().shown and not s.groups[1].playing, "NPCs must hide the effect and stop animations")
s:target({ cursor = "Interface\\Cursor\\Quest", plate = plate, unit = "nameplateQuest" })
Check(not s:sparkle().shown, "Quest objects must not receive gathering sparkles")
s:target(nil)
s:enable(false)
Check(s.cv.SoftTargetNameplateInteract == "1" and s.cv.SoftTargetInteract == "0",
    "Nameplate gating changes must retain the original baseline for restoration")
Check(not next(s.driver.events) and not next(s.ns.db.gatheringSparkles.restore),
    "Disable must restore owned values and release events")

local fallback = New()
fallback.fallback = true
fallback:enable(true)
local fallbackPlate = fallback:plate()
fallback:target({ cursor = 13, unit = "nameplate3" })
Check(not fallback:sparkle(), "Unavailable node plate must wait without drawing")
fallback:target({ cursor = 13, unit = "nameplate3", plate = fallbackPlate })
fallback:fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
fallback:flush()
Check(fallback:sparkle().shown, "Nameplate event must recover a node exposed through a nameplate token")
fallback:fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
Check(not fallback:sparkle().shown, "Removed nameplate must hide synchronously")
fallback:target(nil)
Check(not fallback:sparkle().shown, "Recycled nameplate must not retain the effect")

local combat = New()
combat:combat(true)
combat:enable(true)
Check(#combat.writes == 0 and combat.driver.events.PLAYER_REGEN_ENABLED, "Combat must defer console and visual setup")
combat:combat(false)
combat:fire("PLAYER_REGEN_ENABLED")
combat:flush()
combat:target({ cursor = 11, plate = combat:plate(), unit = "nameplate4" })
combat:combat(true)
combat.ns.ResetSettings()
Check(not combat:sparkle().shown and combat.driver.events.PLAYER_REGEN_ENABLED,
    "Reset in combat must stop animations and retain pending restoration")
combat:combat(false)
combat:fire("PLAYER_REGEN_ENABLED")
combat:flush()
Check(combat.cv.SoftTargetInteract == "0" and combat.cv.SoftTargetNameplateInteract == "1",
    "Reset must restore pre-feature interaction settings")
Check(not next(combat.driver.events), "Completed combat restoration must release all listeners")

local external = New()
external:enable(true)
external.cv.SoftTargetInteractRange = "8"
external:enable(false)
Check(external.cv.SoftTargetInteractRange == "8", "Disable must preserve later external writes")
local gating = New()
gating:enable(true)
gating:target({ cursor = 11, plate = gating:plate(), unit = "nameplate8" })
gating:enable(false)
Check(gating.cv.SoftTargetNameplateInteract == "1",
    "Disabling on a node must restore the baseline from before our nameplate gating")
local reload = New()
reload:enable(true)
reload:target({ cursor = 11, plate = reload:plate(), unit = "nameplate5" })
local restored = New(reload.ns.db, reload.cv)
restored:enable(false)
Check(restored.cv.SoftTargetInteract == "0" and restored.cv.SoftTargetNameplateInteract == "1",
    "Dynamic nameplate ownership must survive reload and character switch")

local unavailable = New()
unavailable.env.SetUnitCursorTexture = nil
unavailable:enable(true)
Check(#unavailable.writes == 0 and unavailable.ns.GetStatus("gatheringSparkles"):find("Waiting"),
    "Missing native target APIs must wait without side effects")
local missing = New()
missing.cv.SoftTargetInteractRange = nil
missing:enable(true)
Check(#missing.writes == 0, "Missing console variable must not partially configure targeting")
missing.cv.SoftTargetInteractRange = "10"
missing:fire("VARIABLES_LOADED")
missing:flush()
Check(missing.cv.SoftTargetInteract == "3", "Readiness event must recover missing variables")
local failed = New()
failed.reject = "SoftTargetInteractRange"
failed:enable(true)
Check(failed.ns.errors.gatheringSparkles ~= nil, "Failed console write must report through shared errors")
failed.reject = nil
failed:fire("PLAYER_ENTERING_WORLD")
failed:flush()
Check(failed.ns.errors.gatheringSparkles == nil and failed.cv.SoftTargetInteractRange == "15",
    "Later readiness event must recover a failed write")
failed.ns.SetSetting("questLootSparkles", "enabled", true)
failed:enable(false)
Check(failed.cv.graphicsOutlineMode == "0" and failed.ns.db.questLootSparkles.enabled,
    "Gathering disable must leave the independent quest toggle enabled")

local forbidden = New()
forbidden:enable(true)
forbidden:target({ cursor = 11, unit = "nameplate6", plate = {
    IsForbidden = function() return true end,
    IsShown = function() error("Must not inspect a forbidden nameplate") end,
} })
Check(not forbidden:sparkle() and #forbidden.errors == 0, "Forbidden plates must not be accessed or drawn on")
local secret = New()
secret.env.issecretvalue = function(value) return value == "unreadable" end
secret:enable(true)
secret:target({ cursor = "unreadable", unit = "nameplate7", plate = secret:plate() })
Check(not secret:sparkle() and #secret.errors == 0, "Unreadable cursor data must skip decoration without errors")
Check(#s.frames == 4 and #s.textures == 6, "Target changes must reuse one effect and one cursor probe")
print("GatheringSparkles: " .. checks .. " checks passed")
