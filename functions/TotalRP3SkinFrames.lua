local _, ns = ...

local Frames = {}
ns.TotalRP3SkinFrames = Frames

local styled = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local failed = setmetatable({}, { __mode = "k" })
local skin, allowed, report
local applied = 0
local conflicts = {}
local Relations

local function Conflicted(key)
    local api = _G.TRP3_API
    if not _G.ElvUI or not api or not api.module or not api.configuration
        or type(api.module.isModuleLoaded) ~= "function"
        or type(api.configuration.getValue) ~= "function" then return false end
    if api.module.isModuleLoaded("trp3_elvui") and api.configuration.getValue(key) then
        conflicts[key] = true
        return true
    end
    return false
end

local function Resolve(path)
    local frame = _G
    for key in path:gmatch("[^.]+") do
        frame = frame and frame[key]
    end
    return frame
end

local function Paint(kind, frame, ...)
    if not frame then return end
    local kinds = styled[frame]
    if kinds and kinds[kind] then return end
    local paint = skin[kind]
    if type(paint) ~= "function" then return end
    paint(frame, ...)
    if not kinds then kinds = {}; styled[frame] = kinds end
    kinds[kind] = true
    applied = applied + 1
end

local function Font(text)
    Paint("Font", text)
end

local function Button(frame)
    if not frame then return end
    Paint("Button", frame, { "Icon", "icon", "Image", "WarningIcon", "SelectedTexture" })
    Font(frame.Text)
end

local function Panel(frame)
    if not frame then return end
    Paint("Panel", frame)
    if frame.NineSlice then Paint("FadeNineSlice", frame.NineSlice) end
end

local function Group(frame)
    if not frame then return end
    Panel(frame)
    if frame.Header then
        Panel(frame.Header)
        Font(frame.Header.Text)
    end
end

local function Scroll(frame)
    if frame then Paint("ScrollBar", frame.ScrollBar) end
end

local function TextArea(frame)
    if not frame then return end
    Panel(frame)
    if frame.InsetFrame then Paint("Inset", frame.InsetFrame) end
    Scroll(frame)
    if frame.scroll then Scroll(frame.scroll) end
end

local function Shell(frame)
    if not frame then return end
    if frame.Backdrop then
        Paint("FadeRegions", frame.Backdrop)
        if frame.Backdrop.NineSlice then Paint("FadeNineSlice", frame.Backdrop.NineSlice) end
    end
    if frame.Border then Paint("FadeRegions", frame.Border) end
    if frame.NineSlice then Paint("FadeNineSlice", frame.NineSlice) end
    Paint("Shell", frame)
    Paint("CloseButton", frame.CloseButton or frame.Close)
    Font(frame.Title)
end

local function IconButton(frame)
    if not frame then return end
    -- Keep checked/status overlays and the original icon masks intact.
    local icon = frame.Icon
    if not icon and type(frame.GetNormalTexture) == "function" then icon = frame:GetNormalTexture() end
    if icon and type(icon.SetTexCoord) == "function" then
        Paint("SquareIcon", icon, frame)
    end
end

local function Run(surface, frame, paint)
    if not frame then return end
    local ready, deferred = allowed()
    if not ready then
        if deferred then pending[frame] = { surface, paint } end
        return
    end
    pending[frame] = nil
    local ok, err = pcall(paint, frame)
    local key = surface .. " (" .. tostring(frame) .. ")"
    local failures = failed[frame]
    if not ok then
        if not failures then failures = {}; failed[frame] = failures end
        local message = tostring(err)
        if not failures[surface] or failures[surface].message ~= message then
            failures[surface] = { key = key, message = message }
            report(key, err)
        end
    elseif failures and failures[surface] then
        report(failures[surface].key, nil)
        failures[surface] = nil
        if not next(failures) then failed[frame] = nil end
    end
end

local function Hook(frame, method, callback)
    if not frame or type(frame[method]) ~= "function" then return end
    local methods = hooked[frame]
    if methods and methods[method] then return end
    hooksecurefunc(frame, method, callback)
    if not methods then methods = {}; hooked[frame] = methods end
    methods[method] = true
end

local function HookScript(frame, script, callback)
    if not frame or type(frame.HookScript) ~= "function" then return end
    local methods = hooked[frame]
    local key = "script:" .. script
    if methods and methods[key] then return end
    frame:HookScript(script, callback)
    if not methods then methods = {}; hooked[frame] = methods end
    methods[key] = true
end

local function EachPath(paths, surface, paint)
    for path in paths:gmatch("%S+") do
        Run(surface, Resolve(path), paint)
    end
end

local function Browser(frame)
    Shell(frame)
    Paint("EditBox", frame.SearchBox)
    Paint("Dropdown", frame.FilterDropdown)
    Button(frame.AcceptButton)
    Button(frame.StopButton)
    Scroll(frame)
    if frame.Filter then Panel(frame.Filter) end
    if frame.Content then
        Panel(frame.Content)
        if frame.Content.Backdrop then Paint("FadeRegions", frame.Content.Backdrop) end
        Scroll(frame.Content)
        if frame.Content.EmptyState then
            Font(frame.Content.EmptyState.Title)
            Font(frame.Content.EmptyState.Text)
        end
        if frame.Content.ProgressOverlay then
            Paint("ApplyBarFill", frame.Content.ProgressOverlay.ProgressBar)
        end
    end
end

local function ProfileRow(row)
    Button(row.BindButton)
    Button(row.MenuButton)
    Font(row.CurrentText)
    Font(row.CountText)
end

local function ProfileList(list)
    Panel(list)
    if list.Background then Paint("FadeRegions", list.Background) end
    Button(list.CreateButton)
    Paint("EditBox", list.SearchBox)
    Scroll(list)
    if list.ScrollBox and type(list.ScrollBox.ForEachFrame) == "function" then
        list.ScrollBox:ForEachFrame(function(row) Run("Profile rows", row, ProfileRow) end)
        Hook(list.ScrollBox, "Update", function()
            if not allowed() then return end
            list.ScrollBox:ForEachFrame(function(row) Run("Profile rows", row, ProfileRow) end)
        end)
    end
end

local function Tabs(bar)
    if type(bar.GetChildren) ~= "function" then return end
    for _, tab in ipairs({ bar:GetChildren() }) do
        if type(tab.SetTabState) == "function" and tab.Text and tab.Icon then
            Paint("Tab", tab)
            Font(tab.Text)
            Hook(tab, "SetTabState", function(button, state)
                if allowed() and type(skin.SetTabSelection) == "function" then
                    skin.SetTabSelection(button, state == "SELECTED")
                end
            end)
            if type(skin.SetTabSelection) == "function" and type(tab.IsMouseEnabled) == "function"
                and type(tab.IsEnabled) == "function" then
                skin.SetTabSelection(tab, tab:IsEnabled() and not tab:IsMouseEnabled())
            end
        end
    end
end

local function Sidebar(container)
    if type(container.GetChildren) ~= "function" then return end
    for _, button in ipairs({ container:GetChildren() }) do
        if type(button.SetSelected) == "function" and button.Text then
            Paint("Tab", button)
            Font(button.Text)
            Hook(button, "SetSelected", function(tab, selected)
                if allowed() and type(skin.SetTabSelection) == "function" then
                    skin.SetTabSelection(tab, selected)
                end
            end)
            if type(button.IsEnabled) == "function" and type(skin.SetTabSelection) == "function" then
                skin.SetTabSelection(button, not button:IsEnabled())
            end
        end
    end
    Button(_G.TRP3_MainFrameMenuButtonCloseAll)
end

local function ConfigWidget(widget)
    Font(widget.Title)
    Button(widget.Button)
    Paint("EditBox", widget.EditBox)
    Paint("Dropdown", widget.Dropdown)
    Paint("Checkbox", widget.Checkbox)
end

local function ConfigStructure(structure)
    local frame = structure.frame
    if not frame then return end
    if frame.Background then Paint("FadeRegions", frame.Background) end
    Font(frame.Title)
    Scroll(frame.ScrollFrame)
    for _, element in ipairs(structure.elements or {}) do
        if element.widget then ConfigWidget(element.widget) end
    end
end

local function CoreConfigurations()
    if not allowed() then return end
    local config = _G.TRP3_API and _G.TRP3_API.configuration
    if not config then return end
    for _, key in ipairs({ "CONFIG_STRUCTURE_GENERAL", "CONFIG_TOOLBAR_PAGE", "CONFIG_TARGETFRAME_PAGE" }) do
        local structure = config[key]
        if structure and structure.frame then
            Run("Configuration", structure.frame, function() ConfigStructure(structure) end)
        end
    end
end

local coreConfigPages = {
    main_config_0_general = true, main_config_chatframe = true, main_config_directory = true,
    main_config_elvui = true, main_config_launcher = true, main_config_nameplates = true,
    main_config_targetframe = true, main_config_toolbar = true, main_config_tooltip = true,
    main_config_unitpopups = true, main_config_zzz_advanced_settings = true,
}

local function ConfigPage(frame)
    if frame.Background then Paint("FadeRegions", frame.Background) end
    Font(frame.Title)
    Scroll(frame.ScrollFrame)
    local content = frame.ScrollFrame and frame.ScrollFrame.Content
    if content and type(content.GetChildren) == "function" then
        for _, widget in ipairs({ content:GetChildren() }) do ConfigWidget(widget) end
    end
end

function Frames.PageOpened(pageId)
    if not skin or not allowed() or (not coreConfigPages[pageId] and pageId ~= "main_config_relations") then return end
    local container = _G.TRP3_MainFramePageContainer
    if not container or type(container.GetChildren) ~= "function" then return end
    for _, page in ipairs({ container:GetChildren() }) do
        local name = type(page.GetName) == "function" and page:GetName()
        if pageId == "main_config_relations" and page.CreateNew and page.Editor and page.ScrollBox
            and type(page.IsShown) == "function" and page:IsShown() then
            Run("Relations", page, Relations)
            return
        elseif coreConfigPages[pageId] and name and name:match("^TRP3_ConfigurationPage%d+$")
            and type(page.IsShown) == "function" and page:IsShown() then
            Run("Configuration", page, ConfigPage)
            return
        end
    end
end

local function Toolbar(frame)
    if Conflicted("elvui_skin_toolbar_frame") then return end
    if frame.Container then
        Panel(frame.Container)
        if frame.Container.Backdrop then Paint("FadeRegions", frame.Container.Backdrop) end
    end
    Panel(frame.TitleBar)
    if frame.TitleBar then Font(frame.TitleBar.Text) end
    if frame.buttonPool and type(frame.buttonPool.EnumerateActive) == "function" then
        for button in frame.buttonPool:EnumerateActive() do IconButton(button) end
    end
    Hook(frame, "UpdateButtons", function() Run("Toolbar", frame, Toolbar) end)
end

local function Target(frame)
    if Conflicted("elvui_skin_target_frame") then return end
    Group(frame)
    if type(frame.GetChildren) ~= "function" then return end
    for _, button in ipairs({ frame:GetChildren() }) do
        local name = type(button.GetName) == "function" and button:GetName()
        if name and name:match("^TRP3_TargetFrameButton%d+$") then IconButton(button) end
    end
end

local function Tooltips(frame)
    if Conflicted("elvui_skin_tooltips") then return end
    Panel(frame)
end

local function DynamicEditors()
    if not allowed() then return end
    local fields = _G.TRP3_RegisterCharact_Edit_CharactPanel_Container
    if fields and type(fields.GetChildren) == "function" then
        for _, row in ipairs({ fields:GetChildren() }) do
            if row.NameField and row.ValueField then
                Run("Custom characteristics", row, function(frame)
                    Paint("EditBox", frame.NameField)
                    Paint("EditBox", frame.ValueField)
                    IconButton(frame.Icon)
                end)
            elseif row.CustomLeftField and row.CustomRightField then
                Run("Custom personality", row, function(frame)
                    Paint("EditBox", frame.CustomLeftField)
                    Paint("EditBox", frame.CustomRightField)
                    IconButton(frame.CustomLeftIcon)
                    IconButton(frame.CustomRightIcon)
                end)
            end
        end
    end
    local index = 1
    while _G["TRP3_RegisterAbout_Template2_Edit" .. index] do
        local prefix = "TRP3_RegisterAbout_Template2_Edit" .. index
        Run("About section editor", _G[prefix], function(frame)
            Panel(frame)
            IconButton(_G[prefix .. "Icon"])
            Button(_G[prefix .. "Delete"])
            Button(_G[prefix .. "Bkg"])
            TextArea(_G[prefix .. "Text"])
        end)
        index = index + 1
    end
    local styles = _G.TRP3_RegisterMiscViewRPStyle
    if styles and type(styles.GetChildren) == "function" then
        for _, row in ipairs({ styles:GetChildren() }) do
            if row.FieldName and row.Values then
                Run("Roleplay style", row, function(frame)
                    Font(frame.FieldName)
                    Paint("Dropdown", frame.Values)
                end)
            end
        end
    end
end

local function TextToolbar(frame)
    Panel(frame)
    Font(frame.title)
    for _, key in ipairs({ "h1", "h2", "h3", "p", "image", "icon", "color", "link" }) do
        Button(frame[key])
    end
end

local function ParagraphEditor(frame)
    Panel(frame)
    local name = frame:GetName()
    if name then
        IconButton(_G[name .. "Icon"])
        Button(_G[name .. "Bkg"])
        TextArea(_G[name .. "Text"])
    end
end

local function PetBrowser(frame)
    Shell(frame)
    if frame.Header then
        Panel(frame.Header)
        Font(frame.Header.Text)
    end
    if frame.IconPager then
        Panel(frame.IconPager)
        Paint("PageButton", frame.IconPager.PrevPageButton, "<")
        Paint("PageButton", frame.IconPager.NextPageButton, ">")
    end
    Button(frame.AcceptButton)
    Font(frame.OverlayText)
    for _, button in ipairs(frame.iconButtons or {}) do IconButton(button) end
    Hook(frame, "UpdateIconButtonVisualization", function(_, button)
        Run("Pet browser icons", button, IconButton)
    end)
end

local function ListRows(scrollBox, surface, paint)
    if not scrollBox or type(scrollBox.ForEachFrame) ~= "function" then return end
    local function ApplyRows()
        if not allowed() then return end
        scrollBox:ForEachFrame(function(row) Run(surface, row, paint) end)
    end
    ApplyRows()
    Hook(scrollBox, "Update", ApplyRows)
end

local function DirectoryRow(row)
    if not row.Click or not row.Name or not row.Flags then return end
    Panel(row)
    Button(row.Click)
    for _, key in ipairs({ "Flags", "Realm", "GuildOrOwner", "Time", "Relations" }) do Font(row[key]) end
end

Relations = function(frame)
    if frame.Background then Paint("FadeRegions", frame.Background) end
    Font(frame.Title)
    Scroll(frame)
    Button(frame.CreateNew)
    local editor = frame.Editor and frame.Editor.Content
    if editor then
        Shell(editor)
        IconButton(editor.Icon)
        Paint("EditBox", editor.Name)
        Paint("EditBox", editor.Description)
        Button(editor.Save)
    end
    ListRows(frame.ScrollBox, "Relation rows", function(row)
        Button(row)
        Font(row.Title)
        Font(row.Text)
    end)
end

local function ProfileDialog(dialog)
    local frames = dialog.Frames
    if not frames then return end
    Paint("CloseButton", frames.CloseButton)
    for _, key in ipairs({ "ChoicesFrame", "ImportFrame", "ExportFrame", "FinalizeFrame" }) do
        local frame = frames[key]
        if frame then
            Shell(frame.Backdrop or frame)
            Font(frame.Title)
            Button(frame.BlankProfile)
            Button(frame.ImportProfile)
            Button(frame.ImportButton)
            Button(frame.ConfirmButton)
            if frame.Content then
                Panel(frame.Content)
                TextArea(frame.Content.ImportText)
                TextArea(frame.Content.ExportText)
            end
            Paint("EditBox", frame.Name)
        end
    end
end

local function StaticFrames()
    EachPath([[
        TRP3_MainFrame TRP3_BackgroundBrowserFrame TRP3_IconBrowserFrame
        TRP3_ColorBrowser TRP3_CompanionBrowser TRP3_ImageBrowser TRP3_MusicBrowser
        TRP3_LinkCopyDialog TRP3_CurrentlyFrame TRP3_NPCTalkFrame TRP3_AtFirstGlanceEditor
        TRP3_MatureDictionaryEditor TRP3_MatureDictionaryEditor.editPopup TRP3_UpdateFrame.popup
    ]], "Windows", Shell)
    EachPath([[
        TRP3_BackgroundBrowserFrame TRP3_IconBrowserFrame TRP3_ColorBrowser TRP3_MusicBrowser
    ]], "Browsers", Browser)
    EachPath([[
        TRP3_MainFrameMenuScroll TRP3_CompanionBrowserContent TRP3_CompanionBrowserFilter
        TRP3_ImageBrowserFilter TRP3_RegisterDefault TRP3_RegisterCharact TRP3_RegisterAbout
        TRP3_RegisterMisc TRP3_RegisterNotes TRP3_CompanionsPageInformation
        TRP3_RegisterListContainer TRP3_MatureFilterPopup TRP3_CharacterImporter
        TRP3_CompanionImporter TRP3_IconBrowserButtonTooltip TRP3_RegisterAbout_Edit_Template2
        TRP3_MatureDictionaryEditor.content TRP3_MatureDictionaryEditor.addNewWord
    ]], "Panels", Panel)
    EachPath([[
        TRP3_CompanionBrowserClose
    ]], "Close buttons", function(frame) Paint("CloseButton", frame) end)
    EachPath([[
        TRP3_RegisterCharact_NamePanel TRP3_RegisterCharact_CharactPanel
        TRP3_RegisterCharact_Edit_NamePanel TRP3_RegisterCharact_Edit_CharactPanel
        TRP3_RegisterMiscViewGlance TRP3_RegisterMiscViewRPStyle TRP3_RegisterMiscViewCurrently
        TRP3_RegisterNotesViewContainer TRP3_RegisterListCharactFilter TRP3_RegisterListPetFilter
        TRP3_CompanionsPageInformationConsult_NamePanel TRP3_CompanionsPageInformationConsult_Glance
        TRP3_CompanionsPageInformationConsult_About TRP3_CompanionsPageInformationEdit_NamePanel
        TRP3_CompanionsPageInformationEdit_About TRP3_Dashboard.StatusPanel TRP3_DashboardBottom
    ]], "Profile panels", Group)
    EachPath([[
        TRP3_RegisterAbout_Edit_Template1
        TRP3_RegisterMiscViewCurrentlyIC TRP3_RegisterMiscViewCurrentlyOOC
        TRP3_RegisterNotesViewProfile TRP3_RegisterNotesViewAccount TRP3_AtFirstGlanceEditorText
        TRP3_CompanionsPageInformationEdit_About_Text TRP3_NPCTalkFrame.MessageText
        TRP3_CurrentlyFrame.CurrentlyText
    ]], "Text areas", TextArea)
    EachPath([[
        TRP3_RegisterAbout_Edit_Template3_Phys TRP3_RegisterAbout_Edit_Template3_Psy
        TRP3_RegisterAbout_Edit_Template3_Hist
    ]], "Paragraph editors", ParagraphEditor)
    EachPath([[
        TRP3_RegisterAbout_Edit_Toolbar TRP3_CompanionsPageInformationEdit_About_Toolbar
    ]], "Formatting toolbars", TextToolbar)
    EachPath([[
        TRP3_RegisterAbout_Edit_SaveButton TRP3_RegisterAbout_Edit_CancelButton
        TRP3_RegisterAbout_Edit_Music_Action TRP3_RegisterAbout_Edit_BckField
        TRP3_RegisterAbout_Edit_Template2_Add TRP3_RegisterAbout_AboutPanel_MusicPlayer_Play
        TRP3_RegisterAbout_AboutPanel_MusicPlayer_Stop TRP3_RegisterCharact_NamePanel_Edit_SaveButton
        TRP3_RegisterCharact_NamePanel_Edit_CancelButton TRP3_RegisterCharact_Edit_MiscAdd
        TRP3_RegisterCharact_Edit_PsychoAdd TRP3_RegisterDefaultViewCreateProfile
        TRP3_ImageBrowserSelect TRP3_NPCTalkFrame.Send TRP3_ColorBrowser.Content.AcceptButton
        TRP3_ColorBrowser.Content.PresetButton TRP3_CompanionsPageInformationEdit_NamePanel_SaveButton
        TRP3_CompanionsPageInformationEdit_NamePanel_CancelButton
        TRP3_CompanionsPageInformationEdit_About_BckField
        TRP3_MatureFilterPopup.cancel TRP3_MatureFilterPopup.accept
        TRP3_MatureFilterPopup.remember TRP3_MatureFilterPopup.disable
        TRP3_MatureDictionaryEditor.addNewWord.button TRP3_MatureDictionaryEditor.editPopup.button
        TRP3_AtFirstGlanceEditorApply
    ]], "Buttons", Button)
    EachPath([[
        TRP3_RegisterCharact_Edit_FirstField TRP3_RegisterCharact_Edit_TitleField
        TRP3_RegisterCharact_Edit_LastField TRP3_RegisterCharact_Edit_FullTitleField
        TRP3_RegisterCharact_Edit_RaceField TRP3_RegisterCharact_Edit_ClassField
        TRP3_RegisterCharact_Edit_AgeField TRP3_RegisterCharact_Edit_EyeField
        TRP3_RegisterCharact_Edit_HeightField TRP3_RegisterCharact_Edit_ResidenceField
        TRP3_RegisterCharact_Edit_BirthplaceField TRP3_RegisterCharact_Edit_WeightField
        TRP3_RegisterListFilterCharactName TRP3_RegisterListFilterCharactGuild
        TRP3_RegisterListPetFilterName TRP3_RegisterListPetFilterOwner
        TRP3_CompanionBrowserFilterBox TRP3_ImageBrowserFilterBox TRP3_ColorBrowser.Content.HexInput
        TRP3_LinkCopyDialog.EditBox TRP3_NPCTalkFrame.Name
        TRP3_CompanionsPageInformationEdit_NamePanel_NameField
        TRP3_CompanionsPageInformationEdit_NamePanel_TitleField
        TRP3_MatureDictionaryEditor.addNewWord.input TRP3_MatureDictionaryEditor.editPopup.input
        TRP3_AtFirstGlanceEditorName
    ]], "Inputs", function(frame) Paint("EditBox", frame) end)
    EachPath([[
        TRP3_RegisterAbout_Edit_TemplateField TRP3_RegisterCharact_Dropdown_RelationshipField
        TRP3_NPCTalkFrame.ChannelDropdown
        TRP3_Dashboard.StatusPanel.RPStatusMenu TRP3_Dashboard.StatusPanel.WUStatusMenu
        TRP3_Dashboard.StatusPanel.XPStatusMenu
    ]], "Dropdowns", function(frame) Paint("Dropdown", frame) end)
    EachPath([[
        TRP3_RegisterListFilterCharactRealm TRP3_RegisterListFilterCharactNotes TRP3_AtFirstGlanceEditorActive
    ]], "Checks", function(frame) Paint("Checkbox", frame) end)
    EachPath([[
        TRP3_CompanionBrowserTitle TRP3_CompanionBrowserTotal TRP3_ImageBrowserTitle TRP3_ImageBrowserTotal
        TRP3_RegisterListHeaderFlags TRP3_RegisterListHeaderRealm TRP3_RegisterListHeaderGuild
        TRP3_RegisterListHeaderTime TRP3_RegisterListHeaderRelations TRP3_RegisterListHeaderName
        TRP3_RegisterListEmpty TRP3_RegisterDefaultViewText TRP3_ConfigurationModule.Title
        TRP3_AtFirstGlanceEditorTitle
        TRP3_Dashboard.StatusPanel.RPStatusLabel TRP3_Dashboard.StatusPanel.WUStatusLabel
        TRP3_Dashboard.StatusPanel.XPStatusLabel
    ]], "Interface labels", Font)
    EachPath([[
        TRP3_RegisterCharact_CharactPanel_Scroll TRP3_RegisterCharact_Edit_CharactPanel_Scroll
        TRP3_RegisterAbout_Edit_Template2_Scroll TRP3_RegisterAbout_AboutPanel_Scroll
        TRP3_MainFrameMenuScroll TRP3_ConfigurationModule.ScrollFrame
    ]], "Scrollbars", Scroll)
    EachPath([[
        TRP3_CompanionBrowserContentSlider TRP3_ImageBrowserContentSlider
    ]], "Scrollbars", function(frame) Paint("ScrollBar", frame) end)
    EachPath([[
        TRP3_MainTooltip TRP3_RefTooltip TRP3_CharacterTooltip TRP3_CompanionTooltip TRP3_Toast
    ]], "Tooltips", Tooltips)
    EachPath([[
        TRP3_ProfileManager.list TRP3_CompanionsProfiles.list
    ]], "Profile lists", ProfileList)
    EachPath([[
        TRP3_RegisterMainTabBar TRP3_ProfileManagerTabBar TRP3_CompanionInfoTabBar
        TRP3_CompanionsProfilesTabBar TRP3_RegisterListTabBar TRP3_DashboardBottom.TabBar
    ]], "Tabs", Tabs)
    EachPath([[
        TRP3_Dashboard.Background TRP3_RegisterCharact.Background TRP3_RegisterAbout.Background
        TRP3_RegisterMisc.Background TRP3_RegisterNotes.Background TRP3_ProfileManager.list.Background
        TRP3_CompanionsPageInformation.Background TRP3_CompanionsProfiles.list.Background
        TRP3_RegisterDefault.Background TRP3_CharacterImporter.Background TRP3_CompanionImporter.Background
    ]], "Page backgrounds", function(frame) Paint("FadeRegions", frame) end)
    Run("Sidebar", _G.TRP3_MainFrameMenuContainer, Sidebar)
    Run("Profile dialogs", _G.TRP3_ProfileCreateDialog, ProfileDialog)
    Run("Toolbar", _G.TRP3_ToolbarFrame, Toolbar)
    Run("Target frame", _G.TRP3_TargetFrame, Target)
    Run("Pet browser", _G.TRP3_PetBrowserFrame, PetBrowser)
    if _G.TRP3_RegisterListContainer then
        Scroll(_G.TRP3_RegisterListContainer)
        ListRows(_G.TRP3_RegisterListContainer.ScrollBox, "Directory rows", DirectoryRow)
    end
    for row = 0, 5 do
        for column = 0, 7 do
            Run("Companion browser icons", _G["TRP3_CompanionBrowserButton_" .. row .. "_" .. column], IconButton)
        end
    end
    for _, name in ipairs({ "TRP3_CharacterImporter", "TRP3_CompanionImporter" }) do
        Button(_G[name .. "All"])
        Panel(_G[name .. "List"])
        for index = 1, 5 do Run("Importer rows", _G[name .. "ListLine" .. index], ProfileRow) end
    end
    if not Conflicted("elvui_skin_target_frame") then
        Run("Glance bar", _G.TRP3_GlanceBar, Panel)
        for index = 1, 5 do
            Run("Glance bar", _G["TRP3_GlanceBarSlot" .. index], IconButton)
        end
    end
    for index = 1, 5 do
        Run("Profile glance", _G["TRP3_RegisterMiscViewGlanceSlot" .. index], IconButton)
    end
    CoreConfigurations()
    DynamicEditors()
    local page = _G.TRP3_API and _G.TRP3_API.navigation and _G.TRP3_API.navigation.page
    if page and type(page.getCurrentPageID) == "function" then Frames.PageOpened(page.getCurrentPageID()) end
end

function Frames.InstallHooks(S, canApply, onError)
    skin, allowed, report = S, canApply, onError
    for _, entry in ipairs({
        { "TRP3_IconBrowserFrame", "OnIconButtonInitialized", IconButton },
        { "TRP3_BackgroundBrowserFrame", "OnImageButtonInitialized", Button },
        { "TRP3_MusicBrowser", "OnListElementInitialize", Button },
    }) do
        local frame = _G[entry[1]]
        local paint = entry[3]
        Hook(frame, entry[2], function(_, button) Run("Browser rows", button, paint) end)
        local scrollBox = frame and (frame.ScrollBox or (frame.Content and frame.Content.ScrollBox))
        if scrollBox and type(scrollBox.ForEachFrame) == "function" then
            scrollBox:ForEachFrame(function(button) Run("Browser rows", button, paint) end)
        end
    end
    local api = _G.TRP3_API
    local menu = api and api.navigation and api.navigation.menu
    for _, method in ipairs({ "rebuildMenu", "selectMenu", "registerMenu", "unregisterMenu" }) do
        Hook(menu, method, function() Run("Sidebar", _G.TRP3_MainFrameMenuContainer, Sidebar) end)
    end
    local config = api and api.configuration
    Hook(config, "refreshPage", function(pageId)
        CoreConfigurations()
        Frames.PageOpened(pageId)
    end)
    Hook(config, "registerConfigurationPage", function(structure)
        if structure and structure.frame and coreConfigPages[structure.id] then
            Run("Configuration", structure.frame, function() ConfigStructure(structure) end)
        end
    end)
    local ui = api and api.register and api.register.ui
    Hook(ui, "showMiscTab", DynamicEditors)
    HookScript(_G.TRP3_RegisterMiscViewRPStyle, "OnShow", DynamicEditors)
    for _, name in ipairs({ "TRP3_RegisterCharact_NamePanel_EditButton", "TRP3_RegisterCharact_Edit_MiscAdd",
        "TRP3_RegisterCharact_Edit_PsychoAdd", "TRP3_RegisterAbout_AboutPanel_EditButton",
        "TRP3_RegisterAbout_Edit_Template2_Add" }) do
        HookScript(_G[name], "OnClick", DynamicEditors)
    end
    for _, name in ipairs({ "TRP3_RegisterCharact_Edit_NamePanel", "TRP3_RegisterAbout_AboutPanel_Edit" }) do
        HookScript(_G[name], "OnShow", DynamicEditors)
    end
    local popup = api and api.popup
    Hook(popup, "showPetBrowser", function()
        Run("Pet browser", _G.TRP3_PetBrowserFrame, PetBrowser)
    end)
    Hook(popup, "showCopyDropdownPopup", function()
        Run("Copy dialog", _G.TRP3_StaticPopUpCopyDropdown, function(frame)
            Shell(frame)
            Paint("EditBox", frame.CopyText)
            Button(frame.DropdownButton)
            Button(frame.Button)
            Font(frame.Text)
        end)
    end)
    Hook(api and api.ui and api.ui.tooltip, "toast", function()
        Run("Toast", _G.TRP3_Toast, Tooltips)
    end)
    if _G.TRP3_TargetFrame and type(_G.TRP3_TargetFrame.Show) == "function" then
        Hook(_G.TRP3_TargetFrame, "Show", function(frame) Run("Target frame", frame, Target) end)
    end
end

function Frames.ClearPending()
    for frame in pairs(pending) do pending[frame] = nil end
    for frame in pairs(failed) do failed[frame] = nil end
end

function Frames.Apply(S, canApply, onError)
    skin, allowed, report = S, canApply, onError
    if allowed() then
        StaticFrames()
        for frame, work in pairs(pending) do Run(work[1], frame, work[2]) end
    end
    return {
        applied = applied,
        unsupported = "Native exceptions: shared Blizzard menus/popups, semantic slider/swatch/glyph art, profile content and module status borders. Visual testing is still required.",
        conflict = next(conflicts) and "TRP3's active ElvUI skin owns tooltip, target or toolbar surfaces; overlapping surfaces were skipped." or nil,
    }
end
