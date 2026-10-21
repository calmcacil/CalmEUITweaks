# SavedVariables schema implementation

## Context

[PRODUCT.md](PRODUCT.md) is the behavior contract. The inspected baseline is
`428b3f6aaf565cd0c786f95757050c6981b00b9e` (0.6.1).
[Settings](../../core/Settings.lua) currently fills defaults before the CVar
runner, and its old version validator repairs malformed markers but does not
reject valid future integers. The CVar runner and quest-only readiness gate must
be replaced, not retained as a second migration system.

## Proposed changes

### One runner and two concrete steps

Use [core/Migrations.lua](../../core/Migrations.lua), registered as `migrations`
through the existing module registry, in place of `LegacyCVars.lua`. Declare
`ns.SCHEMA_VERSION = 2` and a contiguous `ns.schemaMigrations` table. Each entry is
either a historical CVar cleanup descriptor (`settingsKey`, full old `values`,
optional `retired`) or a pure-data `migrate(candidate)` function returning literal
true on verified completion. Never silently treat a missing step as complete.

- Step 1 preserves the old gathering names, applied values and restoration rules.
- Step 2 removes recognized account `version`/`cvarVersion`, and performs the
  existing shared `anchorGap.pixels` migration before defaults obscure absence.

The generic runner checkpoints after each successful entry. Pure-data callbacks
receive a temporary deep copy using the existing copy helper; on true completion,
commit its contents into the original root and write the next checkpoint. A false
return or exception discards that candidate. This is not a parallel settings store
for features. CVar steps operate on the persistent ledger and reuse
`ApplyOwnedCVars(..., false)` because native side effects cannot be rolled back.

### Raw metadata preflight

Before mutating either root, accept nil as a fresh root and reject other non-table
roots. Validate canonical account `schemaVersion` as a finite nonnegative integer
no higher than the declared target. Without it, recognize only legacy `cvarVersion`
0/1 or absence (0). Validate any legacy CVar field independently, even when a
canonical checkpoint is present; a legacy checkpoint ahead of canonical is a
conflict. Legacy account `version` is absent or 1 only, never an adoption source.
Character metadata accepts absent/1 `version`; no character `schemaVersion` is
recognized yet. Invalid/future metadata remains untouched. Keep all schema
markers out of defaults and out of coercing version-normalization helpers.

### Bootstrap sequencing

`InitializeSettings` validates and migrates raw globals before binding `ns.db` and
`ns.charDB` or filling defaults. It returns false while pending/blocked. Known
normalization and per-character spacer import run only after success.

The existing lifecycle gains `ns.ResumeStartup()` and separate saved-data-loaded
and logged-in facts. It retries initialization, invokes feature Initialize once
when data is ready, then invokes OnLogin and ApplySettings once after login.
Unrelated addon loads are forwarded only after initialization. No recursive
completion callback is needed: the outer resume call continues startup itself.

Migration readiness events request the migration module through the existing
coalescer. `RequestApply` permits that one key while `settingsPending` even when
features are not ready, and rechecks before delivery. The migration module's
ApplySettings only asks the lifecycle to resume pending startup. It has no
feature Initialize callback that could restart or recapture bootstrap state.

CVar work waits for login/combat/API readiness. Pure data and empty cleanup steps
can finish before login. Permanent metadata blocks unsubscribe; transient failures
use world/variable/CVar/combat notifications as relevant, without timers polling.

### Preferences, options and notifications

Expose one `SavedVariablesReady()` predicate/reason for feature/options consumers.
Replace the quest-only CVar readiness check. `GetSettings` may serve existing
defaults before initialization, but mutations and reset return false/reason.
Commands must honor reset rejection. Native options controls compose their existing
disabled conditions with saved-data readiness and show its reason.

Capture the pre-default account's nonempty/fresh state and effective starting
version once. Hold a completion notice until login and emit through `ns.Print`
once, after successful full startup. Checkpoint persistence prevents replay on
reload; the notice reports the current session's actual starting checkpoint.
A 0.6.x account at `cvarVersion=1` becomes `schemaVersion=2` without rerunning step1.

### Adding future migrations

Append the next numbered entry and raise the target together. Data callbacks must
be pure, deterministic and safe to retry; no frames, hooks, CVar writes or retained
candidate references. Stage destination values before deleting obsolete source
fields. Do not mutate schema counters inside the callback. CVar descriptors must
contain the FULL historical owned definition, not a subset that would lose other
records during validation. Keep shipped steps immutable. Add character versioning
separately when a real character schema change exists; an account checkpoint
cannot certify unloaded characters.

## Testing and validation

- Upgrade missing/0/1 CVar metadata, schema0/1/current, and fresh/empty databases;
  prove no old targeting writes replay for a shipped cvarVersion1 account.
- Exercise raw gap conversion before defaults, unknown fields, false preferences,
  malformed nested fields, and existing per-character spacer import (product3,9,13).
- Block malformed/future/conflicting account and character metadata before any
  mutation, normalization, feature callback, setter or reset (product1,2,10,11).
- Inject a pure-data failure after candidate mutation, then retry/reload; prove
  atomic data commit, ordered checkpoints and no later steps running early.
- Inject CVar rejection/readback failure, combat and missing APIs. Preserve partial
  cleanup, checkpoint and no-write-before-login guarantees (product4-7).
- Integrate actual Lifecycle/Settings with dummy features and quest module: pending
  upgrades defer all feature callbacks; readiness resumes each once, late addon
  startup works, and queued stale callbacks are harmless (product6,12).
- Capture chat: existing1->2 and pre-versioned0->2, fresh silence, failure silence,
  partial retry, no reload/reset repetitions (product8).
- Run `mise run check`, `git diff --check`, and a read-only safety review. In game,
  back up SavedVariables, upgrade 0.6.1, inspect the notice and status, reload,
  and exercise a combat-deferred upgrade. Mocks cannot prove native CVar effects.

## Parallelization

Keep runtime implementation sequential because runner, lifecycle and settings
gates are coupled. A local regression author may own only
`tests/SchemaMigrations.lua` in the same checkout after this contract is fixed;
the runtime owner adapts existing fixtures and performs combined validation.
A local read-only safety reviewer can inspect the completed code without editing.
No additional branch, worktree, PR or release is created by these delegations.
