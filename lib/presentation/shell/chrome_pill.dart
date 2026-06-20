// ChromePill — single top-right floating glass pill (TASK-06)
//
// Spec refs: FR-01, FR-02, FR-03, FR-16, FR-19, FR-25, NFR-04
// Plan refs: sp-20260617-liquid-glass-floating-chrome-plan.md TASK-06
//
// Supersedes chrome_overlay.dart + share_overlay.dart (twin-mirror retired).
//
// <!-- CANON GAP: merged share+overflow pill anatomy
//      The ui-design-bible.md does not define an anatomy for a merged
//      share+overflow pill. This implementation binds to cross-cutting tokens:
//        surface / outlineVariant / onSurface (via GlassSurface + colorScheme)
//        monochrome-on-theme (Icons.ios_share / Icons.more_horiz)
//        ≥48dp tap targets (NFR-04, FR-25)
//        reduce-motion → Duration.zero (FR-27)
//        crossfade-only animation (no Slide/Scale/Rotation/Size)
//      Per-component pill anatomy is a CANON GAP; routed to the bible via OQ-02. -->
//
// Anatomy:
//   Positioned(top-right)
//   → AnimatedOpacity (crossfade; Duration.zero under reduce-motion)
//   → IgnorePointer (ignoring: !visible)
//   → CompositedTransformTarget (link: widget.layerLink — injected by parent)
//   → GlassSurface(borderRadius: tokens.pillRadius)
//   → Row [
//       share IconButton (onPressed: null when buffer empty/whitespace — FR-03)
//       overflow … IconButton (always enabled)
//     ]
//
// Rules enforced here:
//   • Crossfade ONLY — AnimatedOpacity; no Slide/Scale/Rotation/Size.
//   • Duration.zero when MediaQuery.disableAnimations (reduce-motion gate).
//   • Both buttons ≥ 48dp (NFR-04, FR-25).
//   • Tooltip + Semantics (button:true) on both buttons (FR-25).
//   • share button: onPressed=null when bufferProvider text empty/whitespace (FR-03).
//   • share_plus throws on empty text — guard via onPressed gate, not try/catch.
//   • onOverflow callback: called when user taps …; popover mounting is NOT done here
//     (TASK-11 is the composition root for popover open).
//   • layerLink is INJECTED by the parent (TASK-11 owns + passes it); the same
//     instance is passed to openOverflowPopover(ctx, anchorLink:) so the popover
//     can follow the pill without a GlobalKey on private State.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/editor/editor_layout.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/shell/chrome_reveal_controller.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

// ---------------------------------------------------------------------------
// Internal constants
// ---------------------------------------------------------------------------

/// Crossfade duration for the chrome reveal/hide transition.
///
/// Mirrors the prior overlay constant (200ms Material fade — unobtrusive).
const Duration _kChromeFadeDuration = Duration(milliseconds: 200);

/// Side length (in dp) of each icon button within the pill.
///
/// Must be ≥ 48dp per NFR-04 / FR-25.
const double _kButtonSize = 48.0;

/// Inner padding around the pill content.
///
/// Kept minimal so the pill footprint stays compact. The ≥48dp guarantee
/// is fulfilled by [SizedBox], not padding.
const EdgeInsets _kPillPadding = EdgeInsets.zero;

// ---------------------------------------------------------------------------
// ChromePill widget
// ---------------------------------------------------------------------------

/// Single top-right floating glass pill (TASK-06).
///
/// Contains:
///   • A share [IconButton] — disabled when [bufferProvider] text is
///     empty or whitespace (FR-03; `share_plus` throws on empty).
///   • An always-enabled overflow `…` [IconButton] that calls [onOverflow].
///
/// Both buttons are ≥48dp, carry [Semantics](button:true), and have a
/// [Tooltip] sourced from the localization system (FR-25).
///
/// Visibility is driven by [chromeVisibilityProvider] via [AnimatedOpacity] +
/// [IgnorePointer] (FR-16). The [layerLink] is injected by the parent
/// (composition root TASK-11), which passes the same instance to
/// [openOverflowPopover] / [openMenuSheet] so the popover can track the pill
/// without requiring a [GlobalKey] on private State.
///
/// [onOverflow] is the sole point of contact for opening the popover; this
/// widget does NOT mount the popover (that is TASK-11's responsibility).
class ChromePill extends ConsumerStatefulWidget {
  const ChromePill({
    super.key,
    required this.layerLink,
    required this.onOverflow,
  });

  /// [LayerLink] owned by the parent (composition root TASK-11).
  ///
  /// Used as the [CompositedTransformTarget.link] anchor so the parent can
  /// pass the same instance to [openOverflowPopover] / [openMenuSheet] and
  /// position the popover relative to this pill.
  final LayerLink layerLink;

  /// Callback invoked when the user taps the `…` overflow button.
  ///
  /// Popover mounting is the composition root's responsibility (TASK-11).
  /// This widget fires the callback only.
  final VoidCallback onOverflow;

  @override
  ConsumerState<ChromePill> createState() => _ChromePillState();
}

class _ChromePillState extends ConsumerState<ChromePill> {
  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(chromeVisibilityProvider);
    final bufferText = ref.watch(bufferProvider).text;
    final l10n = AppLocalizations.of(context);
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;

    // Reduce-motion: collapse animation to Duration.zero (FR-27).
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _kChromeFadeDuration;

    // Share gate: null when buffer empty/whitespace (FR-03).
    // share_plus throws ArgumentError on empty text — guard at this level.
    final shareEnabled = bufferText.trim().isNotEmpty;

    // Safe-area top: float the pill below the notch/status-bar (FR-01, EC-09).
    // kChromePillTopGap (= kChromeTopGap/3 ≈ 5.333dp) pulls the pill closer to
    // the top edge than the old kChromeTopGap (16dp) — Fix 1 (TASK-05, FR-01).
    // The find-back-pill in buffer_screen.dart keeps kChromeTopGap (FR-03).
    // safeAreaTop ensures the pill never overlaps the system status bar.
    //
    // <!-- CANON GAP: pill top-offset value not in ui-design-bible.md anatomy;
    //      kChromePillTopGap = kChromeTopGap/3 derived from spec §4 Fix 1 —
    //      routed to next /canon-bootstrap pass (OQ-02). -->
    final safeAreaTop = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: kChromePillTopGap + safeAreaTop,
      right: kChromeSideMargin,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: duration,
        child: IgnorePointer(
          ignoring: !visible,
          child: CompositedTransformTarget(
            link: widget.layerLink,
            child: GlassSurface(
              borderRadius: tokens.pillRadius,
              padding: _kPillPadding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildShareButton(context, l10n, shareEnabled),
                  _buildOverflowButton(context, l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareButton(
    BuildContext context,
    AppLocalizations l10n,
    bool shareEnabled,
  ) {
    return Semantics(
      button: true,
      label: l10n.shareTooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: l10n.shareTooltip,
        child: SizedBox(
          width: _kButtonSize,
          height: _kButtonSize,
          child: IconButton(
            // null when buffer empty/whitespace — prevents share_plus throw (FR-03).
            onPressed: shareEnabled ? _onShare : null,
            // <!-- CANON GAP: Icons.ios_share — user-approved OQ-10 -->
            icon: const Icon(Icons.ios_share),
            tooltip: null, // provided by parent Tooltip
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.expand(),
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowButton(BuildContext context, AppLocalizations l10n) {
    return Semantics(
      button: true,
      label: l10n.menuTooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: l10n.menuTooltip,
        child: SizedBox(
          width: _kButtonSize,
          height: _kButtonSize,
          child: IconButton(
            onPressed: widget.onOverflow,
            icon: const Icon(Icons.more_horiz),
            tooltip: null, // provided by parent Tooltip
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.expand(),
          ),
        ),
      ),
    );
  }

  void _onShare() {
    final text = ref.read(bufferProvider).text;
    final service = ref.read(shareTargetServiceProvider);
    service.shareText(text);
  }
}
