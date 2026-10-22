# Calm UI Tweaks specification

This document defines the 1.0 candidate behavior and verification requirements.
User setup instructions are in [README.md](README.md).

## Scope and integration

The addon targets WoW Forever interface `16001` and requires EllesmereUI.
Options require plugin API version 1 or later, with callable `RegisterPlugin`
and `OpenPlugin` functions. Registration creates a bottom section named
**Calm UI Tweaks**, containing **Calm's Tweaks** and four pages: General,
Macro, Chat and Spacers.

Settings belong to this addon rather than EUI profiles or conditional overrides.
Unavailable or rejected plugin APIs disable options and report a status reason;
features retain their own dependency checks. Pages use native two-slot rows,
filled left to right. Only the final row of a section may have an empty slot,
using a fresh `EllesmereUI.BlankRowCfg()` for that slot. Hidden search builds use
`EllesmereUI.IsSearchPrebuild()` to avoid custom label creation. Settings changes
and page restoration refresh cached labels in place. Native widget refreshes run
only when this plugin's module is active, without rebuilding pages or refreshing
another module. Module lookup and native refresh errors use the shared options
boundary. General contains quest sparkle and LFG controls in one full row, then
the cursor fix with a fresh blank right slot, then a BAG UPGRADE ARROWS section,
with cached live status throughout. Macro controls appear only on Macro.
Module and page errors are isolated and clear when the failing operation
recovers. Repeated reports are deduplicated until recovery; a later recurrence
reports again.

## Storage and lifecycle

| Store | Contents |
| --- | --- |
| `CalmUITweaksDB` | Account preferences, general-macro ownership, saved chat default, spacer geometry (`spacerLayouts`) and sparkle/cursor console-variable restoration records. |
| `CalmUITweaksCharDB` | Character-macro ownership and chat apply records. Initialization removes retired character roots after the legacy spacer import; other keys remain. |
| EUI layout | Native anchor and size-match links, including offsets and growth pins. |

Raw SavedVariables are validated and migrated on this addon's `ADDON_LOADED`,
before defaults or feature initialization. Data-only and empty cleanup steps can
complete there; native cleanup waits for login/out-of-combat readiness. Pending
upgrades delay all feature initialization. Once ready, modules initialize once
and apply after login, or immediately when loaded after login. Deferred requests
use the existing coalescer. Missing APIs can recover on readiness events.

Runtime Lua must not register `OnUpdate` handlers, repeating tickers or timer
polling chains. Deferred work uses coalesced, bounded event-triggered callbacks.
Idle or disabled features release event subscriptions; combat-end listeners are
armed only while protected work is pending. Unrelated addon loads do not schedule
feature work. Runtime, test and packaged Lua must be ASCII only.
The source/package validator enforces ASCII and the source validator enforces
the update-handler/ticker restriction.

Legacy character spacer layouts seed missing account layouts with a deep copy
on initialization. Existing account layouts take precedence. Retired character
storage, including per-character spacer layouts and corner baselines, is removed
after the import. The first loaded legacy character with geometry for a slot
supplies that slot's account layout.

The once-only `OnLogin` module callback runs after settings/readiness initialize,
before settings application. Late initial addon loading uses the same callback.

Preference reset assigns known scalar leaves only, repairing malformed known
tables without replacing valid live subtrees. All boolean preferences become
false and macro names return to defaults. Metadata, unknown nested/provider fields,
macro ownership, chat default/receipts, spacer geometry and character records
remain. Actual macros are not deleted; owned CVars restore through feature paths
and native spacer removal owns link cleanup, without resetting EUI profiles.
`/calmtweaks reset` opens a native EUI confirmation popup. Only confirmation
resets preferences and reloads the UI; cancelling changes nothing. Login,
schema readiness, combat, Unlock Mode, popup and reload availability are checked
before opening and again on confirmation. Typed `reset confirm` cannot bypass
the popup. A rejected reset never reloads.

### Versioned SavedVariables

The [SavedVariables contract](specs/saved-variables/PRODUCT.md) and
[implementation/authoring guide](specs/saved-variables/TECH.md) define upgrades.
Literal `CalmUITweaksDB.calm_forever = true` identifies the Calm Forever lineage;
`schemaVersion = 1` is its first completed schema. Both are metadata outside
preference defaults. Marked v1 reloads preserve user preferences, and later
marked steps remain ordered and append-only.

An absent marker selects legacy validation for schema 0..4/CVar 0..1. Immutable
legacy steps run to 4 before conversion: step 1 restores retired gathering
ownership; step 2 adopts the account schema and migrates shared anchor gaps;
step 3 adds the default-off cursor preference without native writes; step 4 removes
recognized retired account roots (`gatheringSparkles`, `whatsTraining`, `anchorGap`,
`spacerCorners`) and legacy markers. Completed CVar cleanup is not replayed.

The bridge then restores full historical quest graphics and `HardwareCursor`
ledgers before staging a known preference-leaf reset, including macro names.
Every boolean is false: all macro providers, bag arrows and inventory/reagent/bank
scopes, quest sparkles, cursor fix, LFG labels, chat automation and four spacers.
Valid live tables retain unknown nested/provider keys. Account/character macro
ownership, real macros, chat default/receipts, geometry and unknown root keys
survive; explicitly retired roots and invalid ledger entries are exceptions.
Retired character `spacers`/`spacerCorners` are removed only after lazy geometry
import on that character's compatible load. Offline characters are not certified.

Preflight validates both raw stores before mutation or native reads. Non-table
roots, present nontrue markers, marked missing/0/future/malformed checkpoints,
conflicting legacy metadata and unsupported character metadata fail closed.
Marked data cannot contain legacy account version/CVar metadata. Character
`version` remains absent/1, with no character schema counter. Invalid stores are
preserved rather than normalized or reinterpreted as legacy schema 1.

Legacy steps checkpoint only after success. The final baseline preference reset,
marker and v1 checkpoint commit atomically; failed data conversion discards
staged preferences. Partial native restoration is durable and retries after
login, combat or API readiness, including reload/character switches. Pending or
blocked work disables feature initialization, setters and reset; options remain
discoverable with native disabled-state feedback and status reasons. Once ready,
startup resumes once and releases migration subscriptions, without polling.

Existing nonempty accounts get one post-login completion notice naming Calm
Forever v1 and explaining that preferences reset, not an ordinary numeric 4->1
upgrade. Fresh/current accounts stay silent; later same-lineage upgrades use
schema-version notices. Pending/failed work never announces success. Reload and
reset do not repeat notices. Back up SavedVariables before conversion/downgrade:
older binaries ignore the marker; never manually relabel versions or remove it.
The [CVar cleanup guide](specs/cvar-migrations/TECH.md) uses this same runner.

### Retired targeting settings

Ore/herb sparkles have no module, toggle, animations or target/nameplate event
subscriptions. For accounts pending legacy migration 1, the runner validates
`gatheringSparkles.restore` against the eight former targeting CVars, retaining
only recognized applied values and string baselines. Preparation removes the
old enabled preference immediately
and deletes the saved ledger after restoring still-owned values or observing
later external writes. It never sets targeting defaults or touches quest graphics.

Native cleanup starts after login and defers through combat or unavailable console
APIs. Failed restores survive reload and character changes; reset is rejected
while the schema is pending, preserving the unfinished ledger. Only
pending cleanup subscribes to world/variable readiness and relevant CVar changes;
combat-end is subscribed only while waiting. Own writes schedule no work. Fresh
installs and completed cleanup have no cleanup frame subscriptions or polling.
The existing module status/error boundary reports pending work and failures.

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

### Cursor washed-out fix

- One account toggle on General defaults off. Enabled sets `HardwareCursor=0`
  to use the software cursor for washed-out cursor colors. It does not change
  gamma, other graphics settings or cursor size. The tooltip explains possible
  cursor lag or flickering.
- Uses the shared owned-CVar helper. `cursorWashedOut.restore` persists the
  prior/applied value across reloads and characters. Already-matching values
  are not acquired. Disable/reset restores only still-owned values, preserves
  external writes and retains failed restoration records for retry.
- Relevant CVar changes and variable/world readiness coalesce reapplication.
  Own writes and unrelated changes schedule no work. Changes defer in combat;
  combat-end listeners exist only while pending. Disabled/idle releases events.
  Missing APIs or variables wait; failed writes use the module error boundary.
- In game, verify cursor colors and responsiveness, toggle/disable/reset,
  preexisting manual workaround, reload, search/page switching and combat deferral.

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
  elements `CalmUITweaks_Spacer1` through `CalmUITweaks_Spacer4`. They are plain
  anchor elements; no corner alignment or automatic gap behavior remains.
- Frames remain shown as transparent, noninteractive geometry. Initial size is
  24 by 24; native size controls accept dimensions from 1 to 2000.
- Size and standalone position are account-wide. EUI owns attached placement,
  propagation and size matching. Save/Discard callbacks preserve geometry.
- Registration/removal waits until outside combat and any active edit session,
  including combat-suspended sessions. Native open/close notifications retain
  session state even while the editor's visible-active query is false.
  Removal uses `UnregisterUnlockElement`, which also removes native links.

### Chat sharing

- `CUTCHAT2` stores normal tab names, logical tab IDs, docking order, selected
  tab, message groups and channel names. Older formats are rejected.
- Capture, import and apply filter groups against nonempty runtime `ChatTypeGroup`
  definitions. Unsupported groups are omitted; malformed transfer data is rejected.
  Missing runtime definitions defer application. Valid manual requests also wait
  for missing dock/frame/tab instances and retain the selected layout and saved
  date. Imports cancel pending manual work. Missing API functions, unsupported
  frame contracts and insufficient tab capacity reject manual requests without
  retaining readiness listeners; users can retry after resolving the cause.
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

### Macros and bag upgrade arrows

- Macro providers follow [the provider contract](specs/macro-providers/PRODUCT.md)
  and [the registration/addition guide](specs/macro-providers/TECH.md). New
  providers supply metadata and text generation only; shared maintenance owns
  lifecycle, spell-data requests, combat deferral, verified writes and ownership.
  Use the development template in `docs/templates/MacroProvider.lua`. All
  generated macros default off. Conversion/reset restores names and disables
  maintenance without deleting macros or ownership; marked v1 reloads preserve
  later choices. Settings names accept 1-16 bytes, excluding controls and `|`.
- The mage provider maintains a character macro named **FoodWater** using
  supported known rank tiers and localized spell names. Left-click uses
  food/water; right-click conjures via a cast sequence. Updates defer in combat.
  A sole same-name macro is adopted and overwritten; manual edits to an owned
  macro are preserved. Disable, rename and reset do not delete macros.
- The druid providers maintain character macros named **Rebirth** and **Thorns**
  for Rebirth in combat and Revive out of combat, and for self-cast Thorns. Spell
  names are unranked so the client uses the highest learned rank. Both Rebirth and
  Revive must be known.
- **General food macro** maintains one account-wide macro named **Food and Water**
  for every class, even with empty bags. With no items its body is `#showtooltip`;
  a newly created placeholder uses the mage class icon. Food and water independently
  add left-click eat and right-click drink actions at their highest available rank.
  Bag changes remove stale actions and update native item tooltips/icons while the
  generated icon remains owned; manually chosen, adopted and untracked icons stay
  untouched. Bank contents do not count; the last active character's bags win.
- **Macro** pairs each provider's maintenance toggle with a native Rename button on
  one page: General first, then class sections alphabetically. The EUI input
  popup edits the account name preference through shared validation, preserving
  existing macros and ownership. Rename is unavailable before login and during
  combat. Current names and statuses refresh in place.
- General's BAG UPGRADE ARROWS section shows live status. Scope toggles are
  disabled while bag upgrade arrows are off, preserving their saved choices.
- Bag feature/scope controls on General require loaded EllesmereUIBags.
  Native disabled states grey out unavailable controls with dependency tooltips,
  without altering preferences. Dependency checks use `C_AddOns.IsAddOnLoaded`,
  prefer its completed-load flag when present, and disable controls if the API is
  absent. Relevant addon loads refresh cached controls through the existing
  lifecycle, even when the patch preference is off. Unrelated loads do not
  refresh options.
- EUI keeps ownership of native bag item-level text and colors; this feature only
  adds an upgrade arrow at the top right. It does not require SimpleItemLevel.
  The existing `simpleItemLevel` preference key and inventory/reagent/bank scope
  switches remain intact.
- Comparisons use equipped item levels only, not stats or class usability.
  Rings/trinkets use the lower slot, one-handed weapons use main hand,
  two-handed weapons must beat both slots, and offhand items are excluded while
  a two-handed weapon is equipped. Empty slots count as zero; unknown equipped
  data does not. Above-player-level upgrades have red arrows.
- Grey/white candidates only receive arrows for empty matching slots, even if
  their item level exceeds equipped gear. Either paired ring/trinket slot may
  be empty; two-handed candidates require both weapon slots empty. The offhand
  exclusion still applies. Green-or-better comparisons are unchanged; no
  item-level labels or quality filtering are added.
- Bag opening, content events, equipment/level changes while visible and scope
  changes trigger coalesced updates. Level changes invalidate upgrade colors
  outside combat; hidden and disabled scopes have no level-up subscription.
  Unchanged results and pending item callbacks are reused.
  Equipped item levels are cached per open/equipment refresh. Item-data events
  are subscribed only for pending equipped lookups; unrelated and duplicate
  completions do not schedule work. Failed loads wait for a later normal refresh.
  Pending-request bookkeeping expires when completion listeners stop, so reopening
  retries requests whose results could have been missed while all scopes were hidden.
  Hidden/disabled scopes do not scan or compare. Combat changes defer and
  stale callbacks cannot repaint recycled buttons. Disable hides owned arrows
  without changing native text or saved preferences.
- Bag upgrade arrows and all three scope switches default off. Protected changes
  wait through combat.

Font assets and SharedMedia registration are outside this plugin. Packages
must not contain font files; use a separate personal SharedMedia addon.

## Source layout

| Directory | Responsibility |
| --- | --- |
| `core/` | Settings, lifecycle, commands and module registry. |
| `functions/` | Macro maintenance, bags, chat, LFG, spacers and console-variable features. |
| `macros/` | Class-specific macro providers. |
| `options/` | Native EUI plugin registration, pages and chat dialogs. |
| `tests/` | Standalone Lua regression tests with mocked WoW/EUI APIs. |

Spacer integration calls undocumented EUI registration/session/anchor APIs:
`RegisterUnlockElements`, `UnregisterUnlockElement`, `RegisterUnlockModeListener`,
`UnregisterUnlockModeListener`, `IsUnlockModeActive`, `IsUnlockAnchored` and
`ReapplyOwnAnchor`. It does not inspect EUI's private registry or anchor records.
Bag arrows use the private button `_textOverlay` parent when present, with an
owned overlay two frame levels above it; options request native row dividers via
`parent._showRowDivider`. These accepted integrations are outside the supported
plugin contract; retain them and revalidate their behavior when updating EUI.

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

### In-game candidate checklist

The user completes these checks before release approval. Back up account and
character SavedVariables with the client closed; use disposable copies for legacy
or malformed fixtures. Record the candidate revision/ZIP, Forever/EUI versions,
results and any failures. Record and inspect affected UI paths; mocks do not prove
native rendering, CVar restoration or macro execution.

- [ ] Fresh/empty account: confirm `calm_forever = true`, `schemaVersion = 1`, no
  conversion notice and every switch off: four macro providers, bag arrows and
  inventory/reagent/bank scopes, quest sparkles, cursor, LFG, chat auto-apply and
  four spacers. No macro, chat or native CVar changes occur on an empty baseline.
- [ ] Convert unmarked legacy schema 0..4/CVar 0..1 fixtures, including enabled
  features and renamed macros. Verify old cleanup precedes the v1 commit, every
  switch becomes off and names reset once. One post-login notice names the new
  lineage and reset. Real macros/bodies, both ownership scopes, chat default and
  receipts, geometry, unknown root/live nested/provider keys survive; only retired
  roots/invalid ledger entries are discarded. No gathering toggle/search/effect
  remains. Later characters import only missing geometry before retired roots go.
- [ ] With recorded ownership, verify all eight targeting, five quest graphics and
  cursor CVars restore from valid baselines; later external values survive.
  Exercise pending combat/API cleanup, partial restore, reload and another
  character. Marker/v1 must not commit early; options/setters/reset/features wait,
  then startup resumes once. On disposable malformed/future stores, confirm both
  stores remain untouched, editing is blocked and no success notice appears.
- [ ] On marked v1, opt in and rename, reload and switch characters: choices
  survive without another conversion notice. Run normal reset: known leaves and
  names return to defaults, but metadata, nested/provider keys, ownership, real
  macros, chat/history/receipts and geometry remain; owned CVars restore. Run
  `/calmtweaks reset`: Cancel must do nothing; Reset and Reload must reset then
  reload once. Combat or Unlock Mode before/during confirmation must block it.
- [ ] Open all four pages after searching before their first visit. Check native
  row dividers, left-to-right row packing, blank final slots, wrapped status and
  disabled-state tooltips at different UI scales. Switch cached pages and EUI
  profiles; preferences remain independent. Change status while another EUI
  module is selected: it stays untouched and returning refreshes cached controls.
  General contains sparkle/LFG/cursor/bags; macro controls have one home.
- [ ] Cursor fix: note `HardwareCursor`, enable and confirm `0`, inspect colors,
  lag/flicker, reload/alt, disable and reset restoration. A preexisting manual `0`
  is not acquired; later external writes survive restoration. Check combat
  deferral, search and cached-page status.
- [ ] Quest sparkles: enable near a lootable quest object; check all normal/raid
  outline changes, graphics presets, reload/alt, combat, disable/reset restoration
  and a full restart for lingering effects. Ore/herb approach effects stay absent.
- [ ] LFG: disable Where You At. Enable with the browser already open; inspect
  solo/group listings, recycled rows, long/missing zones, narrow space, filters,
  native refreshes and EUI styling/scales. Check late UI load, combat/end,
  disable/reset/reload and cached status. Labels describe leader zones, not range.
- [ ] All four macro providers: mage learned/unlearned localized food/water tiers
  and left/right clicks; druid Rebirth/Revive combat branches and self-Thorns;
  general account macro's highest food/water bag ranks after pickup/consume/trade
  and character switches (bank excluded). Missing spells/data leave spell macros
  unchanged. General food macro must create an empty placeholder, then handle
  food-only, water-only, both and empty-again bags with correct actions/tooltips.
  Check same-name adoption, duplicate/cross-scope conflicts, full slots, manual
  body/icon edits, reload, rename/disable/reset and combat deferral.
- [ ] Rename: cancel, accept a valid name, reject blank/control/`|` names and names
  over 16 bytes (including multibyte input). Check before-login/combat restrictions,
  status, cached pages and reload. Earlier macros are not renamed or deleted.
- [ ] Bags: explicitly enable arrows and each scope. Native item-level text and
  quality colors remain unchanged for every quality; arrows sit above native
  overlays, without obscuring text or stale recycled-button arrows. Check empty
  slots, grey/white rules, paired rings/trinkets, one-/two-hand/offhand comparisons,
  pending item data, reload and combat. Level up with a red above-level upgrade
  visible: red clears when usable. Disable hides only owned arrows.
- [ ] Close bags during a pending equipped-item request and reopen after a failed
  completion; comparisons recover. Compare bag-open/idle CPU with feature off,
  including equipment/non-equipment loot. Scope controls refresh in place and
  retain choices while disabled. With EllesmereUIBags absent/disabled, controls
  grey out with dependency tooltips; late load refreshes without rebuilding,
  including when the feature is saved off.
- [ ] Spacers: enable all four, test centered-bar chains, width/height/position,
  scale changes, Save and Discard separately, reload, removal and re-enable.
  Geometry persists; native link removal does not reset unrelated layouts. Queue
  enable/disable during editing, enter combat and resume: it waits until the
  actual edit session closes, including combat-suspended sessions.
- [ ] Chat: roundtrip exports across characters with missing/extra tabs,
  unsupported groups, delayed channels and reserved voice windows. Preserve
  history, styling and local windows. First Save/Import enables Apply/Export
  immediately. Confirm one-time login auto-apply only for a newer default,
  delayed readiness/combat completion and no mid-session automatic overwrite.

Do not push, tag, publish or upload this candidate until testing is complete and
publication is explicitly approved; follow [CI and releases](docs/CI_RELEASES.md).
