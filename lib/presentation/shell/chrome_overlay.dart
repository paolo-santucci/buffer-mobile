import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/editor_layout.dart'
    show kChromeMenuZoneHeight;
import 'package:buffer/presentation/shell/chrome_reveal_controller.dart';

// ---------------------------------------------------------------------------
// ChromeOverlay — auto-hiding chrome affordance (TASK-08b)
//
// Spec refs  : FR-M6-05, FR-M6-06, NFR-M6-03, NFR-M6-05, EC-12
// Canon ref  : ui-design-bible.md §Components §2 "Auto-hiding overlay chrome"
//
// Anatomy (canon §2 mobile adaptation):
//   Positioned(top-end) → AnimatedOpacity → Container(90%-surface bg) → IconButton
//
// Rules enforced here:
//   • Crossfade ONLY: AnimatedOpacity — no Slide/Scale/Rotation/Size transition.
//   • Duration.zero when MediaQuery.disableAnimations is true (EC-12).
//   • Menu affordance ≥ 48 dp (NFR-M6-05, canon "Promote targets to ≥48dp").
//   • Tooltip + Semantics resolved from ARB key menuTooltip (NFR-M6-02, FR-M6-17).
//   • This widget does NOT import the menu sheet; onMenuTap is wired by TASK-12.
//   • NOT a Column row; constructs NO ScrollController; calls NO jumpTo/animateTo.
// ---------------------------------------------------------------------------

/// The default crossfade duration for the chrome reveal/hide transition.
///
/// Canon §Motion specifies crossfade; no explicit duration for the mobile overlay.
/// 200ms is a standard Material fade duration — unobtrusive and platform-natural.
const Duration _kChromeFadeDuration = Duration(milliseconds: 200);

// TASK-02 repoint: the private tap-target constant was removed and replaced by
// the shared kChromeMenuZoneHeight from editor_layout.dart — the single source
// of truth for the 48dp chrome button box (spec C2b). See SizedBox below.

/// Chrome container background opacity — canon §2:
/// `color-mix(in srgb, var(--view-bg-color) 90%, transparent)`.
const double _kBgOpacity = 0.9;

/// Auto-hiding chrome overlay widget.
///
/// Placed as a [Positioned] top-end child of the editor [Stack] by TASK-12.
/// Watches [chromeVisibilityProvider] and crossfades the menu affordance
/// in/out based on visibility state.
///
/// [onMenuTap] is called when the user taps the menu icon. The callback is
/// wired to open the [MenuSheet] by TASK-12 — this widget does not import it.
class ChromeOverlay extends ConsumerWidget {
  const ChromeOverlay({super.key, required this.onMenuTap});

  /// Callback invoked when the user taps the menu affordance.
  ///
  /// Wired by TASK-12 to call `openMenuSheet(context)`.
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(chromeVisibilityProvider);
    final l10n = AppLocalizations.of(context);

    // Collapse animation to zero when the OS reduce-motion flag is set (EC-12).
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : _kChromeFadeDuration;

    // Canon §2 background token: view-bg-color at 90% opacity.
    // ColorScheme.surface is the Flutter equivalent of --view-bg-color.
    final bgColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: _kBgOpacity);

    return Positioned(
      top: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        // Exclude fully-hidden chrome from hit-testing so the editor
        // beneath remains tappable when chrome is invisible.
        child: IgnorePointer(
          ignoring: !visible,
          child: Semantics(
            label: l10n.menuTooltip,
            button: true,
            excludeSemantics: true,
            child: Tooltip(
              message: l10n.menuTooltip,
              child: Container(
                // Canon §2: surface bg at 90% opacity applied to the chrome box.
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: SizedBox(
                  // Enforce ≥48dp tap target (NFR-M6-05, canon mobile promotion).
                  // Sized from shared kChromeMenuZoneHeight (TASK-02, C2b) so the
                  // chrome button box and the editor top reservation never drift.
                  width: kChromeMenuZoneHeight,
                  height: kChromeMenuZoneHeight,
                  child: IconButton(
                    onPressed: onMenuTap,
                    icon: const Icon(Icons.menu),
                    // Tooltip is provided by the parent Tooltip widget.
                    tooltip: null,
                    // Remove padding — the SizedBox already enforces the
                    // minimum 48dp target; additional padding would overshoot.
                    padding: EdgeInsets.zero,
                    // Constrain the icon to fill the SizedBox.
                    constraints: const BoxConstraints.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
