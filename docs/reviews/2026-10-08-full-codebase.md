# Full codebase review - 2026-10-08

This report closes the original review and its follow-up against the clean
0.2.0 repository at `98de6fb8017aa0b033b744e1e6f48a19b1326d24`. The review
covered runtime Lua, options, regression suites, settings and ownership
contracts, assets, validation scripts and workflows. The current addon loads
16 Lua files and has six options pages. Review fixes remain uncommitted.

The installed source of truth is EllesmereUI 9.4 with plugin API 1, under
`D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\`.
The user confirmed author permission to inspect EUI's reserved-rights source.
WhatsTraining's MIT license was verified. SimpleItemLevel's implementation was
not inspected because no source-inspection permission or license was verified.
External source was used to check contracts; no implementation was copied.

## Remaining finding

**P2 - Native integration still depends on EUI internals.**
`core/AnchorEvents.lua:21` and `functions/SpacerCorners.lua:36` read
`_unlockRegisteredElements`; `compatability/WhatsTraining.lua:31` hooks
`_WSkinRefreshStyles` and `_WSkinRefreshLooks`. Anchor notifications also
post-hook EUI's placement and layout helpers. EUI's plugin guide prohibits
hooking its functions and reading underscore-prefixed fields. These paths
can break on an EUI update even when the plugin API remains compatible.

No equivalent public unlock frame lookup or placement notification was found.
The public skin API chooses its window theme from the majority of Blizzard
windows; the training bridge follows the spellbook's specific skin and must
restore only its own changes. It is not a verified replacement for this bridge.
A migration needs supported element lookup, anchor notifications and
spellbook skin/restoration contracts. Existing behavior is retained until
those integration points are available.

The font distribution issue is resolved in the clean baseline: fonts and
SharedMedia registration are absent from tracked source and the TOC. Source
and package validation reject font assets. This follow-up preserves that work.

## Fixed findings

| Priority | Reachable issue | Fix and regression |
| --- | --- | --- |
| P2 | Saving the first chat default left Apply Default and Export Default disabled until a rebuild. | `options/Chat.lua:14` refreshes native widget state. CoreOptions checks both buttons after the first save. |
| P2 | Anchors left an empty slot before later controls, and blanks bypassed the required EUI factory. | `options/Pages.lua:81` uses fresh native blanks and packs Anchors controls left to right. CoreOptions checks all six pages. |
| P2 | Whitespace-only persisted macro names passed validation and blocked macro generation. | `core/Settings.lua:42` requires a non-whitespace character. CoreOptions checks recovery to the default name. |
| P3 | Disabling the last spacer retained its Unlock Mode callback. | `functions/Spacers.lua:13` shares listener cleanup and releases it after final removal. Spacers checks teardown and re-enable. |
| P3 | An identical failure after recovery did not reach the error handler again. | `core/Bootstrap.lua:49` resets report deduplication on recovery. CoreOptions checks repeated errors before and after recovery. |

## Cleanup retained

- Options use the public `IsSearchPrebuild()` helper, with required helpers
  checked at the existing page boundary. The private search fallback is removed.
- Macro callbacks reuse core error/status reporting. Duplicate fallback error
  tracking, nested wrappers, an unused argument and a timer closure are removed.
  Native macro operations retain their ownership and verification checks.
- Chat and WhatsTraining use Lua 5.1's `unpack` directly.
- Spacers and Anchors descriptions are shorter; removal and Save/Discard
  warnings remain. Detailed setup examples stay in the README.
- A SimpleItemLevel change-history comment now explains only the constraint.
- Chat fixtures use ASCII byte escapes while retaining UTF-8 roundtrip coverage.
  Validation rejects non-ASCII runtime, test and packaged Lua and packaged
  `AGENTS.md`.

The fixes preserve settings stores, macro ownership, EUI layout authority,
combat deferral and optional-addon behavior. Existing suites cover those
invariants. No recurring runtime polling is introduced.

## Installed EUI references

Paths are relative to the installed AddOns directory.

| Reference | Contract |
| --- | --- |
| `EllesmereUI/PLUGINS_API.md:74` | EUI functions and underscore-prefixed internals are outside the supported plugin contract. |
| `EllesmereUI/PLUGINS_API.md:151` | Public search-prebuild helper. |
| `EllesmereUI/EllesmereUI_Panel.lua:5069` | Plugin registration is a dot call. |
| `EllesmereUI/EllesmereUI_Panel.lua:5137` | Plugin opening is a dot call. |
| `EllesmereUI/EllesmereUI_Panel.lua:4254` | Unforced refresh updates registered widget callbacks in place. |
| `EllesmereUIOptions/EllesmereUI_Widgets_PageParts.lua:177` | Blank factory returns a fresh empty label config. |
| `EllesmereUI/EUI_UnlockMode.lua:73` | Listener removal uses its owner key. |
| `EllesmereUI/SKINNING_API.md:65` | Third-party theme follows the majority of Blizzard windows. |

## Verification

Source/version validation, Lua 5.1 syntax and ASCII checks, all ten suites,
ShellCheck 0.11.0, actionlint 1.7.12 with ShellCheck integration, and Git
whitespace checks pass on the current clean 0.2.0 source.

Native local Lua executables are 5.4. Tests instead use Lupa 2.6's
`lupa.lua51.LuaRuntime`, asserting `_VERSION == "Lua 5.1"`. The Windows runner
only adapts fixture paths from the `CalmEUITweaks/` prefix to this checkout.
The aggregate Bash harness was not run; its constituent checks were run on
Windows with that Lua 5.1 runtime.

| Suite | Passing result |
| --- | --- |
| AnchorGap | 81 checks |
| Chat | 102 checks |
| CoreOptions | 63 tests |
| Macros | 49 checks |
| SimpleItemLevel | 6 suites, 113 assertions |
| Smoke | 30 assertions |
| SpacerCorners | 72 checks |
| Spacers | 16 tests |
| WhatsTraining | 130 assertions |
| WhatsTrainingTheme | 231 assertions |

Local evidence is retained under ignored `.release/review-tools/`:

- `check.py` and `logs/resumed-clean-repo.txt`: current Lua 5.1 runner and suite
  results. The three removed CoreOptions tests covered the old font module.
- Pre-fix logs for recovery, names, chat state and row rules demonstrate failing
  regressions from the original review; the current suites pass those cases.
- `package-checks.py` and `logs/package-checks-clean-0.2.0.txt`: matching source
  and ZIP fixtures pass. Font inclusion, development-guide inclusion and
  non-ASCII runtime, test and packaged Lua fail as expected.
- `candidate-clean-0.2.0.zip`: locally generated source package, SHA256
  `24e494fc7c6abb89ec82b6dece9842f1f900309d0638968b7740edfbb7169024`.
  Its contents match current runtime source and contain no font assets. This
  is a validator check, not a BigWigs packager run. Nothing was deployed or
  published.

Normal reproduction uses `bash scripts/check.sh` with Lua 5.1, Python 3,
ShellCheck and actionlint. The retained Windows runners can be invoked with
the bundled Python runtime. Validate a release package with
`bash scripts/check-package.sh <archive>`.

## In-game checks

No in-game run or UI recording was available. Source/API checks and mocks
cannot establish real rendering, clipping, scale or protected-frame behavior.
Run the release checks in `SPEC.md`, focusing on all six options pages and
search, first-save/first-import chat buttons, last-spacer removal and re-enable,
combat/Unlock Mode deferral, native Save/Discard, and WhatsTraining rendering
and restoration in both spellbook skins.

Automated checks pass with residual integration risk. Private API support and
in-game visual/runtime verification remain outstanding.
