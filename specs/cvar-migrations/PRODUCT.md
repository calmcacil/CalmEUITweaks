# CVar cleanup within schema migrations

## Summary

CVar cleanup is one kind of SavedVariables migration, governed by the
[account schema contract](../saved-variables/PRODUCT.md). The old `cvarVersion`
0/1 checkpoints are compatibility inputs only; `schemaVersion` is authoritative.

## Behavior

1. Historical gathering cleanup remains step 1. Accounts already at shipped
   `cvarVersion = 1` adopt that completed step and do not repeat its native writes.
   General schema adoption is step 2, which removes recognized obsolete account
   metadata. Future CVar changes append steps to the same account migration list.
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
   Ready-state reset preserves the schema checkpoint and native ownership records.
7. Invalid or unknown metadata preserves both stores and performs no CVar writes.
   Notices, startup, retry subscriptions and downgrade behavior follow the general
   SavedVariables contract rather than a separate CVar counter or notifier.
