# Changelog

## [0.5.0](https://github.com/calmcacil/CalmEUITweaks/compare/v0.4.0...v0.5.0) (2026-10-15)


### Features

* **lfg:** add opt-in leader zone labels ([#24](https://github.com/calmcacil/CalmEUITweaks/issues/24)) ([b0288a5](https://github.com/calmcacil/CalmEUITweaks/commit/b0288a56b1677b1a2063451f2d483a62d427a916))


### CI

* consolidate Renovate updates and keep validated Ubuntu runners ([#22](https://github.com/calmcacil/CalmEUITweaks/issues/22)) ([1697db8](https://github.com/calmcacil/CalmEUITweaks/commit/1697db89e4462c259908ee20fee7236a5ea46a06))
* **deps:** bump the actions group with 2 updates ([#10](https://github.com/calmcacil/CalmEUITweaks/issues/10)) ([0ee86b1](https://github.com/calmcacil/CalmEUITweaks/commit/0ee86b13eb3008b81c987efce36f7d9390c6c654))

## [0.4.0](https://github.com/calmcacil/CalmEUITweaks/compare/v0.3.0...v0.4.0) (2026-10-11)


### Features

* standardize macro providers and EUI settings ([#8](https://github.com/calmcacil/CalmEUITweaks/issues/8)) ([a825615](https://github.com/calmcacil/CalmEUITweaks/commit/a825615261bba00e9796a48722894c4bf1e3be40))

## [0.3.0](https://github.com/calmcacil/CalmEUITweaks/compare/v0.2.1...v0.3.0) (2026-10-10)


### Features

* add native bag upgrades and optional loot sparkles ([#6](https://github.com/calmcacil/CalmEUITweaks/issues/6)) ([e5fde83](https://github.com/calmcacil/CalmEUITweaks/commit/e5fde8300ae6d80cc7700814c593e36227506619))


### Bug Fixes

* **ci:** guard release App configuration ([#5](https://github.com/calmcacil/CalmEUITweaks/issues/5)) ([27d74a8](https://github.com/calmcacil/CalmEUITweaks/commit/27d74a82d02dd487331be98103895f9a406c6e2b))

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
