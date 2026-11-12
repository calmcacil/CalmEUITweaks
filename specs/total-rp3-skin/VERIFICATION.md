# TRP3 skin alpha verification

Date: 2026-11-12. Baseline: TRP3 3.5.5, Forever executable 1.60.1.70888.
EUI contracts: published plugin API v5 and skin API v4; implementation not read.

## Contract and evidence

| Claim | Failure signal | Evidence | Result |
| --- | --- | --- | --- |
| TRP3 stays optional and default-off | Other features fail or saved choices change with TRP3 absent | CoreOptions dependency/cache/reset regressions, TOC smoke, existing suites | Pass |
| Readiness and opt-out own no repeated work | Duplicate hooks/subscriptions, disabled work queues or protected writes | 17 lifecycle scenarios, 795 assertions using real core lifecycle/settings | Pass in mocks |
| Styling targets owned chrome and preserves content | Foreign page, warning, preview or authored content is passed to destructive primitive | 32 surface assertions, explicit source-backed mappings, independent source review | Pass at primitive boundary |
| Reuse is bounded and errors can recover | Repeated primitive creation, stale error, duplicate reporting | Pooling/idempotence, deferred creation, conflict and recovery regressions | Pass in mocks |
| Alpha and stable channels cannot be mislabeled | Wrong suffix/flag, identity or merged channel accepted | 10 Python tests and real Release Please 17.6.0 parser/versioning contract | Pass locally |
| Installable artifact contains exact runtime source | Wrong TOC/load order, changed Lua, development files or wrong interface | check-package.sh against local testing ZIP | Pass |

`mise trust`, `mise install`, and final `mise run check` completed successfully
through Git Bash. This includes ASCII/source validation, Lua 5.1 syntax and all
Lua regressions, Python release regressions, ShellCheck and actionlint.
`git diff --check` passed. The independent reviewer reported no remaining
actionable findings after fixes. Removing the lifecycle enable guard in memory
made the disabled-hook regression fail; the original runtime then passed again.

Local snapshot: `.release/trp3-testing/CalmEUITweaks-testing.zip`, metadata 1.0.1.
This is a source testing snapshot, not a versioned/public alpha. SHA-256:
`e2f994ee0ef4f81dcce55219a439e3c1f4865569e9b506e89d9d20966dbf65fa`.
Release Please must generate alpha version metadata; the actual release package
must be built and independently validated by CI for its exact tag.

## Remaining verification

No in-game appearance, interaction, transition recording or performance profile
was captured. A running client was detected, but the changed addon was not
installed into it or exercised. The installed EUI runtime was not queried.
Mocks establish primitive targeting and lifecycle; they cannot establish how
the installed EUI paints custom TRP3 widgets or whether every state is usable.

Use [COVERAGE.md](COVERAGE.md) for the complete surface/state checklist and
[TECH.md](TECH.md) for the off/on CPU/memory and reuse workload. Record actual
EUI version, theme and UI scale during testing. In particular verify long labels,
color/preview preservation, lazy editors, pooled rows, keyboard/focus, live theme,
combat/Unlock Mode, opt-out/reload/reset and overlapping skins. Preserve the
original recording and inspect transitions before claiming visual correctness.

## Verdict

PASS WITH RESIDUAL RISK for an explicitly labeled alpha testing artifact.
Visual, interaction and performance acceptance is pending user testing.
Stable readiness is not certified. Source coverage and exceptions are recorded;
no FPS, zero-cost or universal addon-conflict guarantee is made.
