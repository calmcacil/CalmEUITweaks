# Supported SavedVariables

## Summary

Completed Calm Forever schema 1 is the oldest supported saved-data baseline.
Pre-beta conversion is retired. Unsupported or damaged saves remain preserved
until the user confirms discarding them through the existing recovery page.
This boundary was approved on 2026-11-11.

## Behavior

1. A missing or empty account store initializes fresh, with every feature and
   bag scope off and default macro names. Fresh startup is silent and needs no
   native CVar access. Invalid character data still blocks fresh account startup.
2. Nonempty accounts must have literal `calm_forever = true`, an integer
   `schemaVersion` from 1 through the supported version, and no account `version`
   or `cvarVersion`. Nonempty unmarked data is unsupported, including historical
   schema 0..4 and partially completed conversions. It is never upgraded,
   relabeled or automatically discarded.
3. Unsupported account or character data blocks all feature startup and setting
   edits before either store is changed or native CVars are read. The existing
   recovery page explains the reason and offers Reset Saved Data. Cancel retains
   both stores for backup, a compatible build or a later fix. Newer schemas also
   remain preserved; they are not assumed corrupt.
4. Confirmed recovery discards account and current-character addon data and
   reloads to fresh settings. It loses preferences, saved chat, geometry,
   ownership, unknown fields and CVar restoration records. Actual macros, chat
   windows, EUI profiles, current console values and offline character stores
   are unchanged. Login, combat, Unlock Mode, API availability and blocked state
   are rechecked before opening and before confirming. Repeated callbacks reload
   only once. Normal preference reset remains a separate operation.
5. Current supported saves retain choices across reload and character switches:
   enabled preferences, names, ownership, saved chat and receipts, account spacer
   geometry, current CVar ledgers, and unknown root/nested fields. Missing or
   malformed known preference leaves keep the existing normalization rules.
6. Historical character spacer geometry is no longer imported or pruned. Existing
   account geometry remains authoritative. Inert old character `spacers` and
   `spacerCorners` fields remain untouched like unknown data; they do not block
   an otherwise supported account. Character metadata remains absent/1 `version`
   and no `schemaVersion`. A missing character store initializes normally.
7. No historical targeting, quest-graphics or cursor restoration runs for
   unsupported saves. Discarding old ledgers cannot recover past native values;
   users needing that cleanup must use a compatible older build and backup.
   Current quest/cursor enable, disable and normal-reset ownership restoration
   continue to work and preserve later external changes.
8. Future same-lineage upgrades remain ordered and checkpoint only successful
   steps. Native cleanup waits for login, combat end and required APIs; partial
   progress survives reload. Pending work blocks feature startup without data
   loss or success notices. Completed upgrades resume startup once and release
   migration events. Fresh/current accounts do not announce an upgrade.
9. Schema 1 keeps its existing meaning and number. Removing pre-beta support does
   not reset current users or introduce a new lineage. Release versions remain
   independent of schema versions. Downgrades require compatible backups.
