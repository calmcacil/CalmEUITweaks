# Changelog

## [0.2.1](https://github.com/calmcacil/CalmEUITweaks/compare/v0.2.0...v0.2.1) (2026-10-08)


### Bug Fixes

* avoid redundant compatibility refresh work ([#3](https://github.com/calmcacil/CalmEUITweaks/issues/3)) ([2e05f87](https://github.com/calmcacil/CalmEUITweaks/commit/2e05f87056d097eceb6291ae68f367f7783776bc))
* **ci:** reuse checkout history for release verification ([#2](https://github.com/calmcacil/CalmEUITweaks/issues/2)) ([378dfdc](https://github.com/calmcacil/CalmEUITweaks/commit/378dfdc2c26db9096c80e2cebd433d1520398c2a))

## 0.2.0 (2026-10-08)

Consolidated testing release for WoW Forever with EllesmereUI.

### Features

- Mage food/water macro maintenance with rank detection, combat deferral and
  protection for manually edited macros.
- SimpleItemLevel bag/bank integration and WhatsTraining spellbook styling.
- Shared chat defaults with import/export and opt-in updates at login.
- Four account-wide spacer anchors, player/target corner alignment and
  per-side default anchor gaps using native EUI Unlock Mode.
- Native EUI settings pages, status commands and preference reset.

### Fixes and cleanup

- Match WhatsTraining fonts, backgrounds, controls, tab selection and icons to
  the native spellbook while preserving restoration and animation behavior.
- Replace polling with event-driven updates and release idle listeners.
- Preserve account spacer layouts and select automatic chat updates only when
  a newer saved default is available at login.
- Use EUI blank row configurations, pack options controls consistently and
  refresh chat action availability after changes.
- Report recurring errors after recovery, validate saved macro names and
  simplify redundant error handling.
- Move font registration to a standalone personal SharedMedia addon.
- Enforce Lua 5.1, ASCII source and font-free packages; keep regression tests
  and verified release tooling outside installable archives.

The addon remains in testing. A future 1.0.0 marks the first stable release.
