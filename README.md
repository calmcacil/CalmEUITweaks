# Calm UI Tweaks

A companion addon for [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI/)
on WoW Forever. It adds spacer anchors, automatic anchor gaps, shared chat
setups, a mage food/water macro, and compatibility fixes for SimpleItemLevel
and WhatsTraining.

## Requirements and installation

- WoW Forever, interface version `16001`. Other clients have not been validated.
- EllesmereUI with plugin API version 1 or later.
- Optional: SimpleItemLevel, WhatsTraining and EllesmereUIBags for their
  compatibility features.

Place the files in `Interface/AddOns/CalmEUITweaks/`, with `CalmEUITweaks.toc`
directly inside that folder. Rename a GitHub download's extracted folder if
necessary. Restart the client after installation.

Open `/calmtweaks`, or select **Calm UI Tweaks > Calm's Tweaks** in EUI.
The pages are General, Mage Macro, Compatibility, Chat, Spacers and Anchors.
Use `/calmtweaks status` to check dependencies and errors.

## Features and defaults

| Feature | Default | Purpose |
| --- | --- | --- |
| Mage macro | Enabled | Maintains a character macro using supported known food/water ranks. |
| SimpleItemLevel bridge | Enabled for all scopes | Displays SIL item levels and upgrade markers in EUI inventory, reagent bags and bank. |
| WhatsTraining fix | Enabled | Themes the training tab to match EUI's spellbook, including backgrounds, fonts and controls. |
| Chat sharing | Manual; automatic updates off | Shares normal tabs, docking order, message groups and channel subscriptions. |
| Spacer anchors | All four off | Adds invisible, resizable elements to EUI Unlock Mode. |
| Player/Target corners | EUI Default | Aligns facing corners when these frames are anchored to a spacer. |
| Automatic anchor gap | Off; 2 pixels per side | Adds outward spacing to new flush edge links. |

Features can be configured independently. Missing optional dependencies leave
the affected feature waiting. Font assets and registration belong in a separate
SharedMedia addon; Calm UI Tweaks does not include them.

The addon uses no `OnUpdate` handlers or repeating tickers. Anchor changes use
native EUI notifications and secure placement hooks; disabled features release
their event subscriptions. The bag bridge skips hidden/disabled scopes, reuses
unchanged item results, and filters item-data notifications to tracked items.

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

Enable switches, size, standalone position and corner choices are account-wide.
EUI owns the anchor links. Disabling a spacer removes its links;
detach dependent frames first if you want to preserve their placement.
Re-enabling keeps saved geometry but requires recreating links. Change enable
switches outside combat and after closing Unlock Mode.

### Player and Target corners

Anchor the frame to an enabled spacer, save, and exit Unlock Mode. Then choose
its corner on the **Spacers** page. The choice names the **unit frame's corner**
and preserves the native anchor side:

| Native side | Frame corner | Touches spacer corner |
| --- | --- | --- |
| LEFT | Top Right / Bottom Right | Top Left / Bottom Left |
| RIGHT | Top Left / Bottom Left | Top Right / Bottom Right |
| TOP | Bottom Left / Bottom Right | Top Left / Top Right |
| BOTTOM | Top Left / Top Right | Bottom Left / Bottom Right |

Corners facing away from the spacer are disabled. A new selection resets
offsets so the corners touch. Later size changes maintain alignment and retain
manual nudges. **EUI Default** stops maintaining alignment and leaves the
current link in place.

## Automatic anchor gaps

Under **Anchors**, enable **Automatic anchor gap** before creating links in
Unlock Mode. Set Top, Bottom, Left and Right independently from 0 to 10
physical pixels. Each defaults to 2; zero gives flush placement.

The gap moves the child away from the target on only the attached side's axis:
TOP moves up, BOTTOM down, LEFT left and RIGHT right. The other axis keeps its
alignment. For action/CDM bar corner presets:

- Horizontal Top/Bottom corners use the Top/Bottom gap and keep left/right edges aligned.
- Vertical bar corners use the Left/Right gap and keep top/bottom edges aligned.

The feature applies once to a new link whose separation offset is zero.
Existing links, manual separation offsets, center/diagonal anchors, screen-edge
links and all spacer links are left alone. Changing defaults affects future
links. Disabling retains saved gaps. EUI Save and Discard control the resulting
layout normally.

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
ready. City-only or password-protected channels may need a manual join.
Other joined channels are not left.

Automatic updates select work once at login and preserve local edits when the
saved default is equal to or older than the character's applied default.
Importing a default or enabling automatic updates after login waits for the
next login; **Apply Default** remains available for immediate application.
Readiness events finish only work selected at login or requested manually.
If application fails,
resolve the reported issue and retry **Apply Default**. Only `CUTCHAT2` is
supported; save a fresh default for older export formats.

## Mage macro and compatibility

The default macro is **Mage FoodWater**. Left-click uses food and water;
right-click alternates their conjure spells. Updates wait until combat ends.
An existing unowned macro is not overwritten. Choose a free name if there is
a collision. Editing an owned macro suspends maintenance; disabling or
renaming the feature does not delete macros.

The **Compatibility** page controls the SimpleItemLevel bag/bank scopes and
WhatsTraining theme fix. The training tab inherits the native spellbook's
backdrop and dim page artwork, so EUI and Modern skins keep their exact
background, color and opacity. Its separate page coverings are suppressed,
and native spells and controls beneath the tab are suppressed only while it is
open. Switching back immediately restores the native content.
The training tab matches the category tabs' dark selected fill and accent line.
Its book icon uses the native category icon size and clipping mask. The return
tab stays unselected and copies the current category icon. Native silver/gold
tab frames stay suppressed when the spellbook rebuilds its tabs.

Training text and inline colors follow the spellbook's text color. Headers use
EUI's Blizzard Skin font, outline and shadow settings. Spell names and ranks
copy the native spellbook's font faces and shadows while retaining ledger text
sizes; input and control fonts stay native. Compact spell rows use thin dark
icon edges. Larger tiles use the native spellbook's dimmed ring artwork when
it fits, and headings have no icon decoration. Paging uses EUI's image arrows;
small dropdown buttons retain native artwork and interaction. Thin dividers,
window accent settings and a compact class/weapon toggle complete the theme.
Skin and accent changes refresh the tab live; EUI may request a reload for
font changes. Hover effects preserve the native animation's completion without
reapplying the entire theme each frame. Native row text/color updates refresh
only their changed labels, and unchanged fonts/layouts are cached. Available, next-level,
unavailable and muted text retain
WhatsTraining's status tones. Before the spellbook loads, text uses EUI's white
default. Disabling the fix or spellbook skin restores owned visual changes.

SimpleItemLevel remains responsible for filtering and style. Disabling a fix
releases its owned visual changes; protected changes
wait until combat ends.

## Commands and saved settings

```text
/calmtweaks                         Open settings
/calmtweaks status                  Report feature and dependency status
/calmtweaks macro-name <name>       Set the mage macro name preference
/calmtweaks reset                   Show reset instructions
/calmtweaks reset confirm           Reset addon preferences
```

Preferences, the chat default and spacer geometry use `CalmUITweaksDB`.
Character-specific macro ownership, chat apply records and corner baselines use
`CalmUITweaksCharDB`. These are normal WoW SavedVariables, separate from EUI
profiles. Existing character spacer geometry seeds missing account layouts on
first load; later characters cannot replace established account layouts.
Reset preserves the saved chat default, spacer geometry and character records, disables
chat automation and spacers, and does not delete macros or rewrite EUI profiles.

## Development

See [SPEC.md](SPEC.md) for the behavior contract, test commands and release
checks. Mocked regression tests do not replace verification in WoW.

The consolidated testing release is **0.2.0**. A future **1.0.0**
will mark the first stable release. Download the installable ZIP from
[GitHub Releases](https://github.com/calmcacil/CalmEUITweaks/releases).
See [CI and releases](docs/CI_RELEASES.md) for automated checks, versioning,
release App setup, and recovery.
