local _, ns = ...
local module = {}
ns.RegisterModule("gatheringSparkles", module)

local values = {
    { "SoftTargetInteract", "3" },
    { "SoftTargetInteractRange", "15" },
    { "SoftTargetInteractArc", "2" },
    { "SoftTargetInteractOnlyInRange", "0" },
    { "SoftTargetIconInteract", "1" },
    { "SoftTargetIconGameObject", "1" },
    { "SoftTargetLowPriorityIcons", "1" },
    { "SoftTargetNameplateInteract", "0", "1" },
}
local watched = {}
for _, entry in ipairs(values) do watched[string.lower(entry[1])] = true end
local events = CreateFrame("Frame")
local plateUnits, cursorIDs, animations = {}, {}, {}
local probe, sparkle, anchor, anchorUnit

local function Read(func, ...)
    local ok, value = pcall(func, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function HideSparkles()
    if not sparkle then return end
    sparkle:Hide()
    for _, group in ipairs(animations) do group:Stop() end
    sparkle:ClearAllPoints()
    anchor, anchorUnit = nil, nil
end

local function IsGatheringTarget()
    if Read(UnitIsGameObject, "softinteract") ~= true then return false end
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        if GetFileIDFromPath then
            for _, name in ipairs({ "Mine", "UnableMine", "GatherHerbs", "UnableGatherHerbs" }) do
                local path = "Interface\\Cursor\\" .. name
                local id = Read(GetFileIDFromPath, path) or Read(GetFileIDFromPath, path .. ".blp")
                if type(id) == "number" then cursorIDs[id] = true end
            end
        end
    end
    if Read(SetUnitCursorTexture, probe, "softinteract", nil, true) ~= true then return false end
    local texture = Read(probe.GetTexture, probe)
    if type(texture) == "number" and cursorIDs[texture] then return true end
    local cursor = Read(probe.GetAtlas, probe)
    if type(cursor) ~= "string" then cursor = texture end
    if type(cursor) ~= "string" then return false end
    cursor = string.lower(cursor)
    return cursor:find("mine", 1, true) ~= nil or cursor:find("gatherherbs", 1, true) ~= nil
end

local function FindPlate()
    local plate = Read(C_NamePlate.GetNamePlateForUnit, "softinteract")
    local plateUnit = "softinteract"
    if not plate then
        for unit in pairs(plateUnits) do
            if Read(UnitIsUnit, unit, "softinteract") == true then
                plate = Read(C_NamePlate.GetNamePlateForUnit, unit)
                if plate then plateUnit = unit; break end
            end
        end
    end
    if plate and (not plate.IsForbidden or not plate:IsForbidden()) and plate:IsShown() then
        return plate, Read(plate.GetUnit, plate) or plateUnit
    end
end

local function ShowSparkles(plate, unit)
    if not sparkle then
        sparkle = CreateFrame("Frame", nil, UIParent)
        sparkle:SetSize(1, 1)
        sparkle:SetFrameStrata("HIGH")
        sparkle:EnableMouse(false)
        local points = { { -21, 0 }, { -10, 11 }, { 0, -6 }, { 12, 6 }, { 23, -3 } }
        for index, point in ipairs(points) do
            local texture = sparkle:CreateTexture(nil, "OVERLAY")
            texture:SetTexture("Interface\\Cooldown\\star4")
            texture:SetBlendMode("ADD")
            texture:SetSize(16, 16)
            texture:SetPoint("CENTER", sparkle, "CENTER", point[1], point[2])
            texture:SetVertexColor(1, 0.86, 0.45)
            texture:SetAlpha(0)
            local group = texture:CreateAnimationGroup()
            group:SetLooping("REPEAT")
            local fadeIn = group:CreateAnimation("Alpha")
            fadeIn:SetOrder(1)
            fadeIn:SetDuration(0.4)
            fadeIn:SetStartDelay((index - 1) * 0.17)
            fadeIn:SetFromAlpha(0)
            fadeIn:SetToAlpha(0.9)
            local fadeOut = group:CreateAnimation("Alpha")
            fadeOut:SetOrder(2)
            fadeOut:SetDuration(0.65)
            fadeOut:SetFromAlpha(0.9)
            fadeOut:SetToAlpha(0)
            animations[index] = group
        end
    end
    if anchor == plate then return end
    HideSparkles()
    sparkle:SetPoint("CENTER", plate, "CENTER", 0, -40)
    anchor, anchorUnit = plate, unit
    sparkle:Show()
    for _, group in ipairs(animations) do group:Play() end
end

function module:Initialize()
    ns.InitializeCVarRestore(ns.GetSettings("gatheringSparkles"), values)
end

function module:ApplySettings()
    local settings = ns.GetSettings("gatheringSparkles")
    local enabled = settings.enabled
    events:UnregisterAllEvents()
    if enabled then
        events:RegisterEvent("CVAR_UPDATE")
        events:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
        events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    else
        HideSparkles()
        plateUnits = {}
        if not next(settings.restore) then
            ns.SetStatus("gatheringSparkles", "Disabled")
            return
        end
    end
    events:RegisterEvent("VARIABLES_LOADED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if InCombatLockdown() then
        HideSparkles()
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.SetStatus("gatheringSparkles", "Waiting for combat to end.")
        return
    end
    if enabled and (type(UnitIsGameObject) ~= "function" or type(SetUnitCursorTexture) ~= "function"
        or type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function") then
        HideSparkles()
        ns.SetStatus("gatheringSparkles", "Waiting for native interaction targeting.")
        return
    end
    local node = enabled and IsGatheringTarget()
    values[8][2] = node and "1" or "0"
    local ok, reason = ns.ApplyOwnedCVars(settings, values, enabled)
    if not ok then HideSparkles(); ns.SetStatus("gatheringSparkles", reason); return end
    if not enabled then
        events:UnregisterAllEvents()
        ns.SetStatus("gatheringSparkles", "Disabled")
        return
    end
    local plate, unit
    if node then plate, unit = FindPlate() end
    if plate then ShowSparkles(plate, unit) else HideSparkles() end
    ns.SetStatus("gatheringSparkles", plate and "Enabled; nearby gathering node marked."
        or (node and "Waiting for the gathering node's nameplate." or "Enabled; no nearby gathering target."))
end

events:SetScript("OnEvent", function(_, event, name)
    if event == "CVAR_UPDATE" then
        if ns.IsApplyingCVars() or type(name) ~= "string" or not watched[string.lower(name)] then return end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if Read(UnitIsGameObject, name) ~= true and Read(UnitIsUnit, name, "softinteract") ~= true then return end
        plateUnits[name] = true
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plateUnits[name] = nil
        if name ~= anchorUnit then return end
        HideSparkles()
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        HideSparkles()
    elseif event == "PLAYER_ENTERING_WORLD" then
        plateUnits = {}
        HideSparkles()
    end
    ns.RequestApply("gatheringSparkles")
end)
