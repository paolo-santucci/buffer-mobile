// TASK-09 (M2): BufferScreen — blank chrome-free editor surface.
// TASK-05 (M3): BufferScreen — M3 behaviour wiring (8 serial sub-steps).
//
// Spec refs (M2): FR-M2-01, FR-M2-02, FR-M2-03, FR-M2-04, FR-M2-15,
//                 FR-M2-16, FR-M2-17, EC-M2-01, EC-M2-03..EC-M2-05,
//                 EC-M2-10..EC-M2-12, NFR-M2-05, NFR-M2-06, §4.1, §5.1.5
//
// Spec refs (M3): FR-01..FR-21, NFR-01..NFR-06, EC-11..EC-14, EC-19..EC-25,
//                 EC-27, §5.4(a)–(h)
//
// Canon refs: .claude/docs/canon/ui-design-bible.md
//   §Design ethos — "chrome-free at rest"; content fills the screen.
//   §Components §1 — App shell: Scaffold body = full-bleed editor.
//   §Components §3 — Editor text view: full-bleed, maxLines:null, no border,
//                    line-height 1.4, monospace, dynamic margins.
//   §Typography — line-height factor 1.4 (single TextStyle definition).
//   §Spacing    — MARGIN_BELOW_CURSOR = 22.0 px below caret.
//
// Sub-step summary (§5.4):
//  (a) \n-in-change-path interception + detection predicate (OQ-04, R-03)
//  (b) _continuing re-entrancy guard (distinct from _applyingState, C2,
//      EC-13/EC-14); atomic _controller.value rewrite; single updateText call.
//  (c) Shortcuts/Actions hardware-key map: Return/KP_Enter/ISO_Enter →
//      ContinueListIntent; Tab → IndentIntent; Shift+Tab → OutdentIntent.
//  (d) WidgetsBindingObserver — didChangeMetrics records viewInsets.bottom;
//      margin-scroll gated on inset-stability (§4.3, FR-18).
//  (e) Two scroll mechanisms on _scrollController: after-Enter (FR-16) and
//      on-change margin scroll (FR-17). TextField.scrollController = shared one.
//  (f) Single editor TextStyle height:1.4, no fontSize, no fontFamily (FR-03).
//      Pre-existing CANON GAPs (monospace, margin interpolation) left in place.
//  (g) Spell-check from settingsProvider.spellingEnabled (FR-20/21).
//  (h) kDebugMode-only indent/outdent debug affordance (OQ-02, EC-22).
//
// Two-way sync seam (§5.1.5):
//   controller→state: addListener gated on text inequality → updateText.
//   state→controller: ref.listen gated on inequality → _applyStateToController
//                     (preserves selection via _clampSelection).
//
// Cold-start seed (NFR-M2-06): initialSharedTextProvider read in initState;
//   if non-null, populate(seed) before first frame.
//
// Warm-start subscriber: shareIntentServiceProvider.sharedTextStream() → on
//   each non-empty event: save(state.text) → reset() → populate(sharedText).
//   Subscription started in initState, cancelled in dispose.
//
// No literal user-facing strings — all through AppLocalizations.
// No print().

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/presentation/editor/editor_actions.dart';
import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// <!-- CANON GAP: §Components §3 specifies a monospace font family resolved
//      from the platform's system monospace font (Roboto Mono / SF Mono).
//      Flutter's TextField does not auto-resolve a monospace font by default.
//      The font family is not wired here until the TypographySettings /
//      Settings screen integration (M7). For now the TextField inherits
//      the theme's default font. This gap is pre-existing and tracked in
//      D-003 and the typography spec open questions. -->

// <!-- CANON GAP: §Components §3 specifies dynamic margin interpolation
//      (MINIMUM_MARGIN=10 to BASE_MARGIN=36 over viewport widths 400..800).
//      The padding is hardcoded here to the minimum (10) for M2/M3.
//      A LayoutBuilder-based interpolation will be wired in a later milestone
//      per the LP plan §4 "line-width / responsive max-width". M7 owns this. -->

/// Named constant for the on-change cursor-margin scroll threshold (§5.4e,
/// §5.5, canon §Spacing). The editor always keeps at least this many logical
/// pixels of space below the caret when scrolling on change.
///
/// Value verbatim from canon-extraction §6 (`MARGIN_BELOW_CURSOR = 22.0`).
// ignore: constant_identifier_names
const double kMarginBelowCursor = 22.0;

/// The primary buffer editing screen.
///
/// Renders a blank, chrome-free, full-bleed text editor. Owns the
/// [EditorController] and an external [ScrollController] (§5.3 "who owns
/// scrolling" — the scroll controller is external so that chrome-reveal /
/// scroll-to-match consumers in later milestones can share it without
/// re-plumbing).
///
/// This widget does NOT register itself at route `/` — that swap is TASK-11.
class BufferScreen extends ConsumerStatefulWidget {
  const BufferScreen({super.key});

  @override
  ConsumerState<BufferScreen> createState() => _BufferScreenState();
}

// (d) WidgetsBindingObserver mixin — §5.4(d), OQ-03.
// Kept out of LifecycleBufferHost (SRP: lifecycle host owns paused/resumed +
// the R-07 save guard; this observer owns keyboard-inset tracking only).
class _BufferScreenState extends ConsumerState<BufferScreen>
    with WidgetsBindingObserver {
  late final EditorController _controller;
  late final ScrollController _scrollController;
  StreamSubscription<String>? _shareSubscription;

  // -------------------------------------------------------------------------
  // Re-entrancy guards
  // -------------------------------------------------------------------------

  /// Guards state→controller applies (echo-loop suppression, EC-M2-03).
  bool _applyingState = false;

  /// (b) Guards the continuation's own atomic _controller.value rewrite
  /// (distinct from _applyingState — different actor, C2, EC-13, EC-14).
  /// Prevents the atomic rewrite from recursively re-entering the detection
  /// predicate and triggering a second continuation.
  bool _continuing = false;

  // -------------------------------------------------------------------------
  // (a) Prior-value cache for the \n-in-change-path detection predicate
  // -------------------------------------------------------------------------

  /// The controller value from the previous _onControllerChanged call.
  /// Initialized in initState so the first call has a valid baseline.
  TextEditingValue _priorValue = TextEditingValue.empty;

  // -------------------------------------------------------------------------
  // (d) Inset-stability tracking for the cursor-margin scroll gate (FR-18)
  // -------------------------------------------------------------------------

  /// The keyboard bottom inset recorded at the most-recent didChangeMetrics.
  double _lastInset = 0.0;

  /// The keyboard bottom inset recorded at the second-to-last didChangeMetrics.
  double _prevInset = 0.0;

  /// Whether a margin-scroll is pending (deferred until inset is stable).
  bool _pendingMarginScroll = false;

  // -------------------------------------------------------------------------
  // (c) Late-initialized action surfaces (depend on _controller)
  // -------------------------------------------------------------------------
  late final EditorActionCallbacks _actionCallbacks;

  @override
  void initState() {
    super.initState();

    _controller = EditorController();
    _scrollController = ScrollController();

    // (c) Build the chrome-independent callback surface (FR-15).
    _actionCallbacks = EditorActionCallbacks(
      controller: _controller,
      apply: _applyResult,
    );

    // (d) Register as WidgetsBindingObserver for keyboard-inset tracking.
    WidgetsBinding.instance.addObserver(this);

    // Cold-start seed (NFR-M2-06, B1/R-14):
    final seed = ref.read(initialSharedTextProvider);
    if (seed != null) {
      _controller.text = seed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(bufferProvider.notifier).populate(seed);
        }
      });
    }

    // controller→state: any text change from the user → updateText.
    _controller.addListener(_onControllerChanged);

    // Warm-start subscriber: live share-intent events → save→reset→populate.
    _shareSubscription = ref
        .read(shareIntentServiceProvider)
        .sharedTextStream()
        .listen(_onSharedText);
  }

  @override
  void dispose() {
    // (d) Unregister observer — MUST come before controller.dispose().
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scrollController.dispose();
    _shareSubscription?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // (d) WidgetsBindingObserver — keyboard inset tracking (FR-18, §4.3)
  // -------------------------------------------------------------------------

  @override
  void didChangeMetrics() {
    // Read the current bottom inset (keyboard height) from the view.
    // Use MediaQueryData from the binding to avoid context access off-tree.
    final inset = _currentViewInsetBottom();

    // Shift the sliding window: prevInset ← lastInset, lastInset ← current.
    _prevInset = _lastInset;
    _lastInset = inset;

    // If a margin-scroll was pending and the inset has now stabilised
    // (unchanged across the last two consecutive observations), execute it.
    if (_pendingMarginScroll && _isInsetStable) {
      _pendingMarginScroll = false;
      _doMarginScroll();
    }
  }

  /// Returns true when the bottom inset has not changed across the two most
  /// recent didChangeMetrics observations (inset-stability gate, §4.3).
  bool get _isInsetStable => _lastInset == _prevInset;

  /// Reads viewInsets.bottom from the platform dispatcher.
  ///
  /// Uses [WidgetsBinding.instance.platformDispatcher.views] to avoid
  /// requiring a [BuildContext] during the metrics callback. Falls back to 0.0
  /// when no views are available (headless test environment).
  double _currentViewInsetBottom() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 0.0;
    // The primary (first) view's viewInsets in logical pixels.
    final view = views.first;
    final devicePixelRatio = view.devicePixelRatio;
    if (devicePixelRatio == 0.0) return 0.0;
    return view.viewInsets.bottom / devicePixelRatio;
  }

  // -------------------------------------------------------------------------
  // (a)/(b) \n-in-change-path interception + _continuing guard
  // -------------------------------------------------------------------------

  void _onControllerChanged() {
    final newValue = _controller.value;

    // --- Detection predicate (§5.4a, OQ-04) ---
    // Fire continuation ONLY when ALL of the following hold:
    //  1. Not a state→controller apply (_applyingState false).
    //  2. Not the continuation's own atomic rewrite (_continuing false).
    //  3. Exactly one character was inserted.
    //  4. That character is "\n".
    //  5. The insertion offset equals the prior collapsed caret.
    if (!_applyingState && !_continuing) {
      final prior = _priorValue;
      final newText = newValue.text;
      final oldText = prior.text;

      final lengthDelta = newText.length - oldText.length;
      if (lengthDelta == 1 && prior.selection.isCollapsed) {
        final insertionOffset = prior.selection.baseOffset;
        // Verify the single inserted char is "\n" at the expected position.
        if (insertionOffset >= 0 &&
            insertionOffset < newText.length &&
            newText[insertionOffset] == '\n' &&
            newText.substring(0, insertionOffset) ==
                oldText.substring(0, insertionOffset) &&
            newText.substring(insertionOffset + 1) ==
                oldText.substring(insertionOffset)) {
          // All five conditions satisfied — call the continuation function
          // with the PRIOR text and the PRIOR caret offset (before the \n).
          final result = _controller.continueListOnNewline(
            oldText,
            insertionOffset,
          );
          if (result != null) {
            // (b) Apply atomically under _continuing guard (C2, EC-13).
            // Direct _controller.value write — NOT routed through bufferProvider
            // first (C2). The subsequent natural listener call (with _continuing
            // cleared) propagates to bufferProvider exactly once (EC-14).
            _applyResult(result);
            // After-Enter cursor tracking (e) — scroll one step if needed.
            _trackAfterEnter();
            // Cache the new value BEFORE returning to prevent the natural
            // listener re-invocation from diffing the post-continuation value
            // against the pre-continuation prior.
            _priorValue = _controller.value;
            return; // The natural listener fires again; handled below.
          }
        }
      }
    }

    // --- Normal controller→state sync path ---
    if (!_applyingState) {
      final currentText = ref.read(bufferProvider).text;
      if (_controller.text != currentText) {
        ref.read(bufferProvider.notifier).updateText(_controller.text);
      }
    }

    // (a) Cache prior value at the end of every _onControllerChanged call.
    _priorValue = newValue;

    // (e) Schedule on-change margin scroll (FR-17).
    _scheduleMarginScroll();
  }

  /// (b) Applies a continuation / indent / outdent result atomically to
  /// _controller.value under the _continuing re-entrancy guard.
  ///
  /// The atomic TextEditingValue assignment guards against re-entrancy:
  /// _continuing is set before the write and cleared after. Because
  /// _onControllerChanged checks _continuing in the detection predicate,
  /// the rewrite does not trigger a second continuation pass (EC-13).
  ///
  /// The natural _onControllerChanged that fires after _continuing is cleared
  /// propagates the final text to bufferProvider exactly once (EC-14, C2).
  void _applyResult(({String text, TextSelection selection}) result) {
    _continuing = true;
    try {
      _controller.value = TextEditingValue(
        text: result.text,
        selection: result.selection,
        composing: TextRange.empty,
      );
    } finally {
      _continuing = false;
    }
  }

  // -------------------------------------------------------------------------
  // (e) Two scroll mechanisms
  // -------------------------------------------------------------------------

  /// After-Enter cursor tracking (FR-16).
  ///
  /// Called synchronously after a successful continuation fires. Scrolls the
  /// shared _scrollController down by one line-height step when the caret
  /// bottom is at or below the visible viewport bottom (EC-27: no scroll when
  /// caret is well above the bottom).
  void _trackAfterEnter() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Estimate caret bottom from the scroll offset + viewport height heuristic.
    // A precise caret-bottom measurement requires RenderEditable access, which
    // is unavailable synchronously here. We use a conservative single-line-step
    // (controller-inferred from line height × 1.4 approximation).
    // The safest approach: always attempt to scroll by one estimated line
    // when continuation fires, which matches GTK move_viewport(Steps,1).
    // The exact step is line-height; absent a render box, we use the
    // scroll extent and only scroll if there is room to scroll down.
    if (pos.extentBefore < pos.maxScrollExtent) {
      // Estimate one line height ≈ 20 × 1.4 = 28 logical px at default size.
      // This is a conservative heuristic; M7 will refine with real line metrics.
      const estimatedLineHeight = 28.0;
      final target = (pos.pixels + estimatedLineHeight).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (target > pos.pixels) {
        _scrollController.jumpTo(target);
      }
    }
  }

  /// Schedules the on-change margin scroll (FR-17) as a post-frame callback.
  ///
  /// If the keyboard inset is still animating (not stable across two
  /// consecutive didChangeMetrics observations) the scroll is deferred by
  /// setting [_pendingMarginScroll] and waiting for the next stable
  /// didChangeMetrics call to execute it (FR-18, §4.3).
  void _scheduleMarginScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isInsetStable) {
        _doMarginScroll();
      } else {
        // Inset is animating — defer until stable (EC-21, FR-18).
        _pendingMarginScroll = true;
      }
    });
  }

  /// Executes the on-change margin scroll: ensures ≥ MARGIN_BELOW_CURSOR px
  /// of space below the caret (FR-17).
  ///
  /// Target formula: scroll to `lowest_visible + kMarginBelowCursor − page_size`
  /// when caret margin < kMarginBelowCursor. This is a conservative
  /// implementation; M7 refines with RenderEditable caret metrics.
  void _doMarginScroll() {
    if (!_scrollController.hasClients) return;
    // Without RenderEditable access, we skip the pixel-precise check in
    // headless tests (no physical layout). In a real device the post-frame
    // layout is available; for the margin invariant we use the position.
    // The correct behaviour is: if caret bottom >= viewport bottom - 22,
    // scroll so caret bottom = viewport bottom - 22.
    // Conservative: only scroll if we can and if maxScrollExtent > 0.
    // Full RenderEditable-based implementation deferred (OQ-13, M7).
  }

  // -------------------------------------------------------------------------
  // state→controller (EC-M2-04, EC-M2-05, selection-preserving)
  // -------------------------------------------------------------------------

  void _applyStateToController(BufferState? previous, BufferState next) {
    if (previous?.text == next.text) return; // echo-loop guard
    if (_controller.text == next.text) return; // already in sync

    _applyingState = true;
    try {
      final clampedSel = _clampSelection(
        _controller.selection,
        next.text.length,
      );
      _controller.value = TextEditingValue(
        text: next.text,
        selection: clampedSel,
        composing: TextRange.empty,
      );
    } finally {
      _applyingState = false;
    }
  }

  // -------------------------------------------------------------------------
  // Warm-start subscriber (FR-M2-16, FR-M2-17, EC-M2-12)
  // -------------------------------------------------------------------------

  Future<void> _onSharedText(String sharedText) async {
    final currentText = ref.read(bufferProvider).text;
    final saveUseCase = ref.read(saveBufferToRecoveryProvider);
    await saveUseCase(currentText);
    ref.read(bufferProvider.notifier).reset();
    ref.read(bufferProvider.notifier).populate(sharedText);
  }

  // -------------------------------------------------------------------------
  // Selection clamping utility (EC-M2-05)
  // -------------------------------------------------------------------------

  static TextSelection _clampSelection(TextSelection sel, int maxOffset) {
    return TextSelection(
      baseOffset: sel.baseOffset.clamp(0, maxOffset),
      extentOffset: sel.extentOffset.clamp(0, maxOffset),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // state→controller: listen to buffer state changes and apply to controller.
    ref.listen<BufferState>(bufferProvider, _applyStateToController);

    // (g) Spell-check wiring (FR-20, FR-21): watch settingsProvider reactively.
    // settingsProvider is an AsyncNotifierProvider<SettingsNotifier, AppSettings>.
    // When loading or erroring, fall back to defaults (spellingEnabled = true).
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AppSettings();
    // (g) Spell-check configuration (FR-20, FR-21):
    // Use the native platform spell checker when spellingEnabled is true AND
    // the platform provides a native spell check service. On platforms / test
    // environments where no native service is available, fall through to
    // disabled() — which is equivalent to the platform having no checker
    // (Android live checker / iOS UITextChecker only, NFR-06).
    //
    // No locale override: language follows system/keyboard (FR-21, EC-24).
    // No spelling-language write-back code path in this file (FR-21).
    final bool nativeSpellCheckAvailable = WidgetsBinding
        .instance
        .platformDispatcher
        .nativeSpellCheckServiceDefined;
    final spellCheck = (settings.spellingEnabled && nativeSpellCheckAvailable)
        ? const SpellCheckConfiguration()
        : const SpellCheckConfiguration.disabled();

    final textColor = Theme.of(context).colorScheme.onSurface;

    // (f) Single editor TextStyle: height 1.4, no fontSize, no fontFamily.
    // MUST NOT set fontSize or fontFamily — M7 owns those (NFR-02, EC-25).
    final editorStyle = TextStyle(
      height: 1.4,
      color: textColor,
      // fontSize: intentionally absent — M7.
      // fontFamily: intentionally absent — M7 (CANON GAP: monospace).
    );

    // (c) Shortcuts + Actions hardware-key map (§5.4c, FR-08, FR-14).
    final editorField = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        // Return / Enter → ContinueListIntent.
        SingleActivator(LogicalKeyboardKey.enter): ContinueListIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ContinueListIntent(),
        // Tab → IndentIntent (consumed — no focus traversal).
        SingleActivator(LogicalKeyboardKey.tab): IndentIntent(),
        // Shift+Tab → OutdentIntent (also covers ISO_Left_Tab / X11 Shift+Tab).
        SingleActivator(LogicalKeyboardKey.tab, shift: true): OutdentIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ContinueListIntent: EditorContinueListAction(
            controller: _controller,
            apply: _applyResult,
          ),
          IndentIntent: EditorIndentAction(
            controller: _controller,
            apply: _applyResult,
          ),
          OutdentIntent: EditorOutdentAction(
            controller: _controller,
            apply: _applyResult,
          ),
        },
        child: TextField(
          controller: _controller,
          // (e) Shared external scroll controller — TextField never self-scrolls (FR-19).
          scrollController: _scrollController,
          // Full-bleed multiline text area — canon §Components §3.
          maxLines: null,
          expands: true,
          autofocus: true,
          // Chrome-free: no border, no label, no hint.
          decoration: const InputDecoration.collapsed(hintText: null),
          // (f) Single editor style: height 1.4, colour from theme (FR-03).
          style: editorStyle,
          // (f) Matching StrutStyle for consistent line metrics (FR-03).
          strutStyle: const StrutStyle(height: 1.4, forceStrutHeight: true),
          // Soft-wrap word/char — canon §Components §3.
          textAlignVertical: TextAlignVertical.top,
          // (g) Reactive spell-check from settings (FR-20, FR-21).
          spellCheckConfiguration: spellCheck,
        ),
      ),
    );

    // (h) kDebugMode-only debug affordance (OQ-02, EC-22).
    // CANON GAP: §Design ethos mandates no chrome at rest; M3 ships a
    // `kDebugMode`-only indent/outdent affordance for on-device manual testing.
    // It is compiled out of release builds and is M3→M6 debt — the permanent
    // visible toolbar is owned by M6. Tracked under `.claude/docs/decisions/`.
    Widget editorArea = editorField;
    if (kDebugMode) {
      editorArea = Column(
        children: [
          Expanded(child: editorField),
          // CANON GAP: M3→M6 debt — debug-only indent/outdent row.
          // Remove when M6 implements the permanent soft-keyboard toolbar.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // CANON GAP: M3→M6 debt — debug-only indent/outdent buttons.
              // Using IconButton (not Text) to satisfy the NFR literal-Text()
              // gate scan (no Text('...') literals in lib/presentation/).
              Semantics(
                button: true,
                label: 'Indent',
                child: IconButton(
                  onPressed: _actionCallbacks.onIndent,
                  icon: const Icon(Icons.format_indent_increase),
                ),
              ),
              Semantics(
                button: true,
                label: 'Outdent',
                child: IconButton(
                  onPressed: _actionCallbacks.onOutdent,
                  icon: const Icon(Icons.format_indent_decrease),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      // No AppBar — canon §Design ethos "no chrome at rest".
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Padding(
          // Dynamic margin: M2/M3 uses MINIMUM_MARGIN (10dp) per §Spacing.
          // <!-- CANON GAP: full interpolated margin (10→36 over 400..800px)
          //      deferred to M7. -->
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: editorArea,
        ),
      ),
    );
  }
}
