local addonName, ns = ...
local module = {}
local driver, listenerHost, session, store
local observed, dirty = {}, {}
local queued, observing = false, false
local directions = { LEFT = { "offsetX", -1, "left" }, RIGHT = { "offsetX", 1, "right" },
    TOP = { "offsetY", 1, "top" }, BOTTOM = { "offsetY", -1, "bottom" } }

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function AnchorStore()
    local db = _G.EllesmereUIDB
    return type(db) == "table" and type(db.unlockAnchors) == "table" and db.unlockAnchors or nil
end

local function Snapshot()
    store, observed, dirty = AnchorStore(), {}, {}
    for key, info in pairs(store or {}) do observed[key] = info end
end

local function Excluded(key)
    return type(key) ~= "string" or key:match("^SCREEN_") or key:match("^CalmUITweaks_Spacer")
end

local function Scan()
    local eui = _G.EllesmereUI
    if not session or not ns.GetSettings("anchorGap").enabled or InCombatLockdown()
        or not eui:IsUnlockModeActive() then return end
    if AnchorStore() ~= store then Snapshot(); return end
    if not store then return end
    local settings = ns.GetSettings("anchorGap")
    local changed = {}
    for key in pairs(dirty) do
        dirty[key] = nil
        local info = store[key]
        local fresh = observed[key] ~= info
        observed[key] = info
        if fresh and type(info) == "table" and not Excluded(key) and not Excluded(info.target) then
            local direction = directions[info.side]
            if direction then
                local gap = eui.PP.FromPixels(settings[direction[3]])
                -- Native bar corner picks retain a cardinal side. Its axis is the
                -- outward gap; the other offset and growth pin hold corner alignment.
                local axis, sign = direction[1], direction[2]
                local offset = info[axis] or 0
                local other = info[axis == "offsetX" and "offsetY" or "offsetX"] or 0
                if Finite(gap) and gap > 0 and Finite(offset) and Finite(other)
                    and math.abs(offset) < 0.000001 then
                    local delta = gap * sign
                    info.offsetX, info.offsetY = info.offsetX or 0, info.offsetY or 0
                    info[axis] = delta
                    -- EUI growth pins can already be captured by the initial native placement.
                    local pin = axis == "offsetX" and "edgeOffX" or "edgeOffY"
                    local pinDirection = info.refFor
                    local pinsX = pinDirection == "LEFT" or pinDirection == "RIGHT"
                    local pinsY = pinDirection == "UP" or pinDirection == "DOWN"
                    if Finite(info[pin]) and (pinDirection == nil
                        or axis == "offsetX" and pinsX or axis == "offsetY" and pinsY) then
                        info[pin] = info[pin] + delta
                    end
                    changed[#changed + 1] = key
                end
            end
        end
    end
    for _, key in ipairs(changed) do
        eui.ReapplyUnlockAnchor(key)
        if type(eui.PropagateAnchorChain) == "function" then eui.PropagateAnchorChain(key) end
    end
end

local function Queue()
    if queued then return end
    if InCombatLockdown() then driver:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if not observing then return end
        if InCombatLockdown() then driver:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
        local ok, err = pcall(Scan)
        if not ok then ns.ReportError("anchorGap", err) end
    end)
end

local function Changed(key, reason)
    if not observing then return end
    if AnchorStore() ~= store or reason == "layout" then Snapshot(); return end
    if key and store and observed[key] ~= store[key] then
        dirty[key] = true
        Queue()
    end
end

local function UpdateObserver()
    local eui = _G.EllesmereUI
    local active = session and ns.GetSettings("anchorGap").enabled
        and type(eui.ReapplyUnlockAnchor) == "function"
    if active and not observing then Snapshot() end
    observing = active == true
    if not observing then dirty = {}; driver:UnregisterAllEvents() end
    if not ns.ObserveAnchors("anchorGap", observing and Changed or nil) and observing then
        observing = false
        ns.SetStatus("anchorGap", "Waiting for EUI frame placement API.")
        return false
    end
    return true
end

function module:ApplySettings()
    local eui = _G.EllesmereUI
    if not ns.GetSettings("anchorGap").enabled then
        observing, session = false, false
        dirty = {}
        driver:UnregisterAllEvents()
        ns.ObserveAnchors("anchorGap", nil)
        if listenerHost and type(listenerHost.UnregisterUnlockModeListener) == "function" then
            listenerHost:UnregisterUnlockModeListener(addonName .. "_AnchorGap")
            listenerHost = nil
        end
        ns.SetStatus("anchorGap", "Disabled")
        return
    end
    if type(eui) ~= "table" or type(eui.RegisterUnlockModeListener) ~= "function"
        or type(eui.IsUnlockModeActive) ~= "function"
        or type(eui.PP) ~= "table" or type(eui.PP.FromPixels) ~= "function" then
        observing = false
        ns.ObserveAnchors("anchorGap", nil)
        driver:UnregisterAllEvents()
        ns.SetStatus("anchorGap", "Waiting for EUI anchor and pixel APIs.")
        return
    end
    if listenerHost ~= eui then
        listenerHost = eui
        eui:RegisterUnlockModeListener(addonName .. "_AnchorGap", function(active)
            session = active == true
            UpdateObserver()
        end)
    end
    session = eui:IsUnlockModeActive()
    if not UpdateObserver() then return end
    local settings = ns.GetSettings("anchorGap")
    ns.SetStatus("anchorGap", settings.enabled and string.format(
        "New anchors (px): top %d, bottom %d, left %d, right %d.",
        settings.top, settings.bottom, settings.left, settings.right) or "Disabled")
end

function module:Initialize()
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function()
        driver:UnregisterAllEvents()
        if observing and next(dirty) then Queue() end
    end)
end

function module:OnAddonLoaded(name)
    if ns.IsEUIAddon(name) then ns.RequestApply("anchorGap") end
end

ns.RegisterModule("anchorGap", module)
