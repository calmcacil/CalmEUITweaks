# Total RP 3 skin coverage

## Baseline and evidence

Installed source: Total RP 3 3.5.5, interface 120105/16001, under
`D:/Games/World of Warcraft/_forever_/Interface/AddOns/totalRP3`.
Its root Apache-2.0 LICENSE was checked before source inspection.
Upstream research commit: `ea21082e0395f2ec9516ccf8f6f052e9f5f7380b`.
EUI implementation was not inspected. The integration uses the published
SKINNING_API.md primitives and existing Calm lifecycle helpers.

Implementation state is implemented/unverified unless noted otherwise below.
Mocked regression tests verify ownership and lifecycle, not appearance in game.
No surface is certified visually, and no performance measurement has been made.
The in-game version/build/theme/scale and before/after evidence remain required.

## Surface inventory

| Surface | Source and frame/factory | Styling and creation/refresh path | Preserved regions and ownership |
| --- | --- | --- | --- |
| Main shell | UI/Main.xml: TRP3_MainFrame and its Backdrop child | Shell, separate decorative region/NineSlice fade, CloseButton; startup/deferred apply | Native resize/position/input scripts and all anchors; decorative wood is chrome |
| Sidebar | Core/MainStructure.lua; TRP3_MainFrameMenuScroll and TRP3_MainFrameMenuContainer | Panel, ScrollBar; direct category children receive Tab/Font and actual-instance SetSelected post-hooks; known menu entry points refresh the bounded container | Icons and native navigation; no global descendant scan; initial selected state follows category IsEnabled convention |
| Dashboard | Modules/Dashboard/*.xml; TRP3_Dashboard.Background/StatusPanel, DashboardBottom | Fade background chrome, Group panels, Font, status Dropdown controls, dashboard TabBar | Dashboard logo, messages and status values; custom HTML/news body remains native content |
| Current status/NPC talk | Modules/Dashboard/Currently.xml and Dashboard.xml | Shell, CloseButton, TextArea panels, input, send button and channel dropdown | Text, routing, edit cursor/focus, native sounds and scripts |
| Character directory | Modules/Register/Main/RegisterUIList.xml; TRP3_RegisterListContainer | Panel, scrollbars, filters, header fonts; explicit row Click/Flags shape via bounded ScrollBox visible rows | Player-name fonts/colors and flag data; text columns retain native layout; no profile/data queries |
| Profile controls | Modules/Register/Characters/RegisterUICharacteristics.xml | Group panels, named inputs/buttons, relationship Dropdown, text-area chrome and scrollbars | Displayed names/titles/colors, portraits and profile attributes; icon-only actions retain their glyphs |
| Dynamic characteristics/personality | RegisterCharacteristics.lua and RegisterUICharacteristics.xml; exact edit container and NameField/ValueField or CustomLeftField/CustomRightField rows | Post-OnClick hooks on actual edit/add buttons enumerate that container only; EditBox and icon primitives | Meaningful two-color personality bars/sliders and custom swatch colors remain native |
| About editor | RegisterUIAbout.xml; named editor frames and dynamically named TRP3_RegisterAbout_Template2_EditN rows | Paragraph panels, existing text areas, formatting toolbar buttons, background controls; post-edit/add button scripts drain known paragraph rows | Player-authored HTML, selected backgrounds, section title formatting, image/portrait content and music metadata remain intact |
| About viewer | RegisterUIAbout.xml | Outer profile panel and scrollbars only | SimpleHTML, custom template section backgrounds, authored fonts/colors/images and markup remain native by contract |
| Misc/RP style | RegisterUIMisc.xml; exact RPStyle container | Group panels; Values dropdowns and FieldName labels, bounded only after core show/edit paths | RP style values/colors, descriptions and authored content |
| Notes | RegisterUINotes.xml | Group and inset scrolling-edit-box chrome; native scrollbar | Notes content, read-only semantics, text cursor/scroll position and save behavior |
| Profile manager | UI/Profiles.xml and UI/ProfileManager/*.xml; TRP3_ProfileManager.list and TRP3_CompanionsProfiles.list | Panel, CreateButton, SearchBox, ScrollBar and visible row Bind/Menu controls, bounded row refresh hook | Profile identity/icon, names, counts, selection, actions and profile data |
| Profile create/import/export | UI/Profiles.xml; TRP3_ProfileCreateDialog.Frames | Dedicated Backdrop shells; title fonts, choices/import/confirm buttons, input and scrolling text chrome | WarningIcon, warning text, import/export payloads and native validation; no transfer of ownership to Calm |
| Legacy importers | Modules/Importer/Importer.xml; CharacterImporter and CompanionImporter | Root/list panels, existing five rows each and import-all buttons | Profile icons, identity, counts and original import behavior |
| Core settings | Core/Configuration.lua and UI/Configuration.xml | Three exposed core structures at setup; other whitelisted core configuration page IDs through PAGE_OPENED; direct row Title/Button/EditBox/Dropdown/Checkbox fields | Sliders and color swatches preserve native semantics; extension page IDs are excluded |
| Module manager | Core/ModuleManagement.lua and UI/Modules.xml | Page title and scrollbar; row status treatment stays native | Module border colors/status, help/action glyphs and activation behavior |
| Relations | Modules/Register/Relations/RelationsList.xml; anonymous core relations page | PAGE_OPENED for main_config_relations identifies the exact shown CreateNew/Editor/ScrollBox shape; panels, row buttons, editor inputs/save/close | Relation icons/colors, drag order, editor payloads and semantic swatch |
| Icon browser | UI/Browsers/IconBrowser.xml/.lua; TRP3_IconBrowserFrame | Shell, SearchBox, Content/empty-state chrome, ScrollBar and progress bar; actual instance OnIconButtonInitialized hook | Icon content/masks, check/selection overlays, filter data and search task |
| Background browser | UI/Browsers/BackgroundBrowser.xml/.lua | Shell, search, list/empty chrome; actual instance OnImageButtonInitialized hook styles button with Image and SelectedTexture preserved | Image thumbnail, selection and preview masks |
| Music browser | UI/Browsers/MusicBrowser.xml/.lua | Shell, filter/search, stop/close, ScrollBar; actual OnListElementInitialize styles rows | Music entries, selection and playback behavior |
| Companion browser | UI/Browsers/Companions.xml and UI/Popup.lua | Shell, close, filter and native slider; explicit 6-by-8 grid icon textures | RenameWarning and content icons; normal/pushed textures continue native updates |
| Pet browser | UI/Browsers/PetBrowser.xml/.lua | Lazy showPetBrowser path obtains already-created frame; Shell, Header/IconPager panels, PageButtons, accept/close, actual UpdateIconButtonVisualization hooks | PlayerModel, selected pet/overlay content, masks and accepted result; unavailable client capability remains absent |
| Image browser | UI/Browsers/Images.xml | Shell, filter, select and scrollbar; image canvas excluded from art-removal primitives | TRP3_ImageBrowserContentTexture is the actual preview and must not be faded |
| Color browser | UI/Browsers/ColorBrowser.xml | Shell, Content backdrop, accept/preset controls and hex input | ColorSelect wheel/value textures, selected/readable colors and warning icons; swatch regions remain native |
| Copy/link dialog | UI/HTML/LinkCopyDialog.xml; UI/Popup.lua copy popup factory | Shell, edit input and buttons; lazy showCopyDropdownPopup hook | Payload, shortcut instructions and native read-only/focus behavior |
| Toolbar | Modules/Toolbar/ToolbarFrame.xml/.lua | Container/TitleBar panels, Font, active icon pool; actual UpdateButtons post-hook | Native state driver, icons/status overlays, position/size and provider behavior |
| Target frame | Modules/TargetFrame/TargetFrame.xml/.lua | Group panel and explicit TRP3_TargetFrameButtonN children after actual Show | Name/title colors, native targeting/actions, anchored placement and state driver |
| Glance bars/editor | Modules/Register/Main/RegisterUIGlance.xml; RegisterUIMisc.xml | Glance container panel, five icon textures; editor Shell, check/input/text area/apply/close | Authored glance text/icons, mask and status content; no tooltip anchoring changes |
| TRP3 tooltips/toast | UI/Tooltip/*.lua; Core/UITools.lua; named Main/Ref/Character/Companion/Toast tooltips | Panel/NineSlice chrome; lazy toast path styles only its own reusable frame | Line colors, custom fonts and embedded RP descriptions; shared GameTooltip is never styled |
| Mature filter/dictionary | Modules/Register/Filter/RegisterMatureFilter.xml | Filter panel/buttons; dictionary shell, text inputs, add/edit buttons | Filter decisions, warnings, vocabulary data and native line selection |

## Exact native exceptions

These are safety exceptions, not claims that unsupported ordinary work is done.

1. Blizzard-backed action/context menus and standard TRP3 confirmation/text
   prompts remain native. TRP3 uses shared Blizzard Menu and StaticPopup pools;
   EUI's primitives have no documented unskin operation. Styling a temporary
   TRP3 use could persist into other addons' later use of the same frame.
   EUI may already style those Blizzard surfaces independently.
2. Custom horizontal sliders, personality bars and color swatches retain their
   native semantic textures and control geometry. Published EUI skin API v4 has
   no Slider or ColorSwatch primitive. Substituting ScrollBar/Checkbox/Button
   can remove the meaningful thumb, opposing fill or selected/readable color.
   Their surrounding supported panels, labels and ordinary buttons are skinned.
3. Edit/action/help/resize glyph buttons with artwork as their normal texture
   remain native where no matching EUI glyph primitive exists. Applying a plain
   Button would erase the only indication of the action. Close and page arrows
   use their documented EUI equivalents. Informational/warning artwork stays.
4. Profile-rendered HTML, selected profile backgrounds, image preview canvases,
   portraits, pet models and embedded images retain their presentation. These
   are player/resource content. Fading every region on their container would
   remove content and violates Product 8. Their window chrome is skinned.
5. Module-manager row border colors remain native because TRP3 uses them for
   module state. A generic panel pass would erase that status information.
6. Foreign extension page IDs and extension-owned widgets are not styled.
   TRP3 Extended is outside the initial core scope. Known core page-ID checks
   prevent a later extension registration from receiving generic art removal.

## Conflicts

TRP3 3.5.5's bundled `trp3_elvui` module has independently enabled
`elvui_skin_tooltips`, `elvui_skin_target_frame` and
`elvui_skin_toolbar_frame` preferences. The integration checks the module's
loaded state and each preference before touching that overlapping surface.
Unrelated supported surfaces may still receive EUI styling. Disabling a foreign
skin after it has styled frames requires reload; Calm never tries to undo it.
This is a tested known conflict mechanism, not universal skin-addon detection.

## Required game checks

For every implemented row, record actual client build, TRP3/EUI versions and
theme/UI scale, then exercise opening, selection, enabled/disabled/hover state,
keyboard focus/Escape, scrolling/reuse and close/reopen. Test generated custom
fields and About sections after initial login; tooltip and browser content must
remain visible. Confirm warning icons survive import errors and color preview.
Exercise known ElvUI overlap, combat/Unlock Mode deferral, search/page switching,
theme changes, disable/reload/reset and baseline restoration. Run the performance
comparison in TECH.md before making performance claims. Record gaps by exact
surface; no static or mocked result certifies the installed visual integration.
