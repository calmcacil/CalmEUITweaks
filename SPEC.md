# Calm UI Tweaks specification

This document describes the current implementation and its verification
requirements. User setup instructions are in [README.md](README.md).

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

Preference reset restores defaults while retaining the chat default, spacer
geometry and character records. It disables spacers and automatic chat updates,
preserves macros, and lets native spacer removal clean up their links.

### Versioned SavedVariables

The [SavedVariables contract](specs/saved-variables/PRODUCT.md) and
[implementation/authoring guide](specs/saved-variables/TECH.md) define upgrades.
`CalmUITweaksDB.schemaVersion` is the last completed account migration; the code
currently requires version 4. Missing canonical metadata adopts only recognized
legacy `cvarVersion` 0/1, otherwise starts at 0. Step 1 retains gathering cleanup;
step 2 removes recognized obsolete account markers and migrates shared anchor
gaps (step 4 later retires that subtree). Step 3 adds the default-off cursor fix
preference without native writes and preserves any existing subtree. Step 4 is
the 1.0 cleanup: it removes recognized retired account roots such as
`gatheringSparkles`, `whatsTraining`, `anchorGap`, `spacerCorners` and legacy
version markers. Unrecognized keys are preserved, so macro-provider settings and
future preferences survive. Initialization removes the retired character roots
`spacers` and `spacerCorners` after the legacy spacer import; other character
keys remain. Steps checkpoint in order only after success. Pure-data failures
discard tentative changes; native cleanup retains unresolved ownership for retry.

The checkpoint is outside preference defaults and survives reset. Unknown,
malformed or conflicting metadata in either store is preserved and blocks startup.
Character `version` 1 or absence is supported; no new character schema counter is
introduced. While pending or blocked, feature initialization, setters and reset
are unavailable, with native disabled-state feedback and status reasons.

Existing saved data announces completed upgrades once after login, for example
`savedvarsdb updated from "1" to "4"`; fresh/current accounts stay silent. On
successful readiness, startup resumes once and releases migration subscriptions.
The [CVar cleanup guide](specs/cvar-migrations/TECH.md) specializes this same runner;
it is not a separate versioning system.

### Retired targeting settings

Ore/herb sparkles have no module, toggle, animations or target/nameplate event
subscriptions. For accounts pending migration 1, the cleanup module validates
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
  Use the development template in `docs/templates/MacroProvider.lua`.
- The mage provider maintains a character macro using supported known rank tiers
  and localized spell names. Left-click uses food/water; right-click conjures via
  a cast sequence. Updates defer in combat. Unowned or manually changed macros
  are not overwritten; disable, rename and reset do not delete macros.
- The druid providers maintain character macros for Rebirth in combat and Revive
  out of combat, and for self-cast Thorns. Spell names are unranked so the client
  uses the highest learned rank. Both Rebirth and Revive must be known.
- The general provider maintains one account-wide general macro available to all
  classes. Left-click eats the highest-rank conjured food in bags; right-click
  drinks the highest-rank conjured water. `BAG_UPDATE_DELAYED` refreshes the body;
  bank contents do not count and the last active character's bags win.
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
- Bag upgrade arrows default on. Protected changes wait through combat.

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

Spacer integration depends on EUI's private unlock-element registry, anchor
records and native reapply APIs. These dependencies are outside the supported
plugin contract; revalidate them when updating EUI.

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
- [ ] Upgrade from saved gathering settings. Confirm there is no gathering
  toggle/search result/effect, still-owned targeting CVars restore, later external
  values survive, and pending cleanup survives combat/reload without polling.
  Confirm quest loot sparkles remain independent and available. Upgrade older
  schema 3 data and confirm retired account and character roots are removed
  while live preferences, unrecognized keys, chat default, spacer geometry and
  macro ownership survive.
- [ ] Open all four pages, use search, check status and confirm settings survive
  reload and remain independent of EUI profile changes. Check row packing at
  different UI scales and that saving/importing the first chat default enables
  Apply Default and Export Default immediately. Confirm General contains the
  sparkle, LFG, cursor fix and bag upgrade arrow controls with live status;
  macro settings have one home. Change feature status while another EUI module
  is selected: that page must remain untouched, and returning to the plugin must
  refresh its cached controls and status. Check wrapped status text at different
  UI scales.
- [ ] Use Rename Macro, cancel once, confirm a valid name, and reject an invalid
  name. Check current name/status after page switching and reload. Toggle bag
  upgrade arrows and their scope switches; dependent controls must refresh in
  place and keep their saved values. Check rename availability through combat.
- [ ] With EllesmereUIBags absent/disabled, confirm its controls are greyed out
  on General, dependency tooltips are clear, and saved preferences survive
  reload. If loaded later, controls must refresh without rebuilding the page,
  including patches saved off.
- [ ] Exercise all spacers, centered-bar chains, resizing, removal, Save/Discard,
  scales and combat transitions. Queue a spacer enable/disable during editing,
  enter combat, and confirm the change waits through automatic editor resumption
  until the edit session actually closes.
- [ ] Roundtrip chat exports and apply across characters with missing/extra tabs,
  unsupported groups, delayed channels and reserved voice windows. Confirm styling
  preservation and one-time automatic updates after chat becomes ready.
- [ ] Check localized mage ranks, macro collisions, combat deferral, all bag/bank
  scopes and item loading.
- [ ] Confirm EUI still shows native bag item levels and colors at every quality,
  and that disabling the feature removes only owned arrows. Compare bag-open CPU
  usage against the feature off, including idle open bags and
  equipment/non-equipment loot. Check paired rings/trinkets, weapon rules,
  pending equipped data, scope switches, reload and combat transitions. Close
  bags during an equipped-item data request, reopen after a failed completion,
  and check recovery. Level up with an above-level upgrade visible; its red arrow
  must clear when the item becomes usable.
