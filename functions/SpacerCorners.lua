local addonName, ns = ...
local module = {}
local units = { "player", "target" }
local facing = {
    LEFT = { TOPRIGHT = true, BOTTOMRIGHT = true },
    RIGHT = { TOPLEFT = true, BOTTOMLEFT = true },
    TOP = { BOTTOMLEFT = true, BOTTOMRIGHT = true },
    BOTTOM = { TOPLEFT = true, TOPRIGHT = true },
}

function ns.IsSpacerCornerCompatible(side, corner)
    return corner == "DEFAULT" or (facing[side] and facing[side][corner]) == true
end
local driver, listenerHost, snapshot, editing, applying
local hooked = setmetatable({}, { __mode = "k" })
local managed = setmetatable({}, { __mode = "k" })
local seen = {}
local eventMask = {}
local function RegisterEvent(event)
    if not eventMask[event] then driver:RegisterEvent(event); eventMask[event] = true end
end
local function UnregisterEvent(event)
    if eventMask[event] then driver:UnregisterEvent(event); eventMask[event] = nil end
end

local function Active()
    local settings = ns.GetSettings("spacerCorners")
    return settings.player ~= "DEFAULT" or settings.target ~= "DEFAULT"
end

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function FrameFor(eui, key)
    local registry = eui._unlockRegisteredElements
    local element = type(registry) == "table" and registry[key]
    return element and type(element.getFrame) == "function" and element.getFrame(key)
end

local function HookSize(frame)
    if not frame or hooked[frame] then return end
    frame:HookScript("OnSizeChanged", function()
        if not applying and Active() and managed[frame] then ns.RequestApply("spacerCorners") end
    end)
    hooked[frame] = true
end

local function Update()
    if applying then return end
    if InCombatLockdown() then RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    UnregisterEvent("PLAYER_REGEN_ENABLED")
    local eui, db = _G.EllesmereUI, _G.EllesmereUIDB
    if type(eui) ~= "table" or type(eui.ReapplyOwnAnchor) ~= "function"
        or type(db) ~= "table" or type(db.unlockAnchors) ~= "table" then return end
    local changed = {}
    managed = setmetatable({}, { __mode = "k" })
    for _, unit in ipairs(units) do
        local choice = ns.GetSettings("spacerCorners")[unit]
        local info = db.unlockAnchors[unit]
        local replaced = seen[unit] ~= nil and seen[unit] ~= info
        seen[unit] = info
        local index = type(info) == "table" and type(info.target) == "string"
            and tonumber(info.target:match("^CalmUITweaks_Spacer([1-4])$"))
        if choice ~= "DEFAULT" and index and ns.GetSettings("spacers")["spacer" .. index]
            and ns.IsSpacerCornerCompatible(info.side, choice) then
            local child, target = FrameFor(eui, unit), FrameFor(eui, info.target)
            if child then managed[child] = true end
            if target then managed[target] = true end
            HookSize(child); HookSize(target)
            if child and target then
                local scale = UIParent:GetEffectiveScale()
                local horizontal = info.side == "LEFT" or info.side == "RIGHT"
                local childSize = (horizontal and child:GetHeight() or child:GetWidth())
                    * child:GetEffectiveScale() / scale
                local targetSize = (horizontal and target:GetHeight() or target:GetWidth())
                    * target:GetEffectiveScale() / scale
                if Finite(childSize) and Finite(targetSize) and childSize > 0 and targetSize > 0 then
                    -- Native edge anchors use center offsets on the cross axis.
                    local positive = horizontal and choice:find("TOP", 1, true)
                        or not horizontal and choice:find("RIGHT", 1, true)
                    local base = (targetSize - childSize) * (positive and 1 or -1) / 2
                    local record = ns.charDB.spacerCorners[unit]
                    local same = not replaced and type(record) == "table" and record.target == info.target
                        and record.corner == choice and record.side == info.side and Finite(record.base)
                    local cross, normal = base, 0
                    if same then
                        local oldCross = horizontal and info.offsetY or info.offsetX
                        local oldNormal = horizontal and info.offsetX or info.offsetY
                        if Finite(oldCross) then cross = oldCross + base - record.base end
                        if Finite(oldNormal) then normal = oldNormal end
                    end
                    local x, y = horizontal and normal or cross, horizontal and cross or normal
                    if not same then
                        ns.charDB.spacerCorners[unit] = {target = info.target, corner = choice,
                            side = info.side, base = base}
                    else record.base = base end
                    if not Finite(info.offsetX) or not Finite(info.offsetY)
                        or math.abs(info.offsetX - x) > 0.000001 or math.abs(info.offsetY - y) > 0.000001 then
                        info.offsetX, info.offsetY = x, y
                        changed[#changed + 1] = unit
                    end
                end
            end
        else
            ns.charDB.spacerCorners[unit] = nil
        end
    end
    applying = true
    local ok, err = pcall(function()
        for _, unit in ipairs(changed) do
            eui.ReapplyOwnAnchor(unit)
            if type(eui.PropagateAnchorChain) == "function" then eui.PropagateAnchorChain(unit) end
        end
    end)
    applying = false
    if not ok then error(err) end
end

local function Changed(key)
    if not applying and Active() and (not key or key == "player" or key == "target") then
        ns.RequestApply("spacerCorners")
    end
end

function module:ApplySettings()
    local eui = _G.EllesmereUI
    if not Active() then
        ns.ObserveAnchors("spacerCorners", nil)
        managed = setmetatable({}, { __mode = "k" })
        UnregisterEvent("PLAYER_REGEN_ENABLED")
        UnregisterEvent("PLAYER_ENTERING_WORLD")
        if listenerHost and type(listenerHost.UnregisterUnlockModeListener) == "function" then
            listenerHost:UnregisterUnlockModeListener(addonName .. "_SpacerCorners")
            listenerHost = nil
        end
        if ns.charDB then
            ns.charDB.spacerCorners.player, ns.charDB.spacerCorners.target = nil, nil
        end
        ns.SetStatus("spacerCorners", "Player: DEFAULT; Target: DEFAULT.")
        return
    end
    if type(eui) ~= "table" or type(eui.RegisterUnlockModeListener) ~= "function" then
        ns.SetStatus("spacerCorners", "Waiting for EUI Unlock Mode API.")
        return
    end
    if listenerHost ~= eui then
        listenerHost = eui
        eui:RegisterUnlockModeListener(addonName .. "_SpacerCorners", function(active, closeAction)
            editing = active == true
            if editing then
                if Active() then snapshot = ns.Copy(ns.charDB.spacerCorners) end
            else
                -- EUI restores its anchor/size snapshot on Discard; restore our size baseline too.
                if snapshot and closeAction ~= "save" then ns.charDB.spacerCorners = snapshot end
                local db = _G.EllesmereUIDB
                for _, unit in ipairs(units) do
                    seen[unit] = type(db) == "table" and type(db.unlockAnchors) == "table"
                        and db.unlockAnchors[unit] or nil
                end
                local hadSnapshot = snapshot ~= nil
                snapshot = nil
                if Active() or hadSnapshot then ns.RequestApply("spacerCorners") end
            end
        end)
    end
    local connected = ns.ObserveAnchors("spacerCorners", Changed)
    RegisterEvent("PLAYER_ENTERING_WORLD")
    Update()
    if not connected then
        ns.SetStatus("spacerCorners", "Waiting for EUI frame placement API.")
        return
    end
    ns.SetStatus("spacerCorners", "Player: " .. ns.GetSettings("spacerCorners").player
        .. "; Target: " .. ns.GetSettings("spacerCorners").target .. ".")
end

function module:Initialize()
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then UnregisterEvent(event) end
        if ns.ready then ns.CallModule("spacerCorners", "ApplySettings") end
    end)
end

function module:OnAddonLoaded(name)
    if Active() and ns.IsEUIAddon(name) then ns.RequestApply("spacerCorners") end
end

ns.RegisterModule("spacerCorners", module)
