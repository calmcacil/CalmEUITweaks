# SavedVariables schema upgrades

## Summary

The account database stores the last completed schema migration. When the running
addon requires a higher version, it upgrades saved data in order before features
use it, preserves user data on failure, and announces a completed upgrade once.

## Scope

This contract replaces CVar-only versioning. It covers the account database,
startup safety, cleanup and notifications. It does not version addon releases or
EUI profiles. Character data keeps its existing supported format; a separate
character migration counter is deferred until a character schema change needs it.

## Behavior

1. `CalmUITweaksDB.schemaVersion` records the last completed account migration.
   The code declares a target version; the current target is 4, the 1.0 baseline.
   Missing means 0 for pre-versioned data; equal versions require no migration,
   lower versions require ordered steps, and newer, malformed or conflicting
   versions block use without repair or deletion.

2. Shipped `cvarVersion` values 0 and 1 are recognized only when adopting the old
   format. A missing `schemaVersion` adopts that completed checkpoint, not the
   release number or legacy `version` field. Unknown CVar versions are not mapped
   to similarly numbered schema versions. A known canonical schema takes precedence
   over an equal/older recognized legacy checkpoint.

3. Schema step 1 retains the shipped gathering CVar cleanup semantics. Step 2
   adopts general schema versioning, removes the recognized obsolete account
   `version` and `cvarVersion` fields, and migrates the old shared anchor gap into
   missing side preferences. Existing side preferences take precedence.
   Step 3 adds the default-off cursor fix preference without native CVar writes,
   preserving any existing cursor fix subtree. Step 4 is the 1.0 cleanup: it
   removes a defined set of recognized retired account roots (`gatheringSparkles`,
   `whatsTraining`, `anchorGap`, `spacerCorners` and legacy version markers).
   Unrecognized keys are preserved, including macro-provider settings and future
   preferences. It also drops subtrees owned by earlier retired-setting steps.

4. Every outstanding step runs in order. Its checkpoint advances only on verified
   success. Failures stop the chain; later steps never run early. Reload resumes
   at the last completed checkpoint, including upgrades that skip several releases.

5. Migrations receive raw saved data before default filling and field repair.
   Data-only steps and empty cleanup steps may complete at the addon's data-load
   event. Native CVar writes require login and no combat. Temporary readiness
   failures use bounded existing events, never polling or repeating timers.

6. Until migration and normalization complete, features are not initialized or
   applied and do not receive lifecycle callbacks. This intentionally replaces
   the previous CVar-only barrier: pending cleanup pauses the whole addon rather
   than letting features use partially upgraded data. Startup resumes once, including
   the once-only login callbacks, when the schema becomes ready.

7. A data-step failure does not commit its tentative changes. CVar cleanup can
   complete partially; it retains unresolved restoration records for retry.
   Cleanup never restores guessed defaults and never writes an unrecognized CVar.
   A live value different from the recorded addon write is preserved as external.

8. Fresh installs initialize without an upgrade announcement. Existing nonempty
   saved data announces successful completion once after login, for example
   `savedvarsdb updated from "1" to "4"`. The versions are schema versions, not
   addon releases. Repeated events, reset and reload do not repeat the notice.
   Failed, pending and unsupported upgrades do not announce success.

9. Recognized data keeps its enabled/disabled choices, unknown keys, chat default,
   spacer geometry, macro ownership and character receipts unless an explicit
   migration changes that field. Schema step 4 removes only the listed retired
   roots; it does not remove unrecognized keys. Defaults are applied only after
   migration. Nested known fields can be repaired according to their existing
   contracts.

10. A non-table saved root other than a missing root is preserved and blocked,
    not silently replaced. Unknown/malformed account schema metadata and unsupported
    character metadata are checked before either store is changed. Character
    `version` 1 or absence is supported; a character schema from newer code blocks
    startup. No offline character is claimed to have been migrated.

11. Reset while ready restores only preferences, preserving schema checkpoint,
    chat default, spacer geometry and ownership records. Reset and setting changes
    while an upgrade is pending or blocked are explicitly rejected without changing
    raw data. They never report a successful reset when none occurred.

12. Options remain discoverable but editing is disabled while saved data is not
    ready, with a native disabled-state explanation. Status identifies pending,
    failed, unsupported and completed upgrades. Unknown versions have no retry
    subscriptions; migration events are released on completion.

13. Existing per-character spacer import remains lazy: each character supplies
    missing account layouts on its own first compatible load, never overwriting
    established account geometry. After the import, initialization removes the
    retired `spacers` and `spacerCorners` roots; other character keys, including
    macro-provider ownership, remain. Current character ownership records stay local.

14. Historical steps remain append-only and available for direct upgrades from
    old releases. Changing a desired CVar policy first restores the full previous
    owned definition, then lets the current feature acquire its new values.
    Downgrade protection applies to schema-aware builds; older shipped addons
    that do not understand `schemaVersion` cannot be made safe retroactively.
