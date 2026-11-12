# Total RP 3 EUI skin implementation

Status: Approved for implementation on 2026-11-12; in-game acceptance pending.

## Context

[PRODUCT.md](PRODUCT.md) defines the proposed behavior. Research baseline:

- Calm commit `9e43f29725a58a4915743b9c11eb8ec5de43cc71`:
  [core/Lifecycle.lua:8](https://github.com/calmcacil/CalmEUITweaks/blob/9e43f29725a58a4915743b9c11eb8ec5de43cc71/core/Lifecycle.lua#L8)
  coalesces requests and dispatches module startup/addon loading;
  [functions/LFGLeaderLocation.lua:3](https://github.com/calmcacil/CalmEUITweaks/blob/9e43f29725a58a4915743b9c11eb8ec5de43cc71/functions/LFGLeaderLocation.lua#L3)
  demonstrates optional readiness, guarded post-hooks and shared status;
  [core/Settings.lua:3](https://github.com/calmcacil/CalmEUITweaks/blob/9e43f29725a58a4915743b9c11eb8ec5de43cc71/core/Settings.lua#L3)
  owns defaults/reset; `options/Pages.lua` owns cached options/status labels.
- TRP3 upstream commit `ea21082e0395f2ec9516ccf8f6f052e9f5f7380b`:
  [totalRP3.toc](https://github.com/Total-RP/Total-RP-3/blob/ea21082e0395f2ec9516ccf8f6f052e9f5f7380b/totalRP3/totalRP3.toc)
  declares interface 16001; [UI/Main.xml](https://github.com/Total-RP/Total-RP-3/blob/ea21082e0395f2ec9516ccf8f6f052e9f5f7380b/totalRP3/UI/Main.xml)
  defines `TRP3_MainFrame`, a separate decorative Backdrop child and sidebar;
  [UI/TabSystem.lua](https://github.com/Total-RP/Total-RP-3/blob/ea21082e0395f2ec9516ccf8f6f052e9f5f7380b/totalRP3/UI/TabSystem.lua)
  defines custom tab states; Core/Events.lua exposes workflow/navigation events;
  UI/Tooltip/Tooltip.lua implements custom tooltip descriptions and callbacks.
  The root Apache-2.0 license was checked before source inspection. Write
  original integration code; do not copy TRP3 implementation or assets.
- [EUI SKINNING_API.md](https://github.com/EllesmereGaming/EllesmereUI/blob/main/SKINNING_API.md),
  read 2026-11-12, documents `EllesmereUI.RegisterSkin(name, callback)` as a
  function, once-per-session callbacks, idempotent primitives and skin API v4.
  EUI implementation was not inspected. Installed API/version is unverified.

## Proposed changes

### Prerequisites and coverage inventory

After product approval, verify installed TRP3/EUI versions and client build.
Check each source's license before inspecting any local addon. For Blizzard
behavior use wow-ui-source/forever and compare version.txt to the client.
Pin the EUI documentation revision used by implementation.

The user authorized compatibility styling of explicitly identified TRP3 frames
using documented primitives. EUI's "Skin your own frames only" guideline remains
an upstream support assumption, not an author guarantee for external skins.
Keep all operations limited to TRP3-owned chrome and verify them in game; never
substitute EUI internals or style shared Blizzard/EUI frames. This replaces the
original requirement for separate EUI author confirmation.

Create `specs/total-rp3-skin/COVERAGE.md` during implementation. Inventory every
Product 5 surface with source/version, frame/template/factory, creation and
refresh path, semantic regions, protection status, chosen EUI primitives,
conflicting skins, implementation state and verification evidence. Distinguish
implemented/unverified, verified, unavailable-on-client and safety exception.
Audit templates and factories so hidden and pooled controls are included.
Every safety exception requires a concrete reason; unresolved ordinary work
remains incomplete. This inventory is a delivery requirement, not optional scope.

### Runtime integration

Use `functions/TotalRP3Skin.lua` as the lifecycle module, registered through
`ns.RegisterModule("totalRP3Skin", module)`. Keep state local. If surface mapping
requires separation, use a small `functions/TotalRP3SkinFrames.lua` companion
that supplies explicit surface functions to the same module; do not introduce
a generic skin engine, second module registry or widget discovery framework.

Use account preference `totalRP3Skin.enabled = false`. Add `totalRP3` to
OptionalDeps, retaining EllesmereUI as required. Add the runtime file(s) to the
TOC in dependency order. Capture the requested activation at ready login/startup;
later setting changes mark reload pending, with disable immediately preventing
new work. Register EUI skinning only after Calm readiness and when activation
is requested. Use the addon folder name for a unique registration; confirm the
user-facing EUI listing and conflict behavior against author documentation.
Do not impersonate `totalRP3` or overwrite another registration.

EUI's callback supplies S. Store S locally; check documented capabilities at
the optional API boundary. Primitives handle their own visual refresh. Use
`S.IsEnabled()` before late work and the documented look-change callback only
for necessary custom visuals. Determine how disabled callbacks report status
using supported documentation; do not infer "Disabled in EUI" merely because
the callback has not run. If this cannot be distinguished, revise that status
contract explicitly before implementation is considered complete.

Use existing `OnAddonLoaded` dispatch filtered to TRP3, verified TRP3 readiness
callbacks and bounded per-surface initialization. Verify callback signatures
and unregister contracts from licensed source; event names alone are not a
contract. Skin existing instances once, then use narrow secure post-hooks or
documented creation callbacks for lazy/pooled widgets. Hooking a mixin table
after methods have been copied may miss existing frames; verify actual targets.
Avoid hooking global CreateFrame, enumerating all UIParent descendants or
traversing every page on navigation/tooltip updates.

Apply S.Shell/Panel and widget primitives to explicit targets. Fade only
identified decorative regions; a shell does not imply its Backdrop child or
descendant art has been handled. Preserve icons and content regions. Integrate
custom tab states with S.SetTabSelection when available, without altering
TRP3 selection or input behavior. Preserve semantic text colors; apply S.Font
to interface labels with font/size/clipping verification. Keep player-authored
HTML/profile presentation outside generic font and texture passes.

Tooltips require a distinct inventory of TRP3-owned versus shared Blizzard
frames. Skin reusable containers once and handle recreated regions at their
initialization boundary. Never restyle the shared GameTooltip globally. Custom
menus, sliders and swatches may need documented EUI additions; do not assume a
primitive exists or apply an incompatible one just to claim coverage.

Register hooks once per session and keep disabled hooks as constant-time
no-ops. Detach removable callbacks and owned event subscriptions when idle or
disabled. Pending combat/Unlock Mode work uses ns.RequestApply and existing
native edit notifications; listen for combat end only while needed. No polling
chains. Native EUI theme refresh is owned by EUI and must be verified separately.
No saved styling ledger or live unskin subsystem: reload restores native state.

Unexpected third-party failures cross ns.CallModule/ns.ReportError boundaries.
Do not catch and silently discard each widget failure. Track affected surface
status, avoid retry storms, and let safe unrelated surfaces continue. Validate
known skin conflicts through documented APIs or licensed sources; retain a
list of tested conflicts and do not claim detection of every skin addon.

### Settings, options and documentation

Keep core/Migrations.lua's immutable legacy history and baseline bridge intact.
An additive default-off leaf requires no data conversion; use existing settings
normalization/reset. Inspect source validation and schema fixtures for explicit
preference inventories and update only current expectations where required.
Unknown live nested fields and all TRP3 stores remain untouched.

Add General's Compatibility section through existing DualRow patterns, a fresh
BlankRowCfg for a final unused slot, native tooltip and cached live status.
Preserve hidden search prebuild, page switching and active-module refresh.
Do not add a new options page or transfer popup. Update SPEC.md and README.md
with shipped behavior only during implementation; until then they remain the
current runtime contract. Document reload, both switches, supported versions,
coverage and exceptions. No packaging or release is part of this task.

## Testing and validation

- Product 1-4, 11, 14, 17: focused mocked tests in tests/TotalRP3Skin.lua and
  existing CoreOptions/schema suites cover defaults/reset/preservation, search,
  missing APIs, both load orders, post-login load, EUI opt-out, reload pending,
  disable before deferred callback and blocked/pending Calm migrations.
- Product 5-10, 13, 16: explicit frame fixtures verify primitive target identity,
  preserved content/semantic regions, custom tab selection, lazy creation,
  pooled reuse, errors/conflicts and no unrelated native calls. Tests exercise
  observable ownership and lifecycle, not cosmetic source formatting.
- Product 11-15: assert duplicate hooks are not installed; callbacks create no
  new resources for repeated existing instances; idle/disabled releases owned
  subscriptions; combat and Unlock Mode resumption uses latest activation;
  native methods and return values remain intact. Measure behavior with counters
  at creation/skin boundaries rather than relying on brittle implementation tests.
- Run mise trust, mise install and mise run check through Bash as required by
  AGENTS.md, plus git diff --check. Report unavailable checks explicitly.
- In game, record TRP3/EUI/client versions, resolution, UI scale and theme.
  Exercise every inventory surface and state, long/localized labels, keyboard
  focus/Escape, resize/drag, scrolling, tooltips, edit/save/cancel, live theme
  changes, reload/reset, missing dependency, late initialization, combat,
  Unlock Mode Save/Discard and a known competing skin. Capture representative
  before/after screenshots, including exceptions. Do not certify an unvisited
  surface from mocks or a static screenshot of the main window.
- Product 15, 18: compare skin off/on in the same client and workload with
  addon CPU profiling enabled equally. Warm up, then run three samples each
  of 60 seconds idle and the same 30-cycle page/scroll/tooltip sequence. Record
  addon CPU deltas, total UI cost where measurable, memory before/after garbage
  collection and frame/texture/hook counts. EUI may own part of the cost, so
  Calm-only CPU is insufficient. There must be no recurring skin callbacks
  during idle and no increasing skin resources after the pool is warmed.
  If CPU differences exceed repeat-run noise or interactions visibly stall,
  investigate and repeat before making low-overhead claims; do not invent FPS
  or millisecond guarantees without a measured baseline.

## Parallelization

Following explicit spec approval, use local subagents with disjoint file
ownership in `E:/! Projects/! wowaddon/EUI/CalmUITweaks`. Default integration
branch: `codex/total-rp3-skin`; one combined feature PR. The user subsequently
authorized end-to-end delivery and an alpha testing release through the existing
setup. Alpha publishing requires passing checks, review and package validation,
with unavailable in-game verification explicitly documented. Stable publication
still requires separate approval after in-game testing.
No separate worktrees are needed for these disjoint files. The orchestrator
owns the branch, shared integration files and final validation.

1. Sequential prerequisite: orchestrator verifies installed contracts and EUI
   external-frame permission, creates coverage inventory and agrees the small
   lifecycle-to-surface interface before agents edit runtime code.
2. Surface agent owns functions/TotalRP3SkinFrames.lua and COVERAGE.md, maps
   all core surfaces, records exceptions and supplies explicit styling functions.
3. Lifecycle agent owns functions/TotalRP3Skin.lua and tests/TotalRP3Skin.lua,
   implements activation/readiness/deferred work against the agreed interface.
   It can work in parallel with the surface agent after the interface is fixed.
4. Orchestrator owns Settings, TOC, Pages, CoreOptions/schema fixture changes,
   README and SPEC; integrates after agent contracts are stable. Agents message
   contract changes before editing and never modify each other's files.
5. After integration, a read-only review subagent compares the implementation
   against Product invariants, coverage and ownership/performance constraints.
   Orchestrator fixes findings and runs final checks. In-game evidence remains
   required; unavailable game access is an explicit verification gap.

## Risks and unresolved prerequisites

EUI external-frame support, live opt-out notification and unsupported widget
primitives remain integration assumptions. Pre-callback opt-out cannot be
observed through the published API: show truthful callback-waiting guidance.
Installed TRP3 is 3.5.5, Forever client is 1.60.1.70888; EUI runtime behavior
remains to be verified. Remaining assumptions are
specific research tasks after approval, not permission to guess signatures or
silently narrow coverage. If a prerequisite requires changing approved product
behavior, return the concrete proposed change for review before proceeding.
