# Supported SavedVariables Implementation

## Context

The approved boundary in [PRODUCT.md](PRODUCT.md) retires unmarked pre-beta data.
Baseline: commit 9e43f29. `core/Migrations.lua` has legacy steps 1..4, a schema-1
bridge, raw-store preflight, native cleanup descriptors, atomic data-step commits
and event-driven retries. `core/Settings.lua` still imports character spacers.
The 1.0.1 options adapter already supports confirmed discard and reload while
settings are blocked. Reuse it; do not add another recovery mechanism.

## Changes

- Remove `LEGACY_SCHEMA_VERSION`, `legacySchemaMigrations` and the schema-1
  bridge, including retired targeting definitions, gap conversion, retired-root
  pruning, bridge-only preference reset and its completion notice.
- Keep `SCHEMA_VERSION = 1` and an empty `schemaMigrations` table for future
  steps beginning at 2. A missing/empty account starts at baseline 1. Normalize
  fresh account/character candidates before publishing marker and checkpoint;
  no native reads, restoration or migration subscriptions are needed.
- Preflight both roots before mutation. Nil roots are allowed; non-table roots
  block. Nonempty accounts require the marker, bounded integer checkpoint and
  absence of account version/CVar counters. Character metadata remains absent/1
  version and no schema counter. Rejected data sets settingsError and is not
  exposed through ns.db/ns.charDB. Existing options recovery handles it.
- Remove legacy-versus-marked branches from the runner. Retain ordered future
  steps, staged data callbacks, cleanup descriptors, durable partial native
  restoration, status/errors, coalesced readiness retries and numeric notices.
  Do not add hypothetical upgrade entries or another scheduling abstraction.
- Remove character spacer import and retired-character-root deletion from
  NormalizeSettings. Continue filling known defaults, validating macro names
  and preserving live unknown/provider fields. Old character geometry stays
  inert and cannot refill missing account layouts after a confirmed discard.
- Keep core/CVars.lua and quest/cursor feature ownership logic unchanged.
  Historical conversion cleanup is removed; active ownership is still needed.
- Align SPEC.md, README.md, AGENTS.md and specs/cvar-migrations/TECH.md. Replace
  stale instructions requiring immutable pre-beta migrations with this supported
  baseline. Propose release 1.1.0 with a Release-As commit/PR trailer; Release
  Please owns version files. Publication is a separate action.

## Validation

1. Replace conversion fixtures with unsupported-save cases: unmarked schema0..4,
   version1/CVar0..1 combinations, enabled preferences and full old ledgers,
   partially converted/conflicting markers, malformed roots/checkpoints and
   future schemas. Assert both raw stores stay unchanged, no native reads/writes,
   no feature callbacks/notices, no retry subscriptions and rejected setters/reset.
2. Exercise fresh nil/empty roots, invalid opposite root, failed fresh
   normalization, current enabled choices, ownership/chat/unknown fields and
   inert character layouts. Verify reload, late addon load, one-time startup,
   default-off reset and current quest/cursor restoration.
3. Retain meaningful future-schema coverage: copy/commit failure, missing step,
   ordered checkpoints across reload, data rename before defaults, combat/API
   readiness, partial CVar cleanup, external writes and recovery callbacks.
4. Update CoreOptions and TOC smoke fixtures to explicitly identify current
   data. Keep dedicated raw legacy fixtures unmarked. Test blocked recovery
   Cancel/confirm and reloading fresh with settings usable and persistent.
5. Run mise trust, mise install, mise run check and git diff --check. Review the
   diff for unintended deletion of active ownership helpers or current data.
   Native verification remains: back up saves, load old/current/fresh data,
   switch pages/search, cancel and confirm recovery, reload, use an alternate
   character, and check current quest/cursor enable-disable/combat restoration.
