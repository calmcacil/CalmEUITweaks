# CVar cleanup within schema migrations

## Summary

CVar cleanup is one kind of SavedVariables migration, governed by the
[account schema contract](../saved-variables/PRODUCT.md). Literal
`calm_forever = true` identifies the current lineage; `schemaVersion = 1` is its
baseline. An absent marker selects legacy schema 0..4/CVar 0..1 validation and
cleanup, not the new schema 1.

## Behavior

1. Historical gathering cleanup remains legacy step 1. Accounts already at
   shipped `cvarVersion = 1` adopt that completed step without replaying writes.
   Legacy schema adoption is step 2; steps 3/4 remain available and immutable.
   After legacy completion, the v1 bridge restores full historical quest graphics
   and cursor ownership before resetting known preference leaves (names included,
   all booleans/scopes false) and committing marker/checkpoint together. Future
   marked-lineage CVar changes append ordered steps to the shared runner.
2. A CVar step restores only recognized names and recorded applied values from
   its full historical definition. Live values different from the last recorded
   write remain external; cleanup never guesses defaults or reconstructs lost data.
3. Native writes wait for login and the end of combat. Empty cleanup steps may
   finish before login because they perform no native reads or writes. Missing
   APIs or values defer cleanup without completing the step.
4. Partial failures retain unresolved ownership and do not advance the checkpoint.
   Reload retries the unfinished step without rewriting values already restored.
5. Current feature validation and initialization wait for all account schema
   migrations, not only CVar steps. This supersedes the former CVar-only barrier;
   features do not use partially normalized saved data.
6. Settings edits and reset are rejected while migrations are pending or blocked.
   Ready-state reset preserves lineage/checkpoint metadata, user data, unknown
   live nested/provider fields and ownership; active features restore owned CVars.
7. Preflight rejects malformed roots, markers, versions or conflicting metadata
   before either store changes or native state is read. Marked v1 reloads preserve
   preferences without repeating conversion. Conversion notices identify the
   lineage/reset; fresh/current stores stay silent. Startup, bounded retry events
   and downgrade behavior follow the general SavedVariables contract, not a
   separate CVar counter or notifier.
