local addonName, ns = ...

local pendingApply = {}
function ns.RequestApply(key)
    if not ns.ready or pendingApply[key] then return end
    pendingApply[key] = true
    C_Timer.After(0, function()
        pendingApply[key] = nil
        if ns.ready then ns.CallModule(key, "ApplySettings") end
    end)
end

local function Initialize()
    if ns.initialized then return end
    ns.InitializeSettings()
    ns.initialized = true
    for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "Initialize") end
end

local function Start()
    Initialize()
    ns.ready = true
    for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "OnLogin") end
    for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "ApplySettings") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "PLAYER_LOGIN" then
        events:UnregisterEvent("PLAYER_LOGIN")
        Start()
    elseif loadedAddon == addonName then
        Initialize()
        if IsLoggedIn and IsLoggedIn() then
            events:UnregisterEvent("PLAYER_LOGIN")
            Start()
        end
        if ns.optionsError then ns.Print(ns.optionsError) end
    elseif ns.initialized then
        for _, key in ipairs(ns.moduleOrder) do ns.CallModule(key, "OnAddonLoaded", loadedAddon) end
    end
end)
