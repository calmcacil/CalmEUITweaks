# Macro providers

## Summary

Generated macros use one provider contract and the shared macro maintenance
system. A provider supplies class-specific text; the shared system protects user
macros, maintains ownership, and reports readiness. Shipped providers cover the
mage food/water macro, the druid Rebirth/Revive and self-Thorns macros, and a
general food/water macro available to every class. Generated macros are opt-in;
every shipped provider defaults off.

## Provider contract

1. An author adds one provider per independently configured generated macro.
   Registration uses `ns.RegisterMacroProvider(id, provider)` as a function,
   once during addon loading, before module initialization. It returns the
   registered lifecycle module without generating or changing a macro.
2. Each provider has a stable, unique ID and a unique settings/module key. Its
   registration supplies `settingsKey`, `class`, `classLabel`, `defaultName`,
   `Build`, and optionally `scope` and `events`. IDs and metadata are nonempty
   text without control characters. Registration accepts at most 16 UTF-8
   characters for the default name; Settings validation is stricter at 16 bytes
   and rejects `|`. Use defaults that pass both boundaries. Invalid metadata or
   duplicate IDs/module keys fail registration without replacing an existing
   module or reserving a rejected provider ID.
3. `scope` is `character` (default) or `account`. Character providers create and
   maintain a character macro. Account providers create and maintain a general
   macro shared by every character. A provider never edits the other scope.
4. `class` is the game's class token, or `ALL` for an account provider available
   to every class. `classLabel` is its readable label. Settings provide an
   account-wide `enabled` preference, off by default, and macro `name`.
5. Ownership is stored under the same key as the settings. Character providers
   record ownership in `ns.charDB` for the current character. Account providers
   record ownership in `ns.db` for the whole account. Reset preserves both.
6. `Build()` receives no arguments, including no implicit `self`. Success
   returns a nonempty body string, optionally with a fourth return value naming
   a desired icon. Expected unavailability returns `nil`, a useful status string,
   and optionally a dense list of positive spell IDs whose localized data is
   missing. The provider does not return a macro index.
7. A build reads current player/game data and returns the same result for the
   same inputs. It does not write macros, settings, or ownership; register
   events; create timers or frames; request spell data; or manage lifecycle.
   Extra refresh events are declared once through `events` and owned by the
   shared maintenance system.
8. Disabled providers and providers for another class remain inactive, release
   all subscriptions, cancel queued work, and preserve existing macros and
   ownership. Their builders are never called.
9. Enabled eligible providers wait for player login. Combat postpones builds
   and writes; combat end resumes the latest requested work. Disable cancels
   combat work. Provider errors are reported through the shared error/status
   system and do not prevent other providers from running.
10. Level, spellbook, learned-spell, macro, and declared provider events refresh
    eligible providers through coalesced event work. There is no polling or
    repeating timer. Combat-end subscriptions exist only while combat work is
    pending; spell-data subscriptions exist only while requested data is
    outstanding.
11. Only selected missing spell IDs are requested, once per activation,
    including failures. Unrelated data results do nothing. Successful results
    allow a new build; exhausted or unavailable requests give a retry status.
    Toggling off and on permits another request. Normal refreshes may use data
    now available.
12. Macro generation uses localized spell names supplied by the client and item
    IDs where appropriate. It does not guess translated names. Spell macros use
    unranked names, so the client selects the highest learned rank; generated
    text never appends a rank. Missing spell knowledge or localized data leaves
    any existing spell macro unchanged. The general item provider instead emits
    a placeholder or partial body when food or water is absent.
13. Rank selection chooses the first level-eligible, known tier from an explicit
    strongest-first list. A higher player level alone does not select an
    unlearned rank. Independent spell families select their tiers independently.
14. Creation uses a character slot for character providers and a general slot
    for account providers, with a question-mark icon unless the builder supplies
    a desired icon. Invalid names,
    empty/invalid bodies, oversized localized bodies, missing APIs/storage, and
    full capacity leave macros and ownership unchanged and report a status.
15. Names are checked across both account and character scopes. A duplicate in
    the provider's scope, an account-scope match for a character provider, or a
    character-scope match for an account provider is a conflict. A sole
    same-name macro in the provider's scope is adopted when the provider is
    enabled, even if its body differs. Identical text alone does not prove
    ownership; adoption records ownership only after a verified readback.
16. An adopted or owned macro can be updated when it is the sole match in the
    provider's scope. Once owned, a body different from the last verified
    generated body is a manual edit and suspends maintenance. Unchanged body and
    owned icon state cause no write. Names and existing untracked icons remain
    unchanged. A newly created macro with a desired icon records the requested
    icon key and actual native readback; only a still-matching owned icon follows
    later desired-icon changes. A manual icon edit releases icon tracking without
    stopping body maintenance; adopted icons are never acquired.
17. Ownership advances only after a create/edit is read back with the requested
    name and exact body. Failed or unverifiable operations retain prior
    ownership, even if the client partially changed a macro. No rollback or
    deletion is attempted; a subsequent refresh reevaluates the actual macro.
18. Renaming maintains the newly selected name without renaming, deleting, or
    updating earlier macros. Earlier ownership records remain. Selecting an
    earlier name resumes maintenance only if the ownership checks still pass.
    Deleting an owned macro permits recreation when its name is free.
19. One-time Calm Forever v1 conversion and normal reset restore known preference
    leaves, including names and `enabled = false`, while preserving character and
    account ownership, actual macros and unknown nested/provider fields. Marked v1
    reloads preserve later choices. Providers do not migrate or delete each other's
    records; conversion waits behind the shared SavedVariables/CVar barrier.
20. Adding a provider preserves the existing EUI settings, search, caching,
    status, and command behavior. Any new controls use the established options
    patterns; no separate macro options or scheduling framework is introduced.
21. The **Macro** page groups providers into one list: General first, then
    class sections in alphabetical order. Each macro pairs its maintenance
    toggle with a native Rename button. Status and the current name refresh in
    place. Rename uses the shared name validation and is unavailable before
    login and during combat.

## Mage provider

22. Mage registration remains ID `mage`, key `mageMacro`, class `MAGE`, label
    `Mage`, and default name `FoodWater`. It is off by default. Ownership remains
    compatible; conversion/reset changes preferences, not existing macros.
23. Mage requires both a supported known food tier and a supported known water
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
24. Mage returns exactly four lines: `#showtooltip`, `/use [btn:1] item:<food>`,
    `/use [btn:1] item:<water>`, and `/castsequence [btn:2] reset=10 <food name>,
    <water name>`, joined with newlines without a trailing newline. Left-click
    attempts both item uses. Each right-click advances the conjure sequence;
    the sequence resets after 10 seconds without use. Creating the macro does
    not place it on an action bar or execute it.

## Druid providers

25. Druid registration is ID `druidRebirth`, key `druidRebirthMacro`, class
    `DRUID`, label `Druid`, default name `Rebirth`, off by default. The Thorns
    provider is ID `druidThorns`, key `druidThornsMacro`, class `DRUID`, label
    `Druid`, default name `Thorns`, off by default. Both create character macros.
26. Rebirth requires both a known Rebirth tier and a known Revive tier. Their
    strongest-first tiers are:

    | Rebirth level | Rebirth spell |
    | --- | --- |
    | 60 | 20748 |
    | 50 | 20747 |
    | 40 | 20742 |
    | 30 | 20739 |
    | 20 | 20484 |

    | Revive level | Revive spell |
    | --- | --- |
    | 60 | 1237951 |
    | 48 | 1237950 |
    | 36 | 1237949 |
    | 24 | 1237948 |
    | 12 | 437138 |
27. Rebirth returns exactly three lines: `#showtooltip [combat] <rebirth>;
    <revive>`, `/cast [combat] <rebirth>`, and `/cast [nocombat] <revive>`,
    joined with newlines without a trailing newline. The tooltip follows the
    active branch. Names are unranked.
28. Thorns requires a known Thorns tier. Its strongest-first tiers are:

    | Minimum level | Spell |
    | --- | --- |
    | 54 | 9910 |
    | 44 | 9756 |
    | 34 | 8914 |
    | 24 | 1075 |
    | 14 | 782 |
    | 6 | 467 |

29. Thorns returns exactly two lines: `#showtooltip <thorns>` and
    `/cast [@player] <thorns>`, joined with newlines without a trailing newline.
    Names are unranked.

## General provider

30. General food/water registration is ID `foodWater`, key
    `generalFoodWaterMacro`, scope `account`, class `ALL`, label `All classes`,
    default name `Food and Water`, off by default. It declares
    `BAG_UPDATE_DELAYED` as its refresh event and creates a general macro.
31. Enabling creates a macro even when no supported items are in bags. With
    neither food nor water, its body is exactly `#showtooltip`; newly created
    placeholders use the mage class icon. The strongest-first item tiers are
    the mage food/water item columns in item 23. Bank contents do not count.
32. With both item families it returns three lines: `#showtooltip [btn:2]
    item:<water>; item:<food>`, `/use [btn:1] item:<food>`, and
    `/use [btn:2] item:<water>`. With only one family, the tooltip names that
    item and only its corresponding use line is included. Losing items removes
    stale use lines. Bag changes update each family independently. Generated
    icons use the question-mark icon for native item tooltips while items exist,
    and return to the mage icon when empty, but only while the icon remains owned.
    Adopted, untracked and manually customized icons are not overwritten.
33. Because the macro is account-wide, the last active character's bag contents
    determine its current body. Ownership is account-wide and survives character
    switches and preference reset.
