// KeyboardAccessoryBar — iOS keyboard input-accessory bar (SP-20260620 TASK-06).
//
// Spec refs: FR-16, FR-18, FR-20, FR-21, NFR-04, NFR-08
// Plan refs: sp-20260620-ui-chrome-morph-transparency-spacing-plan.md TASK-06
//
// <!-- CANON GAP: iOS keyboard-accessory bar not in bible; cross-cutting a11y
//      minimums applied; per spec §4 CANON PARTIAL / OQ-06/OQ-13 -->
//
// Anatomy:
//   GlassSurface(borderRadius: tokens.pillRadius)   — 0.68 translucency from
//     TASK-02; opaque fallback under highContrast (EC-10).
//   → SafeArea(top: false, bottom: false)            — horizontal safe-area only.
//   → Row(mainAxisAlignment: end)
//   → Semantics(button: true)
//   → Tooltip(message: l10n.keyboardDoneTooltip)
//   → SizedBox(≥48dp) → IconButton(CupertinoIcons.chevron_down, onPressed: onDone)
//
// Rules enforced here:
//   • Pure StatelessWidget — no Ref, no Riverpod, no platform predicate,
//     no focus manipulation (host owns all of that — FR-19/ISP).
//   • Intrinsic height via kKeyboardAccessoryBarHeight (TASK-01 constant).
//   • No hardcoded alpha/spacing literals — GlassSurface token + named const.
//   • Done button: ≥48dp, CupertinoIcons.chevron_down, ARB tooltip, Semantics.
//   • 0.68 translucency comes from GlassSurface/TASK-02 for free; not hardcoded.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/editor/editor_layout.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

// ---------------------------------------------------------------------------
// Internal constant
// ---------------------------------------------------------------------------

/// Minimum size for the Done button (≥48dp, NFR-04/HIG).
///
/// Equals [kKeyboardAccessoryBarHeight] — the button fills the bar vertically
/// so the entire bar height is the hit target.
const double _kDoneButtonSize = kKeyboardAccessoryBarHeight;

// ---------------------------------------------------------------------------
// KeyboardAccessoryBar
// ---------------------------------------------------------------------------

/// iOS keyboard input-accessory bar shown above the soft keyboard.
///
/// Renders a full-width [GlassSurface] strip containing a trailing "Done"
/// chevron-down [IconButton] that calls [onDone] when tapped.
///
/// **Pure presentation**: this widget owns no platform or keyboard logic.
/// The host (`buffer_screen.dart` TASK-07) is responsible for:
///   - Gating visibility to `defaultTargetPlatform == TargetPlatform.iOS &&
///     keyboardInset > 0` (FR-17/FR-19).
///   - Wiring [onDone] to `_editorFocusNode.unfocus()` (FR-18).
///   - Positioning `Positioned(left:0, right:0, bottom:keyboardInset)` so the
///     bar sits immediately above the soft keyboard (FR-13).
///
/// The 0.68 glass fill alpha is provided by [GlassSurface] + the registered
/// [GlassTokens] (SP-20260620 TASK-02); it is NOT hardcoded here (FR-21/NFR-02).
///
/// Under `MediaQuery.highContrastOf(context) == true` the [GlassSurface]
/// automatically switches to its fully opaque, blur-free branch — no
/// [BackdropFilter] in the sub-tree (EC-10/NFR-03).
class KeyboardAccessoryBar extends StatelessWidget {
  const KeyboardAccessoryBar({super.key, required this.onDone});

  /// Called when the user taps the Done button.
  ///
  /// The host wires this to `_editorFocusNode.unfocus()` (FR-18). This widget
  /// performs no focus manipulation itself (ISP: host owns gating + unfocus).
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;

    return SizedBox(
      height: kKeyboardAccessoryBarHeight,
      child: GlassSurface(
        borderRadius: tokens.pillRadius,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Semantics(
                button: true,
                label: l10n.keyboardDoneTooltip,
                excludeSemantics: true,
                child: Tooltip(
                  message: l10n.keyboardDoneTooltip,
                  child: SizedBox(
                    width: _kDoneButtonSize,
                    height: _kDoneButtonSize,
                    child: IconButton(
                      onPressed: onDone,
                      icon: const Icon(CupertinoIcons.chevron_down),
                      tooltip: null, // provided by parent Tooltip
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
