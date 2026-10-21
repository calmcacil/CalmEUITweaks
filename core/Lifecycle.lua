local addonName, ns = ...

local pendingApply = {}
local function CanApply(key)
    return ns.ready or (key == "migrations" and ns.settingsPending)
end

function ns.RequestApply(key)
    if not CanApply(key) or pendingApply[key] then return end
    pendingApply[key] = true
    C_Timer.After(0, function()
        pendingApply[key] = nil
        if CanApply(key) then ns.CallModule(key, "ApplySettings") end
    end)
end

local loaded, starting = false, false
function ns.ResumeStartup()
    if not loaded or starting then return end
    starting = true
    local resumed = ns.settingsPending
    if not ns.initialized then
        local ok, initialized = pcall(ns.InitializeSettings)
        if not ok then
            ns.settingsError = "SavedVariables initialization failed; data was not activated."
            ns.ReportError("migrations", initialized)
        end
        if not ok or not initialized then starting = false; return end
        ns.initialized = true
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "Initialize") end
    end
    if ns.loggedIn and not ns.ready then
        ns.ready = true
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "OnLogin") end
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "ApplySettings") end
        if resumed and ns.RefreshOptions then
            local ok, err = pcall(ns.RefreshOptions)
            if not ok then ns.ReportError("options", err, true) end
        end
    end
    starting = false
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "PLAYER_LOGIN" then
        events:UnregisterEvent("PLAYER_LOGIN")
        ns.loggedIn = true
        ns.ResumeStartup()
    elseif loadedAddon == addonName then
        loaded = true
        if IsLoggedIn and IsLoggedIn() then
            events:UnregisterEvent("PLAYER_LOGIN")
            ns.loggedIn = true
        end
        ns.ResumeStartup()
        if ns.optionsError then ns.Print(ns.optionsError) end
    elseif ns.initialized then
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "OnAddonLoaded", loadedAddon) end
        if ns.OnOptionsAddonLoaded then ns.OnOptionsAddonLoaded(loadedAddon) end
    end
end)
