# Authoring CVar schema steps

## Context

[The SavedVariables technical spec](../saved-variables/TECH.md) owns the runner,
checkpoint, lifecycle and failure contract. This guide describes the native-CVar
step type. The former `LegacyCVars.lua` runner is replaced by
[core/Migrations.lua](../../core/Migrations.lua); do not add a second CVar version
counter, event driver or notification mechanism.

## Proposed changes and authoring rules

1. Append an entry to `ns.schemaMigrations` and raise `ns.SCHEMA_VERSION` together.
   Preserve every shipped historical step and its ordinal, including gathering
   cleanup step 1.
2. Set `settingsKey` to the account subtree with a `restore` ledger, and `values`
   to its FULL previous CVar definition using the existing helper entry format.
   Set `retired = true` only when that entire subtree can be removed.
3. The runner validates this historical ledger and uses
   `ApplyOwnedCVars(settings, values, false)` after login/outside combat. It does
   not replace ownership with the desired values from the new feature policy.
4. For active features, preserve preferences while restoring old ownership. After
   the schema becomes ready, the feature validates its new definition and applies
   the latest enabled preference. It must use `SavedVariablesReady()` rather than
   the removed CVar-only gate.
5. Do not pass only a subset of old names to the ledger validator: it replaces the
   ledger, which would silently discard other records. Restore the complete prior
   policy, then let the active feature acquire its new desired values.
6. Do not modify schema checkpoints from feature initialization or settings reset.
   Completion belongs to the shared runner. A false readiness result or thrown
   setter failure is not completion.

## Testing and validation

[SchemaMigrations tests](../../tests/SchemaMigrations.lua) cover retirement,
known-version adoption, current/future metadata, partial failures, combat/API
readiness, active-policy upgrades and the global startup barrier.
[QuestLootSparkles tests](../../tests/QuestLootSparkles.lua) cover ordinary owned
writes and disable/reset restoration. Extend both when changing desired values.

Run `mise run check` and `git diff --check`; test the upgrade in game with a
SavedVariables backup. Native CVar side effects are not proven by mocked tests.

## Parallelization

CVar step code and its historical ledger tests are tightly coupled to the schema
runner. Keep edits coordinated with its owner; independent read-only safety review
is useful and requires no additional worktree or release action.
