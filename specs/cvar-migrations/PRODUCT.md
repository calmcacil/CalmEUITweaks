# CVar cleanup within supported schema upgrades

## Summary

CVar cleanup is one kind of future SavedVariables upgrade governed by the
[account schema contract](../saved-variables/PRODUCT.md). Completed Calm Forever
schema 1 is the oldest supported baseline. Pre-beta native restoration is
retired; unsupported saves stay preserved until confirmed recovery.

## Behavior

1. Future same-lineage CVar changes use ordered schema upgrades. There is no
   legacy CVar counter, gathering cleanup or preference-reset bridge.
2. Cleanup restores only recognized names and recorded applied values from its
   complete historical policy. Later external writes are preserved. Missing
   records never cause guessed defaults or reconstructed baselines.
3. Native writes wait for login and combat end. Empty cleanup can complete before
   login without native reads. Missing APIs or values leave work pending.
4. Partial failure retains unfinished ownership and the old schema checkpoint.
   Reload resumes without undoing native restoration that already succeeded.
5. All feature initialization waits for the complete account schema, including
   data-only steps. Current feature policy cannot erase historical ownership
   before its future upgrade cleanup finishes.
6. Normal preference reset preserves metadata, saved content, unknown fields and
   ownership. Active quest/cursor features keep their enable/disable/reset
   restoration behavior. Removing pre-beta migration does not remove these paths.
7. Invalid, unmarked nonempty or unsupported stores cause no native access or
   mutation. Confirmed recovery discards their ledgers without native restoration;
   Cancel retains them for a compatible build or future fix. Supported current
   reloads preserve preferences. Fresh/current startup is silent; future completed
   upgrades report schema versions through the shared runner.
