# Post-v0.1.1 performance fixes

The review covered main commit `88bbf5bad4a4f4c16d26bb83f9d06f856692ace5`
and shipped release `v0.1.1`. These changes resolve its seven findings.

| Finding | Resolution | Regression coverage |
| --- | --- | --- |
| Corner alignment runs continuously, including DEFAULT | Shared EUI placement notifications and managed-frame size hooks; DEFAULT releases observers and events | SpacerCorners |
| Anchor gaps scan all links every frame | Snapshot at editor open, keyed dirty notifications, coalesced one-shot processing; closing cancels work | AnchorGap |
| SIL subscribes broadly and scans hidden/disabled bags | Visibility/scope event masks, scoped scans, tracked-item filtering, unchanged-result reuse | SimpleItemLevel |
| Chat keeps four idle subscriptions | Subscribe only while automatic or pending application needs work; filter channel notices | Chat |
| Unrelated dependency loads and settled combat/world listeners cause work | Filter dependency loads; arm combat listeners for deferred work; remove theme world listener | Macros, Spacers, SpacerCorners, WhatsTraining |
| Spacers miss late unlock listener API | Idempotent listener installation during settings application | Spacers |
| Macro/chat timer fallback registers OnUpdate | Bounded synchronous fallback when timer API is unavailable | Macros, Chat |

`core/AnchorEvents.lua` observes the public EUI placement helper because the
native anchor picker captures its internal link setter. Hooks track function
identity so a late implementation can replace an early EUI stub. EUI reference
source inspected: commit `52e68688b68bfaeba4af4cbf2cb702aa35a541a8`.

First-party TOC-loaded code has no OnUpdate, repeating ticker, self-rescheduling
timer chain, or persistent polling loop. Bounded deferred callbacks remain.
Source validation and EventPolicy reject OnUpdate and NewTicker in runtime Lua;
timer chains still require code review. Retained secure hooks cannot be removed,
so callbacks check active observers/settings before doing feature work.

Validation: 28 Lua files passed Lua 5.1 syntax checks and all eleven suites
passed locally using Lua 5.1 through Lupa. Source/version validation and diff
whitespace checks passed. GitHub CI additionally runs native Lua, ShellCheck,
actionlint, and package validation before merge.

No in-game verification or CPU profiling was performed. Save/Discard,
combat deferral, late dependencies, item callbacks, and idle feature behavior
have fixture coverage; compatibility with the installed EUI/client still needs
the manual checks in SPEC.md. No measured CPU improvement is claimed.
