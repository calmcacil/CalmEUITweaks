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
`EllesmereUI.IsSearchPrebuild()` to avoid custom label creation. Page callbacks
refresh cached labels; chat actions also refresh native widget states in place.
Module and page errors are isolated and clear when the failing operation
recovers. Repeated reports are deduplicated until recovery; a later recurrence
reports again.

## Storage and lifecycle

| Store | Contents |
| --- | --- |
| `CalmUITweaksDB` | Account preferences, saved chat default and spacer geometry (`spacerLayouts`). |
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

- The mage provider maintains a character macro using supported known rank tiers
  and localized spell names. Left-click uses food/water; right-click conjures via
  a cast sequence. Updates defer in combat. Unowned or manually changed macros
  are not overwritten; disable, rename and reset do not delete macros.
- SimpleItemLevel controls filtering/style for labels and upgrade markers in
  EUI inventory, reagent bags and bank. Standard SIL settings changes reconcile
  the bridge; direct external database writes wait for a normal refresh.
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
  changed label. Stable fonts and decoration layouts are cached; hidden pooled
  rows are skipped until shown. Pooled
  widgets are picked up on normal layout/show events. Disabling the fix or
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

Use Lua 5.1 and run from the parent directory containing `CalmEUITweaks/`:

```powershell
lua CalmEUITweaks/tests/CoreOptions.lua
lua CalmEUITweaks/tests/Macros.lua
lua CalmEUITweaks/tests/Chat.lua
lua CalmEUITweaks/tests/Spacers.lua
lua CalmEUITweaks/tests/AnchorGap.lua
lua CalmEUITweaks/tests/SpacerCorners.lua
lua CalmEUITweaks/tests/SimpleItemLevel.lua
lua CalmEUITweaks/tests/WhatsTraining.lua
lua CalmEUITweaks/tests/WhatsTrainingTheme.lua
lua CalmEUITweaks/tests/Smoke.lua
```

Before a release, verify on the installed Forever/EUI build:

- [ ] Open all six pages, use search, check status and confirm settings survive
  reload and remain independent of EUI profile changes. Check row packing at
  different UI scales and that saving/importing the first chat default enables
  Apply Default and Export Default immediately.
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
- [ ] Compare training fonts, tab icons/selection, icon rings, dropdowns, page
  arrows and header lines with the native spellbook. Switch categories and
  reopen WT in both skins. Hover the class/weapon toggle and confirm stable FPS.
