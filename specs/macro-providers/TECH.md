# Macro provider implementation

## Context

[PRODUCT.md](PRODUCT.md) defines the provider and mage behavior contracts.
Research baseline: `481776ab6a4b3d0bc585c3bd68a12b88c6475dbe`.

- [functions/Macros.lua:32 at baseline](https://github.com/calmcacil/CalmEUITweaks/blob/481776ab6a4b3d0bc585c3bd68a12b88c6475dbe/functions/Macros.lua#L32)
  registers providers and owns maintenance, events, verified writes, and errors.
- [macros/mage.lua:81 at baseline](https://github.com/calmcacil/CalmEUITweaks/blob/481776ab6a4b3d0bc585c3bd68a12b88c6475dbe/macros/mage.lua#L81)
  registers the existing mage provider after building localized rank text.
- [core/Settings.lua:3 at baseline](https://github.com/calmcacil/CalmEUITweaks/blob/481776ab6a4b3d0bc585c3bd68a12b88c6475dbe/core/Settings.lua#L3)
  declares account defaults, initializes character stores, validates names, and
  preserves ownership on reset. Lifecycle uses the shared module registry.

## Proposed changes

Keep `functions/Macros.lua` as the sole maintenance implementation. Registration
validates metadata at the author boundary and delegates module-key uniqueness
to `ns.RegisterModule`. Record the provider ID only after module registration
succeeds so rejected registrations can be corrected and retried.

The provider surface is:

```lua
ns.RegisterMacroProvider("stable-id", {
    settingsKey = "featureMacro",
    class = "CLASS_TOKEN",
    classLabel = "Readable class",
    defaultName = "Macro Name",
    Build = Build,
})
```

`Build` is called as `provider.Build()`, never as a method. It returns either
`body` or `nil, status, missingSpellIDs`. Do not mutate registration metadata
after registration. Expected readiness failures use return values; unexpected
exceptions reach the shared asynchronous error boundary. Builders do not catch
their entire operation or clear core errors. The shared module clears errors
after a successful run, including an expected waiting/conflict result.

Expose the existing mage spell lookups as `ns.MacroSpells.HighestKnown(tiers)`
and `ns.MacroSpells.Name(spellID)` in the shared macro file. `HighestKnown`
accepts a dense strongest-first array of `{ level, spell }` records and returns
the selected record or nil. Extra provider-specific fields such as `item`
remain on the returned record. `Name` returns a nonempty localized name or nil.

Known-spell lookup tries `C_SpellBook.IsSpellKnownOrInSpellBook`,
`C_SpellBook.IsSpellKnown`, `IsSpellKnown`, then `IsPlayerSpell`. Missing, throwing,
or nil-returning APIs fall through; the first non-nil answer, including false,
is authoritative. Name lookup tries `C_Spell.GetSpellInfo(id).name`, then
`GetSpellInfo(id)`. The protected calls are client API compatibility boundaries.
The helpers do not cache knowledge/names or request data.

Mage retains its FOOD/WATER data and exact output. Replace its private spell
helpers with calls to the shared helpers. Preserve ID, key, defaults, settings
schema, character ownership schema, and TOC entry. No migration is required.

Ownership remains `ns.charDB[settingsKey].ownedMacros[name].lastGeneratedBody`.
The shared runtime supports a missing preference name by using `defaultName`;
authors must still declare valid settings defaults and initialize the character
table. There is no dynamic settings registration. Existing settings setters
limit names to 16 bytes and reject controls and `|`; runtime validation counts
characters and rejects controls. Keep shipped default names ASCII and at most
16 bytes so both boundaries agree. Bodies use the client's byte limit
`MAX_MACRO_LENGTH`, defaulting to 255.

### Addition scaffold

Start with [MacroProvider.lua](../../docs/templates/MacroProvider.lua), which is
development-only and deliberately has no tiers. It demonstrates selecting one
known spell, returning missing localized data, generating text, and registration.
Replace its example identifiers and supply verified class-specific data; adapt
the body to the feature's behavior. Mage demonstrates two independent families.

For every addition:

1. Copy the template to `macros/<feature>.lua`. Choose a new stable provider ID
   and settings key; IDs need not equal keys. Fill in the real class token,
   label, default name, known tiers, and macro commands. Confirm spells/items
   through wago.tools and game/API behavior through Blizzard's wow-ui-source.
2. Add `{ enabled = <default>, name = <defaultName> }` to `ns.defaults` in
   `core/Settings.lua`. Add an empty character table under the same key to
   `InitializeSettings`' character defaults. Do not overwrite existing records.
3. Extend the existing name validation paths in `InitializeSettings` and
   `SetSetting` for the new key, preserving mage validation. Use existing
   settings helpers; do not create another store or special reset routine.
4. Add the provider to `CalmEUITweaks.toc` after `functions/Macros.lua` and before
   options. Do not call `RegisterModule`, initialize, or apply the provider
   separately; registration returns the module enrolled in the shared lifecycle.
5. Add controls/status via existing options and commands when the feature needs
   them. Follow same-file EUI examples, native dual-row packing, search prebuild,
   and live page callbacks. Verify changed EUI API contracts against author docs.
   A new provider does not require its own page or slash command.
6. Add focused provider regressions and update `SPEC.md`, `README.md`, and the
   provider's behavior spec. Run the repository checks and installed-game checks
   before release. Do not add events, polling, or write/ownership helpers to the
   provider. Requirements needing other readiness events need an explicit shared
   maintenance change and tests.

Exclude `specs/` through `.pkgmeta` and package validation. The template lives
under already excluded `docs/`; neither development artifact is a TOC file.

## Testing and validation

- `tests/MacroProviders.lua`: registration shape, duplicates and failed retry
  (1-4); multiple-provider lifecycle/settings/ownership isolation and scaffold
  readiness (3-7, 17); shared rank/name fallbacks (10-11).
- `tests/Macros.lua`: mage metadata and all supported rank boundaries, independent
  families, missing knowledge/data, and exact localized output (4-5, 10-11,
  19-21); existing tests cover coalescing, combat, cancellation, data requests,
  ownership, capacity, length, and error recovery (6-16). Add duplicate matches,
  same-body unowned matches, unverifiable writes, and owned deletion/recreation.
- `tests/CoreOptions.lua` and `tests/Smoke.lua`: real module registration, TOC
  order, settings validation/reset, commands, cached options, and error recovery
  (1, 3, 17-19). Run `bash scripts/check.sh` for source validation, Lua 5.1
  syntax/regressions, ShellCheck, and actionlint. Syntax-check the development
  template with `luac5.1 -p docs/templates/MacroProvider.lua`.
- Mage settings pair the maintenance toggle with a native button using the
  existing EUI input popup pattern. It calls `ns.SetSetting` for validation and
  reports the result. CoreOptions covers rename, cancellation, invalid input,
  ownership preservation, combat/login availability, and live status (22).
  `ns.RefreshOptions` refreshes cached labels and native widget state through
  an unforced page refresh; native refresh failures participate in the existing
  options error boundary.
- Installed Forever/EUI: verify learned/unlearned rank changes and localized
  names, both click buttons and the sequence reset, reload ownership, collisions
  in both scopes, icon preservation, manual edits, rename/disable/reset, combat
  transitions, search/page switching/status, and full slots (6-22). Mocked APIs
  cannot verify client spell IDs, macro parsing, click behavior, or UI rendering.

## Parallelization

Implement sequentially in the current checkout. The contract, shared helpers,
mage changes, and regressions are small and depend on the same API decisions;
separate worker agents would add coordination without useful isolation.
