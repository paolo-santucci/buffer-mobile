// ToastOverlay — TASK-13b (M6) + TASK-10 glass restyle.
//
// Spec refs: FR-M6-14, FR-M6-15, NFR-M6-03, EC-04, EC-12, §Components §8
//            FR-28, FR-20, FR-27, NFR-06, EC-08, EC-09
// Canon ref: .claude/docs/canon/ui-design-bible.md §Components §8
//            "Timed notification toast" — Positioned top-centre, crossfade only.
//
// Anatomy (canon §Components §8):
//   Adw.Bin (valign: start, halign: center)
//     → Revealer (transition-type: crossfade)
//       → Box style `app-notification`
//         → Label
//
// Flutter mapping:
//   Positioned(top:, left:0, right:0)   — halign: center via full-width
//     Align(topCenter)
//       AnimatedOpacity                 — crossfade reveal/hide (EC-12)
//         GlassSurface(pillRadius, opacity)  — glass container (TASK-10)
//           Text
//
// EC-04: Positioned overlay — never a Column sibling; never resizes the editor.
// EC-08: GlassSurface high-contrast→opaque branch inherited; no toast-specific logic.
// EC-09: GlassSurface.opacity receives visible ? 1.0 : 0.0 so the unmount-at-zero
//        rule applies when the toast is hidden (BackdropFilter absent at opacity==0).
// EC-12: Under MediaQuery.disableAnimations, crossfade duration collapses to
//        Duration.zero (safe for AnimatedOpacity).
// FR-27: reduce-motion→instant inherited from GlassSurface.
// Motion: AnimatedOpacity only — no SlideTransition, no ScaleTransition.
//
// <!-- CANON GAP: `app-notification` style class is a libadwaita token with no
//      explicit hex mapping in ui-design-bible.md. The bible states the style
//      class name and its placement/behaviour; the concrete colors (background,
//      border, blur) are platform-theme resolved by libadwaita at runtime.
//      Flutter equivalent: GlassSurface(pillRadius) with colorScheme.onSurface
//      text — reuses the glass-surface canon gap from TASK-01 (no new component
//      anatomy; same GlassSurface consumer). See D-003 for --border-color gap
//      precedent. -->

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/presentation/shell/toast_controller.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

/// Top-centre crossfade toast overlay (FR-M6-14/15, §Components §8, FR-28).
///
/// Must be placed as a [Positioned] child inside the [BufferScreen]'s [Stack]
/// (never a [Column] row) so it never resizes the editor (EC-04).
///
/// Watches [toastProvider]; crossfades the message pill in when state is
/// non-null and back out when null. Reduced motion collapses the crossfade
/// to [Duration.zero] (EC-12). The pill is a [GlassSurface] — high-contrast
/// (EC-08) and unmount-at-zero (EC-09) branches are inherited from it.
///
/// **Usage (TASK-12):**
/// ```dart
/// Stack(children: [
///   _buildEditorField(context, spellCheck, editorStyle),
///   const ChromeOverlay(...),
///   const ToastOverlay(),           // ← Positioned top-centre, no resize
/// ])
/// ```
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  // -------------------------------------------------------------------------
  // Motion
  // -------------------------------------------------------------------------

  /// Standard crossfade duration for the toast appear/disappear animation.
  ///
  /// Under [MediaQuery.disableAnimations] this collapses to [Duration.zero]
  /// (EC-12). Using [Duration.zero] is safe for [AnimatedOpacity] — unlike
  /// [AnimatedCrossFade] which triggers a [RenderAnimatedSize] re-dirty
  /// assertion on zero duration.
  static const Duration _kDuration = Duration(milliseconds: 200);

  Duration _animDuration(BuildContext context) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : _kDuration;

  // -------------------------------------------------------------------------
  // Padding / sizing — derived from canon §Components §8 / §Spacing.
  //
  // <!-- CANON GAP: §Components §8 specifies the app-notification style class
  //      but does not enumerate exact padding values for the mobile adaptation.
  //      Using 12dp vertical / 20dp horizontal as a reasonable pill padding
  //      consistent with Material 3 notification/chip conventions. -->
  // -------------------------------------------------------------------------
  static const EdgeInsets _kPadding = EdgeInsets.symmetric(
    horizontal: 20.0,
    vertical: 10.0,
  );

  // Top offset: sits just below the safe-area top edge; the host (TASK-12)
  // wraps the Stack inside SafeArea, so a small fixed offset is sufficient.
  static const double _kTopOffset = 16.0;

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toastMsg = ref.watch(toastProvider);
    final visible = toastMsg != null;
    final animDuration = _animDuration(context);
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;

    return Positioned(
      top: _kTopOffset,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: animDuration,
          child: IgnorePointer(
            ignoring: !visible,
            // GlassSurface pill (FR-28, TASK-10).
            // opacity fed from the logical visibility so the unmount-at-zero
            // rule (EC-09) removes BackdropFilter when the toast is hidden.
            // High-contrast→opaque (EC-08) and reduce-motion (FR-27) are
            // inherited from GlassSurface — no toast-specific branches needed.
            //
            // <!-- CANON GAP: see file-level comment. -->
            child: GlassSurface(
              borderRadius: tokens.pillRadius,
              opacity: visible ? 1.0 : 0.0,
              padding: _kPadding,
              child: Text(
                toastMsg?.text ?? '',
                style: TextStyle(color: colorScheme.onSurface),
                textAlign: TextAlign.center,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
