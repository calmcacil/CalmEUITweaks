# Versioned CVar migrations

## Summary

CVar changes must have an explicit, repeatable upgrade path that preserves users'
previous settings. An account-wide `cvarVersion` records completed cleanup, not
just which addon release has run.

## Scope

This contract covers addon-owned console settings and their restoration records.
It does not version EUI profiles, all addon preferences, or the game client's CVar
catalog. It adds no settings page, polling, forced default reset, or gathering
sparkle behavior.

## Behavior

1. `cvarVersion` is the last completed CVar migration. It is independent of the
   addon release and general settings versions. A missing value means version 0;
   zero is valid. Only nonnegative integer versions supported by this addon are
   accepted.

2. Upgrades run every outstanding migration in numerical order. A successful
   step advances the saved version immediately. An incomplete or failed step
   does not advance it, and later steps do not run early. Installing several
   releases at once must not skip intermediate cleanup.

3. Version 1 retires gathering sparkle targeting settings. It restores only
   values backed by valid ownership records from that feature, then removes its
   obsolete saved settings. It never enables gathering effects or substitutes
   guessed targeting defaults.

4. A future change to an active feature's CVar names or desired values first
   restores the previous version's owned settings. Only after all cleanup is
   complete may the current feature apply its new definition. The latest enabled
   preference is respected; finishing cleanup must not re-enable a disabled feature.

5. A recorded value is still owned only while the live value matches the addon
   write recorded for it. Cleanup restores its saved baseline. A different live
   value is preserved as an external change. No attempt is made to infer ownership
   or reconstruct a missing or already-corrupted baseline.

6. Recognized historical CVar names and applied values bound each migration.
   Malformed records and records outside that historical definition cannot cause
   writes to arbitrary console settings. Historical definitions remain available
   for users upgrading from older versions.

7. CVar writes occur only after login and outside combat. Missing console APIs
   or required values leave cleanup pending without advancing its version.
   Steps with no valid owned records may complete after login even in combat or
   without console APIs, because they require no CVar writes.

8. Rejected, throwing, or unverified restoration writes do not mark the step
   complete. Remaining ownership survives reloads and character changes. Work
   already completed is not replayed after retry or reload.

9. The completion version is shared across characters. Reopening options,
   entering the world again, or reloading an already-upgraded account does not
   repeat completed migrations or acquire new ownership for retired features.

10. Preference reset preserves the migration checkpoint and unfinished ownership
    records. Reset may disable features normally, but it cannot cancel required
    cleanup, revive retired preferences, or make completed migrations run again.

11. A malformed version or a version newer than the running addon blocks CVar
    migrations and active CVar writes. Its raw version and restoration records
    remain unchanged, including through reset. Status explains the problem;
    the addon does not silently downgrade, repair, or erase unknown data.

12. Until migrations finish, quest-loot CVar application and restoration wait
    behind the migration barrier. This includes waiting for unrelated retired
    targeting cleanup: safety takes precedence over partially applying the new
    CVar policy. Macro, chat, bag, anchor, and other unrelated features continue.

13. Existing saved data announces a completed upgrade once in chat, naming the
    previous and new versions (for example, `savedvarsdb updated from "0" to "1"`).
    Fresh installs and accounts already at the current version stay silent, and
    later logins or repeated lifecycle events do not repeat the message.

14. Existing status reporting distinguishes completed, pending, combat-deferred,
    failed, and unsupported-version states. Cleanup uses bounded lifecycle or
    relevant CVar notifications, never polling or repeating timers. Completed
    migrations and unsupported-version states have no migration event subscriptions.

15. A feature's current-definition validation cannot discard an old restoration
    record before its historical migration has had a chance to process it. After
    migrations complete, current settings apply without repeated writes when
    their live values already match.
