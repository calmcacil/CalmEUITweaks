local addonName, ns = ...
local module = { asyncErrors = true }
ns.RegisterModule("totalRP3Skin", module)

local requested, registered, skin, pending, editing
local listenerHost, callbackHost, events
local summary = {}
local surfaceErrors = {}

local function ClearFailures()
    surfaceErrors = {}
    ns.ClearError("totalRP3Skin")
end

local function Loaded()
    local api = C_AddOns
    if not api or type(api.IsAddOnLoaded) ~= "function" then return false end
    local available, loaded = api.IsAddOnLoaded("totalRP3")
    if loaded ~= nil then return loaded == true end
    return available == true
end

local function Enabled()
    return requested and ns.ready and ns.GetSettings("totalRP3Skin").enabled
        and skin and skin.IsEnabled()
end

local function Editing()
    local eui = _G.EllesmereUI
    return editing or (eui and type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive())
end

local function ReleaseWaits()
    pending = false
    if ns.TotalRP3SkinFrames.ClearPending then ns.TotalRP3SkinFrames.ClearPending() end
    events:UnregisterAllEvents()
    if listenerHost then
        listenerHost:UnregisterUnlockModeListener(addonName .. "_TotalRP3Skin")
        listenerHost = nil
    end
    editing = false
    if callbackHost then
        callbackHost.UnregisterCallback(module, "PAGE_OPENED")
        callbackHost = nil
    end
end

local function Allowed()
    if not Enabled() then return false end
    if InCombatLockdown() or Editing() then
        pending = true
        if InCombatLockdown() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false, true
    end
    return true
end

local function Report(surface, err)
    surfaceErrors[surface] = err and tostring(err) or nil
    if err then
        ns.ReportError("totalRP3Skin", surface .. ": " .. tostring(err))
    elseif not next(surfaceErrors) then
        ns.ClearError("totalRP3Skin")
    end
end

function module:GetStatus()
    local wanted = ns.GetSettings("totalRP3Skin").enabled
    if requested ~= nil and wanted ~= requested then
        return "Reload required; " .. (wanted and "enable" or "restore native") .. " Total RP 3 styling."
    end
    if not wanted then return "Disabled" end
    if not Loaded() then return "Waiting for Total RP 3 to be installed, enabled, and loaded." end
    local eui = _G.EllesmereUI
    if not eui or type(eui.RegisterSkin) ~= "function" then return "Waiting for EUI skinning API." end
    if not skin then return "Waiting for EUI skin callback; check CalmEUITweaks in EUI third-party skins." end
    if not skin.IsEnabled() then return "Disabled in EUI; enable CalmEUITweaks in third-party skins and reload." end
    if InCombatLockdown() and pending then return "Waiting for combat to end." end
    if Editing() and pending then return "Waiting for EUI Unlock Mode to close." end
    if summary.conflict then return "Conflict: " .. summary.conflict end
    if summary.unsupported then return "Partial coverage: " .. summary.unsupported end
    if (summary.applied or 0) == 0 then return "Waiting for supported Total RP 3 frames." end
    return "Active; Total RP 3 uses the EUI theme."
end

function module:Initialize()
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function()
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pending then ns.RequestApply("totalRP3Skin") end
    end)
end

function module:OnLogin()
    requested = ns.GetSettings("totalRP3Skin").enabled
end

function module:ApplySettings()
    if not requested or not ns.GetSettings("totalRP3Skin").enabled then
        ReleaseWaits()
        ClearFailures()
        return
    end
    if not Loaded() then return end
    local eui = _G.EllesmereUI
    if not eui or type(eui.RegisterSkin) ~= "function" then return end
    if not registered then
        eui.RegisterSkin(addonName, function(supplied)
            if type(supplied) ~= "table" or type(supplied.IsEnabled) ~= "function" then
                ns.ReportError("totalRP3Skin", "EUI supplied an incompatible skinning API.")
                return
            end
            skin = supplied
            if type(skin.OnLooksChanged) == "function" then
                local wasEnabled = skin.IsEnabled()
                skin.OnLooksChanged(function()
                    local nowEnabled = skin.IsEnabled()
                    if not nowEnabled then ReleaseWaits(); ClearFailures()
                    elseif not wasEnabled then ns.RequestApply("totalRP3Skin") end
                    wasEnabled = nowEnabled
                    if ns.RefreshOptions then ns.RefreshOptions() end
                end)
            end
            ns.RequestApply("totalRP3Skin")
        end)
        registered = true
    end
    if not skin or not Enabled() then
        ReleaseWaits()
        if skin and not skin.IsEnabled() then ClearFailures() end
        return
    end
    if not listenerHost and type(eui.RegisterUnlockModeListener) == "function"
        and type(eui.UnregisterUnlockModeListener) == "function" then
        listenerHost = eui
        eui:RegisterUnlockModeListener(addonName .. "_TotalRP3Skin", function(active)
            editing = active == true
            if not editing and pending then ns.RequestApply("totalRP3Skin") end
        end)
    end
    if not Allowed() then return end
    pending = false
    events:UnregisterAllEvents()
    local frames = ns.TotalRP3SkinFrames
    local trp = _G.TRP3_Addon
    if not callbackHost and trp and type(trp.RegisterCallback) == "function"
        and type(trp.UnregisterCallback) == "function" then
        trp.RegisterCallback(module, "PAGE_OPENED", function(_, pageId, context)
            ns.CallModule("totalRP3Skin", "OnPageOpened", pageId, context)
        end)
        callbackHost = trp
    end
    frames.InstallHooks(skin, Allowed, Report)
    summary = frames.Apply(skin, Allowed, Report)
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function module:OnPageOpened(pageId, context)
    if Enabled() and ns.TotalRP3SkinFrames.PageOpened then
        ns.TotalRP3SkinFrames.PageOpened(pageId, context)
    end
end

function module:OnAddonLoaded(name)
    if requested and (name == "totalRP3" or ns.IsEUIAddon(name)) then
        ns.RequestApply("totalRP3Skin")
    end
end
