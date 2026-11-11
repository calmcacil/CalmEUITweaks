# Authoring CVar schema steps

## Context

The [SavedVariables contract](../saved-variables/PRODUCT.md) and
[implementation guide](../saved-variables/TECH.md) own startup and checkpoints.
Completed Calm Forever schema 1 is the supported baseline. Pre-beta schema0..4,
retired gathering cleanup and the one-time bridge are removed; do not restore
those paths or add a second version counter or migration event driver.

## Future same-lineage steps

1. Append future steps from 2 onward to `ns.schemaMigrations` and raise
   `ns.SCHEMA_VERSION` with the entry. Schema 1 initializes fresh stores directly;
   unsupported nonempty accounts are preserved for confirmed recovery.
2. Set `settingsKey` to the account subtree containing a `restore` ledger. Set
   `values` to the FULL historical CVar definition in the shared helper format.
   Use `retired = true` only when the entire subtree can be removed. Multiple
   cleanup descriptors can precede a staged data callback through `cleanup`.
3. Restore through `ApplyOwnedCVars(settings, values, false)` after login and
   outside combat. Preserve later external writes. Do not validate with a subset
   of old CVar names: validation replaces the ledger and would discard records.
4. Active feature initialization waits for the full schema. After historical
   cleanup succeeds, the current feature may acquire its current policy using
   the original baseline. Current quest/cursor disable and normal-reset paths
   retain their ordinary ownership restoration; these are not pre-beta code.
5. Commit checkpoints only after successful steps. Stage data on isolated copies;
   failed callbacks cannot publish tentative preferences. Preserve durable native
   partial progress across readiness events and reload. Missing steps block.
   No preference-reset bridge is part of future schema upgrades by default.
6. Reuse the shared runner, status/error boundary and coalesced readiness events.
   Release migration subscriptions when complete; combat-end is armed only while
   protected cleanup is pending. Do not add polling or repeating timers.

## Validation

Use tests/SchemaMigrations.lua for ordered checkpoints, partial failure/reload,
combat/API readiness, no native access on rejected data and startup isolation.
QuestLootSparkles.lua and CursorWashedOut.lua cover current enable/disable/reset
restoration. Include complete historical ledgers, later external writes and
failure before feature policy initialization when adding a future step.
Run mise run check and git diff --check. Back up real SavedVariables before
native tests; mocks do not establish installed game behavior.
