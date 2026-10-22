# SavedVariables schema implementation

## Context

[PRODUCT.md](PRODUCT.md) defines the approved preference-preserving reset choice.
At baseline c7be7b8, [Migrations](../../core/Migrations.lua) runs legacy steps
1..4; [Settings](../../core/Settings.lua) fills defaults afterward and normal
reset replaces known subtrees. [Lifecycle](../../core/Lifecycle.lua) already
blocks features until settings are ready. Reuse that runner, event driver and
barrier rather than adding another lifecycle.

## Proposed changes

### Explicit lineages and bridge

Keep the shipped legacy entries unchanged in `ns.legacySchemaMigrations`, with
fixed `ns.LEGACY_SCHEMA_VERSION = 4`. Declare `ns.SCHEMA_VERSION = 1` for the new
lineage and a separate `ns.schemaMigrations` table in the same module. The new
lineage is identified by literal `calm_forever = true`, not by a release number.

Preflight both raw globals before mutating or reading native state. Accept nil
roots, reject other non-table roots. Missing marker uses the existing legacy
validator (schema0..4, CVar0/1, account version absent/1 and conflict checks).
Present nontrue markers block. Marked stores require integer schemaVersion1..target
and no legacy account version/CVar metadata; true+missing/0/future/malformed
checkpoint blocks. Character metadata remains absent/1 version and no schemaVersion.
Keep marker and checkpoint outside preference defaults.

For unmarked data, run outstanding legacy entries to4, checkpointing each as
before. Then run the baseline step. It restores full historical quest graphics
and HardwareCursor definitions in disabled mode through the existing persistent
ledger helper, before staging the preference reset. No native read is needed
for empty ledgers. Register readiness/world/CVar/combat events only while work
is pending; own writes do not queue recursion. Failure leaves marker absent and
legacy checkpoint durable, so reload resumes without guessing prior values.

The baseline entry supports cleanup descriptors followed by a pure-data
callback. Current descriptors are immutable historical snapshots, not aliases to
future feature policies. Reuse existing CVar-step execution and atomic copy/commit
for data steps. A failure or exception does not stamp completion. The final
account commit includes reset preferences, marker and schema1 together. Future
marked steps remain ordered and append-only, with no ordinary bridge replay.

### Preference reset and normalization

Add one `ns.ResetPreferences(db)` helper that recursively assigns only known
scalar defaults, repairing malformed known tables without replacing valid ones.
Empty defaults such as spacerLayouts do not erase user contents. This preserves
nested unknown/provider fields, ownership, chat.default, geometry and restoration
ledgers. Reuse it for baseline conversion and normal ResetSettings; remove the
old save-and-reinsert whitelist once redundant. This helper has no lifecycle,
frames or native writes. Every boolean default, including bag scopes, is false.

Stage the baseline account copy before commit; do not invoke public ResetSettings
from a migration. Normal settings initialization retains lazy character spacer
import and retired character cleanup. Character data is not reset or certified
by the account marker. Account/root identity and existing shared stores remain.

### Notifications and downgrade safety

Capture starting lineage/version and whether raw account data was nonempty.
Converted existing accounts get one post-login notice naming calm_forever v1 and
that preferences reset. Fresh and marked-current stores are silent; future marked
upgrades retain numeric version notices. Do not describe old4->new1 as an ordinary
numeric upgrade. The in-memory notice cannot guarantee delivery across a crash.
Older binaries ignore the marker; document backup/restore rather than claiming
retroactive downgrade protection. External deletion of the marker can replay
conversion and is not a supported normal operation.

## Testing and validation

- Product1..3,7: fresh/empty, legacy CVar0/1/schema0..4 versus marked1; all boolean
  defaults and reset leaves false; preserved choices after marked reload; marker
  and checkpoint are atomic and excluded from reset/defaults.
- Product4,9,11: unknown root/live nested fields, account/character/provider macro
  ownership, actual macro bodies, chat default/receipts, account geometry and lazy
  character imports; original root identity. Explicitly retired roots remain the
  preservation exception. Native macro/chat writes never occur on conversion.
- Product5..8: gathering plus five quest CVars and cursor restore; login, combat,
  missing APIs/values, setter rejection/throw/readback failure, external values,
  partial progress/reload/alternate-character, injected data-step failures.
- Product8: false/string/table marker, marked nil/0/future/malformed checkpoints,
  legacy metadata conflicts and unsupported opposite root; no mutations/reads or
  feature callbacks, options editing or successful reset while blocked.
- Product6,10,12: integration through real Lifecycle/Settings, one startup, pending
  options disabled then cached recovery, notice timing/silence, released events.
- Preserve tests that exercise historical entries instead of blindly renumbering
  old4 assertions to1. Mark current-behavior fixtures explicitly as calm_forever1.
- Slash reset uses the native EUI popup via the options adapter. CoreOptions
  tests cancellation/no early mutation, single confirmed reset-before-reload,
  callback readiness/combat/Unlock Mode rechecks and unavailable APIs or failures.
  Direct `ResetSettings` stays a non-reloading preference operation for callers.
- Run focused Lua regressions, full `mise run check`, `git diff --check`, independent
  read-only safety review and local archive validation using check-package.sh.
  Prove high-value tests fail when baseline reset/checkpoint or opt-in defaults
  are temporarily broken, then restore and rerun.
- Product14: user backs up real SavedVariables and tests fresh install, legacy
  conversion, pending combat/API cleanup, reload/alt and each opt-in feature.
  Include cursor response/restore, native bag overlay layering, dividers/search,
  all macro providers and spacer Save/Discard. Mocks cannot prove native UI/CVars.

## Parallelization

The orchestrator owns coupled settings, migrations and fixture adaptation in the
main checkout; read-only reviewers independently inspect the same files without
edits. Independent implementation workers use isolated worktrees and bounded file
ownership if needed. Integrate before final combined checks. No agent pushes,
creates PRs, tags or publishes before user testing and release approval. Avoid
extra branches/worktrees for read-only review. Recovery state and task contracts
live under ignored .release/1.0-preparation/SAGA.md.
