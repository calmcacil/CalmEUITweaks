local addonName, ns = ...
local key = "restedXPSkin"
local module = {}
ns.RegisterModule(key, module)

local dark, forever = "Calm True Dark V2", "Calm Forever V2"
local palettes = {
    [dark] = {
        panel = {0.045, 0.045, 0.045, 0.98}, header = {0.09, 0.09, 0.09, 1},
        border = {0.27, 0.27, 0.27, 1}, accent = {0.83, 0.83, 0.83, 1},
        text = {0.93, 0.93, 0.93, 1}, muted = {0.71, 0.71, 0.71, 1},
        arrow = "RestedXPArrowTrueDark.tga",
    },
    [forever] = {
        panel = {0.065, 0.052, 0.041, 0.98}, header = {0.12, 0.085, 0.055, 1},
        border = {0.48, 0.32, 0.17, 1}, accent = {0.90, 0.70, 0.42, 1},
        text = {0.93, 0.90, 0.84, 1}, muted = {0.74, 0.67, 0.57, 1},
        arrow = "RestedXPArrowForever.tga",
    },
}
local registered, events, unlockHost, editing
local offer, fittedWindow
local checkedName, checkedSize, checkedBottom
local function Loaded(name)
    if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
    local available, loaded = C_AddOns.IsAddOnLoaded(name)
    if loaded ~= nil then return loaded == true end
    return available == true
end

local function Conflict()
    if Loaded("EUISkin_RXP") then return "Standalone EUISkin_RXP is loaded." end
    if Loaded("EUIAddonSkins")
        and not (type(EUIAddonSkinsDB) == "table" and EUIAddonSkinsDB.disabled) then
        return "Turn off EUI AddonSkins skinning and reload."
    end
end

local function GetRXP()
    if not Loaded("RXPGuides") then return end
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    return ace and ace:GetAddon("RXPGuides", true)
end

local quiet = {}
ns.RegisterModule("restedXPQuiet", quiet)
local partyAnnouncements = {
    "enableLevelUpAnnounceGroup", "enableCompleteStepAnnouncements",
    "enableCollectStepAnnouncements", "enableFlyStepAnnouncements",
}

function quiet:ApplySettings()
    if not ns.GetSettings("restedXPQuiet").enabled then return end
    local rxp = GetRXP()
    local settings = rxp and rxp.settings
    local profile = settings and settings.profile
    if not profile or type(settings.SaveLocalProfile) ~= "function" then return end
    local changed = {}
    for _, key in ipairs(partyAnnouncements) do
        if profile[key] == true then
            profile[key] = false
            changed[#changed + 1] = key
        end
    end
    if #changed == 0 then return end
    local ok, err = pcall(settings.SaveLocalProfile, settings)
    if not ok then
        for _, key in ipairs(changed) do profile[key] = true end
        error(err)
    end
end

function quiet:OnAddonLoaded(name)
    if name == "RXPGuides" and ns.GetSettings("restedXPQuiet").enabled then
        ns.RequestApply("restedXPQuiet")
    end
end

local function Selected()
    return ns.GetSettings(key).forever and forever or dark
end

local function Configured(profile, name, fontSize, anchor)
    return profile.enableBetaFeatures == true and profile.enableV2Interface == true
        and profile.activeTheme == name and profile.guideFontSize == fontSize
        and profile.anchorOrientation == anchor
end

local function Editing()
    local eui = EllesmereUI
    return editing or (type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive())
end

local function CapFontSize(label, limit)
    local font, size, flags = label:GetFont()
    if font and size and size > limit then label:SetFont(font, limit, flags) end
end

local function FitGuideWindow(rxp)
    local v2 = rxp.v2
    local window = type(v2.GetGuideWindow) == "function" and v2:GetGuideWindow()
    if not window or not window.title or not window.subtitle
        or type(window.UpdateSubTheme) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    local function Fit()
        if not ns.GetSettings(key).enabled or Conflict() or not rxp.activeTheme
            or not palettes[rxp.activeTheme.name] or InCombatLockdown() or Editing() then return end
        local dark = rxp.themes and rxp.themes.DarkMode
        local close = window.closebutton
        if close then
            local glyph = "Interface/AddOns/" .. addonName .. "/media/RestedXPClose.tga"
            close:SetNormalTexture(glyph)
            close:SetPushedTexture(glyph)
            close:SetHighlightTexture(glyph, "ADD")
            close:GetHighlightTexture():SetAlpha(0.25)
        end
        local class = rxp.player and rxp.player.class
        if dark and dark.texturePath and class and window.classIcon then
            window.classIcon:SetTexture(dark.texturePath .. class)
        end
        local steps = window.guideSteps
        local bar = steps and steps.scroll and steps.scroll.scrollbar
        if bar then
            local colors = palettes[rxp.activeTheme.name]
            for _, texture in pairs({
                bar.ThumbTexture,
                bar.ScrollUpButton and bar.ScrollUpButton.Normal,
                bar.ScrollDownButton and bar.ScrollDownButton.Normal,
            }) do
                texture:SetDesaturated(true)
                texture:SetVertexColor(unpack(colors.muted))
            end
        end
        -- The native V2 header reserves a fixed height for both lines.
        window.title:SetMaxLines(1)
        window.subtitle:SetMaxLines(1)
        CapFontSize(window.title, 13)
        CapFontSize(window.subtitle, 11)
        if window.footerText then CapFontSize(window.footerText, 10) end
    end
    if fittedWindow ~= window then
        hooksecurefunc(window, "UpdateSubTheme", Fit)
        fittedWindow = window
    end
    Fit()
end

local function Register(rxp, base)
    local function Applicable() return rxp.v2:IsEnabled() end
    for name, colors in pairs(palettes) do
        local theme = ns.Copy(base)
        theme.name, theme.displayName, theme.author = name, name, "Calm UI Tweaks"
        theme.version, theme.applicable = 2, Applicable
        local darkMode = rxp.v2.themes.DarkMode
        if darkMode and darkMode.guideWindow then
            for _, icon in ipairs({"logo", "settingsIcon", "guideSelectIcon"}) do
                theme.guideWindow[icon] = darkMode.guideWindow[icon] or theme.guideWindow[icon]
            end
        end
        theme.navigationArrow = "Interface/AddOns/" .. addonName .. "/media/" .. colors.arrow
        theme.headerTexture = {texCoords = {0, 1, 0, 1}}
        theme.backgroundColors = {
            common = colors.panel, guideWindow = colors.panel, guideName = colors.header,
            scrollbar = colors.header, guideSelector = colors.header, inactivePartyTab = colors.header,
            activeStepCheckbox = colors.panel, activeStepCheckboxChecked = colors.accent,
        }
        theme.borderColors = {
            common = colors.border, commonEdge = colors.border, inactivePartyTab = colors.border,
            activeStepCheckboxChecked = colors.accent,
        }
        theme.textColor = {common = colors.text, title = colors.accent, inactivePartyTab = colors.muted}
        theme.edge.edgeFile = "Interface/Buttons/WHITE8X8"
        theme.edge.texCoords = {
            top = {0, 1, 0, 1}, bottom = {0, 1, 0, 1},
            left = {0, 1, 0, 1}, right = {0, 1, 0, 1},
        }
        -- RXP resolves the selection through its legacy registry by the same name.
        rxp.v2.themes[name] = theme
        rxp:RegisterTheme({
            name = name, displayName = name, author = theme.author, version = 1, applicable = Applicable,
            background = colors.panel, bottomFrameBG = colors.header,
            bottomFrameHighlight = colors.border, textColor = colors.text,
        })
    end
    registered = rxp
end

local function ReleaseWaits()
    if events then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    if unlockHost then
        unlockHost:UnregisterUnlockModeListener("CalmUIRestedXP")
        unlockHost = nil
    end
    editing = false
end

local function Wait()
    local combat = InCombatLockdown()
    if not combat and not Editing() then ReleaseWaits(); return false end
    if combat then
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", function()
                events:UnregisterEvent("PLAYER_REGEN_ENABLED")
                ns.RequestApply(key)
            end)
        end
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return true
end

local function WatchUnlock()
    local eui = EllesmereUI
    if unlockHost or type(eui.RegisterUnlockModeListener) ~= "function"
        or type(eui.UnregisterUnlockModeListener) ~= "function" then return end
    unlockHost = eui
    editing = Editing()
    eui:RegisterUnlockModeListener("CalmUIRestedXP", function(active)
        editing = active == true
        if not editing then ns.RequestApply(key) end
    end)
end

function module:Confirm(request)
    local settings = request.rxp.settings
    local profile = request.profile
    if offer ~= request or request.accepted then return end
    local prefs = ns.GetSettings(key)
    if not prefs.enabled or prefs.fontSize ~= request.fontSize or prefs.bottom ~= request.bottom
        or Selected() ~= request.name or settings.profile ~= profile or Conflict()
        or InCombatLockdown() or Editing() or type(ReloadUI) ~= "function" then
        offer = nil
        ns.SetStatus(key, "Toggle Skin RestedXP to retry setup.")
        return
    end
    request.accepted = true
    if Configured(profile, request.name, request.fontSize, request.anchor) then return end
    local beta, v2, theme = profile.enableBetaFeatures, profile.enableV2Interface, profile.activeTheme
    local fontSize, anchor = profile.guideFontSize, profile.anchorOrientation
    profile.enableBetaFeatures, profile.enableV2Interface, profile.activeTheme = true, true, request.name
    profile.guideFontSize, profile.anchorOrientation = request.fontSize, request.anchor
    local ok, err = pcall(settings.SaveLocalProfile, settings)
    if not ok then
        profile.enableBetaFeatures, profile.enableV2Interface, profile.activeTheme = beta, v2, theme
        profile.guideFontSize, profile.anchorOrientation = fontSize, anchor
        offer = nil
        error(err)
    end
    ReloadUI()
end

function module:ApplySettings()
    if not ns.GetSettings(key).enabled or not Loaded("RXPGuides") then
        offer = nil
        checkedName = nil
        ReleaseWaits()
        ns.SetStatus(key, registered and "Reload to disable." or "Disabled.")
        return
    end
    local conflict = Conflict()
    local rxp = not conflict and GetRXP()
    local settings = rxp and rxp.settings
    local profile = settings and settings.profile
    local base = rxp and rxp.v2 and rxp.v2.themes and rxp.v2.themes["RXP Blue V2"]
    if conflict or not (profile and base and base.edge and type(rxp.RegisterTheme) == "function"
        and type(rxp.v2.IsEnabled) == "function" and type(settings.SaveLocalProfile) == "function") then
        offer = nil
        ReleaseWaits()
        ns.SetStatus(key, conflict or "Waiting for RestedXP V2.")
        return
    end
    local prefs = ns.GetSettings(key)
    local name, fontSize, bottom = Selected(), prefs.fontSize, prefs.bottom
    local anchor = bottom and "bottom" or "top"
    if offer and (offer.profile ~= profile or offer.name ~= name
        or offer.fontSize ~= fontSize or offer.bottom ~= bottom) then offer = nil end
    if checkedName == name and checkedSize == fontSize and checkedBottom == bottom then return end
    WatchUnlock()
    if Wait() then
        ns.SetStatus(key, InCombatLockdown() and "Waiting for combat to end." or "Close Unlock Mode.")
        return
    end
    if registered ~= rxp then Register(rxp, base) end
    if Configured(profile, name, fontSize, anchor) then
        offer = nil
        -- RestedXP initializes before optional dependents and may have cached its fallback.
        if not rxp.activeTheme or rxp.activeTheme.name ~= name then
            if profile.enableThemeLiveReload then
                rxp:ReloadTheme()
            else
                rxp.activeTheme = nil
                rxp:UpdateTheme(false, true)
                rxp.v2:UpdateGuideWindow()
            end
        end
        FitGuideWindow(rxp)
        ns.SetStatus(key, "Active.")
    elseif not offer then
        local eui = EllesmereUI
        if type(eui.ShowConfirmPopup) ~= "function" or type(ReloadUI) ~= "function" then
            ns.SetStatus(key, "Setup confirmation or UI reload is unavailable.")
            return
        end
        local request = {rxp = rxp, profile = profile, name = name, fontSize = fontSize, bottom = bottom, anchor = anchor}
        offer = request
        eui:ShowConfirmPopup({
            title = "Set up RestedXP V2",
            message = "Enable RestedXP Beta Features and V2 Interface, select " .. name
                .. ", set guide font size to " .. fontSize .. " and the current step anchor to " .. anchor
                .. " for this RestedXP profile, then reload the UI?",
            confirmText = "Apply and Reload", cancelText = "Not Now",
            onConfirm = function() ns.CallModule(key, "Confirm", request) end,
        })
        ns.SetStatus(key, "Sync needed. Toggle Skin RestedXP to retry.")
    end
    checkedName, checkedSize, checkedBottom = name, fontSize, bottom
end

function module:OnAddonLoaded(name)
    if ns.GetSettings(key).enabled and Loaded("RXPGuides")
        and (name == "RXPGuides" or name == "EUISkin_RXP" or name == "EUIAddonSkins") then
        ns.RequestApply(key)
    end
end
