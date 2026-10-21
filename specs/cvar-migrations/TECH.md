# CVar migration implementation

## Context

[PRODUCT.md](PRODUCT.md) defines the behavior contract. Research used commit
`5bcaf10393abc83893219860118641bcf79a60a4` plus the current uncommitted gathering
removal and review fixes. The cleanup module does not exist in that base commit,
so working-tree links below identify the actual implementation surface.

- [core/LegacyCVars.lua](../../core/LegacyCVars.lua) owns retired targeting cleanup.
- [core/CVars.lua](../../core/CVars.lua) validates ownership and restores still-owned
  values; its initializer replaces the supplied ledger with validated records.
- [core/Lifecycle.lua](../../core/Lifecycle.lua) initializes all modules before
  applying any at login. It provides coalesced `RequestApply` callbacks.
- [functions/QuestLootSparkles.lua](../../functions/QuestLootSparkles.lua) is the
  remaining active CVar consumer.
- [core/Settings.lua](../../core/Settings.lua) fills defaults and resets preferences
  while preserving the quest restoration ledger.

## Proposed changes

### Persistent checkpoint and definitions

Use `CalmUITweaksDB.cvarVersion` as the last completed migration. Do not add it to
`ns.defaults` or pass it through the general settings version normalizer. Missing
means 0; malformed, fractional, negative, nonfinite, and future values fail closed.
Current-version data is not prepared or sanitized by the migration module.

Keep a dense, append-only `ns.cvarMigrations` definition list in the existing
cleanup module. Each numbered step contains:

- `settingsKey`: the account feature settings subtree containing `restore`.
- `values`: the COMPLETE historical CVar names and allowed applied values for
  that subtree, using the existing CVar helper's entry format.
- `retired`: true only when the entire obsolete subtree can be removed.

The target version is the number of contiguous steps. Step 1 describes the
removed gathering feature, including both historical nameplate-gating values.
This is an internal definition list, not a new module or callback registry.

### Preparation and execution

1. Validate the raw checkpoint before touching any ledger. Unsupported versions
   report status and leave both checkpoint and feature records unchanged.
2. Prepare only the next step. Validate records against that step's historical
   allowlist, not the active feature's latest values. Retired subtrees retain only
   their validated ledger; active subtrees retain all current preferences.
3. Initialization may prepare saved data but performs no CVar writes and does not
   advance the checkpoint. The existing login lifecycle invokes execution.
4. Empty steps complete without requiring native CVar APIs or leaving events.
   Otherwise arm existing readiness/CVar events, defer in combat, and restore
   with `ApplyOwnedCVars(settings, historicalValues, false)`.
5. A false readiness result or thrown failure leaves the checkpoint unchanged.
   Retain the remaining ledger for retry. The shared module boundary reports
   errors; do not equate a successful `pcall` with completed migration work.
6. On success, remove a retired subtree and persist that step's number. Prepare
   and execute the next step. Resolve the active settings subtree from `ns.db`
   on each attempt: reset replaces tables and must not resurrect stale preferences.
7. Once every step completes, release migration subscriptions and request quest
   settings application through existing coalescing. Notify only on advancement
   to readiness, not on every later application. A duplicate idempotent startup
   application is acceptable; an extra scheduler to avoid it is not.

No additional persisted in-progress flag is necessary. The checkpoint plus each
ledger describes unfinished work. Completed restore records cannot be reacquired
by cleanup, which always uses disabled/restoration mode.

### Active CVar barrier

Expose `ns.CVarMigrationsReady()` returning a boolean and, when blocked, a status
reason. Quest application checks it before subscriptions, ledger sanitization,
`next(restore)`, or any CVar reads/writes. Remove eager quest ledger validation
from module initialization; validate its current definition once after the gate
opens. A pending or unsupported migration leaves other feature modules untouched.

Preference reset keeps the raw checkpoint because it is outside defaults, and
continues preserving quest `restore`. A prepared migration must never overwrite
the latest enabled preference with a table cached before reset.

### Adding a future CVar change

1. Append the next integer step; never rewrite, reorder, renumber, or delete a
   shipped step. Record the feature's FULL prior CVar definition in `values`.
2. For an active feature, leave `retired` false/absent. Restore the old policy
   before applying the new desired values. For whole-feature removal, use true.
3. Update the active feature's desired values separately. All active CVar writers
   must honor the migration barrier, and completion must request their application.
4. Do not use a subset of retired names against an entire active ledger: the
   validation helper replaces that ledger and would drop other owned records.
   This design deliberately restores the full previous policy before reapplying.
5. Do not set `cvarVersion` in defaults, release tooling, or a new feature's
   initialization. Only verified step completion advances it.
6. Add regression coverage for upgrade from each supported older checkpoint,
   partial failure/reload, later external writes, and the latest feature preference.
   Update both specs and the main behavior contract in the same change.

## Testing and validation

Extend [tests/LegacyCVars.lua](../../tests/LegacyCVars.lua) and
[tests/QuestLootSparkles.lua](../../tests/QuestLootSparkles.lua), using existing
mocked lifecycle/CVar fixtures rather than a separate runtime:

| Product invariants | Probe |
| --- | --- |
| 1, 2, 9 | Missing/0/current checkpoints; fresh empty cleanup; no replay on reload. |
| 2, 7, 8 | Two ordered steps; second-step rejection preserves the first checkpoint; reload resumes remaining work. |
| 3, 5, 6 | Existing gathering cleanup tests; external values, malformed records, both old gating modes. |
| 4, 10, 12, 14 | Integrated migration plus enabled quest lifecycle; retain old quest names until historical cleanup; reset/disable during pending work respects latest preference. |
| 7, 13 | Combat and unavailable APIs; empty migration still completes without writes; no polling or idle subscriptions. |
| 11 | String, boolean, negative, fractional, NaN, infinite and future versions: no writes or ledger changes through initialization/login/reset. |

Tests may append a synthetic step to the internal definition list before module
initialization to exercise multi-step behavior without shipping a fictitious
migration. Preserve the existing red-before-fix evidence and run the full
`mise run check` suite after implementation; also inspect `git diff --check`.

In game, back up SavedVariables, upgrade an account with outstanding gathering
records, confirm status/checkpoint completion, reload, and verify quest sparkles
and unrelated features. Exercise combat deferral and preference reset while work
is pending. Native CVar side effects cannot be established by mocked tests.

## Parallelization

Implementation stays sequential in the current checkout because checkpoint,
ledger preparation, quest gating and fixture changes are tightly coupled. A
read-only local design/safety review can run independently; it owns no files and
creates no branch or PR. The implementing agent owns final validation and any
future user-authorized commit.
