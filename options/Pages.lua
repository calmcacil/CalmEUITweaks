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

local function CompatibilityToggle(key, text, tooltip)
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
    elseif page == "Mage Macro" then
        Section("MAGE FOOD AND WATER")
        Row(Toggle("mageMacro", "enabled", "Maintain character macro",
            "Left-click uses food and water; right-click alternates conjure spells with a 10-second reset. Only owned macros are maintained; disabling leaves the macro intact."), {
            type = "button", text = "Rename Macro", noCapture = true,
            tooltip = "Choose the character macro name. Existing macros and manual edits are preserved. The name preference is account-wide.",
            disabled = function() return not ns.ready or InCombatLockdown() end,
            disabledTooltip = "Available after login and outside combat.",
            onClick = function()
                eui:ShowInputPopup({
                    title = "Rename Mage Macro",
                    message = "Choose a free macro name. Existing macros remain unchanged.",
                    initialText = ns.GetSettings("mageMacro").name, maxLetters = 16,
                    confirmText = "Rename Macro", cancelText = "Cancel",
                    onConfirm = function(name)
                        local ok, reason = ns.SetSetting("mageMacro", "name", name)
                        ns.Print(ok and "Macro name changed; previous macros are left intact." or reason)
                    end,
                })
            end,
        })
        Text(nil, function()
            return "Macro name: " .. ns.GetSettings("mageMacro").name
                .. "\nStatus: " .. ns.GetStatus("mageMacro")
        end, 60)
    elseif page == "Compatibility" then
        Section("BAG ITEM LEVELS")
        local function Scope(key, text, tooltip)
            local cfg = Toggle("simpleItemLevel", key, text, tooltip)
            cfg.disabled = function()
                return not DependencyLoaded("simpleItemLevel") or not ns.GetSettings("simpleItemLevel").enabled
            end
            cfg.disabledTooltip = "Requires loaded EllesmereUIBags and enabled bag / bank item levels."
            return cfg
        end
        Row(CompatibilityToggle("simpleItemLevel", "Enable bag / bank item levels",
            "Requires EUI Bags. Arrows mark higher item level than equipped gear, not better class stats."),
            Scope("inventory", "Inventory bags",
                "Show equipment item levels in normal inventory bags when bag item levels are enabled."))
        Row(Scope("reagent", "Reagent bags",
            "Show equipment item levels in reagent bags when bag item levels are enabled."),
            Scope("bank", "Bank",
                "Show equipment item levels in bank bags when bag item levels are enabled."))
        Text(nil, function() return "Status: " .. ns.GetStatus("simpleItemLevel") end)
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
        Spacer()
        Section("PLAYER / TARGET CORNER ALIGNMENT")
        local function Corner(unit, label)
            return {
                type = "dropdown", text = label .. " corner", noCapture = true,
                values = { DEFAULT = "EUI Default", TOPLEFT = "Top Left", TOPRIGHT = "Top Right",
                    BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right" },
                order = { "DEFAULT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
                getValue = function() return ns.GetSettings("spacerCorners")[unit] end,
                setValue = function(value) ns.SetSetting("spacerCorners", unit, value) end,
                itemDisabled = function(value)
                    local db = _G.EllesmereUIDB
                    local info = db and db.unlockAnchors and db.unlockAnchors[unit]
                    return type(info) == "table" and type(info.target) == "string"
                        and info.target:match("^CalmUITweaks_Spacer[1-4]$")
                        and not ns.IsSpacerCornerCompatible(info.side, value)
                end,
                itemDisabledTooltip = function()
                    return "Choose a frame corner facing the spacer on the current anchor side."
                end,
                disabled = function()
                    return not ns.ready or InCombatLockdown()
                        or (type(eui.IsUnlockModeActive) == "function" and eui:IsUnlockModeActive())
                end,
                disabledTooltip = "Choose the alignment after finishing Unlock Mode, outside combat.",
                tooltip = "Select the unit frame's corner facing the spacer. Keeps the native anchor side and makes the facing corners touch, resetting offsets on a new selection. Later size changes preserve manual nudges. EUI Default leaves the current link in place.",
            }
        end
        Row(Corner("player", "Player"), Corner("target", "Target"))
        Text("Choose the corner facing the spacer after saving its anchor. A new selection resets offsets; EUI Default keeps the current link.")
    elseif page == "Anchors" then
        Section("DEFAULT ANCHOR SPACING")
        local function Gap(side, label)
            return {
                type = "slider", text = label .. " gap (pixels)", min = 0, max = 10, step = 1, noCapture = true,
                getValue = function() return ns.GetSettings("anchorGap")[side] end,
                setValue = function(value) ns.SetSetting("anchorGap", side, value) end,
                disabled = function() return not ns.GetSettings("anchorGap").enabled end,
                disabledTooltip = "Enable automatic anchor gap first.",
                tooltip = "Spacing outside the target's " .. label:lower() .. " side, in physical pixels. Zero keeps new links flush. Applies to future anchors only.",
            }
        end
        Row(Toggle("anchorGap", "enabled", "Automatic anchor gap",
            "Adds the side's default gap once to newly created flush edge anchors in EUI Unlock Mode. Existing links and manual offsets are preserved. Defaults off."))
        Spacer()
        Section("DEFAULT GAPS")
        Row(Gap("top", "Top"), Gap("bottom", "Bottom"))
        Row(Gap("left", "Left"), Gap("right", "Right"))
        Text("Applies to new flush edge links in EUI Unlock Mode. Existing offsets stay unchanged. Save keeps new gaps; Discard restores the layout.")
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
