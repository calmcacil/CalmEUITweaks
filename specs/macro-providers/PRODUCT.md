# Macro providers

## Summary

Future generated macros use one provider contract and the existing macro
maintenance system. A provider supplies class-specific text; the shared system
protects user macros, maintains character ownership, and reports readiness.
The mage food/water macro is the reference provider.

## Behavior

1. An author adds one provider per independently configured generated macro.
   Registration uses `ns.RegisterMacroProvider(id, provider)` as a function,
   once during addon loading, before module initialization. It returns the
   registered lifecycle module without generating or changing a macro.
2. Each provider has a stable, unique ID and a unique settings/module key.
   Its registration supplies `settingsKey`, `class`, `classLabel`,
   `defaultName`, and a callable `Build`. IDs and metadata are nonempty text
   without control characters. The default macro name has at most 16
   characters. Invalid metadata or duplicate IDs/module keys fail registration
   without replacing an existing module or reserving a rejected provider ID.
3. `class` is the game's class token; `classLabel` is its readable label.
   Settings provide an account-wide `enabled` preference and macro `name`.
   Ownership records belong to the current character under the same key.
   Registration does not create settings or options controls for the author.
4. `Build()` receives no arguments, including no implicit `self`. Success
   returns a nonempty body string. Expected unavailability returns `nil`, a
   useful status string, and optionally a dense list of positive spell IDs
   whose localized data is missing. The provider does not return a macro index.
5. A build reads current player/game data and returns the same result for the
   same inputs. It does not write macros, settings, or ownership; register
   events; create timers or frames; request spell data; or manage lifecycle.
6. Disabled providers and providers for another class remain inactive, release
   all subscriptions, cancel queued work, and preserve existing macros and
   ownership. Their builders are never called.
7. Enabled eligible providers wait for player login. Combat postpones builds
   and writes; combat end resumes the latest requested work. Disable cancels
   combat work. Provider errors are reported through the shared error/status
   system and do not prevent other providers from running.
8. Level, spellbook, learned-spell, and macro changes refresh eligible providers
   through coalesced event work. There is no polling or repeating timer.
   Combat-end subscriptions exist only while combat work is pending; spell-data
   subscriptions exist only while requested data is outstanding.
9. Only selected missing spell IDs are requested, once per activation, including
   failures. Unrelated data results do nothing. Successful results allow a new
   build; exhausted or unavailable requests give a retry status. Toggling off
   and on permits another request. Normal refreshes may use data now available.
10. Macro generation uses localized spell names supplied by the client and
    item IDs where appropriate. It does not guess translated names. Missing
    spell knowledge or localized data leaves any existing macro unchanged.
11. Rank selection chooses the first level-eligible, known tier from an explicit
    strongest-first list. A higher player level alone does not select an
    unlearned rank. Independent spell families select their tiers independently.
12. Creation uses a character slot and the question-mark icon. Account macros
    are never edited or adopted. Invalid names, empty/invalid bodies, oversized
    localized bodies, missing APIs/storage, and full character capacity leave
    macros and ownership unchanged and report a status.
13. Names are checked across both account and character scopes. Any duplicate,
    account-scope match, or character match without a valid ownership record is
    a conflict, even if its body equals generated text. Identical text does not
    prove ownership.
14. An existing macro can be updated only when it is the sole character match
    and its body equals the last verified generated body for that name. Manual
    body edits suspend maintenance. An unchanged generated body causes no write.
    Owned updates preserve the macro's name and icon.
15. Ownership advances only after a create/edit is read back with the requested
    name and exact body. Failed or unverifiable operations retain prior
    ownership, even if the client partially changed a macro. No rollback or
    deletion is attempted; a subsequent refresh reevaluates the actual macro.
16. Renaming maintains the newly selected name without renaming, deleting, or
    updating earlier macros. Earlier ownership records remain. Selecting an
    earlier name resumes maintenance only if the ownership checks still pass.
    Deleting an owned macro permits recreation when its name is free.
17. Reset restores account defaults and preserves all character ownership and
    existing macros. Providers do not migrate or delete each other's records.
18. Adding a provider preserves the existing EUI settings, search, caching,
    status, and command behavior. Any new controls use the established options
    patterns; no separate macro options or scheduling framework is introduced.
19. Mage registration remains ID `mage`, key `mageMacro`, class `MAGE`, label
    `Mage`, default name `Mage FoodWater`, and enabled by default. Existing
    preferences and ownership remain compatible.
20. Mage requires both a supported known food tier and a supported known water
    tier. Their strongest-first tiers are:

    | Minimum level | Food spell | Food item | Water spell | Water item |
    | --- | --- | --- | --- | --- |
    | 52 | 28612 | 22895 | 10140 | 8079 |
    | 42 | 10145 | 8076 | 10139 | 8078 |
    | 32 | 10144 | 8075 | 10138 | 8077 |
    | 22 | 6129 | 1487 | 6127 | 3772 |
    | 12 | 990 | 1114 | 5506 | 2136 |
    | 6 | 597 | 1113 | 5505 | 2288 |
    | 1 | 587 | 5349 | 5504 | 5350 |

    These are the existing supported tiers, not a claim that every spell in the
    Forever client has been verified. New tiers require verified game data.
21. Mage returns exactly four lines: `#showtooltip`, `/use [btn:1] item:<food>`,
    `/use [btn:1] item:<water>`, and `/castsequence [btn:2] reset=10 <food name>,
    <water name>`, joined with newlines without a trailing newline. Left-click
    attempts both item uses. Each right-click advances the conjure sequence;
    the sequence resets after 10 seconds without use. Creating the macro does
    not place it on an action bar or execute it.
22. Mage Macro pairs the maintenance toggle with a native Rename Macro button.
    The EUI input popup starts with the current name and accepts at most 16
    input characters. Confirmation uses shared name validation (including its
    byte limit); invalid input reports the reason and keeps the preference.
    Opening or cancelling makes no changes. Rename is unavailable before login
    and during combat. The account name preference and live status refresh
    without rebuilding the page; the slash command remains available.
