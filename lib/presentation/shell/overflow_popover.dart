// OverflowPopover — anchored glass popover bubble with morph open/dismiss
//
// Spec refs: FR-04, FR-05, FR-06, FR-07, FR-08, FR-19, NFR-06, NFR-07
// Plan refs: TASK-04 (Wave 1 morph rewrite),
//            qp-20260620-overflow-popover-morph-rework.md
//            sp-20260620-ui-chrome-morph-transparency-spacing-plan.md
//            TASK-07 (original), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// Component C6: a CompositedTransformFollower hosted in an OverlayEntry,
// wrapping the menu body in GlassSurface(popoverRadius) with a dual-axis clip morph.
//
// The pill → popover trigger is wired in buffer_screen.dart (TASK-07/Wave 3).
// This file delivers the popover widget + open/dismiss/entry behaviour in
// isolation.
//
// Navigation pattern (Ref-free, reused from menu_sheet.dart):
//   - Pop the overlay entry (dismiss the popover).
//   - Then pushNamed via the hostContext captured at open time.
//   This preserves the pop-then-pushNamed nav seam from the former bottom-sheet.
//
// Outside-tap dismiss (FR-07 / EC-15):
//   An opaque full-screen GestureDetector is stacked BEHIND the follower.
//   Tapping the barrier triggers the async dismiss funnel.
//
// Morph (FR-04/FR-05):
//   _MorphedBubble drives a single AnimationController (260ms open /
//   160ms reverseDuration close) on Curves.fastEaseInToSlowEaseOut.
//   An AnimatedBuilder drives four transforms outside-in:
//     (a) ClipRRect — borderRadius lerps from tokens.pillRadius (32dp) to
//         tokens.popoverRadius (16dp), clipping the GlassSurface BackdropFilter
//         blur boundary to the morphing shape (C-05).
//     (b) SizedBox — width lerps from _kPillWidth (96dp) to _kBubbleWidth (280dp),
//         anchored topRight; inner _PopoverBubble wrapped in OverflowBox so
//         sub-200dp frames cannot throw RenderFlex overflow (C-06).
//     (c) Align(alignment: topRight, heightFactor: t) — height reveal.
//     (d) Opacity — content fades in from t=_kContentFadeStart (0.4).
//   On open: forward(). On dismiss: reverseOut() → awaits completion → remove.
//
// <!-- CANON GAP: morph-motion exception for off-anatomy popover;
//      per spec §4 CANON PARTIAL / OQ-03. The dual-axis clip morph is a
//      deliberate exception to the bible §Motion crossfade-only ethos. -->
//
// <!-- CANON GAP: anchored popover bubble anatomy + outside-tap-dismiss rule
//      ui-design-bible.md does not define the anatomy or dismiss behaviour for
//      anchored popover bubbles. Implementation binds to surface/outlineVariant
//      (via GlassSurface), GlassTokens.popoverRadius, and ≥48dp entries.
//      Flag for upstream bible amendment per OQ-17. -->

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/shell/theme_selector.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';
import 'package:foglietto/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// Private constants
// ---------------------------------------------------------------------------

/// Open duration for the dual-axis clip morph (forward pass).
///
/// Under reduce-motion (MediaQuery.disableAnimations) both durations are set
/// to Duration.zero so the popover opens and dismisses instantly.
const Duration _kMorphOpenDuration = Duration(milliseconds: 260);

/// Close/reverse duration for the dual-axis clip morph (reverse pass).
const Duration _kMorphCloseDuration = Duration(milliseconds: 160);

/// Width of the pill in logical pixels (2 × _kButtonSize from chrome_pill.dart:64 = 48.0).
/// Keep in sync with `_kButtonSize` in `chrome_pill.dart`.
const double _kPillWidth = 96.0;

/// Width of the expanded popover bubble in logical pixels.
/// Matches the maxWidth in _PopoverBubble's ConstrainedBox.
const double _kBubbleWidth = 280.0;

/// Content fade start threshold (controller value t).
/// Opacity of the popover content = ((t - _kContentFadeStart) / 0.6).clamp(0,1).
const double _kContentFadeStart = 0.4;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Vertical gap (logical px) between the anchor widget and the popover top.
///
/// TASK-04: Gap is now 0.0 — the morph grows FROM the pill's top-right corner.
/// Kept as a named constant for source-scan compatibility and potential future use.
const double kPopoverGap = 0.0;

// ---------------------------------------------------------------------------
// openOverflowPopover — public entry point
// ---------------------------------------------------------------------------

/// Opens the overflow menu as a floating anchored popover bubble with a
/// scale+fade morph that grows out of the pill's top-right corner.
///
/// [anchorLink] must be the [LayerLink] attached to the pill's
/// [CompositedTransformTarget]. The popover morphs from the pill's top-right.
///
/// Returns an **idempotent** dismiss callback — safe to call multiple times.
/// All internal dismissal paths (outside-tap barrier, the 3 menu tiles) AND
/// the returned callback funnel through ONE async closure that:
///   1. Reverse-animates (collapses back into pill corner) before removal.
///   2. Removes the [OverlayEntry] **guarded** — a `bool` latch ensures
///      `entry.remove()` is called at most once.
///   3. Invokes [onDismissed] exactly once per open, on EVERY dismissal path.
///
/// The returned [VoidCallback] is fire-and-forget; the async reverse runs
/// internally without blocking the caller.
///
/// [onDismissed] is fired AFTER guarded removal (BUG-B fix from qp-20260619).
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
  var dismissing = false;

  // Morph bubble key — used by dismiss() to call reverseOut() on the morph state.
  final morphKey = GlobalKey<_MorphedBubbleState>();

  // Async dismiss funnel — all paths route through here.
  // Fire-and-forget from the public VoidCallback; the async reverse runs on the
  // animation ticker without blocking.
  Future<void> dismissAsync() async {
    if (dismissing) return;
    dismissing = true;
    await morphKey.currentState?.reverseOut();
    if (entry.mounted) entry.remove();
    onDismissed?.call();
  }

  // Fire-and-forget wrapper — the public VoidCallback signature stays unchanged.
  void dismiss() => dismissAsync();

  entry = OverlayEntry(
    builder: (overlayContext) => _PopoverOverlayContent(
      anchorLink: anchorLink,
      hostContext: context,
      onDismiss: dismiss,
      morphKey: morphKey,
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
///   2. CompositedTransformFollower → _MorphedBubble → GlassSurface → menu body.
///
/// Tests locate the popover via `find.byType(OverflowPopover)` (OQ-12).
class OverflowPopover extends StatelessWidget {
  const OverflowPopover({
    required this.anchorLink,
    required this.hostContext,
    required this.onDismiss,
    required this.morphBubble,
    super.key,
  });

  /// LayerLink from the pill's CompositedTransformTarget.
  final LayerLink anchorLink;

  /// BuildContext of the screen that opened the popover.
  ///
  /// Navigation calls (pushNamed) go through this context so that named routes
  /// resolve via the app's root Navigator (pop-then-pushNamed seam).
  final BuildContext hostContext;

  /// Callback invoked to start the async dismiss sequence.
  final VoidCallback onDismiss;

  /// The morph bubble widget (already keyed by the overlay content).
  /// Passed as a pre-built child to avoid exposing the private State type in
  /// the public constructor (library_private_types_in_public_api).
  final Widget morphBubble;

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
          // Intercepts outside taps and triggers the async dismiss (FR-07/EC-15).
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
          //
          // TASK-04 MORPH ANCHOR (FR-04):
          //   targetAnchor: topRight  → follower origin at pill's top-right.
          //   followerAnchor: topRight → bubble's top-right aligns to origin.
          //   offset: Offset.zero → no gap; morph grows from pill's corner.
          //
          // (Old: targetAnchor=bottomRight, followerAnchor=topRight,
          //        offset=Offset(0, kPopoverGap=8) — bubble dropped 8dp below)
          // -----------------------------------------------------------------
          CompositedTransformFollower(
            link: anchorLink,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.topRight,
            offset: Offset.zero,
            child: morphBubble,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PopoverOverlayContent — wires OverflowPopover into the OverlayEntry.
//
// Holds the GlobalKey<_MorphedBubbleState> internally so the private type
// never appears in OverflowPopover's public constructor
// (library_private_types_in_public_api guard).
// ---------------------------------------------------------------------------

class _PopoverOverlayContent extends StatelessWidget {
  // GlobalKey<_MorphedBubbleState> is mutable — const constructor is impossible.
  // ignore: prefer_const_constructors_in_immutables
  _PopoverOverlayContent({
    required this.anchorLink,
    required this.hostContext,
    required this.onDismiss,
    required this.morphKey,
  });

  final LayerLink anchorLink;
  final BuildContext hostContext;
  final VoidCallback onDismiss;

  // Received from openOverflowPopover — the dismiss funnel holds this key
  // to call reverseOut() before removing the entry.
  final GlobalKey<_MorphedBubbleState> morphKey;

  @override
  Widget build(BuildContext context) {
    return OverflowPopover(
      anchorLink: anchorLink,
      hostContext: hostContext,
      onDismiss: onDismiss,
      morphBubble: _MorphedBubble(
        key: morphKey,
        hostContext: hostContext,
        onDismiss: onDismiss,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MorphedBubble — dual-axis clip morph wrapper for _PopoverBubble
//
// CANON GAP: morph-motion exception for off-anatomy popover;
// per spec §4 CANON PARTIAL / OQ-03. The dual-axis clip morph is a deliberate
// exception to the bible §Motion crossfade-only ethos. One AnimationController
// at 260ms open / 160ms reverseDuration close on fastEaseInToSlowEaseOut drives:
//   (a) ClipRRect radius lerp (tokens.pillRadius 32dp → tokens.popoverRadius 16dp)
//   (b) SizedBox width lerp (_kPillWidth 96dp → _kBubbleWidth 280dp) + OverflowBox guard
//   (c) Align(topRight, heightFactor: t) for height reveal
//   (d) Opacity content fade from t=_kContentFadeStart (0.4)
// ---------------------------------------------------------------------------

class _MorphedBubble extends StatefulWidget {
  const _MorphedBubble({
    super.key,
    required this.hostContext,
    required this.onDismiss,
  });

  final BuildContext hostContext;
  final VoidCallback onDismiss;

  @override
  State<_MorphedBubble> createState() => _MorphedBubbleState();
}

class _MorphedBubbleState extends State<_MorphedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _forwardStarted = false;

  @override
  void initState() {
    super.initState();
    // Create with default open duration; didChangeDependencies updates both
    // duration and reverseDuration before the first build.
    _controller = AnimationController(
      vsync: this,
      duration: _kMorphOpenDuration,
      reverseDuration: _kMorphCloseDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is available here (not in initState).
    // Duration.zero under reduce-motion (disableAnimations) — guard/latch unchanged.
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _controller.duration = disableAnimations
        ? Duration.zero
        : _kMorphOpenDuration;
    _controller.reverseDuration = disableAnimations
        ? Duration.zero
        : _kMorphCloseDuration;

    // Forward immediately on first mount — morph open (FR-04).
    if (!_forwardStarted) {
      _forwardStarted = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reverses the morph animation and returns a Future that completes when
  /// the controller reaches the dismissed state (value == 0.0).
  ///
  /// Called by the dismiss funnel in [openOverflowPopover] before removing
  /// the OverlayEntry (FR-05 — collapse before remove).
  Future<void> reverseOut() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;

    // CurvedAnimation on the forward pass; auto-inverted on reverse.
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.fastEaseInToSlowEaseOut,
    );

    // Single AnimatedBuilder drives all four morph transforms.
    // Composition order (outside-in):
    //   (a) ClipRRect — lerped radius clips the GlassSurface BackdropFilter
    //       blur boundary to the morphing shape (C-05 / NFR-10).
    //   (b) Align(topRight, heightFactor: t) — height reveal from 0 → full.
    //   (c) SizedBox — width lerp anchored topRight; OverflowBox prevents
    //       RenderFlex overflow on sub-200dp frames (C-06).
    //   (d) Opacity — content fades in after t reaches _kContentFadeStart.
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;
        final radius = BorderRadius.lerp(
          tokens.pillRadius,
          tokens.popoverRadius,
          t,
        )!;
        final width = lerpDouble(_kPillWidth, _kBubbleWidth, t)!;
        final contentOpacity = ((t - _kContentFadeStart) / 0.6).clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: radius,
          child: Align(
            alignment: Alignment.topRight,
            heightFactor: t,
            child: SizedBox(
              width: width,
              child: OverflowBox(
                minWidth: 0,
                maxWidth: _kBubbleWidth,
                alignment: Alignment.topRight,
                child: Opacity(
                  opacity: contentOpacity,
                  child: _PopoverBubble(
                    hostContext: widget.hostContext,
                    onDismiss: widget.onDismiss,
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
