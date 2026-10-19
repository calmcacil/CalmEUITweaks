# Calm UI Tweaks specification

This document describes the current implementation and its verification
requirements. User setup instructions are in [README.md](README.md).

## Scope and integration

The addon targets WoW Forever interface `16001` and requires EllesmereUI.
Options require plugin API version 1 or later, with callable `RegisterPlugin`
and `OpenPlugin` functions. Registration creates a bottom section named
**Calm UI Tweaks**, containing **Calm's Tweaks** and six pages: General,
Mage Macro, Compatibility, Chat, Spacers and Anchors.

Settings belong to this addon rather than EUI profiles or conditional overrides.
Unavailable or rejected plugin APIs disable options and report a status reason;
features retain their own dependency checks. Pages use native two-slot rows,
filled left to right. Only the final row of a section may have an empty slot,
using a fresh `EllesmereUI.BlankRowCfg()` for that slot. Hidden search builds use
`EllesmereUI.IsSearchPrebuild()` to avoid custom label creation. Settings changes
and page restoration refresh cached labels and native widget states in place,
without rebuilding pages. Native refresh errors use the shared options boundary.
Module and page errors are isolated and clear when the failing operation
recovers. Repeated reports are deduplicated until recovery; a later recurrence
reports again.

## Storage and lifecycle

| Store | Contents |
| --- | --- |
| `CalmUITweaksDB` | Account preferences, saved chat default, spacer geometry (`spacerLayouts`) and sparkle console-variable restoration records. |
| `CalmUITweaksCharDB` | Macro ownership, chat apply records and corner baselines tied to native EUI anchors. |
| EUI layout | Native anchor and size-match links, including offsets and growth pins. |

SavedVariables initialize on this addon's `ADDON_LOADED`. Modules initialize
once and apply after login, or immediately when loaded after login. Deferred
requests are coalesced. Protected mutations wait through combat. Missing APIs
and late-loaded dependencies can recover on subsequent lifecycle events.

Runtime Lua must not register `OnUpdate` handlers, repeating tickers or timer
polling chains. Deferred work uses coalesced, bounded event-triggered callbacks.
Idle or disabled features release event subscriptions; combat-end listeners are
armed only while protected work is pending. Unrelated addon loads do not schedule
geometry or theme work. Runtime, test and packaged Lua must be ASCII only.
The source/package validator enforces ASCII and the source validator enforces
the update-handler/ticker restriction.

Legacy character spacer layouts seed missing account layouts with a deep copy
on initialization. Existing account layouts take precedence; obsolete character
spacer storage is removed after migration. The first loaded legacy character
with geometry for a slot supplies that slot's account layout.

The once-only `OnLogin` module callback runs after settings/readiness initialize,
before settings application. Late initial addon loading uses the same callback.

Preference reset restores defaults while retaining the chat default, spacer geometry and
character records. It disables spacers and automatic chat updates, preserves
macros and existing non-spacer anchor offsets, and lets native spacer removal
clean up links.

## Feature contracts

### Quest loot sparkles

- One account toggle on General defaults off. It enables the native quest-object
  effect, with no gathering-node effects, custom textures or animation loop.
- Enabled values are `outlineModeShowLootEffectWhenDisabled=1`,
  `graphicsOutlineMode=0`, `OutlineEngineMode=0`, `raidGraphicsOutlineMode=0`
  and `RAIDOutlineEngineMode=0`. Normal and raid outlines are disabled.
- Login, world entry, variable readiness and relevant console-variable changes
  apply settings through coalesced callbacks. Own writes and unrelated changes
  schedule no work. No timers poll; disabled features release event subscriptions.
  Combat-end subscription exists only while a change or restoration is pending.
- `questLootSparkles.restore` retains previous and applied values account-wide
  across reloads and character switches. Values already matching the requested
  mode are not acquired. Graphics changes enforced while enabled establish new
  restoration baselines. Disable restores only still-owned values, preserving
  later external writes. Reset retains records until restoration completes.
- Missing native graphics APIs or variables leave the enabled feature waiting;
  failed writes report through the shared module error boundary. Failed restores
  retain records for retry. No other addon's settings or assets are used.
- Turning the mode off can require a full game restart to remove lingering
  sparkles on Forever; `/reload` is insufficient according to the researched
  addon's documentation. This client behavior requires installed-game validation.

### Gathering sparkles

- An independent account toggle on General defaults off. One reusable golden
  glint cluster marks only the nearest soft-targeted ore vein or herb. NPCs,
  quest objects and unrelated interactions are excluded. There is no range or
  skill feedback, custom asset or quest-log scan.
- Native cursor texture IDs, paths or atlases identify mining/herbalism targets.
  Forbidden or unreadable targets/plates are skipped. The interaction plate is
  resolved directly or through matching nameplate unit tokens.
- Native alpha animation groups twinkle at fixed positions, stopping on target
  loss, removal, pending combat changes or disable. Target/nameplate changes,
  world entry, variable readiness and relevant console changes coalesce updates.
  No Lua frame updates or polling run. Unrelated NPC plate events are ignored.
- While enabled, `SoftTargetInteract=3`, `SoftTargetInteractRange=15`,
  `SoftTargetInteractArc=2`, `SoftTargetInteractOnlyInRange=0`,
  `SoftTargetIconInteract=1`, `SoftTargetIconGameObject=1` and
  `SoftTargetLowPriorityIcons=1`. `SoftTargetNameplateInteract` is 1 only for
  detected gathering nodes, otherwise 0. Interaction icons can affect other
  objects. The actual detection radius is client-owned and unverified in game.
- Both sparkle modules use the shared owned-console-variable helper.
  `gatheringSparkles.restore` retains original values through owned nameplate
  gating transitions, reloads, character changes and reset. Disable restores
  only still-owned settings. Missing APIs/variables wait; failed writes report.
  Combat-end is subscribed only while work is pending. Disabled idle features
  have no subscriptions; pending restoration retains readiness events.

### LFG leader location

- One account toggle on General defaults off. It adds the listing leader's
  current `areaName` beside the native LFG activity, using
  `C_LFGList.GetSearchResultLeaderInfo`. This is a zone hint for group formation,
  not stone-distance detection or a report about every member.
- Labels use soft blue text and inherit the current activity font, shadow,
  opacity and line height.
  They occupy only the gap before group data, without changing native content.
  Missing/blank zones, hidden results, section dividers and insufficient space
  produce no label. Pooled rows reuse labels and hide stale zones on refresh.
- A secure post-hook on `LFGBrowseSearchEntry_Update` follows native result
  updates. Enabling refreshes existing ScrollBox rows; disabling/reset hides
  owned labels immediately. The once-installed hook does no work while disabled.
  No polling or extra search requests run. Late loading of
  `Blizzard_GroupFinder_VanillaStyle` retries through the shared lifecycle.
- Decoration changes defer through combat; affected labels hide until visible
  rows refresh after combat. The combat-end subscription exists only while work
  is pending. Missing native APIs leave the feature waiting. Callback failures
  use the shared module error boundary. No third-party code or assets are used.
- Native row fields and update functions are outside EUI's plugin API; verify
  their behavior when updating the Forever client or EUI skin.

### Spacers

- Four independent account switches, off by default, register native Unlock Mode
  elements `CalmUITweaks_Spacer1` through `CalmUITweaks_Spacer4`.
- Frames remain shown as transparent, noninteractive geometry. Initial size is
  24 by 24; native size controls accept dimensions from 1 to 2000.
- Size and standalone position are account-wide. EUI owns attached placement,
  propagation and size matching. Save/Discard callbacks preserve geometry.
- Registration/removal waits until outside combat and any active edit session.
  Removal uses `UnregisterUnlockElement`, which also removes native links.

### Player/Target corner alignment

- Independent account choices are `DEFAULT`, `TOPLEFT`, `TOPRIGHT`,
  `BOTTOMLEFT` and `BOTTOMRIGHT`; both default to `DEFAULT`.
- Only EUI `player`/`target` links to enabled spacers are eligible. The native
  side remains unchanged. Facing corners are documented in the README;
  incompatible choices leave the link untouched.
- LEFT/RIGHT links align height edges through `offsetY`; TOP/BOTTOM links align
  width edges through `offsetX`. Dimensions use each frame's effective scale
  relative to UIParent.
- A new corner, side or link establishes alignment with zero separation.
  Persisted side/corner/target baselines let later size changes preserve nudges.
  `DEFAULT` releases management without undoing current offsets.
- Size hooks and native placement/registration/profile notifications trigger
  recalculation. Movement uses
  `ReapplyOwnAnchor` and `PropagateAnchorChain`, skips combat, and restores its
  baseline alongside native Discard.

### Default anchor gaps

- Automation defaults off. Each side defaults to 2 physical pixels and accepts
  integers from 0 to 10. A legacy shared value fills missing side defaults.
- Anchors groups Top/Bottom and Left/Right sliders in two full native rows.
  Sliders are disabled while automation is off and retain their saved values.
- During Unlock Mode, new link records with zero separation receive the selected
  side's outward gap once. `PP.FromPixels` converts pixels to native coordinates.
- TOP/BOTTOM affect only Y; LEFT/RIGHT affect only X. The alignment offset is
  preserved. Native action/CDM corner presets are cardinal links with a separate
  alignment offset, so they follow the same rule without diagonal displacement.
- Growth pins on the separation axis receive the same delta. Alignment pins
  remain unchanged; when a growth direction is recorded, inactive pin fields
  also remain unchanged.
- Existing links, nonzero separation offsets, center/diagonal sides, screen-edge
  links and spacer links are excluded. A replaced anchor store is a layout load,
  not a collection of new links. Defaults never change existing gaps.
- Secure post-hooks on EUI's shared placement/reapply helpers notify changed
  unlock keys. There is no frame watcher. Reapply and propagation use native EUI
  APIs; queued mutations stop outside editing and defer through combat. Native
  Save/Discard owns persistence.

### Chat sharing

- `CUTCHAT2` stores normal tab names, logical tab IDs, docking order, selected
  tab, message groups and channel names. Older formats are rejected.
- Capture, import and apply filter groups against nonempty runtime `ChatTypeGroup`
  definitions. Unsupported groups are omitted; malformed transfer data is rejected.
  Missing runtime definitions defer application.
- Apply matches existing normal windows by name, reuses available user windows,
  allocates missing windows through native APIs and closes extra normal tabs.
  Combat-log filters, reserved voice windows and temporary windows remain local.
- Surviving windows retain history, geometry, styling and interaction settings.
  Presets exclude passwords, CVars and EUI profiles. Required channels are joined;
  unrelated joined channels are not left.
- Import saves the default without immediate live application. Manual save/apply
  uses confirmation; automatic apply defaults off.
- Automatic apply selects a default once at login only when enabled and its saved
  timestamp is strictly newer than the character's `appliedSavedAt`, or no valid
  receipt exists. Equal/older timestamps do not apply, even if content differs.
  Save/import timestamps advance monotonically, including same-second changes.
  Mid-session imports and enabling auto-apply wait until the next login; imports
  cancel queued/pending automatic work. Manual apply remains available.
- Records advance only after restoration and required subscriptions complete.
  World/channel/combat-end events finish selected work without gameplay polling;
  they do not select a new automatic default during the session.
- API failures can leave partial tab changes. Failed attempts retain the prior
  apply record so manual retry remains possible.

### Macro and compatibility

- Macro providers follow [the provider contract](specs/macro-providers/PRODUCT.md)
  and [the registration/addition guide](specs/macro-providers/TECH.md). New
  providers supply metadata and text generation only; shared maintenance owns
  lifecycle, spell-data requests, combat deferral, verified writes and ownership.
  Use the development template in `docs/templates/MacroProvider.lua`.
- The mage provider maintains a character macro using supported known rank tiers
  and localized spell names. Left-click uses food/water; right-click conjures via
  a cast sequence. Updates defer in combat. Unowned or manually changed macros
  are not overwritten; disable, rename and reset do not delete macros.
- Mage Macro pairs its maintenance toggle with a native Rename Macro button.
  The EUI input popup edits the account name preference through shared
  validation, preserving existing macros and ownership. Rename is unavailable
  before login and during combat. The current name and status refresh in place.
- Compatibility shows live bag and training status. Bag scope toggles are
  disabled while bag item levels are off, preserving their saved choices.
- On General and Compatibility, bag feature/scope controls require loaded
  EllesmereUIBags; the training toggle requires loaded WhatsTraining. Native
  disabled states grey out unavailable controls with dependency tooltips, without
  altering preferences. Dependency checks use `C_AddOns.IsAddOnLoaded`, prefer
  its completed-load flag when present, and disable controls if the API is absent.
  Relevant addon loads refresh cached controls through the existing lifecycle,
  even when the patch preference is off. Unrelated loads do not refresh options.
- Native bag item levels replace the former SimpleItemLevel bridge without
  requiring SIL. The existing `simpleItemLevel` preference key and scope switches
  remain intact. Equipment labels use Blizzard's detailed item level, quality
  color, NumberFontNormal at top right, and an upgrade arrow at top left.
- Comparisons use equipped item levels only, not stats or class usability.
  Rings/trinkets use the lower slot, one-handed weapons use main hand,
  two-handed weapons must beat both slots, and offhand items are excluded while
  a two-handed weapon is equipped. Empty slots count as zero; unknown equipped
  data does not. Above-player-level upgrades have red arrows.
- Grey/white candidates only receive arrows for empty matching slots, even if
  their item level exceeds equipped gear. Either paired ring/trinket slot may
  be empty; two-handed candidates require both weapon slots empty. The offhand
  exclusion still applies. Green-or-better comparisons and all labels are unchanged.
- Bag opening, content events, equipment changes while visible and scope changes
  trigger coalesced updates. Unchanged results and pending item callbacks are
  reused. Native texture, quality and refresh writes do no item queries.
  Equipped item levels are cached per open/equipment refresh. Item-data events
  are subscribed only for pending equipped lookups; unrelated and duplicate
  completions do not schedule work. Failed loads wait for a later normal refresh.
  Hidden/disabled scopes do not scan or compare. Combat changes defer and
  stale callbacks cannot repaint recycled buttons. Disable restores owned native
  visibility without changing native text or SIL saved settings.
- WhatsTraining matches text and inline colors to the native spellbook's current
  text color in EUI and Modern skins, using EUI's white default before native
  controls load. It recognizes both parchment and already-dark WT text, retains
  WT's dark-theme status tones and each label's alpha, and refreshes on native
  text recolors, skin/look changes and spellbook show events without polling.
- The WT tab inherits the native spellbook backdrop and dim page artwork by
  suppressing its separate coverings. Native spellbook child content is
  suppressed only while the training overlay is open and restored synchronously
  when it closes. Background color/opacity stays owned
  by EUI's spellbook skin, independently of other windows' skin choices.
- WT's launcher follows overlay visibility and uses the native category tabs'
  dark selected fill and one-pixel accent underline. Its return tab stays
  unselected and masks the selected native category button beneath it while
  open; other category tabs stay visible. Closing WT restores the native button
  without changing category selection. WT draws an `INV_Misc_Book_09` launcher
  icon and the current native category's return icon at 36 by 35, centered with
  the native `SquareMask` clipping two pixels from the top and right. Original
  WT icons stay untouched behind the replacement textures and return when the
  fix is disabled. Native square-tab frame/glow artwork stays suppressed across
  `SetSquareMode` and pooled `Init` calls so all category tabs retain EUI's flat
  styling. Category changes and pooled button replacements refresh without polling.
- WT headers follow EUI's Blizzard Skin face, outline and rendered shadow
  FontObject. Spell rows sample native spellbook name/rank fonts and shadows;
  controls retain native faces. Each label preserves its ledger size. Spell
  icons use thin dark edges in compact rows; larger tiles copy native ring art
  and proportions at EUI's half alpha and half desaturation when the ring fits
  their height, falling back to dimmed WT rings until native items exist.
  Heading rows and invisible icons suppress every owned icon decoration.
  Paging uses image arrows; small dropdowns keep their native art and click
  handling. Dividers and EUI tab accents use one-pixel lines. The
  class/weapon toggle is styled around its badge. Its animated glow is hidden
  through vertex alpha so the native alpha-driven animation can finish without
  scheduling per-frame theme walks. Native text/color setters update only the
  changed label. Unchanged native font setters do not schedule theme passes.
  The hidden spellbook defers theme work until shown. Stable fonts and decoration
  layouts are cached; hidden pooled rows are skipped until shown. Pooled widgets
  are picked up on normal layout/show events. Disabling the fix or
  spellbook skin restores owned alpha, fonts, shadows, colors and markup and
  hides created decorations, retaining later native or external writes.
- Compatibility fixes default on. Protected restoration waits through combat.

Font assets and SharedMedia registration are outside this plugin. Packages
must not contain font files; use a separate personal SharedMedia addon.

## Source layout

| Directory | Responsibility |
| --- | --- |
| `core/` | Settings, lifecycle, commands and module registry. |
| `functions/` | Macro maintenance, chat, spacers and anchor behavior. |
| `macros/` | Class-specific macro providers. |
| `compatability/` | One bridge per optional addon; spelling matches the source tree. |
| `options/` | Native EUI plugin registration, pages and chat dialogs. |
| `tests/` | Standalone Lua regression tests with mocked WoW/EUI APIs. |

Anchor integration depends on EUI's private element registry, anchor records,
placement hooks and native reapply APIs. WhatsTraining also hooks private skin
refresh helpers. These dependencies are outside the supported plugin contract;
revalidate them when updating EUI.

## Verification

From the repository root, trust the project config, install the pinned tools,
and run the full check suite:

```powershell
mise trust
mise install
mise run check
```

Use `mise run test` to run only the Lua 5.1 regression suites. On Windows, run
these tasks from Git Bash or WSL so the existing Bash test harness is available.

Before a release, verify on the installed Forever/EUI build:

- [ ] Search for LFG leader location before opening General. Enable it with the
  LFG browser already open; inspect solo/group listings, scrolling/recycled rows,
  long activity/zone names, missing locations, filters, EUI styling and UI scales.
  Check late UI loading, native result updates, combat/end, disable, reset,
  cached pages, reload and account-wide persistence. Confirm it defaults off
  and describes leader zones without claiming stone range. Disable Where You At
  during these checks. Record and inspect the affected UI paths in game.
- [ ] Confirm quest sparkles default off and are searchable on General. Enable
  near a lootable quest object; check normal/raid outline changes, graphics
  presets, reload, character switch, combat deferral, disable/reset restoration
  and a full game restart. Confirm ore/herb approach effects are absent.
- [ ] Enable gathering sparkles independently near ore/herbs. Confirm nameplate
  anchoring, golden native animation, target loss/recycling and no NPC/quest
  decorations. Walk between nodes and test world transitions, fallback plate
  tokens, combat, reload, reset and restoration of prior soft-target settings.
  Record and inspect the animation and transitions on the installed client.
- [ ] Open all six pages, use search, check status and confirm settings survive
  reload and remain independent of EUI profile changes. Check row packing at
  different UI scales and that saving/importing the first chat default enables
  Apply Default and Export Default immediately.
- [ ] Use Rename Macro, cancel once, confirm a valid name, and reject an invalid
  name. Check current name/status after page switching and reload. Toggle bag
  item levels and anchor automation; dependent controls must refresh in place
  and keep their saved values. Check rename availability through combat.
- [ ] With EllesmereUIBags or WhatsTraining absent/disabled, confirm their
  controls are greyed out on General and Compatibility, dependency tooltips are
  clear, and saved preferences survive reload. If loaded later, controls must
  refresh without rebuilding the page, including patches saved off.
- [ ] Exercise all spacers, centered-bar chains, resizing, removal, Save/Discard,
  facing corners, scales, manual nudges and combat transitions.
- [ ] Create side and action/CDM corner links with asymmetric gaps, including zero.
  Confirm outward-only spacing, growth alignment, reload and unchanged existing links.
- [ ] Roundtrip chat exports and apply across characters with missing/extra tabs,
  unsupported groups, delayed channels and reserved voice windows. Confirm styling
  preservation and one-time automatic updates after chat becomes ready.
- [ ] Check localized mage ranks, macro collisions, combat deferral, all bag/bank
  scopes, item loading, training pages in EUI/Modern skins, live skin changes,
  late spellbook loading and restoration when fixes or spellbook skins are disabled.
- [ ] With SimpleItemLevel disabled, compare bag-open CPU usage against the bag
  item-level switch off, including idle open bags and equipment/non-equipment
  loot. Check paired rings/trinkets, weapon rules, pending equipped data, native
  label restoration, scope switches, reload and combat transitions.
- [ ] Compare training fonts, tab icons/selection, icon rings, dropdowns, page
  arrows and header lines with the native spellbook. Switch categories and
  reopen WT in both skins. Hover the class/weapon toggle and confirm stable FPS.
