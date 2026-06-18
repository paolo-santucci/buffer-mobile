// TASK-08 (M4): FindSearchBar — mobile search-bar widget.
// TASK-09 (Wave 2): Container restyled to GlassSurface(pillRadius).
//
// Spec refs: FR-12, FR-13, FR-15, FR-18, FR-19, FR-20; NFR-06, NFR-07
// Canon ref: .claude/docs/canon/ui-design-bible.md Component 4
//            "Search header bar" mobile adaptation.
//
// Anatomy (Component 4 mobile — upstream GNOME Buffer search bar):
//   A GlassSurface pill container (TASK-09) wrapping:
//   Row 1: [back] [filled rounded search pill + leading glyph] [count 0.58]
//          [prev] [next] [replace toggle]
//   Row 2 (AnimatedCrossFade, hidden by default):
//          [aligned filled rounded replace pill] [accent-filled Replace button]
//
// Positioning (top → bottom) and the toolbar↔find-pill swap belong to TASK-11.
// Only the container surface treatment changes in TASK-09.
//
// All user-facing strings via AppLocalizations — no literal Text('...') in this file.
// <!-- CANON GAP: bottom find pill anatomy — the ui-design-bible.md does not define
//      the anatomy of the bottom find pill (exact padding, inner field radii, button
//      layout). Container binds to surface/outlineVariant/onSurfaceVariant tokens
//      via GlassSurface; per-pill internals deferred to TASK-11 refinement. -->
// <!-- CANON GAP: OQ-06 — search-highlight colour (primaryContainer/secondaryContainer)
//      is resolved theme-driven; not a gap owned by this widget. See TASK-05. -->

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/find/find_provider.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

/// Mobile search-bar widget for find/replace (FR-18 / UI bible Component 4).
///
/// Reads [findProvider] directly and calls its verb methods on user
/// interactions. Mounts replace row via [AnimatedCrossFade] (crossfade-only,
/// reduce-motion aware). All strings resolve through [AppLocalizations].
///
/// Does NOT mount itself into [buffer_screen.dart] (TASK-07 owns that) and
/// does NOT implement scroll/focus restore (also TASK-07).
///
/// **Integration seams wired by TASK-07:**
///
/// [onReplace] — called when the user taps the Replace button. The caller
/// (buffer_screen.dart) receives this notification and routes the replace
/// through the M3 [_applyResult] atomic-rewrite path. The widget still
/// calls [findProvider.notifier.replaceCurrent()] itself; this callback is
/// an additional notification for the screen to intercept the result (§5.2).
///
/// [onToggleReplace] — called when the replace-row toggle fires, allowing
/// the Ctrl+H keyboard shortcut in [ToggleReplaceAction] to drive the
/// same UI state as the on-screen toggle button (FR-21 single-path).
class FindSearchBar extends ConsumerStatefulWidget {
  const FindSearchBar({
    super.key,
    this.onReplace,
    this.focusNode,
    this.replaceRowNotifier,
  });

  /// Called when the user taps the Replace button. The caller (buffer_screen.dart)
  /// receives this notification and routes the replace through the M3
  /// [_applyResult] atomic-rewrite path (NFR-04 / §5.2 / TASK-07).
  ///
  /// When this callback is provided, the widget does NOT call
  /// [replaceCurrent()] itself — the caller is responsible for the full
  /// replace flow. When null, [replaceCurrent()] is called directly (for
  /// standalone widget testing without a screen wrapper).
  final VoidCallback? onReplace;

  /// Optional [FocusNode] to control search-field focus from outside (FR-22).
  /// When null, the widget manages its own internal focus.
  final FocusNode? focusNode;

  /// Optional external controller for the replace-row visibility.
  ///
  /// When provided, the widget reads/writes this notifier to sync the replace
  /// row visibility with the parent screen. Allows [ToggleReplaceAction]
  /// (Ctrl+H) to drive replace-row state from outside the widget (FR-21).
  /// When null, the widget manages its own internal [_replaceVisible] state.
  final ValueNotifier<bool>? replaceRowNotifier;

  @override
  ConsumerState<FindSearchBar> createState() => _FindSearchBarState();
}

class _FindSearchBarState extends ConsumerState<FindSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  /// Internal replace-row visibility state (used when [widget.replaceRowNotifier]
  /// is null). When the notifier is provided, external state is used instead.
  bool _replaceVisibleInternal = false;

  /// Whether the replace row is currently visible (reads external notifier
  /// when provided, falls back to internal flag).
  bool get _replaceVisible =>
      widget.replaceRowNotifier?.value ?? _replaceVisibleInternal;

  @override
  void initState() {
    super.initState();
    // Listen to external notifier changes to rebuild when Ctrl+H toggles
    // the replace row from outside (FR-21 / ToggleReplaceAction).
    widget.replaceRowNotifier?.addListener(_onExternalReplaceToggle);
  }

  @override
  void dispose() {
    widget.replaceRowNotifier?.removeListener(_onExternalReplaceToggle);
    _searchController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  /// Called when the external [replaceRowNotifier] changes (Ctrl+H path).
  void _onExternalReplaceToggle() => setState(() {});

  // ---------------------------------------------------------------------------
  // Interactions
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String value) {
    ref.read(findProvider.notifier).setQuery(value);
  }

  void _onPrevious() {
    ref.read(findProvider.notifier).previous();
  }

  void _onNext() {
    ref.read(findProvider.notifier).next();
  }

  /// Toggles the replace row visibility.
  ///
  /// When [widget.replaceRowNotifier] is provided, updates the external
  /// notifier (which rebuilds this widget via the listener). When not
  /// provided, updates the internal [_replaceVisibleInternal] flag.
  ///
  /// Called by the on-screen toggle button. The Ctrl+H path toggles
  /// [widget.replaceRowNotifier] directly from the screen (FR-21 / TASK-07).
  void _onToggleReplace() {
    if (widget.replaceRowNotifier != null) {
      // External notifier: flip its value. The listener calls setState.
      widget.replaceRowNotifier!.value = !widget.replaceRowNotifier!.value;
    } else {
      setState(() => _replaceVisibleInternal = !_replaceVisibleInternal);
    }
  }

  void _onReplaceTermChanged(String value) {
    ref.read(findProvider.notifier).setReplaceTerm(value);
  }

  void _onReplace() {
    // Notify the screen (buffer_screen.dart) to apply the replace via
    // _applyResult. The screen's onReplace callback calls replaceCurrent()
    // and pipes the record to _applyResult; this widget does NOT duplicate
    // that call to avoid a double-mutation (NFR-04 / §5.2).
    //
    // If no onReplace is wired (standalone search-bar widget test), the
    // notifier is called directly so the widget remains independently testable.
    if (widget.onReplace != null) {
      widget.onReplace!();
    } else {
      ref.read(findProvider.notifier).replaceCurrent();
    }
  }

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

  /// Returns the crossfade duration honouring reduce-motion (NFR-07 / bible Motion).
  ///
  /// When [MediaQuery.disableAnimations] is true we use 1 ms rather than
  /// Duration.zero to avoid the RenderAnimatedSize re-dirty assertion that
  /// fires when AnimatedCrossFade receives an exactly-zero duration during
  /// layout. 1 ms is perceptually instant and passes in tests with a single
  /// extra pump().
  Duration _crossfadeDuration(BuildContext context) {
    final disable = MediaQuery.of(context).disableAnimations;
    return disable
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 200);
  }

  /// Builds a 48×48 icon button with a tooltip (= semantic label for TalkBack).
  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 48.0,
      height: 48.0,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
        // Padding removed so the entire 48×48 SizedBox is the hit target.
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
      ),
    );
  }

  /// Count label text: empty when count == 0, otherwise ICU expansion
  /// of `{position} of {count}` (FR-12).
  String _countLabelText(AppLocalizations l10n, int? position, int count) {
    if (count == 0 || position == null) return '';
    return l10n.findCountLabel(position, count);
  }

  /// Pill border radius for the search / replace entry fields and the Replace
  /// button (upstream GNOME Buffer uses fully-rounded search entries).
  static const double _kPillRadius = 22.0;

  /// Square size of each icon-only control (back / prev / next / toggle).
  static const double _kIconBtnSize = 48.0;

  /// Width of the trailing control cluster on each row: three icon buttons on
  /// the search row, and the Replace button (boxed to the same width) on the
  /// replace row. Reserving the SAME trailing width on both rows — together
  /// with the matching leading column — makes the two pills exactly equal width.
  static const double _kTrailingClusterWidth = _kIconBtnSize * 3;

  /// Filled, fully-rounded "pill" decoration for the search / replace entries.
  ///
  /// Mirrors the upstream search bar: a soft grey rounded field with a leading
  /// glyph and no hard border, gaining a 1.5 px accent ring on focus.
  /// An optional [suffixIcon] hosts the in-field match-count label so it does
  /// not eat into the search pill's width.
  InputDecoration _pillDecoration(
    ThemeData theme, {
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kPillRadius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20.0),
      prefixIconConstraints: const BoxConstraints(minWidth: 40.0, minHeight: 0),
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 10.0,
        horizontal: 8.0,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kPillRadius),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final findState = ref.watch(findProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final countText = _countLabelText(
      l10n,
      findState.position,
      findState.count,
    );
    final duration = _crossfadeDuration(context);

    // The match-count label lives INSIDE the search pill (as a suffix) so it
    // never eats into the pill's width — that keeps the search and replace pills
    // exactly equal width. Always rendered (empty string when count == 0) so the
    // layout and the widget tests stay stable.
    final countLabel = Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Opacity(
        opacity: 0.58,
        child: Text(countText, style: theme.textTheme.bodySmall),
      ),
    );

    // ── Row 1: search pill (+ count) | prev | next | replace toggle ──
    // No leading column — the back affordance is delivered by FindBackPill
    // (a separate top-left widget, later task). Trailing cluster = three
    // 48dp icon buttons. The replace row mirrors the trailing width exactly.
    final searchRow = Row(
      children: [
        // Search pill, filling available space (filled rounded entry).
        Expanded(
          child: TextField(
            controller: _searchController,
            // Optional FocusNode wired by buffer_screen.dart (FR-22, TASK-07)
            // so the screen can control search-field focus (Ctrl+F re-press
            // refocus + select-all, OQ-05).
            focusNode: widget.focusNode,
            onChanged: _onSearchChanged,
            // TextInputAction.search maps the mobile soft-keyboard "Search"
            // key onSubmitted → findProvider.next() (OQ-05, spec §5.5).
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => ref.read(findProvider.notifier).next(),
            decoration: _pillDecoration(
              theme,
              hint: l10n.findHintText,
              icon: Icons.search,
              suffixIcon: countLabel,
            ),
          ),
        ),
        const SizedBox(width: 4.0),

        // Trailing cluster: prev | next | replace toggle (3 × 48dp).
        SizedBox(
          width: _kTrailingClusterWidth,
          child: Row(
            children: [
              // Previous match (FR-11 / bible up-large-symbolic).
              _iconBtn(
                icon: Icons.keyboard_arrow_up,
                tooltip: l10n.findPreviousTooltip,
                onPressed: _onPrevious,
              ),
              // Next match (FR-10 / bible down-large-symbolic).
              _iconBtn(
                icon: Icons.keyboard_arrow_down,
                tooltip: l10n.findNextTooltip,
                onPressed: _onNext,
              ),
              // Replace toggle (bible edit-find-replace-symbolic).
              _iconBtn(
                icon: Icons.find_replace,
                tooltip: l10n.findReplaceToggleTooltip,
                onPressed: _onToggleReplace,
              ),
            ],
          ),
        ),
      ],
    );

    // ── Row 2: replace pill + Replace button (revealed via crossfade) ──
    // No leading spacer — search row has no leading column after back-cell
    // removal. Trailing cluster width mirrors the search row's trailing cluster
    // so the replace pill is exactly as wide as the search pill.
    final replaceRow = Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          // Replace pill — same width as the search pill (equal leading +
          // trailing on both rows; no leading spacer needed).
          Expanded(
            child: TextField(
              controller: _replaceController,
              onChanged: _onReplaceTermChanged,
              decoration: _pillDecoration(
                theme,
                hint: l10n.findReplaceHintText,
                icon: Icons.find_replace,
              ),
            ),
          ),
          const SizedBox(width: 4.0),

          // Replace button — accent-filled, enabled only when a current match
          // exists (FR-15). Boxed to the trailing-cluster width so it occupies
          // the same column as the search row's prev/next/toggle icons. Kept an
          // ElevatedButton (styled filled accent) to match the upstream blue
          // "Replace" action and the existing widget tests.
          SizedBox(
            width: _kTrailingClusterWidth,
            child: ElevatedButton(
              onPressed: findState.hasCurrent ? _onReplace : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                // Stay in the accent colour when disabled (no current match) —
                // just dimmed — rather than going grey, matching the upstream
                // blue "suggested-action" Replace button.
                disabledBackgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.5,
                ),
                disabledForegroundColor: theme.colorScheme.onPrimary.withValues(
                  alpha: 0.7,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_kPillRadius),
                ),
              ),
              child: Text(
                l10n.findReplaceButton,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );

    // Glass pill container (TASK-09 / FR-19).
    //
    // Replaces the former flat Material+DecoratedBox header band with the
    // shared GlassSurface primitive. The surface treatment (blur + fill +
    // hairline border + shadow) is inherited from GlassSurface; the bottom
    // divider is dropped — the pill shape provides visual separation.
    //
    // Positioning (top → bottom move) and the toolbar↔find-pill swap are
    // TASK-11 and are NOT done here.
    //
    // <!-- CANON GAP: bottom find pill anatomy -->
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;
    return GlassSurface(
      borderRadius: tokens.searchBarRadius,
      padding: const EdgeInsets.fromLTRB(4.0, 8.0, 8.0, 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchRow,

          // AnimatedCrossFade reveals / hides the replace row (FR-18 /
          // bible Motion). firstChild = empty, secondChild = replaceRow.
          // Reduce-motion → 1ms duration → perceptually instant switch.
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: replaceRow,
            crossFadeState: _replaceVisible
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: duration,
          ),
        ],
      ),
    );
  }
}
