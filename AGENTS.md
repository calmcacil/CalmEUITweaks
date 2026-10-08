# Agent Instructions

## Purpose and scope

Calm UI Tweaks is a small EllesmereUI plugin for personal use and sharing with
friends. Keep it simple, reliable, and easy to maintain. Prefer existing helpers
and native EUI systems over new abstractions or parallel implementations.

Read `SPEC.md` for the behavior contract and `README.md` for user-facing setup.
Inspect the relevant implementation and tests before changing behavior. Keep
these documents aligned when behavior changes. If a rule here conflicts with an
explicit user instruction, follow the user instruction.

## Sources and original code

- Never read, search, summarize, or learn from another addon's source unless it
  has an open source license or its author has given permission. A public
  repository is not proof of permission. Check the license or permission before
  opening source files, including local sibling addon directories.
- Research game behavior through Blizzard's UI source, using
  [wow-ui-source](https://github.com/Gethe/wow-ui-source). Look up game data on
  [wago.tools](https://wago.tools/).
- Use the author's published documentation for
  [EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI/) to verify plugin
  API contracts. Documentation access does not grant permission to study or
  copy the addon's implementation.
- Write original code. Do not copy implementations from other addons or
  projects, including code reproduced by an AI tool. Review generated code
  before submission. Reuse helpers and patterns already in this repository.
- Verify redistribution rights before adding or publishing third-party assets.

## Lua and code style

- Target WoW Forever interface `16001` and Lua 5.1. No `goto`, `::labels::`, or
  APIs and syntax that require a later Lua version. Use the
  [Lua 5.1 reference manual](https://www.lua.org/manual/5.1/) when uncertain.
- Use ASCII only in source, comments, strings, and new text files. Do not add
  smart quotes, em dashes, emoji, a byte-order mark, or other multibyte
  punctuation; it breaks EUI's packaging pipeline.
- Match the surrounding file's indentation, naming, and function shape. Runtime
  Lua uses four-space indentation and the shared `local addonName, ns = ...` or
  `local _, ns = ...` namespace pattern. Keep internal state local.
- Keep comments brief. Explain a constraint or non-obvious reason; do not
  narrate statements, record change history, or add decorative section banners.
- Reuse shared settings, lifecycle, status, error, and anchor helpers. Do not
  introduce a second module registry, settings store, or scheduling framework.
- Keep checks at real boundaries: saved data, user input, optional dependencies,
  and third-party callbacks. Avoid repeated internal validation and `pcall`
  wrappers that hide failures without useful recovery or reporting.
- Remove dead code, redundant helpers, noisy logging, and unsupported claims.
  Do not add abstractions or fallbacks for hypothetical future requirements.

## EUI plugin integration and options

- Use EUI's plugin API for registration and opening settings. Verify API version,
  signatures, return values, and callback contracts against author documentation;
  do not guess method versus function calling conventions.
- This addon owns its preferences. EUI owns profiles, native anchor links,
  propagation, and Unlock Mode Save/Discard. Use the existing integration points
  instead of replacing EUI behavior or duplicating its layout engine.
- Before building or changing a row, slider, swatch, or cog popup, find the
  nearest existing example in the same file and match its shape. Apply the
  explicit rules here when an existing example violates them.
- Options controls use two-slot `W:DualRow` rows. Fill slots left to right with
  no gaps. Never pass `nil` as the right slot. Use
  `EllesmereUI.BlankRowCfg()` for an empty slot; obtain a fresh blank label config
  on every call. Only the last row of a section may have an empty slot.
- Use `EllesmereUI.ShowWidgetTooltip` and `EllesmereUI.HideWidgetTooltip` for
  plain-text tooltips. Native item/spell tooltips such as
  `GameTooltip:SetHyperlink` are allowed.
- Use `EllesmereUI:ShowConfirmPopup` for confirmations, never `StaticPopup_Show`.
  Use the existing EUI input popup pattern for text transfer dialogs.
- Preserve EUI's fonts, spacing, dividers, disabled states, and visual language.
  Keep explanatory text useful and concise. Put detailed setup instructions in
  `README.md` instead of crowding options pages.
- Preserve search prebuild and page cache behavior. Do not create custom labels
  during hidden search builds. Refresh live status and disabled states through
  the existing page callbacks.

## Runtime behavior and ownership

- Keep optional addons optional. Missing or late-loaded dependencies must leave
  their feature waiting without breaking unrelated features.
- Defer protected changes through combat and respect active Unlock Mode edits.
  Use the existing coalesced requests and native notifications.
- Do not add `OnUpdate` handlers, repeating tickers, or timer polling chains.
  Bounded event-triggered callbacks are allowed. Disabled or idle features must
  release event subscriptions; listen for combat end only while work is pending.
- Prefer secure post-hooks and documented callbacks. Avoid replacing global
  functions or native scripts when an existing hook can do the job.
- Compatibility fixes must track what they own and restore only owned changes.
  Preserve later native or external writes, macro edits, chat history, and local
  window styling. Follow each feature's contract in `SPEC.md`.
- Preserve account versus character settings, existing migrations, and macro
  ownership. Do not silently delete saved data or reset user preferences during
  a cleanup.

## Repository layout and validation

- `core/`: namespace, module registry, settings, lifecycle, and commands.
- `functions/` and `macros/`: feature behavior and class macro providers.
- `compatability/`: optional-addon bridges; keep the existing directory spelling.
- `options/`: EUI plugin registration, pages, and dialogs.
- `tests/`: mocked Lua regressions.
- `scripts/` and `.github/`: validation, packaging, and releases.

From the repository root, run `bash scripts/check.sh` with Python 3, Lua 5.1,
`luac5.1`, ShellCheck, and actionlint available. It runs source validation, Lua
syntax checks, all Lua regression tests, shell lint, and workflow lint. Use the
Bash harness in Git Bash or WSL on Windows; `scripts/test.sh` creates the
`CalmEUITweaks/` path that the test fixtures expect.

Add focused regression tests for bugs or material behavior changes. Do not add
tests that only mirror the implementation or assert cosmetic source formatting.
Mocked tests cannot prove the installed WoW/EUI UI works. For options or native
integration changes, verify the affected paths in game when available, including
search, page switching, disabled states, reload, and relevant combat transitions.
Report any unavailable checks and remaining runtime uncertainty explicitly.

For release work, run `bash scripts/check-package.sh <archive>` after building
the package and follow the in-game checks in `SPEC.md` and release process in
`docs/CI_RELEASES.md`. Keep agent guidance, tests, and other development files out
of the installable addon archive.

## Review and refactor discipline

Ground findings in reachable behavior and cite file/line references. Prioritize
bugs, EUI API misuse, options layout violations, and maintenance cost. Follow the
anti-ai-slop skill when requested. A full-codebase review is permitted when the
user asks for it; ordinary feature cleanup stays within the task's scope.

Preserve existing user changes. Keep refactors focused and behavior-preserving
unless a confirmed bug requires a behavior change. Verify the final diff and
report what changed, evidence from checks, and any unresolved issues.
