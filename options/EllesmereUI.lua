local addonName, ns = ...
local moduleKey = "Tweaks"
local registeredHost

local function Install()
    local eui = _G.EllesmereUI
    if type(eui) ~= "table" then return false, "EUI is unavailable." end
    local config = {
        key = moduleKey,
        title = "Calm's Tweaks",
        description = "Personal conveniences and third-party compatibility fixes.",
        pages = { "General", "Macro", "Chat", "Spacers" },
        buildPage = ns.BuildOptionsPage,
        onPageCacheRestore = ns.RefreshOptions,
    }

    if eui.RegisterPlugin == nil then
        return false, "EUI plugin API is unavailable. Update EllesmereUI to use these options."
    end
    if type(eui.RegisterPlugin) ~= "function" or type(eui.PLUGIN_API_VERSION) ~= "number"
        or eui.PLUGIN_API_VERSION < 1 or type(eui.OpenPlugin) ~= "function" then
        return false, "Unsupported EUI plugin API. Update EllesmereUI to use these options."
    end
    local accepted = eui.RegisterPlugin(addonName, {
        label = ns.title, position = "bottom", modules = { config },
    })
    if accepted ~= true then
        return false, "EUI plugin registration was rejected; check the error handler for details."
    end
    registeredHost = eui
    return true
end

local ok, installed, reason = pcall(Install)
ns.optionsInstalled = ok and installed == true
ns.optionsError = reason
if not ok then ns.optionsError = "EUI options registration failed: " .. tostring(installed) end

function ns.OpenOptions()
    if not ns.optionsInstalled or type(InCombatLockdown) ~= "function" then return false end
    local checked, combat = pcall(InCombatLockdown)
    if not checked or combat ~= false then return false end
    local eui = _G.EllesmereUI
    if eui ~= registeredHost then
        ns.optionsError = "EUI options host changed; /reload is required."
        return false
    end
    if type(eui.OpenPlugin) ~= "function" then
        ns.optionsError = "EUI plugin opening API is unavailable."
        return false
    end
    local opened, result = pcall(eui.OpenPlugin, addonName, moduleKey)
    if opened and result ~= true then
        ns.optionsError = "EUI could not open the registered tweaks plugin."
        return false
    end
    if not opened then
        ns.optionsError = "EUI options could not open: " .. tostring(result)
    else
        ns.optionsError = nil
    end
    return opened
end

local function ResetUnavailable()
    local ready, reason = ns.SavedVariablesReady()
    if not ready then return reason end
    if not ns.ready then return "Wait for player login before resetting preferences." end
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then
        return "Cannot reset preferences during combat."
    end
    local eui = _G.EllesmereUI
    if type(eui) ~= "table" or type(eui.ShowConfirmPopup) ~= "function" then
        return "EUI reset confirmation is unavailable; preferences were not reset."
    end
    if type(ReloadUI) ~= "function" then return "UI reload is unavailable; preferences were not reset." end
    if type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive() then
        return "Finish EUI Unlock Mode before resetting preferences."
    end
end

local function GuardReset(callback)
    return function()
        local ok, err = pcall(callback)
        if not ok then ns.ReportError("options", err) end
    end
end

ns.RequestReset = GuardReset(function()
    local reason = ResetUnavailable()
    if reason then ns.Print(reason); return end
    local confirmed = false
    EllesmereUI:ShowConfirmPopup({
        title = "Reset Calm UI Tweaks",
        message = "Reset preferences and reload the UI? All features will be disabled and macro names reset. Existing macros, ownership, saved chat, spacer geometry and character records are kept.",
        confirmText = "Reset and Reload", cancelText = "Cancel",
        onConfirm = GuardReset(function()
            if confirmed then return end
            local reason = ResetUnavailable()
            if reason then ns.Print(reason); return end
            local reset, problem = ns.ResetSettings()
            if not reset then ns.Print(problem); return end
            confirmed = true
            ns.Print("Preferences reset; reloading UI.")
            ReloadUI()
        end),
    })
end)
