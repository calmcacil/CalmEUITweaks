local addonName, ns = ...
local statusLabels = setmetatable({}, { __mode = "k" })
local refreshing = false
local failures = setmetatable({}, { __mode = "k" })
local ownedError
local dependencies = { simpleItemLevel = "EllesmereUIBags" }

local function Failed(owner, err)
    failures[owner] = true
    ns.ReportError("options", err, true)
    ownedError = ns.errors.options
end

local function Recovered(owner)
    failures[owner] = nil
    -- Only release our error after every failed page and label has recovered.
    if ownedError and not next(failures) and ns.errors.options == ownedError then
        ownedError = nil
        ns.ClearError("options")
    end
end

local function UpdateText(label, text, getText)
    if not getText then label:SetText(text); return end
    local readable, value = pcall(getText)
    local err
    if readable then text = value
    else err, text = value, "Setting unavailable." end
    local written, writeError = pcall(label.SetText, label, text)
    if not readable or not written then Failed(label, err or writeError)
    else Recovered(label) end
end

local function RefreshActivePage(eui)
    if type(eui.GetPluginModuleKey) ~= "function" or type(eui.GetActiveModule) ~= "function" then return end
    local key = eui.GetPluginModuleKey(addonName, "Tweaks")
    if key and eui:GetActiveModule() == key then
        eui:RefreshPage()
        return true
    end
end

function ns.RefreshOptions()
    if refreshing then return end
    refreshing = true
    for label, getText in pairs(statusLabels) do UpdateText(label, nil, getText) end
    local eui = _G.EllesmereUI
    if eui and type(eui.RefreshPage) == "function" then
        local ok, refreshed = pcall(RefreshActivePage, eui)
        if not ok then Failed(eui, refreshed)
        elseif refreshed then Recovered(eui) end
    end
    refreshing = false
end

function ns.OnOptionsAddonLoaded(name)
    for _, dependency in pairs(dependencies) do
        if name == dependency then ns.RefreshOptions(); return end
    end
end

local function DependencyLoaded(key)
    if not C_AddOns or type(C_AddOns.IsAddOnLoaded) ~= "function" then return false end
    local available, loaded = C_AddOns.IsAddOnLoaded(dependencies[key])
    -- Prefer the completed-load flag on clients that also report loads in progress.
    if loaded ~= nil then return loaded == true end
    return available == true
end

local function Description(parent, y, text, getText, minimumHeight)
    local eui = _G.EllesmereUI
    if eui.IsSearchPrebuild() then return y - 48 end
    y = y - 12
    local label = eui.MakeFont(parent, 12, nil, 1, 1, 1, 0.65)
    local pad = eui.CONTENT_PAD + 20
    eui.PanelPP.Point(label, "TOPLEFT", parent, "TOPLEFT", pad, y)
    eui.PanelPP.Point(label, "TOPRIGHT", parent, "TOPRIGHT", -pad, y)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    UpdateText(label, text, getText)
    if getText then statusLabels[label] = getText end
    return y - math.max(label:GetStringHeight(), minimumHeight or 20) - 12
end

local function Toggle(moduleKey, key, text, tooltip)
    return {
        type = "toggle", text = text, tooltip = tooltip, noCapture = true,
        getValue = function() return ns.GetSettings(moduleKey)[key] end,
        setValue = function(value) ns.SetSetting(moduleKey, key, value) end,
    }
end

local function DependencyToggle(key, text, tooltip)
    local cfg = Toggle(key, "enabled", text, tooltip)
    cfg.disabled = function() return not DependencyLoaded(key) end
    cfg.disabledTooltip = "Requires " .. dependencies[key] .. " to be installed, enabled, and loaded."
    return cfg
end

local function BuildPage(page, parent, y)
    local eui = _G.EllesmereUI
    local widgets = eui and eui.Widgets
    if type(widgets) ~= "table" or type(widgets.SectionHeader) ~= "function"
        or type(widgets.DualRow) ~= "function" or type(widgets.Spacer) ~= "function"
        or type(eui.BlankRowCfg) ~= "function" or type(eui.IsSearchPrebuild) ~= "function"
        or type(eui.MakeFont) ~= "function" or type(eui.CONTENT_PAD) ~= "number"
        or type(eui.PanelPP) ~= "table" or type(eui.PanelPP.Point) ~= "function" then
        ns.optionsRenderError = "EUI widget interface is unavailable or incompatible."
        return 60
    end
    ns.optionsRenderError = nil
    parent._showRowDivider = true
    local function Section(text)
        local _, height = widgets:SectionHeader(parent, text, y)
        y = y - height
    end
    local function Row(left, right)
        right = right or eui.BlankRowCfg()
        for _, cfg in ipairs({left, right}) do
            if cfg.type ~= "label" then
                local disabled, tooltip = cfg.disabled, cfg.disabledTooltip
                cfg.disabled = function()
                    return not ns.SavedVariablesReady() or (disabled and disabled()) or false
                end
                cfg.disabledTooltip = function()
                    local ready, reason = ns.SavedVariablesReady()
                    if not ready then return reason end
                    return type(tooltip) == "function" and tooltip() or tooltip
                end
            end
        end
        local _, height = widgets:DualRow(parent, y, left, right)
        y = y - height
    end
    local function Text(text, getText, minimumHeight)
        y = Description(parent, y, text, getText, minimumHeight)
    end
    local function Spacer()
        local _, height = widgets:Spacer(parent, y, 20)
        y = y - height
    end
    local function RenameButton(moduleKey, title, text, tooltip)
        return {
            type = "button", text = text, noCapture = true, tooltip = tooltip,
            disabled = function() return not ns.ready or InCombatLockdown() end,
            disabledTooltip = "Available after login and outside combat.",
            onClick = function()
                eui:ShowInputPopup({
                    title = title,
                    message = "Choose a free macro name. Existing macros remain unchanged.",
                    initialText = ns.GetSettings(moduleKey).name, maxLetters = 16,
                    confirmText = "Rename Macro", cancelText = "Cancel",
                    onConfirm = function(name)
                        local ok, reason = ns.SetSetting(moduleKey, "name", name)
                        ns.Print(ok and "Macro name changed; previous macros are left intact." or reason)
                    end,
                })
            end,
        }
    end

    if page == "General" then
        Section("PERSONAL TWEAKS")
        Row(Toggle("questLootSparkles", "enabled", "Quest loot sparkles",
            "Enables native quest-object sparkles by disabling normal and raid outlines. Off by default. Disabling restores owned graphics settings; restart the game to remove lingering sparkles."),
            Toggle("lfgLeaderLocation", "enabled", "LFG leader location",
                "Shows each leader's current zone beside the activity in Looking For Group. Helps judge travel progress; does not measure distance to a summoning stone. Off by default."))
        Row(Toggle("cursorWashedOut", "enabled", "Cursor washed-out fix",
            "Disables the hardware cursor to fix washed-out cursor colors. May cause cursor lag or flickering. Off by default. Disabling restores the previous setting only if still owned."))
        Text(nil, function()
            return "Quest loot sparkles: " .. ns.GetStatus("questLootSparkles")
                .. "\nLFG leader location: " .. ns.GetStatus("lfgLeaderLocation")
                .. "\nCursor washed-out fix: " .. ns.GetStatus("cursorWashedOut")
        end, 80)
        Spacer()
        Section("BAG UPGRADE ARROWS")
        local function Scope(key, text, tooltip)
            local cfg = Toggle("simpleItemLevel", key, text, tooltip)
            cfg.disabled = function()
                return not DependencyLoaded("simpleItemLevel") or not ns.GetSettings("simpleItemLevel").enabled
            end
            cfg.disabledTooltip = "Requires loaded EllesmereUIBags and enabled bag upgrade arrows."
            return cfg
        end
        Row(DependencyToggle("simpleItemLevel", "Bag upgrade arrows",
            "Requires EUI Bags. Adds an up arrow when an item beats the equipped item level; red means the required level is not met. EUI keeps displaying item levels."),
            Scope("inventory", "Inventory bags",
                "Show upgrade arrows in normal inventory bags when bag upgrade arrows are enabled."))
        Row(Scope("reagent", "Reagent bags",
            "Show upgrade arrows in reagent bags when bag upgrade arrows are enabled."),
            Scope("bank", "Bank",
                "Show upgrade arrows in bank bags when bag upgrade arrows are enabled."))
        Text(nil, function() return "Bag upgrade arrows: " .. ns.GetStatus("simpleItemLevel") end)
    elseif page == "Macro" then
        -- General macros first, then class sections in alphabetical order.
        Section("GENERAL")
        Row(Toggle("generalFoodWaterMacro", "enabled", "Maintain general macro",
            "Maintains a general (account-wide) macro. Left-click eats the highest-rank conjured food in your bags; right-click drinks the highest-rank conjured water. The macro updates when bag contents change."),
            RenameButton("generalFoodWaterMacro", "Rename Food and Water", "Rename Macro",
                "Choose the general macro name. The name and macro are shared by all characters."))
        Text(nil, function()
            return "General macro name: " .. ns.GetSettings("generalFoodWaterMacro").name
                .. "\nStatus: " .. ns.GetStatus("generalFoodWaterMacro")
        end, 60)
        Spacer()
        Section("DRUID")
        Row(Toggle("druidRebirthMacro", "enabled", "Rebirth / Revive",
            "Maintains a character macro that casts Rebirth in combat and Revive out of combat. The highest learned rank is used automatically. Only owned macros are maintained; disabling leaves the macro intact."),
            RenameButton("druidRebirthMacro", "Rename Rebirth", "Rename Rebirth",
                "Choose the Rebirth / Revive character macro name. The name preference is account-wide."))
        Row(Toggle("druidThornsMacro", "enabled", "Self Thorns",
            "Maintains a character macro that casts Thorns on yourself. The highest learned rank is used automatically. Only owned macros are maintained; disabling leaves the macro intact."),
            RenameButton("druidThornsMacro", "Rename Thorns", "Rename Thorns",
                "Choose the Thorns character macro name. The name preference is account-wide."))
        Text(nil, function()
            return "Rebirth / Revive: " .. ns.GetSettings("druidRebirthMacro").name
                .. "\nStatus: " .. ns.GetStatus("druidRebirthMacro")
                .. "\nThorns: " .. ns.GetSettings("druidThornsMacro").name
                .. "\nStatus: " .. ns.GetStatus("druidThornsMacro")
        end, 70)
        Spacer()
        Section("MAGE")
        Row(Toggle("mageMacro", "enabled", "Maintain character macro",
            "Left-click uses food and water; right-click alternates conjure spells with a 10-second reset. Only owned macros are maintained; disabling leaves the macro intact."),
            RenameButton("mageMacro", "Rename FoodWater", "Rename Macro",
                "Choose the character macro name. Existing macros and manual edits are preserved. The name preference is account-wide."))
        Text(nil, function()
            return "Mage macro name: " .. ns.GetSettings("mageMacro").name
                .. "\nStatus: " .. ns.GetStatus("mageMacro")
        end, 60)
    elseif page == "Chat" then
        local function Button(text, action, tooltip, needsDefault)
            return {
                type = "button", text = text, tooltip = tooltip, noCapture = true,
                onClick = ns.ChatOptions[action],
                disabled = function()
                    return not ns.ready or InCombatLockdown()
                        or (needsDefault and (type(ns.db.chat.default) ~= "table"
                            or type(ns.db.chat.default.export) ~= "string"))
                end,
                disabledTooltip = needsDefault and "Save or import a default first; actions are unavailable in combat."
                    or "Chat actions are available after login and outside combat.",
            }
        end
        Section("CHARACTER CHAT SETUP")
        Row(Button("Save Default", "SaveDefault", "Save this character's current chat setup as the account-wide default."),
            Button("Apply Default", "ApplyDefault", "Replace normal chat tabs and message/channel routing without moving or restyling chat windows.", true))
        Row(Toggle("chat", "autoApply", "Auto Apply Updated Default",
            "Account-wide opt-in: at login, apply only when the saved default is newer than this character's applied default. Enabling this or importing a default after login waits for the next login."))
        Text(nil, function() return ns.Chat.GetSummary() end, 60)
        Spacer()
        Section("EXPORT AND IMPORT")
        Row(Button("Export Default", "ExportDefault", "Copy the saved default as a portable chat setup string.", true),
            Button("Import Default", "ImportDefault", "Replace the saved default from a chat setup string. Does not immediately change this character's chat."))
        Text("Shares normal tabs, docking order, message groups and channels. Window styling and history stay local.")
    elseif page == "Spacers" then
        Section("EDIT MODE SPACERS")
        local function SpacerToggle(index)
            local cfg = Toggle("spacers", "spacer" .. index, "Enable Spacer " .. index,
                "Adds an invisible, resizable anchor in EUI Unlock Mode. Disabling removes its EUI anchor and size-match links. Finish Unlock Mode before changing this setting.")
            cfg.disabled = function()
                return not ns.ready or InCombatLockdown()
                    or (type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive())
            end
            cfg.disabledTooltip = "Available after login, outside combat and outside Unlock Mode."
            return cfg
        end
        Row(SpacerToggle(1), SpacerToggle(2))
        Row(SpacerToggle(3), SpacerToggle(4))
        Text("Resize and attach spacers in EUI Unlock Mode. Disabling removes their links; detach dependent frames first. Settings and sizes are account-wide.")
    end
    return math.abs(y) + 12
end

function ns.BuildOptionsPage(...)
    local ok, height = pcall(BuildPage, ...)
    if not ok then
        ns.optionsRenderError = "EUI settings page failed: " .. tostring(height)
        Failed(select(1, ...), height)
        return 60
    end
    if not ns.optionsRenderError then Recovered(select(1, ...)) end
    return height
end
