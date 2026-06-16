import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/editor_layout.dart'
    show kChromeMenuZoneHeight;
import 'package:buffer/presentation/shell/chrome_reveal_controller.dart';

// ---------------------------------------------------------------------------
// ShareOverlay — top-left mirror of ChromeOverlay (TASK-07)
//
// Spec refs  : FR-01, FR-02, FR-03, FR-05, FR-17, NFR-02, NFR-03,
//              EC-01, EC-11, EC-12, EC-14, §5.1.5
// Canon ref  : ui-design-bible.md §Components §2 "Auto-hiding overlay chrome",
//              §Accessibility, §Motion
//
// Anatomy (three deltas from ChromeOverlay):
//   Positioned(top:0, LEFT:0)                ← delta 1: left vs right
//   → AnimatedOpacity (_kChromeFadeDuration; Duration.zero under EC-11)
//   → IgnorePointer(ignoring: !visible)
//   → Semantics(label: l10n.shareTooltip, button:true, excludeSemantics:true)
//   → Tooltip(message: l10n.shareTooltip)
//   → Container(surface@90%, borderRadius: only(bottomRight: …))  ← delta 2
//   → SizedBox(kChromeMenuZoneHeight × kChromeMenuZoneHeight)
//   → IconButton(Icons.ios_share, ...)        ← delta 3: icon + enabled gate
//
// Rules enforced here:
//   • Crossfade ONLY: AnimatedOpacity — no Slide/Scale/Rotation/Size transition.
//   • Duration.zero when MediaQuery.disableAnimations is true (EC-11).
//   • Affordance ≥ 48 dp (NFR-02, canon "Promote targets to ≥48dp").
//   • Tooltip + Semantics resolved from ARB key shareTooltip (FR-17, EC-14).
//   • Watches the SAME chromeVisibilityProvider as ChromeOverlay (FR-02).
//   • enabled:false → onPressed:null, ≥48dp footprint retained (FR-05, EC-01).
//   • NOT a Column row; constructs NO ScrollController; calls NO jumpTo/animateTo.
//   • chrome_overlay.dart is NOT modified (anti-pattern rule).
// ---------------------------------------------------------------------------

/// The crossfade duration shared with ChromeOverlay.
///
/// Mirrors [_kChromeFadeDuration] in chrome_overlay.dart — both overlays
/// use the same 200ms fade so they appear and disappear in lockstep (FR-02).
const Duration _kShareFadeDuration = Duration(milliseconds: 200);

/// Chrome container background opacity — canon §2:
/// `color-mix(in srgb, var(--view-bg-color) 90%, transparent)`.
const double _kBgOpacity = 0.9;

/// Auto-hiding share button overlay widget.
///
/// Placed as a [Positioned] top-LEFT child of the editor [Stack] by TASK-09.
/// This is a 1:1 mirror of [ChromeOverlay] with three documented deltas:
///   1. [Positioned] uses `left: 0` (ChromeOverlay places at the opposite edge).
///   2. [Container] radius is `bottomRight` (ChromeOverlay uses the opposite corner).
///   3. [IconButton] uses [Icons.ios_share] and gates [onPressed] on [enabled].
///
/// Watches the same [chromeVisibilityProvider] as [ChromeOverlay] (FR-02).
///
/// [onShareTap] is called when the user taps the share icon (enabled state only).
/// [enabled] controls whether the button is interactive; when false, [onPressed]
/// is null but the ≥48dp footprint is always preserved (FR-05).
class ShareOverlay extends ConsumerWidget {
  const ShareOverlay({
    super.key,
    required this.onShareTap,
    required this.enabled,
  });

  /// Callback invoked when the user taps the share affordance.
  ///
  /// Only fired when [enabled] is true. Wired by TASK-09 to call
  /// [shareTargetServiceProvider].shareText with the live buffer text.
  final VoidCallback onShareTap;

  /// Whether the share button is interactive.
  ///
  /// Set to false when the buffer text is empty (FR-05, EC-01).
  /// The ≥48dp footprint is retained in both states.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(chromeVisibilityProvider);
    final l10n = AppLocalizations.of(context);

    // Collapse animation to zero when the OS reduce-motion flag is set (EC-11).
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : _kShareFadeDuration;

    // Canon §2 background token: view-bg-color at 90% opacity.
    // ColorScheme.surface is the Flutter equivalent of --view-bg-color.
    final bgColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: _kBgOpacity);

    return Positioned(
      top: 0,
      left:
          0, // delta 1: top-LEFT corner (ChromeOverlay places at the opposite edge)
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        // Exclude fully-hidden chrome from hit-testing so the editor
        // beneath remains tappable when chrome is invisible.
        child: IgnorePointer(
          ignoring: !visible,
          child: Semantics(
            label: l10n.shareTooltip,
            button: true,
            excludeSemantics: true,
            child: Tooltip(
              message: l10n.shareTooltip,
              child: Container(
                // Canon §2: surface bg at 90% opacity applied to the chrome box.
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(8), // delta 2: bottomRight
                  ),
                ),
                child: SizedBox(
                  // Enforce ≥48dp tap target (NFR-02, canon mobile promotion).
                  // Sized from shared kChromeMenuZoneHeight so the chrome
                  // button box and the editor top reservation never drift.
                  width: kChromeMenuZoneHeight,
                  height: kChromeMenuZoneHeight,
                  child: IconButton(
                    // delta 3: enabled gate — null onPressed preserves footprint
                    onPressed: enabled ? onShareTap : null,
                    // <!-- CANON GAP: Icons.ios_share — UI bible Iconography has
                    //      no outgoing-share row (OQ-04/OQ-10, user-approved) -->
                    icon: const Icon(Icons.ios_share),
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
