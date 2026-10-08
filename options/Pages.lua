local _, ns = ...
local statusLabels = setmetatable({}, { __mode = "k" })
local refreshing = false
local failures = setmetatable({}, { __mode = "k" })
local ownedError

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

function ns.RefreshOptions()
    if refreshing then return end
    refreshing = true
    for label, getText in pairs(statusLabels) do UpdateText(label, nil, getText) end
    refreshing = false
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
        local _, height = widgets:DualRow(parent, y, left, right or eui.BlankRowCfg())
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
        Row(Toggle("mageMacro", "enabled", "Mage food / water macro",
            "Maintains a character macro for known food and water ranks. Configure it on the Mage Macro tab."),
            Toggle("simpleItemLevel", "enabled", "SimpleItemLevel bridge",
                "Shows SimpleItemLevel labels in EUI bags and bank. Configure scopes on the Compatibility tab."))
        Row(Toggle("whatsTraining", "enabled", "WhatsTraining spellbook theme",
            "Themes the WhatsTraining tab to match the active EUI spellbook skin, including fonts, controls and backgrounds. Disabling restores owned changes."))
    elseif page == "Mage Macro" then
        Section("MAGE FOOD AND WATER")
        Row(Toggle("mageMacro", "enabled", "Maintain character macro",
            "Left-click uses food and water; right-click alternates conjure spells with a 10-second reset. Only owned macros are maintained; disabling leaves the macro intact."))
        Text(nil, function() return "Macro name: " .. ns.GetSettings("mageMacro").name end)
        Text("Rename with /calmtweaks macro-name <name>. Choose a free name; existing or manually edited macros are never overwritten.")
    elseif page == "Compatibility" then
        Section("SIMPLEITEMLEVEL")
        Row(Toggle("simpleItemLevel", "enabled", "Enable bag / bank bridge",
            "Requires SimpleItemLevel and EUI Bags. Appearance, filters and upgrade rules are controlled by SimpleItemLevel."),
            Toggle("simpleItemLevel", "inventory", "Inventory bags",
                "Show SimpleItemLevel labels in normal inventory bags when the bridge is enabled."))
        Row(Toggle("simpleItemLevel", "reagent", "Reagent bags",
            "Show SimpleItemLevel labels in reagent bags when the bridge is enabled."),
            Toggle("simpleItemLevel", "bank", "Bank",
                "Show SimpleItemLevel labels in bank bags when the bridge is enabled."))
        Spacer()
        Section("WHATSTRAINING")
        Row(Toggle("whatsTraining", "enabled", "Match spellbook theme",
            "Themes the entire WhatsTraining spellbook tab to match EUI's fonts, controls and backgrounds while preserving training status colors. Disabling restores owned changes."))
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
        Text("Includes normal tabs, docking order, message groups and channels. Position, size, fonts, backgrounds and voice transcription are not copied.")
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
        Text("Enable up to four spacers, then open EUI Unlock Mode. Find them under Calm UI Tweaks and set their Width / Height to the gap you want.")
        Text("Anchor a spacer between two frames using zero offsets. Its width sets LEFT / RIGHT gaps; its height sets TOP / BOTTOM gaps. See the README for a centered power bar example.")
        Text("Spacer settings and geometry are account-wide. EUI owns the links in its current layout. Disabling removes those links; detach dependent frames first to preserve their placement.")
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
        Text("Choose a frame corner facing the spacer after saving its anchor. New selections reset offsets so the corners touch; later size changes preserve manual nudges. EUI Default leaves the current link in place.")
    elseif page == "Anchors" then
        Section("DEFAULT ANCHOR SPACING")
        local function Gap(side, label)
            return {
                type = "slider", text = label .. " gap (pixels)", min = 0, max = 10, step = 1, noCapture = true,
                getValue = function() return ns.GetSettings("anchorGap")[side] end,
                setValue = function(value) ns.SetSetting("anchorGap", side, value) end,
                tooltip = "Spacing outside the target's " .. label:lower() .. " side, in physical pixels. Zero keeps new links flush. Applies to future anchors only.",
            }
        end
        Row(Toggle("anchorGap", "enabled", "Automatic anchor gap",
            "Adds the side's default gap once to newly created flush edge anchors in EUI Unlock Mode. Existing links and manual offsets are preserved. Defaults off."),
            Gap("top", "Top"))
        Row(Gap("bottom", "Bottom"), Gap("left", "Left"))
        Row(Gap("right", "Right"))
        Text("Enable before creating links in EUI Unlock Mode. Zero keeps new links flush. Bar corner presets keep their edge alignment and move outward on the attached side only.")
        Text("Existing links, manual offsets, center/diagonal anchors, screen edges and spacer links are preserved. Save keeps new gaps; Discard restores the layout. Disabling retains saved offsets.")
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
