local root = "CalmEUITweaks/"
local ns = {}
assert(loadfile(root .. "core/Bootstrap.lua"))("CalmEUITweaks", ns)
assert(loadfile(root .. "core/Settings.lua"))("CalmEUITweaks", ns)
ns.db = ns.Copy(ns.defaults)
local prefs = ns.db.restedXPSkin
assert(prefs.forever and prefs.fontSize == 12 and not prefs.enabled)
prefs.forever = false
local loaded, popup, saved, reloaded, offers = {}, nil, 0, 0, 0
local profile = {activeTheme = "Default", unrelated = "keep"}
local settings = {profile = profile, SaveLocalProfile = function(self)
    saved = saved + 1
    assert(self.profile.enableBetaFeatures and self.profile.enableV2Interface)
end}
local legacy = {}
local baseTheme = {edge = {edgeFile = "original"}}
local rxp = {
    settings = settings,
    v2 = {themes = {["RXP Blue V2"] = baseTheme}, IsEnabled = function()
        return settings.profile.enableBetaFeatures and settings.profile.enableV2Interface
    end},
    RegisterTheme = function(_, theme) legacy[theme.name] = theme end,
    ReloadTheme = function(self) self.activeTheme = assert(legacy[settings.profile.activeTheme]) end,
}
C_AddOns = {IsAddOnLoaded = function(name) return loaded[name], loaded[name] == true end}
LibStub = function() return {GetAddon = function() return rxp end} end
EllesmereUI = {ShowConfirmPopup = function(_, cfg) popup, offers = cfg, offers + 1 end}
local combat, afterCombat
InCombatLockdown = function() return combat == true end
CreateFrame = function()
    return {
        SetScript = function(_, _, callback) afterCombat = callback end,
        RegisterEvent = function(_, event) assert(event == "PLAYER_REGEN_ENABLED") end,
        UnregisterEvent = function() end,
    }
end
ReloadUI = function() reloaded = reloaded + 1 end
local queued
ns.RequestApply = function(key) assert(key == "restedXPSkin"); queued = true end
settings.RefreshProfile = function(self, newProfile) self.profile = newProfile end
hooksecurefunc = function(owner, method, callback)
    local original = owner[method]
    owner[method] = function(...) original(...); callback() end
end
assert(loadfile(root .. "skins/RestedXP.lua"))("CalmEUITweaks", ns)
local module = ns.modules.restedXPSkin
loaded.RXPGuides = true
module:ApplySettings()
assert(not popup and not next(legacy))
prefs.enabled = true
loaded.RXPGuides = false
module:ApplySettings()
assert(not popup and not next(legacy))
module:OnAddonLoaded("EUIAddonSkins")
assert(not queued and ns.GetStatus("restedXPSkin") == "Disabled.")
loaded.RXPGuides, loaded.EUISkin_RXP = true, true
module:ApplySettings()
assert(not popup and not next(legacy))
loaded.EUISkin_RXP, loaded.EUIAddonSkins = false, true
module:ApplySettings()
assert(not popup and not next(legacy))
loaded.EUIAddonSkins, combat = false, true
module:ApplySettings()
assert(afterCombat and not popup and not next(legacy))
combat = false
afterCombat()
assert(queued)
module:ApplySettings()
local first = assert(popup)
assert(first.message:find("Calm True Dark V2", 1, true))
assert(legacy["Calm True Dark V2"] and legacy["Calm Forever V2"])
assert(baseTheme.edge.edgeFile == "original")
module:ApplySettings()
assert(offers == 1 and saved == 0 and reloaded == 0 and profile.activeTheme == "Default")

prefs.forever = true
prefs.bottom = true
module:ApplySettings()
first.onConfirm()
assert(saved == 0 and reloaded == 0 and profile.activeTheme == "Default")
assert(offers == 2 and popup.message:find("Calm Forever V2", 1, true))
popup.onConfirm()
popup.onConfirm()
assert(saved == 1 and reloaded == 1 and profile.unrelated == "keep")
assert(profile.activeTheme == "Calm Forever V2")
assert(profile.guideFontSize == 12 and profile.anchorOrientation == "bottom")
profile.enableThemeLiveReload = true
prefs.enabled = false
module:ApplySettings()
prefs.enabled = true
module:ApplySettings()
assert(offers == 2 and saved == 1 and rxp.activeTheme.name == profile.activeTheme)

queued = false
settings:RefreshProfile({activeTheme = "Default"})
assert(not queued)
module:ApplySettings()
assert(offers == 2)
prefs.fontSize = 13
module:ApplySettings()
assert(offers == 3)
prefs.enabled = false
popup.onConfirm()
assert(saved == 1 and reloaded == 1 and settings.profile.activeTheme == "Default")
local quiet = ns.modules.restedXPQuiet
local announcements = settings.profile
announcements.enableLevelUpAnnounceGroup = true
announcements.enableCompleteStepAnnouncements = true
announcements.enableCollectStepAnnouncements = false
announcements.enableFlyStepAnnouncements = true
announcements.enableLevelUpAnnounceGuild = true
announcements.enableLevelUpAnnounceSolo = true
announcements.ignoreQuestieConflicts = true
settings.SaveLocalProfile = function() saved = saved + 1 end
quiet:ApplySettings()
assert(announcements.enableFlyStepAnnouncements and saved == 1)
local refreshed = 0
rxp.title = "RestedXP Guides"
local getAddon = LibStub
LibStub = function(name)
    if name == "AceConfigRegistry-3.0" then
        return {NotifyChange = function(_, title)
            assert(title == rxp.title and announcements.enableFlyStepAnnouncements == false)
            refreshed = refreshed + 1
        end}
    end
    return getAddon()
end
ns.ready, ns.settingsReady = true, true
local messages = {}
ns.Print = function(message) messages[#messages + 1] = message end
assert(ns.SetSetting("restedXPQuiet", "enabled", true))
assert(announcements.enableLevelUpAnnounceGroup == false and announcements.enableCompleteStepAnnouncements == false)
assert(announcements.enableCollectStepAnnouncements == false and announcements.enableFlyStepAnnouncements == false)
assert(announcements.enableLevelUpAnnounceGuild == false and announcements.enableLevelUpAnnounceSolo == false)
assert(announcements.ignoreQuestieConflicts == false)
assert(saved == 2 and reloaded == 1 and #messages == 6)
assert(messages[2] == "Shut up, RXP! Announce Level Ups (Guild Chat) set to disabled.")
quiet:ApplySettings()
assert(saved == 2 and refreshed == 1 and #messages == 6)
print("RestedXP setup tests passed")
