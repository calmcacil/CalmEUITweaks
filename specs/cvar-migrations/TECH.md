# Authoring CVar schema steps

## Context

[The SavedVariables technical spec](../saved-variables/TECH.md) owns the runner,
checkpoint, lifecycle and failure contract. This guide describes the native-CVar
step type. The former `LegacyCVars.lua` runner is replaced by
[core/Migrations.lua](../../core/Migrations.lua); do not add a second CVar version
counter, event driver or notification mechanism.

## Proposed changes and authoring rules

1. New marked-lineage steps append to `ns.schemaMigrations`; raise
   `ns.SCHEMA_VERSION` with the entry. Preserve immutable shipped steps 1..4 in
   `ns.legacySchemaMigrations` with `ns.LEGACY_SCHEMA_VERSION = 4`, including
   gathering cleanup step 1. Missing marker selects that legacy list before the
   Calm Forever v1 bridge; never renumber old checkpoints as new schema 1.
2. Set `settingsKey` to the account subtree with a `restore` ledger, and `values`
   to its FULL previous CVar definition using the existing helper entry format.
   Set `retired = true` only when that entire subtree can be removed.
3. The runner validates this historical ledger and uses
   `ApplyOwnedCVars(settings, values, false)` after login/outside combat. It does
   not replace ownership with the desired values from the new feature policy.
4. Ordinary marked-lineage policy upgrades preserve preferences while restoring
   old ownership; features validate/apply their latest policy only after
   `SavedVariablesReady()`. The one-time v1 bridge is the explicit exception:
   restore all five historical quest graphics names and `HardwareCursor` before
   staging the known preference-leaf reset. Preserve user data, unknown live nested
   fields and account/character ownership. Commit reset, marker and schema 1
   atomically, without calling public reset from a migration.
5. Do not pass only a subset of old names to the ledger validator: it replaces the
   ledger, which would silently discard other records. Restore the complete prior
   policy, then let the active feature acquire its new desired values.
6. Do not modify schema checkpoints from feature initialization or settings reset.
   Completion belongs to the shared runner. A false readiness result or thrown
   setter failure is not completion. Preflight both raw stores before native reads
   or mutation; durable partial native restores retry through login/combat/API
   readiness and reload, without committing tentative preference changes.

## Testing and validation

[SchemaMigrations tests](../../tests/SchemaMigrations.lua) cover retirement,
known-version adoption, current/future metadata, partial failures, combat/API
readiness, active-policy upgrades and the global startup barrier.
[QuestLootSparkles tests](../../tests/QuestLootSparkles.lua) and
[CursorWashedOut tests](../../tests/CursorWashedOut.lua) cover ordinary owned writes
and disable/reset restoration. Extend the relevant suites when changing policy;
cover complete historical ledgers, external writes, partial progress/reload,
atomic baseline commit, marked v1 preservation and malformed-store fail-closed
behavior. Follow the [in-game checklist](../../SPEC.md#in-game-candidate-checklist).

Run `mise run check` and `git diff --check`; test the upgrade in game with a
SavedVariables backup. Native CVar side effects are not proven by mocked tests.

## Parallelization

CVar step code and its historical ledger tests are tightly coupled to the schema
runner. Keep edits coordinated with its owner; independent read-only safety review
is useful and requires no additional worktree or release action.
