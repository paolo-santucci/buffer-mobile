// OverflowPopover — anchored glass popover bubble (TASK-07, Wave 2)
//
// Spec refs: FR-04, FR-05, FR-06, FR-19
// Plan refs: TASK-07, sp-20260617-liquid-glass-floating-chrome-plan.md
//
// Component C6: a CompositedTransformFollower hosted in an OverlayEntry,
// wrapping the menu body in GlassSurface(popoverRadius).
//
// The pill → popover trigger is wired in TASK-11 (Wave 3). This file delivers
// the popover widget + open/dismiss/entry behaviour in isolation.
//
// Navigation pattern (Ref-free, reused from menu_sheet.dart):
//   - Pop the overlay entry (dismiss the popover).
//   - Then pushNamed via the hostContext captured at open time.
//   This preserves the pop-then-pushNamed nav seam from the former bottom-sheet.
//
// Outside-tap dismiss (FR-06 / EC-15):
//   An opaque full-screen GestureDetector is stacked BEHIND the follower.
//   Tapping the barrier removes the OverlayEntry and selects nothing.
//
// <!-- CANON GAP: anchored popover bubble anatomy + outside-tap-dismiss rule
//      ui-design-bible.md does not define the anatomy or dismiss behaviour for
//      anchored popover bubbles. Implementation binds to surface/outlineVariant
//      (via GlassSurface), GlassTokens.popoverRadius, and ≥48dp entries.
//      Flag for upstream bible amendment per OQ-17. -->

import 'package:flutter/material.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/shell/theme_selector.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';
import 'package:foglietto/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Vertical gap (logical px) between the anchor widget and the popover top.
///
/// C6 anchor geometry: followerAnchor = topRight, targetAnchor = bottomRight,
/// offset = Offset(0, kPopoverGap).
const double kPopoverGap = 8.0;

// ---------------------------------------------------------------------------
// openOverflowPopover — public entry point
// ---------------------------------------------------------------------------

/// Opens the overflow menu as a floating anchored popover bubble.
///
/// [anchorLink] must be the [LayerLink] attached to the pill's
/// [CompositedTransformTarget]. The popover is positioned below the pill's
/// bottom-right corner.
///
/// Returns an **idempotent** dismiss callback — safe to call multiple times.
/// All internal dismissal paths (outside-tap barrier, the 3 menu tiles) AND
/// the returned callback funnel through ONE closure that:
///   1. Removes the [OverlayEntry] **guarded** — a `bool` latch ensures
///      `entry.remove()` is called at most once, avoiding the Flutter
///      `assert(_overlay != null, 'An OverlayEntry should be removed only
///      once.')` on the second call.
///   2. Invokes [onDismissed] exactly once per open, on EVERY dismissal
///      path (barrier, menu tile, or programmatic caller).
///
/// [onDismissed] is fired AFTER the guarded removal. Use it to clear the
/// host's programmatic-dismiss latch on every path (BUG-B fix).
///
/// [onFind] is kept for API symmetry with the former [openMenuSheet] but is
/// **not** used — the Find/Replace tile is absent from the popover (FR-05).
VoidCallback openOverflowPopover(
  BuildContext context, {
  required LayerLink anchorLink,
  VoidCallback? onDismissed,
  // ignore: avoid_unused_constructor_parameters — kept for API symmetry;
  // Find tile absent from popover per FR-05.
  VoidCallback? onFind,
}) {
  late OverlayEntry entry;
  var dismissed = false;

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
    onDismissed?.call();
  }

  entry = OverlayEntry(
    builder: (overlayContext) => _PopoverOverlayContent(
      anchorLink: anchorLink,
      hostContext: context,
      onDismiss: dismiss,
    ),
  );

  Overlay.of(context).insert(entry);
  return dismiss;
}

// ---------------------------------------------------------------------------
// OverflowPopover — public widget (the bubble itself)
//
// This widget is the detectable "handle" for find.byType(OverflowPopover) in
// tests (OQ-12). It is the root widget of the OverlayEntry builder chain.
// ---------------------------------------------------------------------------

/// The visible root of the overflow popover overlay.
///
/// Stacks:
///   1. Full-screen transparent GestureDetector (barrier — behind the bubble).
///   2. CompositedTransformFollower → GlassSurface → menu body.
///
/// Tests locate the popover via `find.byType(OverflowPopover)` (OQ-12).
class OverflowPopover extends StatelessWidget {
  const OverflowPopover({
    required this.anchorLink,
    required this.hostContext,
    required this.onDismiss,
    super.key,
  });

  /// LayerLink from the pill's CompositedTransformTarget.
  final LayerLink anchorLink;

  /// BuildContext of the screen that opened the popover.
  ///
  /// Navigation calls (pushNamed) go through this context so that named routes
  /// resolve via the app's root Navigator (pop-then-pushNamed seam).
  final BuildContext hostContext;

  /// Callback invoked to remove this OverlayEntry.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // The OverlayEntry renders above the MaterialApp's Scaffold, so there
    // is no Material ancestor for ListTile / IconButton. Wrap in Material
    // with type = transparency so it provides the required ancestor without
    // adding visual chrome of its own. The GlassSurface provides the
    // visual container.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // -----------------------------------------------------------------
          // Barrier — full-screen, opaque GestureDetector behind the bubble.
          // Intercepts outside taps and dismisses the popover (FR-06/EC-15).
          // behavior: HitTestBehavior.opaque ensures the barrier catches taps
          // even when the underlying content is transparent.
          // -----------------------------------------------------------------
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),

          // -----------------------------------------------------------------
          // Bubble — anchored to the pill via CompositedTransformFollower.
          // targetAnchor: bottomRight  → follower origin at the anchor's
          //   bottom-right corner.
          // followerAnchor: topRight   → bubble's top-right aligns to origin.
          // offset: Offset(0, kPopoverGap) → drop the bubble by kPopoverGap.
          // -----------------------------------------------------------------
          CompositedTransformFollower(
            link: anchorLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, kPopoverGap),
            child: _PopoverBubble(
              hostContext: hostContext,
              onDismiss: onDismiss,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PopoverOverlayContent — wires OverflowPopover into the OverlayEntry
// ---------------------------------------------------------------------------

class _PopoverOverlayContent extends StatelessWidget {
  const _PopoverOverlayContent({
    required this.anchorLink,
    required this.hostContext,
    required this.onDismiss,
  });

  final LayerLink anchorLink;
  final BuildContext hostContext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return OverflowPopover(
      anchorLink: anchorLink,
      hostContext: hostContext,
      onDismiss: onDismiss,
    );
  }
}

// ---------------------------------------------------------------------------
// _PopoverBubble — the glass-wrapped menu body
// ---------------------------------------------------------------------------

/// The visible glass bubble containing the menu entries.
///
/// Entry set (FR-05): ThemeSelector, FontSizeStepper, Preferences, About,
/// Recovery. NO Find/Replace tile (Find moved to the bottom toolbar).
///
/// Each navigation tile pops the popover first, then pushes the named route
/// via [hostContext] (pop-then-pushNamed seam, reused from menu_sheet.dart).
class _PopoverBubble extends StatelessWidget {
  const _PopoverBubble({required this.hostContext, required this.onDismiss});

  final BuildContext hostContext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;

    // Constrain width so the bubble does not span the full screen.
    // 280 dp is a comfortable reading width for the menu entries.
    // The column is wrapped in a SingleChildScrollView to handle edge cases
    // where the screen is very short (e.g. default 800×600 test viewport).
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: GlassSurface(
        borderRadius: tokens.popoverRadius,
        // ClipRRect clips the Material's ink splashes to the popover radius.
        child: ClipRRect(
          borderRadius: tokens.popoverRadius,
          // Transparent Material so ListTile ink splashes paint on this
          // surface rather than the outer OverflowPopover Material, avoiding
          // the "DecoratedBox hides ink splash" Flutter assertion.
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // -------------------------------------------------------
                    // ThemeSelector
                    // -------------------------------------------------------
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      child: const ThemeSelector(),
                    ),

                    // -------------------------------------------------------
                    // FontSizeStepper (FR-05, FR-M7-06)
                    // -------------------------------------------------------
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      child: FontSizeStepper(),
                    ),

                    const Divider(height: 1),

                    // -------------------------------------------------------
                    // Preferences → /settings
                    // Touch target: ListTile default >= 56dp (NFR-04, FR-25)
                    // -------------------------------------------------------
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(l10n.menuPreferences),
                      onTap: () {
                        onDismiss();
                        Navigator.of(hostContext).pushNamed('/settings');
                      },
                    ),

                    // -------------------------------------------------------
                    // About → /about
                    // -------------------------------------------------------
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(l10n.menuAbout),
                      onTap: () {
                        onDismiss();
                        Navigator.of(hostContext).pushNamed('/about');
                      },
                    ),

                    // -------------------------------------------------------
                    // Recovery → /recovery
                    // -------------------------------------------------------
                    ListTile(
                      leading: const Icon(Icons.history_outlined),
                      title: Text(l10n.menuRecovery),
                      onTap: () {
                        onDismiss();
                        Navigator.of(hostContext).pushNamed('/recovery');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
