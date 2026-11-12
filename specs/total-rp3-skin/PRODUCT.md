# Total RP 3 EUI skin

Status: Approved for implementation on 2026-11-12; in-game acceptance pending.

## Summary

Calm UI Tweaks offers an optional Total RP 3 skin that matches the user's EUI
style across core TRP3 windows and controls wherever this can be done safely.
TRP3 retains its functionality, content, configuration, and layout ownership.

## Visual references

The supplied visual concept is the installed EUI style, including its window
shells, panel fills, borders, typography, accent, hover and disabled states.
[EUI's published skinning documentation](https://github.com/EllesmereGaming/EllesmereUI/blob/main/SKINNING_API.md)
defines the supported styling vocabulary. Match the user's resolved EUI theme;
do not invent a separate Calm theme or assume a fixed accent or dark palette.

## Behavior

1. **Opt-in.** One account-wide "Total RP 3 EUI Skin" switch defaults off.
   Existing installations retain every unrelated preference. Enabling requests
   the complete supported skin; there are no separate switches per widget.

2. **Activation.** The switch appears on General under a Compatibility section,
   following native EUI row, search, tooltip, and disabled-state conventions.
   Missing TRP3 or an unavailable EUI skinning API disables the control with a
   useful dependency explanation, without erasing the saved preference.

3. **Reload.** Changes take effect after UI reload. The page shows "Reload
   required" when the saved preference differs from this session's activation.
   No automatic reload occurs. Turning off or resetting preferences stops new
   skin application immediately; existing styled frames may remain until reload.
   After reload with the switch off, TRP3 has its normal appearance unless
   another addon styles it.

4. **EUI controls.** EUI's third-party skin switch also governs the integration.
   Before EUI supplies a skin callback, Calm reports that it is waiting and
   directs the user to EUI's third-party skin switch; the published API cannot
   distinguish initial opt-out from a callback that has not arrived. After the
   callback, Calm can identify opt-out through EUI's enabled query. The controls
   have a documented relationship and a unique, recognizable registration name.
   Neither addon silently enables the other's preference.

5. **Coverage.** The release targets all core TRP3 interface surfaces: main
   window and sidebar; dashboard and character/companion directory; profile
   viewing and editing controls; notes and profile management; configuration;
   icon, background, color, music and companion browsers; import/export and
   confirmation dialogs; context menus; toolbar; target frame and glance bars;
   and TRP3-owned tooltips. Lists, empty states, selected rows, nested panels,
   pagination, popups and dynamically created controls are included.

6. **Consistent styling.** Supported surfaces use EUI shells, panels, borders,
   interface fonts, inputs, buttons, tabs, scrollbars, checks, highlights and
   disabled states. TRP3's decorative wood, parchment and ornamental borders
   are removed where they are interface chrome. Unselected, selected, pressed,
   hovered, disabled and focused states remain distinguishable. No input or
   content disappears when decorative regions are removed.

7. **Safe exceptions.** Full coverage means every surface in invariant 5 is
   assessed, not that unsafe styling is forced. A surface or element remains
   native when styling would break behavior, obscure information, violate an
   integration contract, or require continuous enforcement. Every exception
   names the affected element, concrete reason and remaining native appearance
   in the coverage record and release documentation. Unimplemented work is not
   a safety exception. Partial coverage is reported as partial.

8. **Content.** Character names, class/reaction/RP-status colors, warnings,
   rarity and other meaningful colors retain their meaning and readability.
   Player-authored profile fonts, colors, images, backgrounds and markup remain
   intact. Interface chrome around such content follows EUI. Profile artwork
   and useful icons are not removed as decoration. Core TRP3 branding may remain
   where it does not conflict with the window treatment.

9. **Interaction.** Navigation, editing, selection, scrolling, resizing,
   dragging, saved positions, close/Escape behavior, keyboard focus, tooltips,
   links, sound controls and import/export retain TRP3 behavior. Existing text
   sizes and content space remain usable at supported UI scales; changing the
   interface font must not clip labels or introduce overlapping hit regions.

10. **Theme changes.** EUI-supported live theme, accent and font changes reach
    styled controls without rebuilding TRP3 pages or losing edits, focus,
    selection or scroll position. If a documented EUI setting requires reload,
    this integration follows that requirement and explains it where relevant.

11. **Readiness.** Startup, later TRP3 loading and first opening a lazy panel
    produce the same appearance. A missing optional dependency leaves the
    feature waiting and does not break TRP3 or other Calm features. Saved-data
    readiness remains governed by Calm's existing migration lifecycle.

12. **Combat and layout edits.** Skin setup that cannot safely execute during
    combat or active EUI Unlock Mode waits until the current restrictions end.
    Deferred work uses the current activation state. No skin operation changes
    secure actions, native anchors, EUI layout links or in-progress layout edits.

13. **Other skins and updates.** A known active skin for the same TRP3 surface
    is not layered with Calm's skin. The affected surface is skipped with a
    conflict explanation. Unknown or changed TRP3 widgets are left functional
    and reported as unsupported rather than forcibly restyled. A failure in
    one surface does not disable unrelated Calm features or TRP3 functionality.

14. **Status.** General and `/calmtweaks status` distinguish Disabled, Reload
    required, Waiting for dependency/readiness, Disabled in EUI, Waiting for
    combat/Unlock Mode, Active, Partial coverage, Conflict and Error. Messages
    identify the actionable cause. Partial application is never labeled fully
    active. Repeated errors do not flood chat.

15. **Performance.** The integration adds no periodic or per-frame activity.
    With TRP3 closed it performs no recurring skin work. Reopening, scrolling
    and page switching reuse existing styling resources; resource use grows
    only when new supported widget instances are created and stabilizes when
    those instances are reused. Normal tooltip and target updates must not
    trigger repeated full-window styling or noticeable interaction delay.

16. **Ownership.** The integration does not modify TRP3 files, profiles, saved
    configuration, communication, RP data, chat formatting, nameplates or map
    behavior. Blizzard's shared UI and other addons' widgets retain their own
    styling. TRP3 Extended and other TRP3 extensions are outside initial coverage;
    their presence must not break core TRP3 or cause their content to be stripped.

17. **Reset.** Normal Calm preference reset returns this switch to off and
    follows the existing confirmed reset/reload flow. It does not reset TRP3
    or EUI preferences. Existing migration history and stored unrelated data
    retain their current guarantees.

18. **Compatibility claims.** Release documentation names the tested TRP3 and
    EUI versions and Forever client build, supported surfaces, exceptions and
    conflicting skins. Unverified versions and surfaces are not described as
    proven compatible. Performance claims require measurements in game.
