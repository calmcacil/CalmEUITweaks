local addonName, ns = ...
local module = {}
local frames, elements, registered = {}, {}, {}
local pending = false
local events, listenerHost
local eventMask = {}
local function RegisterEvent(event)
    if not eventMask[event] then events:RegisterEvent(event); eventMask[event] = true end
end
local function UnregisterEvent(event)
    if eventMask[event] then events:UnregisterEvent(event); eventMask[event] = nil end
end
local function UnregisterListener()
    if listenerHost and type(listenerHost.UnregisterUnlockModeListener) == "function" then
        listenerHost:UnregisterUnlockModeListener(addonName .. "_Spacers")
    end
    listenerHost = nil
end
local points = { CENTER = true, LEFT = true, RIGHT = true, TOP = true, BOTTOM = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Dimension(value, fallback)
    if not Finite(value) then return fallback end
    return math.max(1, math.min(2000, value))
end

local function Layout(index)
    local store = ns.db.spacerLayouts
    if type(store[index]) ~= "table" then store[index] = {} end
    local layout = store[index]
    layout.width = Dimension(layout.width, 24)
    layout.height = Dimension(layout.height, 24)
    local pos = layout.position
    if type(pos) ~= "table" or not points[pos.point] or not points[pos.relPoint]
        or not Finite(pos.x) or not Finite(pos.y) then
        layout.position = { point = "CENTER", relPoint = "CENTER", x = (index - 2.5) * 60, y = -180 }
    end
    return layout
end

local function ApplyPosition(index)
    if InCombatLockdown() then pending = true; RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    local frame = frames[index]
    if not frame then return end
    local eui = _G.EllesmereUI
    local key = elements[index].key
    -- EUI owns chained anchors; standalone placement must not overwrite them.
    if type(eui.IsUnlockAnchored) == "function" and eui.IsUnlockAnchored(key) then
        if type(eui.ReapplyOwnAnchor) == "function" then eui.ReapplyOwnAnchor(key) end
        return
    end
    local pos = Layout(index).position
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    -- The early login API has ReapplyOwnAnchor before IsUnlockAnchored exists.
    if type(eui.ReapplyOwnAnchor) == "function" then eui.ReapplyOwnAnchor(key) end
end

local function MakeElement(index)
    local key = "CalmUITweaks_Spacer" .. index
    local frame = CreateFrame("Frame", key, UIParent)
    frames[index] = frame
    -- Keep the anchor frame shown without artwork or input, even outside edit mode.
    frame:EnableMouse(false)
    local layout = Layout(index)
    frame:SetSize(layout.width, layout.height)
    local pos = layout.position
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    frame:Show()
    local function SetDimension(axis, value)
        if not Finite(value) then return end
        if InCombatLockdown() then return end
        local current = Layout(index)
        current[axis] = Dimension(value, current[axis])
        frame:SetSize(current.width, current.height)
    end
    local element = {
        key = key, label = "Spacer " .. index, group = "Calm UI Tweaks", order = 900 + index,
        getFrame = function() return frame end,
        getSize = function() return frame:GetWidth(), frame:GetHeight() end,
        setWidth = function(_, value) SetDimension("width", value) end,
        setHeight = function(_, value) SetDimension("height", value) end,
        loadPosition = function() return ns.Copy(Layout(index).position) end,
        savePosition = function(_, point, relPoint, x, y)
            if not points[point] or not points[relPoint] or not Finite(x) or not Finite(y) then return end
            Layout(index).position = { point = point, relPoint = relPoint, x = x, y = y }
            local eui = _G.EllesmereUI
            if not (type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive()) then
                ApplyPosition(index)
            end
        end,
        clearPosition = function() Layout(index).position = nil; Layout(index) end,
        applyPosition = function() ApplyPosition(index) end,
    }
    elements[index] = element
    return element
end

function module:ApplySettings()
    local eui = _G.EllesmereUI
    local wanted = false
    for index = 1, 4 do
        if ns.GetSettings("spacers")["spacer" .. index] or registered[index] then wanted = true end
    end
    if not wanted then
        pending = false
        UnregisterEvent("PLAYER_REGEN_ENABLED")
        UnregisterEvent("PLAYER_ENTERING_WORLD")
        UnregisterListener()
        ns.SetStatus("spacers", "Disabled")
        return
    end
    if type(eui) == "table" and type(eui.RegisterUnlockModeListener) == "function"
        and listenerHost ~= eui then
        listenerHost = eui
        eui:RegisterUnlockModeListener(addonName .. "_Spacers", function(active)
            if not active and pending then ns.RequestApply("spacers") end
        end)
    end
    if InCombatLockdown() then pending = true; RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    UnregisterEvent("PLAYER_REGEN_ENABLED")
    if type(eui) ~= "table" or type(eui.RegisterUnlockElements) ~= "function"
        or type(eui.UnregisterUnlockElement) ~= "function" then
        ns.SetStatus("spacers", "Waiting for EUI Unlock Mode API.")
        return
    end
    if type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive() then
        pending = true
        ns.SetStatus("spacers", "Changes pending until Unlock Mode closes.")
        return
    end
    pending = false
    local count = 0
    for index = 1, 4 do
        local enabled = ns.GetSettings("spacers")["spacer" .. index]
        if enabled then
            count = count + 1
            if not registered[index] then
                local element = elements[index] or MakeElement(index)
                local layout = Layout(index)
                frames[index]:SetSize(layout.width, layout.height)
                eui:RegisterUnlockElements({ element }, addonName)
                registered[index] = true
            end
            ApplyPosition(index)
        elseif registered[index] then
            eui:UnregisterUnlockElement(elements[index].key)
            registered[index] = nil
        end
    end
    ns.SetStatus("spacers", count == 0 and "Disabled" or (count .. " spacer(s) enabled."))
    if count > 0 then RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        UnregisterEvent("PLAYER_ENTERING_WORLD")
        UnregisterListener()
    end
end

function module:Initialize()
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then UnregisterEvent(event) end
        if ns.ready and (event ~= "PLAYER_REGEN_ENABLED" or pending) then
            ns.CallModule("spacers", "ApplySettings")
        end
    end)
end

function module:OnAddonLoaded(name)
    if ns.IsEUIAddon(name) then ns.RequestApply("spacers") end
end

ns.RegisterModule("spacers", module)
