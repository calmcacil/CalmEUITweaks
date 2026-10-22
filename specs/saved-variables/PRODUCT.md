# SavedVariables schema upgrades

## Summary

The 1.0 release establishes a Calm Forever saved-data lineage. Its first load
resets plugin preferences to opt-in defaults without discarding user-created data
or ownership records. Later upgrades preserve preferences unless a migration
explicitly changes them.

## Behavior

1. `CalmUITweaksDB.calm_forever = true` identifies the new lineage.
   `schemaVersion = 1` is its first completed schema. The marker and checkpoint
   are metadata, not preferences; normal preference reset preserves both.

2. Missing `calm_forever` identifies pre-1.0 data, not a current schema with a
   missing flag. Recognized legacy schema versions 0 through 4 and CVar
   checkpoints 0/1 are upgraded safely before conversion. Fresh installs use
   the same v1 baseline without an upgrade notice.

3. On conversion, every known preference returns to its default, including macro
   names. Every boolean preference is false: macros, bag arrows and all three
   bag scopes, quest sparkles, cursor fix, LFG labels, chat automation and four
   spacers. A feature only activates after explicit user action.

4. Conversion preserves actual game macros, account and character macro
   ownership, saved chat default, chat receipts, spacer geometry, unknown root
   keys and unknown fields inside live settings. Historical cleanup still deletes
   explicitly retired feature roots and invalid CVar ledger entries. Existing character layouts
   still seed missing account layouts on that character's first compatible load.
   Existing account layouts win. Offline characters are not claimed to be migrated.

5. Still-owned targeting, sparkle and cursor CVars are restored before conversion
   completes. Only validated recorded baselines are used; later external writes
   are preserved. No guessed defaults or unrecognized CVars are written.
   Native cleanup requires login and no combat. Missing APIs and failed writes
   retain unfinished records across reloads and character changes.

6. The lineage marker and v1 checkpoint are committed together only after cleanup
   and preference conversion succeed. Pending conversion does not initialize
   features, edit options or allow setters/reset. A failed data conversion does
   not commit tentative preference changes. Partial native restores remain
   durable because native side effects cannot be rolled back.

7. Once the marker is present and v1 is complete, reload, character switches,
   later events and normal reset do not repeat conversion. User choices made
   after conversion survive reload. New marked schemas run later ordered steps
   and checkpoint only successful steps; missing steps do not count as complete.

8. Non-table roots, false or malformed lineage markers, unsupported future
   schemas, missing marked checkpoints, conflicting legacy metadata, and
   unsupported character metadata are preserved and block startup before either
   store is changed. A marked v1 store is never interpreted as legacy schema 1.
   Character metadata still accepts absent/1 `version`; no separate character
   lineage counter is introduced.

9. Supported historical steps remain available and immutable for direct upgrades.
   Legacy CVar checkpoints do not replay completed targeting cleanup. Retired
   account roots and legacy account version markers are removed by their ordered
   steps. Retired character `spacers` and `spacerCorners` roots are removed only
   after the legacy spacer import; other character data remains.

10. Existing nonempty accounts receive one completion notice after login that
    identifies the Calm Forever v1 baseline and explains that preferences were
    reset. Fresh/current accounts stay silent. Later same-lineage upgrades use
    schema-version notices. Pending, failed and unsupported upgrades never
    announce success; reload and reset do not repeat notices.

11. Normal reset applies the same opt-in preference defaults while preserving
    metadata, user data, unknown fields and ownership. Still-owned active CVars
    restore through their existing feature paths. It does not delete macros,
    modify chat history or rewrite EUI profiles. Native spacer removal owns link
    cleanup; no separate EUI layout reset is performed. The slash command opens
    native EUI confirmation and reloads only after a successful confirmed reset.
    Cancel is inert; combat, active Unlock Mode, incomplete login and unavailable
    popup/reload APIs reject without resetting. Conditions are rechecked when
    confirming, and typed `reset confirm` cannot bypass the popup.

12. Options remain discoverable while blocked/pending, but editing is disabled
    with a native explanation. Shared status reports the reason. Startup resumes
    once when ready and releases migration subscriptions. Readiness retries use
    bounded events, not polling, repeating timers or update handlers.

13. Back up SavedVariables before conversion or downgrading. Older releases that
    do not recognize `calm_forever` cannot enforce downgrade safety. Version
    numbers in the old lineage must not be manually relabeled as new v1.

14. The 1.0 candidate is prepared and validated locally, then tested in game by
    the user. No push, release tag, public release or asset upload occurs before
    that testing and explicit release approval.
