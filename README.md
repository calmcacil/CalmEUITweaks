# Calm UI Tweaks

A companion addon for [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI/)
on WoW Forever. It adds spacer anchors, shared chat setups, mage, druid and
general macros, bag upgrade arrows, quest-object sparkles, LFG leader locations
and a washed-out cursor fix.

## Requirements and installation

- WoW Forever, interface version `16001`. Other clients have not been validated.
- EllesmereUI with plugin API version 1 or later.
- Optional: EllesmereUIBags for bag upgrade arrows.

Place the files in `Interface/AddOns/CalmEUITweaks/`, with `CalmEUITweaks.toc`
directly inside that folder. Rename a GitHub download's extracted folder if
necessary. Restart the client after installation.

Open `/calmtweaks`, or select **Calm UI Tweaks > Calm's Tweaks** in EUI.
The pages are General, Macro, Chat and Spacers. General contains the sparkle,
LFG, cursor fix and bag upgrade arrow controls with live feature status.
Configure macro maintenance on Macro, grouped as General, Druid and Mage.
Use `/calmtweaks status` to check dependencies and errors.

## Features and defaults

| Feature | Default | Purpose |
| --- | --- | --- |
| Mage macro | Off | Maintains a character macro using supported known food/water ranks. |
| Druid macros | Off | Maintains character macros for Rebirth/Revive and self-cast Thorns. |
| General macro | Off | Maintains an account-wide food/water macro from the highest conjured items in your bags. |
| Bag upgrade arrows | Enabled for all scopes | Adds upgrade arrows in EUI inventory, reagent bags and bank; EUI keeps showing native item levels. |
| Quest loot sparkles | Off | Enables native quest-object sparkles with normal and raid outlines disabled. |
| LFG leader location | Off | Shows the leader's current zone beside each LFG activity. |
| Cursor washed-out fix | Off | Disables the hardware cursor to work around washed-out cursor colors. |
| Chat sharing | Manual; automatic updates off | Shares normal tabs, docking order, message groups and channel subscriptions. |
| Spacer anchors | All four off | Adds invisible, resizable elements to EUI Unlock Mode. |

Features can be configured independently. Missing optional dependencies leave
the affected feature waiting. Font assets and registration belong in a separate
SharedMedia addon; Calm UI Tweaks does not include them.

The addon uses no `OnUpdate` handlers or repeating tickers. Spacer registration
waits through combat and Unlock Mode sessions; disabled features release their
event subscriptions. The bag display skips hidden/disabled scopes and reuses
unchanged item results.
Opening bags and bag/bank content events trigger updates; equipment and level
changes refresh comparisons while bags are visible. Equipped item-data
notifications are subscribed only while a requested lookup is pending in a
visible scope; reopening bags retries requests whose completion could have been
missed.

## LFG leader location

Enable **LFG leader location** on **General** to show each listing leader's
current zone beside the activity in the Looking For Group browser. The label
uses soft blue text with the row's current font and opacity, including EUI styling. No extra addon
is required. Disable Where You At if installed to avoid duplicate labels.

Use the zone to judge travel progress while forming a group. It describes only
the leader, not every member, and does not confirm summoning-stone range.
Location data updates when the native LFG result refreshes; unavailable zones
and labels without enough room stay hidden. Disabling or resetting preferences
hides the labels immediately. The setting is account-wide and defaults off.

## Cursor washed-out fix

Enable **Cursor washed-out fix** on **General** if your cursor appears pale or
washed out. It sets `HardwareCursor` to `0`, using a software cursor. This can
cause cursor lag or flickering; disable the fix if responsiveness suffers.

The account-wide toggle defaults off. Disabling or resetting restores the prior
CVar value only if it still matches this feature's last write. Restoration
survives reloads and character changes, and changes wait through combat.
If you already disabled the hardware cursor manually, enabling this feature
does not acquire that value; disabling it will leave your manual workaround on.
To restore the hardware cursor manually, use `/console hardwareCursor 1`.

## Quest loot sparkles

Enable **Quest loot sparkles** on **General** to use the client's native sparkle
effect on lootable quest objects. This disables normal and raid outline
highlighting. Graphics changes reapply the sparkle settings while enabled;
there is no polling or custom animation.

Disabling or resetting the toggle restores graphics values changed by this
feature when they still match its last writes. Previous values survive reloads
and character switches; later external values are preserved. Changes wait until
combat ends. Restart the game to remove lingering sparkles; `/reload` is not
enough on the researched Forever build.

When replacing ForeverLootSparkles, turn its options off first, then disable
that addon and restart the game. Console variables persist independently of
addons. Calm UI Tweaks cannot recover graphics values previously changed by
another addon; values already configured for sparkles are left as found.

## Saved-data upgrades

Ore/herb sparkles have been removed. On upgrade, the addon restores targeting
settings recorded by the old feature only when they still match its last writes;
subsequent changes by you or another addon are preserved. Cleanup waits through
combat or unavailable APIs, keeps unfinished records across reloads, and removes
the obsolete settings when complete. The account-wide `schemaVersion` now tracks
all saved-data migrations. Existing 0.6.x `cvarVersion = 1` data adopts that completed
cleanup and upgrades to schema 4 without replaying it. Step 3 adds the cursor fix
preference, defaulting off without changing the native cursor. Step 4 is the 1.0
cleanup: it removes recognized retired account roots such as gathering sparkles,
What's Training, anchor gaps and corner alignment, while keeping live
preferences. Unrecognized keys are preserved so macro providers and future
settings are not lost. Initialization also removes retired character roots after
the one-time spacer import. After login, an existing account gets one notice
such as
`savedvarsdb updated from "3" to "4"`; fresh and already-current accounts stay
silent.

`/calmtweaks status` reports upgrade progress or errors. Features and options
editing wait until the saved schema is ready, so nothing uses partially upgraded
data. Unsupported account or character versions are preserved rather than reset.
Do not manually raise the version to bypass cleanup. Back up SavedVariables before
upgrading or downgrading; older releases that do not understand the new schema
cannot enforce its downgrade protection.

## Spacer anchors

Enable the spacers you need under **Spacers**, then open EUI Unlock Mode.
They appear as **Spacer 1** through **Spacer 4** under **Calm UI Tweaks**.
Use EUI's Width and Height controls to set their size.

For matching gaps around a centered power bar:

1. Set Spacer 1 and Spacer 2 to the same width, such as 24.
2. Anchor Spacer 1 to the power bar's LEFT side, then Player to Spacer 1's LEFT side.
3. Anchor Spacer 2 to the power bar's RIGHT side, then Target to Spacer 2's RIGHT side.
4. Set anchor offsets to zero and save. Each gap equals the spacer width.

For TOP/BOTTOM chains, spacer height determines the gap. Spacers follow EUI's
anchor chains when the central element changes size, and remain invisible and
noninteractive during gameplay.

Enable switches, size and standalone position are account-wide. EUI owns the
anchor links, and Unlock Mode Save/Discard keeps spacer geometry. Disabling a
spacer removes its links; detach dependent frames first if you want to preserve
their placement. Re-enabling keeps saved geometry but requires recreating links.
Change enable switches outside combat and after closing Unlock Mode. Pending
changes also wait through combat-suspended Unlock Mode sessions until you finish
editing.

## Shared chat setup

Configure chat on one character, then use the **Chat** page:

- **Save Default** captures an account-wide setup, replacing the previous default after confirmation.
- **Apply Default** replaces this character's normal tabs and routing after confirmation, closing extra normal tabs and joining required channels.
- **Export Default / Import Default** transfer a `CUTCHAT2` string. Import saves the default without immediately changing live chat.
- **Auto Apply Updated Default** checks at login and applies only when the saved default is newer than this character's applied default, or no apply record exists. It defaults off.

The setup includes tab names, docking order, selected tab, message groups and
per-tab channel names. Existing tabs retain their history, position, size,
fonts and styling. Combat-log filters, reserved voice windows and temporary
whisper windows remain local. Newly created tabs use native defaults.

Unsupported message groups are skipped according to the running client's
definitions. Application waits for combat to end and for chat/channels to be
ready. A manual request retains the selected default while waiting for message
definitions or chat frames; importing another default cancels that pending request.
Missing API functions or insufficient tab capacity require an explicit retry after
the cause is resolved. City-only or password-protected channels may need a manual join.
Other joined channels are not left.

Automatic updates select work once at login and preserve local edits when the
saved default is equal to or older than the character's applied default.
Importing a default or enabling automatic updates after login waits for the
next login; **Apply Default** remains available for immediate application.
Readiness events finish only work selected at login or requested manually.
If application fails,
resolve the reported issue and retry **Apply Default**. Only `CUTCHAT2` is
supported; save a fresh default for older export formats.

## Macros and bag upgrade arrows

Open **Macro** to configure generated macros. Sections are General first, then
Druid and Mage. Each macro pairs its maintenance toggle with a **Rename** button.
Macro names are account-wide. Renaming does not delete earlier macros, and an
existing unowned macro is never overwritten; choose a free name if there is a
collision. Editing an owned macro suspends maintenance, and disabling a feature
does not delete its macro.

**General food and water** is one account-wide macro available to every class.
Left-click eats the highest-rank conjured food in your bags; right-click drinks
the highest-rank conjured water. It updates when bag contents change. Bank
contents do not count, and the last active character's bags decide the current
item ranks. If either food or water is missing, an existing macro is left
unchanged.

**Druid Rebirth** casts Rebirth in combat and Revive out of combat. Both spells
must be learned. **Druid Thorns** casts Thorns on yourself. Both druid macros use
unranked spell names, so the client casts the highest learned rank. Drag the
character macro onto an action bar to use it.

**FoodWater** remains conjure-based. Left-click uses food and water;
right-click alternates the conjure spells. Both conjure spells must be learned.
Each right-click advances the sequence, which resets after 10 seconds without
use. If localized spell data remains unavailable, turn the feature off and on to
retry loading it. `/calmtweaks macro-name <name>` changes only the mage name.

Updates wait until combat ends. For new macro additions, follow the
[provider contract](specs/macro-providers/PRODUCT.md) and
[registration checklist](specs/macro-providers/TECH.md), starting from
[`docs/templates/MacroProvider.lua`](docs/templates/MacroProvider.lua).

The **BAG UPGRADE ARROWS** section below the personal tweaks on **General**
controls bag, reagent bag and bank scopes with live status. Scope controls are
disabled while bag upgrade arrows are off and retain your choices. They are
greyed out until EllesmereUIBags is loaded. Tooltips identify the required addon;
saved preferences remain unchanged.

The arrows use Blizzard's native item API and do not require SimpleItemLevel.
The feature only adds an up arrow when an item is an item-level upgrade. EUI
keeps showing its native item-level text and colors; this feature does not hide
or restyle them. The arrow is red when the item's required level is above your
level. Comparisons use equipped item levels only: rings and trinkets compare
against the lower equipped slot, one-handed weapons against the main hand, and
two-handed weapons must beat both weapon slots. Shields and offhand items
receive no arrow while a two-handed weapon is equipped. Empty slots count as
zero; unknown equipped data waits to load. Grey/white items receive arrows only
for empty matching slots; two-handed candidates require both weapon slots empty.
These arrows compare item level only, without class usability or stat weighting.
The `simpleItemLevel` preference key and the three scope switches remain
unchanged. Disabling removes owned arrows; protected changes wait until combat
ends.

## Commands and saved settings

```text
/calmtweaks                         Open settings
/calmtweaks status                  Report feature and dependency status
/calmtweaks macro-name <name>       Set the mage macro name preference
/calmtweaks reset                   Show reset instructions
/calmtweaks reset confirm           Reset addon preferences
```

Preferences, general-macro ownership, the chat default and spacer geometry use
`CalmUITweaksDB`. Character-macro ownership and chat apply records use
`CalmUITweaksCharDB`. These are normal WoW SavedVariables, separate from EUI
profiles. Schema version 4 removes recognized retired feature roots while
keeping live preferences and unrecognized keys. Existing character spacer
geometry seeds missing account layouts on first load; later characters cannot
replace established account layouts, and retired character roots are removed
after that import.
Reset preserves the schema checkpoint, saved chat default, spacer geometry and
character records, disables chat automation and spacers, and does not delete
macros or rewrite EUI profiles. Reset and setting changes are rejected while an
upgrade is pending or blocked; the status reason explains why.

## Development

Trust the project config with `mise trust`, then install its pinned tools with
`mise install`. Run `mise run check` from Git Bash or WSL on Windows. See
[SPEC.md](SPEC.md) for the behavior contract and release checks. Mocked regression
tests do not replace verification in WoW. Before changing saved data, follow the
[SavedVariables contract](specs/saved-variables/PRODUCT.md) and
[schema step-authoring guide](specs/saved-variables/TECH.md). Native console changes
also follow the [CVar cleanup guide](specs/cvar-migrations/TECH.md).

The consolidated testing release is **0.2.0**. A future **1.0.0**
will mark the first stable release. Download the installable ZIP from
[GitHub Releases](https://github.com/calmcacil/CalmEUITweaks/releases).
See [CI and releases](docs/CI_RELEASES.md) for automated checks, versioning,
release App setup, and recovery.
