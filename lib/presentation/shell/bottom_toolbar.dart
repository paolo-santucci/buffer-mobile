// BottomToolbar — floating glass bottom toolbar (C5).
//
// Spec refs: FR-07, FR-15, FR-19, FR-25, FR-26, NFR-04
// Plan refs: TASK-08 (Wave 2), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// <!-- CANON GAP: bottom floating toolbar anatomy
//      The ui-design-bible.md defines no anatomy for a bottom floating toolbar.
//      This implementation binds to cross-cutting tokens only:
//        surface / outlineVariant / onSurfaceVariant — from colorScheme (no hex literals)
//        monochrome-on-theme icons (onSurface foreground)
//        ≥48dp tap targets (IconButton constraints)
//        reduce-motion → Duration.zero (GlassSurface contract)
//      Per-component anatomy is flagged as a canon gap pending OQ-02 bible update. -->
//
// Behavioural contract (C5):
//   - STRICTLY presentational; Ref-free (no provider access of any kind).
//   - Exposes onCopy / onPaste / onFind VoidCallbacks (injection seam, mirrors MenuSheet.onFind).
//   - All three buttons are ALWAYS enabled (FR-15); no-op when nothing to act on is
//     the wired actions' responsibility (TASK-11), not this widget's.
//   - Provider wiring lives ONLY in buffer_screen.dart (TASK-11).
//   - GlassSurface(pillRadius) container (FR-19).
//   - Each button: Semantics(button:true) + Tooltip (ARB-resolved) + ≥48dp (FR-25).

import 'package:flutter/material.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

/// Floating glass bottom toolbar with Copy, Paste, and Find buttons.
///
/// This widget is **strictly presentational**: it holds no provider and no
/// Riverpod reference. Provider wiring (Copy/Paste/Find actions, chrome-visibility
/// gating, find-active swap) lives only in `buffer_screen.dart` (TASK-11).
///
/// All three buttons are always enabled (FR-15). Acting on an empty buffer or
/// empty clipboard is a no-op handled by the wired actions, not by disabling
/// the buttons here.
///
/// ### Usage
/// ```dart
/// BottomToolbar(
///   onCopy: () => Actions.maybeInvoke(context, const CopyIntent()),
///   onPaste: () => Actions.maybeInvoke(context, const PasteAtEndIntent()),
///   onFind: _dispatchOpenFind,
/// )
/// ```
class BottomToolbar extends StatelessWidget {
  const BottomToolbar({
    required this.onCopy,
    required this.onPaste,
    required this.onFind,
    super.key,
  });

  /// Called when the user taps the Copy button.
  /// Wired by TASK-11 to dispatch [CopyIntent].
  final VoidCallback onCopy;

  /// Called when the user taps the Paste button.
  /// Wired by TASK-11 to dispatch [PasteAtEndIntent].
  final VoidCallback onPaste;

  /// Called when the user taps the Find button.
  /// Wired by TASK-11 to call [_dispatchOpenFind].
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;
    final l10n = AppLocalizations.of(context);
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return GlassSurface(
      borderRadius: tokens.pillRadius,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // Deterministic spacing: children are packed from the start.
        // mainAxisSize.min already prevents the Row from expanding beyond
        // its content, so alignment is largely academic here — but pinning
        // it makes the intent explicit and guards against future changes
        // to the default (G6 regression sentinel).
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _ToolbarButton(
            key: const ValueKey('toolbar_copy'),
            icon: Icons.copy_outlined,
            tooltip: l10n.copyTooltip,
            semanticsLabel: l10n.copySemantics,
            onPressed: onCopy,
            iconColor: iconColor,
          ),
          _ToolbarButton(
            key: const ValueKey('toolbar_paste'),
            icon: Icons.content_paste_outlined,
            tooltip: l10n.pasteTooltip,
            semanticsLabel: l10n.pasteSemantics,
            onPressed: onPaste,
            iconColor: iconColor,
          ),
          _ToolbarButton(
            key: const ValueKey('toolbar_find'),
            icon: Icons.search_outlined,
            tooltip: l10n.findTooltip,
            semanticsLabel: l10n.findSemantics,
            onPressed: onFind,
            iconColor: iconColor,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ToolbarButton — single button cell.
//
// Enforces:
//   - Semantics(button:true, label:semanticsLabel, excludeSemantics:true)
//   - Tooltip(message) wrapping the IconButton
//   - ≥48dp tap target via IconButton.constraints (NFR-04/FR-25)
// ---------------------------------------------------------------------------

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.semanticsLabel,
    required this.onPressed,
    required this.iconColor,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final String semanticsLabel;
  final VoidCallback onPressed;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor),
          // Tooltip is provided by the parent Tooltip widget.
          tooltip: null,
          // Enforce ≥48dp tap target (NFR-04/FR-25).
          // constraints: expand fills the 48dp minimum box.
          constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
          padding: const EdgeInsets.all(12.0),
        ),
      ),
    );
  }
}
