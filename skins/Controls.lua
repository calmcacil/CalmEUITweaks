local _, ns = ...

function ns.RegisterControlSkin(key, addon, label, roots, usesAuctionHouse, journalDisplay)
    local module = {}
    ns.RegisterModule(key, module)
    local skin, requested, registered, events, unlockHost, editing, displayHook
    local watched = setmetatable({}, { __mode = "k" })

    local function Loaded(name)
        if not C_AddOns or not C_AddOns.IsAddOnLoaded then return false end
        local available, loaded = C_AddOns.IsAddOnLoaded(name)
        if loaded ~= nil then return loaded end
        return available
    end

    local function Queue()
        if requested and ns.GetSettings(key).enabled and skin and skin.IsEnabled() then
            ns.RequestApply(key)
        end
    end

    local function ReleaseWaits()
        if events then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        if unlockHost then
            unlockHost:UnregisterUnlockModeListener(key)
            unlockHost = nil
        end
        editing = false
    end

    local function Visit(frame)
        if frame.IsForbidden and frame:IsForbidden() then return end
        if frame:IsObjectType("EditBox") then
            skin.EditBox(frame)
        elseif frame:IsObjectType("CheckButton") then
            skin.Checkbox(frame)
        elseif frame:IsObjectType("Button") and frame.GetText and frame:GetText() then
            skin.Button(frame, {"Icon", "icon"})
        end
        local scrollBar = frame.ScrollBar
        if scrollBar and scrollBar.IsObjectType and not (scrollBar.IsForbidden and scrollBar:IsForbidden()) then
            skin.ScrollBar(scrollBar)
        end
        for _, child in ipairs({frame:GetChildren()}) do Visit(child) end
    end

    function module:OnLogin()
        requested = ns.GetSettings(key).enabled
    end

    function module:ApplySettings()
        local wanted = ns.GetSettings(key).enabled
        local eui = EllesmereUI
        local reason
        if requested ~= wanted then reason = wanted and "Reload to enable." or "Reload to disable."
        elseif not wanted then reason = "Disabled."
        elseif not Loaded(addon) then reason = "Waiting for " .. label .. " to load."
        elseif Loaded("EUIAddonSkins") and not (type(EUIAddonSkinsDB) == "table" and EUIAddonSkinsDB.disabled) then
            reason = "Turn off EUI AddonSkins skinning and reload."
        elseif type(eui.RegisterSkin) ~= "function" then reason = "EUI skinning API unavailable."
        end
        if reason then
            if events then events:UnregisterAllEvents() end
            ReleaseWaits()
            ns.SetStatus(key, reason)
            return
        end
        if not registered then
            eui.RegisterSkin("Calm UI Tweaks - " .. label, function(api)
                skin = api
                Queue()
            end)
            registered = true
        end
        if not skin or not skin.IsEnabled() then
            ReleaseWaits()
            if events then events:UnregisterAllEvents() end
            ns.SetStatus(key, "Check EUI's third-party skin switch.")
            return
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", Queue)
        end
        if usesAuctionHouse then events:RegisterEvent("AUCTION_HOUSE_SHOW") end
        local combat = InCombatLockdown()
        if combat or editing or (type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive()) then
            if combat then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
            if not unlockHost and type(eui.RegisterUnlockModeListener) == "function"
                and type(eui.UnregisterUnlockModeListener) == "function" then
                unlockHost = eui
                eui:RegisterUnlockModeListener(key, function(active)
                    editing = active == true
                    if not editing then Queue() end
                end)
            end
            ns.SetStatus(key, combat and "Waiting for combat to end." or "Close Unlock Mode.")
            return
        end
        ReleaseWaits()
        if journalDisplay and not displayHook and type(Journalator) == "table"
            and type(Journalator.ToggleView) == "function" and type(hooksecurefunc) == "function" then
            hooksecurefunc(Journalator, "ToggleView", Queue)
            displayHook = true
        end
        local found
        for name, kind in pairs(roots) do
            local frame = _G[name]
            if frame and frame.IsObjectType and not (frame.IsForbidden and frame:IsForbidden()) then
                found = true
                if not watched[frame] then
                    frame:HookScript("OnShow", Queue)
                    watched[frame] = true
                end
                if kind == "shell" then skin.Shell(frame)
                elseif kind == "panel" then skin.Panel(frame)
                elseif kind == "tab" then skin.Tab(frame) end
                if kind ~= "tab" then Visit(frame) end
            end
        end
        if usesAuctionHouse and skin.SetTabSelection and type(Auctionator) == "table" then
            local state = Auctionator.Tabs and Auctionator.Tabs.State
            for _, entry in ipairs(state and state.knownTabs or {}) do
                local tab = type(entry.name) == "string" and _G["AuctionatorTabs_" .. entry.name]
                local content = type(entry.tabFrameName) == "string" and _G[entry.tabFrameName]
                if tab and content and type(content.IsVisible) == "function" then
                    skin.Tab(tab)
                    skin.SetTabSelection(tab, content:IsVisible())
                    if not watched[content] then
                        content:HookScript("OnShow", Queue)
                        watched[content] = true
                    end
                end
            end
        end
        ns.SetStatus(key, found and "Active." or "Open the addon's window.")
    end

    function module:OnAddonLoaded(name)
        if requested and ns.GetSettings(key).enabled
            and (name == addon or name == "EUIAddonSkins" or name == "Blizzard_Settings" or name == journalDisplay) then
            ns.RequestApply(key)
        end
    end
end
