# Macro provider implementation

## Context

[PRODUCT.md](PRODUCT.md) defines the provider, druid, mage, and general macro
contracts. The researched game-data baseline is Forever build 1.60.1.70450
(ForeverDB, extracted 2026-10-19).

- [functions/Macros.lua](../../functions/Macros.lua) registers providers and owns
  maintenance, scope, events, verified writes, and errors.
- [macros/mage.lua](../../macros/mage.lua) registers the conjure-based mage
  provider.
- [macros/druid.lua](../../macros/druid.lua) registers the Rebirth/Revive and
  self-Thorns providers.
- [macros/general.lua](../../macros/general.lua) registers the account-wide
  food/water provider.
- [core/Settings.lua](../../core/Settings.lua) declares account defaults,
  initializes character stores, validates names, and preserves ownership on
  reset.

## Proposed changes

Keep `functions/Macros.lua` as the sole maintenance implementation. Registration
validates metadata at the author boundary and delegates module-key uniqueness
to `ns.RegisterModule`. Record the provider ID only after module registration
succeeds so rejected registrations can be corrected and retried.

The provider surface is:

```lua
ns.RegisterMacroProvider("stable-id", {
    settingsKey = "featureMacro",
    scope = "account",              -- optional; "character" by default
    class = "CLASS_TOKEN",          -- or "ALL" for an account provider
    classLabel = "Readable class",
    defaultName = "Macro Name",
    events = { "BAG_UPDATE_DELAYED" }, -- optional refresh events
    Build = Build,
})
```

`Build` is called as `provider.Build()`, never as a method. It returns either
`body` or `nil, status, missingSpellIDs`. Do not mutate registration metadata
after registration; declared events are copied at registration. Expected
readiness failures use return values; unexpected exceptions reach the shared
asynchronous error boundary. Builders do not catch their entire operation or
clear core errors. The shared module clears errors after a successful run,
including an expected waiting/conflict result.

## Shared helpers

`functions/Macros.lua` exposes the shared conjured food and water tiers as
`ns.MacroItems.Food` and `ns.MacroItems.Water`. Each entry keeps `level`, `spell`,
and `item`; mage uses spell and item, general uses item only.

`ns.MacroSpells.HighestKnown(tiers)` accepts a dense strongest-first array of
`{ level, spell }` records and returns the selected record or nil. Extra fields
such as `item` remain on the returned record. `ns.MacroSpells.Name(spellID)`
returns a nonempty localized name or nil. `ns.MacroSpells.HighestOwned(tiers)`
returns the first tier whose `item` is present in the player's bags, ignoring
bank contents.

Known-spell lookup tries `C_SpellBook.IsSpellKnownOrInSpellBook`,
`C_SpellBook.IsSpellKnown`, `IsSpellKnown`, then `IsPlayerSpell`. Missing, throwing,
or nil-returning APIs fall through; the first non-nil answer, including false,
is authoritative. Name lookup tries `C_Spell.GetSpellInfo(id).name`, then
`GetSpellInfo(id)`. Bag lookup scans bags 0 through `NUM_BAG_SLOTS`, using
`C_Container.GetContainerItemInfo`, then `C_Container.GetContainerItemID`, then
legacy `GetContainerItemID`. The protected calls are client API compatibility
boundaries. The helpers do not cache knowledge, names, or bag contents.

Macro text uses localized base names without rank suffixes. The client selects
the highest learned rank for an unranked spell name. Do not append "Rank N".

## Scope and ownership

Character providers use `ns.charDB[settingsKey].ownedMacros[name].lastGeneratedBody`.
Account providers use `ns.db[settingsKey].ownedMacros[name].lastGeneratedBody`.
Both records are read and written by the same verified create/edit path.

Names are checked across both scopes. A character provider accepts a sole
character-slot match; an account-scope match is a conflict. An account provider
accepts a sole general-slot match; any character-scope match is a conflict.

A sole same-name macro with no valid ownership record is adopted: its body is
replaced when it differs, the readback is verified, and only then is ownership
recorded. If the body already matches, adoption records ownership without a
write. Once owned, a body that differs from `lastGeneratedBody` is a manual edit
and is preserved.

Creation calls `CreateMacro(name, icon, body, true)` for character providers and
passes nil as the fourth argument for account providers. Capacity checks use the
returned account and character counts separately. Edits preserve the owned
macro's name and icon in both scopes.

`ns.ResetSettings` restores preference defaults but preserves every
`ownedMacros` table found on account settings, so general-macro ownership
survives reset. Character ownership is already outside account defaults.

## Refresh events and lifecycle

The shared frame always subscribes to `PLAYER_LEVEL_UP`, `SPELLS_CHANGED`,
`LEARNED_SPELL_IN_TAB`, and `UPDATE_MACROS` while active. A provider may declare
additional refresh events; registration validates a dense array of nonempty
event names without controls. The shared frame registers declared events on
activation and releases all of them on stop. Declared events use the same
coalesced queue as built-in events; providers never create frames or timers.

The general provider declares `BAG_UPDATE_DELAYED`, so the body follows bag
contents. Combat postpones bag-triggered writes until `PLAYER_REGEN_ENABLED`,
and the combat-end subscription exists only while work is pending.

## Settings, names, and options

Aggregate macro providers use the existing account settings table. Character
scope also needs an empty character table under the same key; account scope does
not. Shipped defaults are:

```lua
mageMacro = { enabled = false, name = "FoodWater" }
druidRebirthMacro = { enabled = false, name = "Rebirth" }
druidThornsMacro = { enabled = false, name = "Thorns" }
generalFoodWaterMacro = { enabled = false, name = "Food and Water" }
```

Every generated macro is opt-in. Existing saved `enabled` values are preserved,
so an earlier install that had a provider enabled remains enabled.

`InitializeSettings` repairs invalid persisted names for every defaults table
that has a string `name`. `SetSetting` applies the shared macro-name validation
to every such key, not only the mage key. Existing names remain limited to 16
characters and reject controls and `|`.

All macro controls live on one **Macro** page. Sections are **General** first,
then class sections alphabetically; shipped order is General, Druid, Mage. Each
provider pairs a maintenance toggle with a native Rename button in one
two-slot row. Do not create a separate page per class or per provider.

## Addition scaffold

Start with [MacroProvider.lua](../../docs/templates/MacroProvider.lua), which is
development-only and deliberately has no tiers. It demonstrates selecting one
known spell, returning missing localized data, generating text, and registration.
Replace its example identifiers and supply verified class-specific data; adapt
the body to the feature's behavior.

For every addition:

1. Copy the template to `macros/<feature>.lua`. Choose a new stable provider ID
   and settings key; IDs need not equal keys. Fill in the real class token,
   label, default name, known tiers, and macro commands. Confirm spells/items
   through wago.tools or the Forever client data, and game/API behavior through
   Blizzard's `forever` wow-ui-source branch.
2. Add `{ enabled = <default>, name = <defaultName> }` to `ns.defaults` in
   `core/Settings.lua`. For character scope, add an empty character table under
   the same key to `InitializeSettings`' character defaults. Account scope uses
   account ownership instead. Do not overwrite existing records.
3. Name validation is keyed off the defaults table's string `name`, so no new
   validation branch is needed. Do not create another store or reset routine.
4. Add the provider to `CalmEUITweaks.toc` after `functions/Macros.lua` and
   before options. Do not call `RegisterModule`, initialize, or apply the
   provider separately; registration returns the module enrolled in the shared
   lifecycle.
5. Add the provider to the matching section on the single **Macro** options page.
   Follow same-file EUI examples, native dual-row packing, search prebuild, and
   live page callbacks. A new provider does not require its own page or slash
   command.
6. Add focused provider regressions and update `SPEC.md`, `README.md`, and this
   contract. Run the repository checks and installed-game checks before release.
   Do not add events, polling, or write/ownership helpers to the provider.
   Requirements needing events beyond `PLAYER_LEVEL_UP`, `SPELLS_CHANGED`,
   `LEARNED_SPELL_IN_TAB`, `UPDATE_MACROS`, and declared provider events need an
   explicit shared maintenance change and tests.

Exclude `specs/` through `.pkgmeta` and package validation. The template lives
under already excluded `docs/`; neither development artifact is a TOC file.

## Testing and validation

- `tests/MacroProviders.lua`: registration shape, duplicates and failed retry
  (1-4); multiple-provider lifecycle/settings/ownership isolation and scaffold
  readiness (5-10, 19); shared rank/name fallbacks (11-13).
- `tests/ProviderMacros.lua`: druid metadata and exact bodies; unranked names;
  Rebirth/Revive tier boundaries and missing data; Thorns creation; general
  metadata, account scope, bag-rank selection, bag updates, manual edits,
  conflicts, combat deferral, and disabled/non-class behavior (3-10, 12-14,
  25-33).
- `tests/Macros.lua`: mage metadata and all supported rank boundaries, independent
  families, missing knowledge/data, exact localized output, and same-name
  adoption (15-16, 22-24); existing tests cover coalescing, combat, cancellation,
  data requests, ownership, capacity, length, and error recovery (9-18).
- `tests/CoreOptions.lua` and `tests/Smoke.lua`: real module registration, TOC
  order, settings validation/reset, commands, cached options, the single Macro
  page, and error recovery (1-3, 19-21). Run `mise run check` for source
  validation, Lua 5.1 syntax/regressions, ShellCheck, and actionlint.
- Installed Forever/EUI: verify learned/unlearned Druid ranks, Rebirth/Revive
  combat switching, Thorns self-cast, localized names, general bag-rank updates
  on pickup/consume/trade and character switch, collision handling in both
  scopes, icon preservation, manual edits, rename/disable/reset, combat
  transitions, search/page switching/status, and full slots. Mocked APIs cannot
  verify client spell IDs, macro parsing, account macro storage, click behavior,
  or UI rendering.
