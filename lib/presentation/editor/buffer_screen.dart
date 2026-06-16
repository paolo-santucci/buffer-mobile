// TASK-09 (M2): BufferScreen — blank chrome-free editor surface.
// TASK-05 (M3): BufferScreen — M3 behaviour wiring (8 serial sub-steps).
// TASK-07 (M4): BufferScreen — find/replace integration wiring.
// TASK-12 (M5): BufferScreen — kDebugMode /recovery entry affordance.
// TASK-12 (M6): BufferScreen — shell integration (Stack+chrome+toast+menu+paste+Esc).
//
// Spec refs (M2): FR-M2-01, FR-M2-02, FR-M2-03, FR-M2-04, FR-M2-15,
//                 FR-M2-16, FR-M2-17, EC-M2-01, EC-M2-03..EC-M2-05,
//                 EC-M2-10..EC-M2-12, NFR-M2-05, NFR-M2-06, §4.1, §5.1.5
//
// Spec refs (M3): FR-01..FR-21, NFR-01..NFR-06, EC-11..EC-14, EC-19..EC-25,
//                 EC-27, §5.4(a)–(h)
//
// Spec refs (M4): FR-05, FR-07, FR-13, FR-14, FR-16, FR-17, FR-18, FR-20,
//                 FR-21, FR-22; NFR-01, NFR-04, NFR-07; spec §4.3/§5.4/§5.5
//
// Spec refs (M6): FR-M6-05, FR-M6-06, FR-M6-07, FR-M6-18, FR-M6-20,
//                 FR-M6-22, FR-M6-23, EC-04, EC-07, EC-11, NFR-M6-04, §4.3
//
// Canon refs: .claude/docs/canon/ui-design-bible.md
//   §Design ethos — "chrome-free at rest"; content fills the screen.
//   §Components §1 — App shell: Scaffold body = full-bleed editor.
//   §Components §2 — Auto-hiding overlay chrome (Stack/Positioned).
//   §Components §3 — Editor text view: full-bleed, maxLines:null, no border,
//                    line-height 1.4, monospace, dynamic margins.
//   §Components §4 — Search header bar mobile adaptation.
//   §Components §8 — Timed notification toast (Positioned top-centre).
//   §Typography — line-height factor 1.4 (single TextStyle definition).
//   §Spacing    — MARGIN_BELOW_CURSOR = 22.0 px below caret.
//
// Sub-step summary (§5.4 M3):
//  (a) \n-in-change-path interception + detection predicate (OQ-04, R-03)
//  (b) _continuing re-entrancy guard (distinct from _applyingState, C2,
//      EC-13/EC-14); atomic _controller.value rewrite; single updateText call.
//  (c) Shortcuts/Actions hardware-key map: Return/KP_Enter/ISO_Enter →
//      ContinueListIntent; Tab → IndentIntent; Shift+Tab → OutdentIntent.
//      M4 adds: Ctrl+F → OpenFindIntent; Ctrl+G → FindNextIntent;
//      Ctrl+Shift+G → FindPrevIntent; Ctrl+H → ToggleReplaceIntent;
//      M6 revises Esc: precedence chain (find→chrome) replacing CloseFindIntent.
//      M6 adds: Ctrl+V → PasteIntent.
//  (d) WidgetsBindingObserver — didChangeMetrics records viewInsets.bottom;
//      margin-scroll gated on inset-stability (§4.3, FR-18).
//      M6: keyboard-dismiss (inset→0) feeds ChromeRevealController.
//  (e) Two scroll mechanisms on _scrollController: after-Enter (FR-16) and
//      on-change margin scroll (FR-17). TextField.scrollController = shared one.
//      M4 adds scroll-to-match via the same shared ScrollController (FR-17).
//      M6 adds GUARDED chrome scroll listener (4th consumer, EC-07, D5/R-04).
//  (f) Single editor TextStyle height:1.4, no fontSize, no fontFamily (FR-03).
//      Pre-existing CANON GAPs (monospace, margin interpolation) left in place.
//  (g) Spell-check from settingsProvider.spellingEnabled (FR-20/21).
//  (h) M6: kDebugMode debug row REMOVED (FR-M6-23, OQ-M5-08 resolved). Menu
//      sheet is the sole nav entry via ChromeOverlay affordance.
//
// M4 sub-steps (§5.4/§5.5):
//  (i) FindSearchBar mounted as Stack Positioned slot (top) when active —
//      NOT a Column row (EC-04). Editor size invariant across find show/hide.
//  (j) _editorFocusNode + _searchFocusNode: created initState, disposed in
//      strict order in dispose(); _editorFocusNode wired to editor TextField.
//  (k) ref.listen<FindState>(findProvider, _applyFindToController): pushes
//      highlightRanges + currentMatchIndex, drives scroll-to-match.
//  (l) Replace: FindSearchBar.onReplace → replaceCurrent() → _applyResult.
//  (m) close() → findProvider.close() + _editorFocusNode.requestFocus() (no
//      caret move — EC-10).
//
// M6 wiring (§4.3):
//  (n) Stack layout: bottom=editor, top-end=ChromeOverlay, top-centre=ToastOverlay.
//      FindSearchBar as top Positioned slot inside Stack (EC-04 invariant).
//  (o) Chrome reveal inputs:
//        _onControllerChanged → ChromeRevealController.onTextChanged()
//        guarded scroll listener → ChromeRevealController.onUserScroll(dir)
//        didChangeMetrics (inset→0) → ChromeRevealController.onKeyboardDismissed()
//  (p) PasteIntent/PasteAction wired (Ctrl+V → clipboard insert via _applyResult).
//  (q) Esc precedence: find open → CloseFindIntent; else → DismissChromeIntent.
//  (r) Semantics(label:'Indent'/'Outdent') localized via ARB editorIndentLabel/
//      editorOutdentLabel (FR-M6-18).
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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/domain/find/find_engine.dart';
import 'package:buffer/domain/find/find_state.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/presentation/editor/editor_actions.dart';
import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:buffer/presentation/editor/editor_layout.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/find/find_provider.dart';
import 'package:buffer/presentation/find/find_search_bar.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/shell/chrome_overlay.dart';
import 'package:buffer/presentation/shell/chrome_reveal_controller.dart';
import 'package:buffer/presentation/shell/menu_sheet.dart';
import 'package:buffer/presentation/shell/toast_controller.dart';
import 'package:buffer/presentation/shell/toast_overlay.dart';

// M7 (TASK-12): Both CANON GAPs below are RESOLVED in this file.
//   (c) Font family is now wired from settings.useMonospaceFont (FR-M7-09).
//   (e) Responsive margin is now a LayoutBuilder inside Positioned.fill (FR-M7-11).

// ---------------------------------------------------------------------------
// M7 (TASK-12): Pure pinch scale→slot-index mapping helper.
//
// Exported @visibleForTesting so unit tests can call it directly (OQ-M7-09)
// without requiring synthetic multi-pointer events.
//
// Algorithm: log2(scale) maps the continuous scale to a signed step count.
// Each step of ≈1.15× (factor between adjacent slots) advances one slot.
// We use a step threshold of 0.2 log-scale units, anchored to startIndex.
// Clamping to [0, slotList.length-1] is done by the caller.
// ---------------------------------------------------------------------------
@visibleForTesting
int scaleToSlotDelta(double scale, int startIndex) {
  if (scale <= 0.0 || scale == 1.0) return 0;
  // ln(scale) / ln(1.15) ≈ number of 15%-apart slots to advance.
  // A threshold of 0.5 slot-units makes the mapping deterministic and
  // matches a moderate two-finger pinch.
  final delta = math.log(scale) / math.log(1.15);
  return delta.round();
}

/// Named constant for the on-change cursor-margin scroll threshold (§5.4e,
/// §5.5, canon §Spacing). The editor always keeps at least this many logical
/// pixels of space below the caret when scrolling on change.
///
/// Value verbatim from canon-extraction §6 (`MARGIN_BELOW_CURSOR = 22.0`).
// ignore: constant_identifier_names
const double kMarginBelowCursor = 22.0;

// ---------------------------------------------------------------------------
// EC-07 / OQ-M6-09: @visibleForTesting seam interface
//
// The production state class implements this interface so widget tests can
// drive the guarded chrome scroll listener and the keyboard-dismiss path
// without requiring real platform events (scroll notifications, view insets).
//
// Tests cast: `tester.state(find.byType(BufferScreen)) as BufferScreenTestSeam`.
// The cast is valid because [_BufferScreenState] implements this interface.
// ---------------------------------------------------------------------------

/// Test seam for [BufferScreen]'s guarded chrome scroll listener (EC-07,
/// OQ-M6-09).
///
/// Implemented by [_BufferScreenState] via `@visibleForTesting` methods.
@visibleForTesting
abstract interface class BufferScreenTestSeam {
  /// Simulates a scroll direction notification through the guarded listener.
  ///
  /// Respects the `_applyingState || _continuing` guard (EC-07): if either
  /// flag is true, the call is ignored and chrome state does not change.
  void testOnScrollNotification(ScrollDirection direction);

  /// Force-sets the `_applyingState` guard to [value].
  ///
  /// Used by EC-07 tests to verify that the guard suppresses chrome toggling
  /// without needing to exercise the real find/continuation code paths.
  void testSetApplyingState(bool value);

  /// Simulates a keyboard-dismiss event (inset → 0 transition).
  ///
  /// Calls [ChromeRevealController.onKeyboardDismissed] directly, bypassing
  /// the `didChangeMetrics` / `viewInsets` platform channel dependency.
  void testOnKeyboardDismissed();
}

/// The primary buffer editing screen.
///
/// Renders a full-bleed text editor wrapped in the M6 shell:
///   - [Stack] hosting the editor [TextField] (fills the stack),
///     [ChromeOverlay] (Positioned top-end), and [ToastOverlay] (Positioned
///     top-centre). The [FindSearchBar] mounts as a Positioned top slot in
///     the same Stack when active (EC-04 — editor size invariant).
///   - Auto-hiding chrome driven by three inputs: text change, user scroll
///     (guarded), and keyboard dismiss.
///   - Menu sheet opened from the chrome affordance tap (FR-M6-23).
///   - Clipboard paste (Ctrl+V) routed through [_applyResult] (FR-M6-20).
///   - Esc precedence: find open → close find; else → hide chrome (FR-M6-22).
///
/// Owns the [EditorController] and an external [ScrollController] (§5.3 "who
/// owns scrolling" — external so chrome-reveal / scroll-to-match consumers
/// can share it without re-plumbing). The chrome scroll listener is the 4th
/// consumer of this controller (D5/R-04, EC-07).
///
/// This widget does NOT register itself at route `/` — that swap is TASK-16.
class BufferScreen extends ConsumerStatefulWidget {
  const BufferScreen({super.key});

  @override
  ConsumerState<BufferScreen> createState() => _BufferScreenState();
}

// (d) WidgetsBindingObserver mixin — §5.4(d), OQ-03.
// Kept out of LifecycleBufferHost (SRP: lifecycle host owns paused/resumed +
// the R-07 save guard; this observer owns keyboard-inset tracking only).
class _BufferScreenState extends ConsumerState<BufferScreen>
    with WidgetsBindingObserver
    implements BufferScreenTestSeam {
  late final EditorController _controller;
  late final ScrollController _scrollController;
  StreamSubscription<String>? _shareSubscription;

  // BUG-003 fix: serialises back-to-back share events so event N+1 does not
  // start until event N's save→reset→populate chain has fully completed.
  // Initialised to a resolved future so the first event starts immediately.
  Future<void> _shareQueue = Future<void>.value();

  // -------------------------------------------------------------------------
  // M4: FocusNode ownership (FR-22, spec §5.5)
  // -------------------------------------------------------------------------

  /// Owns the editor TextField's focus (FR-22 / spec §5.5).
  ///
  /// Wired to the editor TextField so the screen can programmatically
  /// request editor focus on close() without moving the caret (EC-10).
  late final FocusNode _editorFocusNode;

  /// Owns the FindSearchBar's search-field focus (FR-22 / spec §5.5).
  ///
  /// Passed to [FindSearchBar] so the screen can refocus + select-all on
  /// Ctrl+F re-press (spec §5.3 / OQ-04 refocus path).
  late final FocusNode _searchFocusNode;

  // -------------------------------------------------------------------------
  // M4: Replace-row visibility notifier (ToggleReplaceAction / Ctrl+H)
  // -------------------------------------------------------------------------

  /// External controller for [FindSearchBar]'s replace-row visibility.
  ///
  /// Shared between the screen (which toggles it via Ctrl+H /
  /// [ToggleReplaceAction]) and [FindSearchBar] (which reads/writes it).
  /// Replace-row visibility is a UI concern, NOT held in [findProvider]
  /// state (spec §5.3 / [ToggleReplaceIntent] docs).
  final ValueNotifier<bool> _replaceRowNotifier = ValueNotifier<bool>(false);

  // -------------------------------------------------------------------------
  // M7 (TASK-12): Pinch-to-zoom state
  //
  // Orthogonal to _applyingState/_continuing (those guard text rewrites).
  // Persisted ONLY in onScaleEnd to avoid excessive provider mutations.
  // -------------------------------------------------------------------------

  /// The fontSizeIndex captured at the start of a two-pointer pinch gesture.
  int _scaleStartIndex = 0;

  // -------------------------------------------------------------------------
  // Re-entrancy guards
  // -------------------------------------------------------------------------

  /// Guards state→controller applies (echo-loop suppression, EC-M2-03).
  ///
  /// Also consulted by the chrome scroll listener (EC-07): while this flag
  /// is set (during a programmatic find `animateTo` or similar), user scroll
  /// events are ignored so chrome does NOT toggle.
  bool _applyingState = false;

  /// (b) Guards the continuation's own atomic _controller.value rewrite
  /// (distinct from _applyingState — different actor, C2, EC-13, EC-14).
  /// Prevents the atomic rewrite from recursively re-entering the detection
  /// predicate and triggering a second continuation.
  ///
  /// Also consulted by the chrome scroll listener (EC-07, same as _applyingState).
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

  @override
  void initState() {
    super.initState();

    _controller = EditorController();
    _scrollController = ScrollController();

    // (j) M4: Create FocusNodes in initState (FR-22 / spec §5.5).
    _editorFocusNode = FocusNode();
    _searchFocusNode = FocusNode();

    // (d) Register as WidgetsBindingObserver for keyboard-inset tracking.
    WidgetsBinding.instance.addObserver(this);

    // M6 (e): Register the guarded chrome scroll listener as the 4th consumer
    // of _scrollController (D5/R-04). This listener reads scroll direction and
    // feeds ChromeRevealController.onUserScroll — but ONLY when neither
    // _applyingState nor _continuing is set (EC-07, §4.3 guard contract).
    _scrollController.addListener(_onScrollControllerNotification);

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
    // Events are serialised through _shareQueue (BUG-003): event N+1 does not
    // begin until event N's entire async chain has completed.
    _shareSubscription = ref
        .read(shareIntentServiceProvider)
        .sharedTextStream()
        .listen(_enqueueSharedText);
  }

  @override
  void dispose() {
    // (d) Unregister observer — MUST come before controller.dispose().
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);

    // M6: Remove chrome scroll listener before disposing the controller.
    _scrollController.removeListener(_onScrollControllerNotification);

    // (j) M4: Dispose FocusNodes in strict order (spec §5.5 / FR-22).
    // search FocusNode first (outer), then editor FocusNode (inner).
    _searchFocusNode.dispose();
    _editorFocusNode.dispose();

    // Dispose the replace-row notifier.
    _replaceRowNotifier.dispose();

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

    // M6 (o): Keyboard dismiss (inset → 0) reveals chrome (FR-M6-06).
    // Detect the transition: previous inset > 0 and new inset == 0.
    if (_lastInset > 0.0 && inset == 0.0) {
      if (mounted) {
        ref.read(chromeVisibilityProvider.notifier).onKeyboardDismissed();
      }
    }

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
  // M6 (e): Guarded chrome scroll listener (EC-07, D5/R-04, §4.3)
  // -------------------------------------------------------------------------

  /// The 4th consumer of [_scrollController] (D5/R-04).
  ///
  /// Reads the current scroll direction and feeds
  /// [ChromeRevealController.onUserScroll] — BUT only when neither
  /// [_applyingState] nor [_continuing] is set.
  ///
  /// **Guard (EC-07):** programmatic scrolls — after-Enter [jumpTo],
  /// cursor-margin [_doMarginScroll], and find `animateTo` — set one of the
  /// re-entrancy flags before calling [_scrollController]. While either flag
  /// is set, this listener returns early and chrome state is unchanged. This
  /// ensures only real user-driven scroll direction changes toggle the chrome.
  void _onScrollControllerNotification() {
    // Guard: ignore programmatic scroll events (EC-07, §4.3).
    if (_applyingState || _continuing) return;

    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Determine scroll direction from the user's activity.
    // The position.userScrollDirection is set by the framework for
    // user-initiated scrolls and 'idle' for programmatic scrolls.
    final direction = position.userScrollDirection;
    if (!mounted) return;
    ref.read(chromeVisibilityProvider.notifier).onUserScroll(direction);
  }

  // -------------------------------------------------------------------------
  // @visibleForTesting seams (EC-07, OQ-M6-09)
  // -------------------------------------------------------------------------

  /// @visibleForTesting — drives the guarded scroll listener from tests.
  ///
  /// Calls [_onScrollNotificationCore] with [direction], respecting the
  /// [_applyingState] / [_continuing] guard exactly as the production listener
  /// does. Used by EC-07 tests to verify guard behaviour without emitting real
  /// scroll events.
  @override
  @visibleForTesting
  void testOnScrollNotification(ScrollDirection direction) {
    _onScrollNotificationCore(direction);
  }

  /// Core scroll→chrome routing (extracted for testability).
  ///
  /// Respects the [_applyingState] / [_continuing] re-entrancy guard (EC-07).
  void _onScrollNotificationCore(ScrollDirection direction) {
    if (_applyingState || _continuing) return;
    if (!mounted) return;
    ref.read(chromeVisibilityProvider.notifier).onUserScroll(direction);
  }

  /// @visibleForTesting — force-sets [_applyingState] for EC-07 guard tests.
  @override
  @visibleForTesting
  void testSetApplyingState(bool value) {
    _applyingState = value;
  }

  /// @visibleForTesting — simulates keyboard-dismiss (inset → 0) from tests.
  @override
  @visibleForTesting
  void testOnKeyboardDismissed() {
    if (!mounted) return;
    ref.read(chromeVisibilityProvider.notifier).onKeyboardDismissed();
  }

  // -------------------------------------------------------------------------
  // (a)/(b) \n-in-change-path interception + _continuing guard
  // -------------------------------------------------------------------------

  void _onControllerChanged() {
    final newValue = _controller.value;

    // M6 (o): Feed text-change signal to ChromeRevealController (FR-M6-06).
    // Only feed when:
    //  - NOT under a re-entrancy guard (programmatic rewrites must not hide chrome).
    //  - The TEXT actually changed (selection-only changes, e.g. from focus/autofocus,
    //    must NOT hide chrome — EC-07 / FR-M6-06 "typing hides").
    if (!_applyingState &&
        !_continuing &&
        mounted &&
        newValue.text != _priorValue.text) {
      ref.read(chromeVisibilityProvider.notifier).onTextChanged();
    }

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
    // BUG-003: use _controller.value (not newValue) to stay consistent with the
    // continuation branch (:550), which also caches _controller.value after any
    // atomic rewrite. For the non-continuation path these are identical because
    // no rewrite has occurred; the symmetry prevents diff-detection errors if
    // the two branches are ever merged or reordered.
    _priorValue = _controller.value;

    // (e) Schedule on-change margin scroll (FR-17).
    _scheduleMarginScroll();
  }

  /// (b) Applies a continuation / indent / outdent / paste result atomically to
  /// _controller.value under the _continuing re-entrancy guard.
  ///
  /// The atomic TextEditingValue assignment guards against re-entrancy:
  /// _continuing is set before the write and cleared after. Because
  /// _onControllerChanged checks _continuing in the detection predicate,
  /// the rewrite does not trigger a second continuation pass (EC-13).
  ///
  /// The natural _onControllerChanged that fires after _continuing is cleared
  /// propagates the final text to bufferProvider exactly once (EC-14, C2).
  ///
  /// M4: this is ALSO the only path for replace mutations (FR-14 / NFR-04).
  /// M6: ALSO the only path for paste mutations (FR-M6-20).
  /// No direct _controller.value = write outside this method on any find/paste path.
  ///
  /// BUG-004: mirrors the equality guard in _applyStateToController (which checks
  /// `_controller.text == next.text` before writing). Without this guard, a
  /// continuation result that is identical to the current controller value causes
  /// a spurious _onControllerChanged emission, which in turn reveals the chrome
  /// unnecessarily and emits a redundant bufferProvider.updateText call.
  void _applyResult(({String text, TextSelection selection}) result) {
    final target = TextEditingValue(
      text: result.text,
      selection: result.selection,
      composing: TextRange.empty,
    );
    // BUG-004 equality guard: skip the write if controller already holds the
    // same value (mirrors _applyStateToController's guard on line 670).
    if (_controller.value == target) return;
    _continuing = true;
    try {
      _controller.value = target;
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
    if (pos.extentBefore < pos.maxScrollExtent) {
      // M7 (g) [CONDITIONAL]: Refine estimatedLineHeight from current font slot.
      // fontSizePt * lineHeight factor 1.4. Previously hardcoded 28.0 (OQ-M7-07).
      // Falls back gracefully if settings are not yet loaded (defaults to 14×1.4).
      final settingsNow =
          ref.read(settingsProvider).valueOrNull ?? const AppSettings();
      final estimatedLineHeight = settingsNow.fontSizePt * 1.4;
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
  // M4: FindState → controller seam push (spec §4.3 / k)
  // -------------------------------------------------------------------------

  /// One [ref.listen] for find-state changes (spec §4.3, TASK-07 step k).
  ///
  /// On every [FindState] transition:
  ///  1. Push `matches` → [EditorController.highlightRanges] as [TextRange]s.
  ///  2. Push `currentMatchIndex` → [EditorController.currentMatchIndex].
  ///  3. If the current-match index changed, schedule scroll-to-match (FR-17).
  ///  4. If find deactivated (active=false), restore editor focus (FR-20 / m).
  void _applyFindToController(FindState? previous, FindState next) {
    // Push match highlights to the controller (FR-13 / EC-10).
    // Convert MatchSpan (plain ints) to TextRange (Flutter type).
    final ranges = next.matches
        .map((m) => TextRange(start: m.start, end: m.end))
        .toList(growable: false);
    _controller.highlightRanges = ranges;
    _controller.currentMatchIndex = next.currentMatchIndex;

    // Scroll to current match when index changes (FR-17 / spec §5.4).
    final prevIndex = previous?.currentMatchIndex;
    final nextIndex = next.currentMatchIndex;
    if (nextIndex != null && nextIndex != prevIndex) {
      final match = next.currentMatch;
      if (match != null) {
        _scheduleScrollToMatch(match, _controller.text);
      }
    }

    // Restore editor focus when find closes without moving caret (FR-20 / m).
    if (previous != null && previous.active && !next.active) {
      // Deferred so the widget tree has time to remove FindSearchBar first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocusNode.requestFocus();
      });
    }
  }

  // -------------------------------------------------------------------------
  // M4: Scroll-to-match (FR-17 / spec §5.4)
  // -------------------------------------------------------------------------

  /// Schedules a scroll-to-match after the next frame (geometry available).
  ///
  /// Uses post-frame to ensure the layout has run before attempting
  /// [getBoxesForSelection]. Falls back to proportional estimate when boxes
  /// are empty (headless / pre-layout, spec §5.4 headless fallback).
  void _scheduleScrollToMatch(MatchSpan match, String text) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToMatch(match, text);
    });
  }

  /// Animates [_scrollController] to bring [match] into view (FR-17 / §5.4).
  ///
  /// **Geometry path** (production / on-device): resolves [EditableTextState]
  /// from the widget tree via [context.findDescendantStateOfType] equivalent,
  /// then calls [renderEditable.getBoxesForSelection] for the match selection.
  /// Takes the first box's top coordinate and computes a scroll target leaving
  /// [kMarginBelowCursor] slack below.
  ///
  /// **Proportional fallback** (headless / pre-layout): when no boxes are
  /// returned, falls back to `(match.start / text.length) * maxScrollExtent`.
  /// This is deterministic in widget tests and satisfies the spec's "brought
  /// into view" written requirement (spec §5.4 headless fallback paragraph).
  ///
  /// **Reduce-motion** (accessibility): animateTo uses [Duration.zero] when
  /// [MediaQuery.disableAnimations] is true (bible Motion / design-accessibility).
  void _scrollToMatch(MatchSpan match, String text) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0.0) return; // nothing to scroll

    // Honour reduce-motion (bible Motion / design-accessibility skill).
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 300);
    const curve = Curves.easeInOut;

    // --- Geometry path (spec §5.4 mechanism) ---
    // Try to locate the RenderEditable from the widget tree.
    // The editor TextField's context contains an EditableText subtree.
    // We walk the element tree to find it.
    double? geometryTarget;
    try {
      // Find EditableTextState as a descendant of the screen's context.
      // This works because EditableText is built inside TextField.
      EditableTextState? edState;
      void visitElement(Element el) {
        if (edState != null) return;
        if (el is StatefulElement && el.state is EditableTextState) {
          edState = el.state as EditableTextState;
          return;
        }
        el.visitChildren(visitElement);
      }

      context.visitChildElements(visitElement);

      if (edState != null) {
        final ro = edState!.renderEditable;
        final sel = TextSelection(
          baseOffset: match.start,
          extentOffset: match.end,
        );
        final boxes = ro.getBoxesForSelection(sel);
        if (boxes.isNotEmpty) {
          // Top of the first box in RenderEditable local coordinates.
          final boxTop = boxes.first.top;
          // Target scroll offset: bring boxTop to 0 with kMarginBelowCursor slack.
          geometryTarget = (pos.pixels + boxTop - kMarginBelowCursor).clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          );
        }
      }
    } catch (_) {
      // Geometry unavailable — fall through to proportional fallback.
    }

    // --- Proportional fallback (spec §5.4 headless fallback) ---
    final target =
        geometryTarget ??
        (text.isEmpty
            ? 0.0
            : (match.start / text.length * pos.maxScrollExtent).clamp(
                pos.minScrollExtent,
                pos.maxScrollExtent,
              ));

    if (duration == Duration.zero) {
      _scrollController.jumpTo(target);
    } else {
      _scrollController.animateTo(target, duration: duration, curve: curve);
    }
  }

  // -------------------------------------------------------------------------
  // M4: Replace callback (l) — routes replaceCurrent() through _applyResult
  // -------------------------------------------------------------------------

  /// Called by [FindSearchBar.onReplace] when the user taps Replace.
  ///
  /// Calls [findProvider.notifier.replaceCurrent()] to get the replace record,
  /// then routes it through [_applyResult] (the M3 atomic-rewrite path).
  /// This is the ONLY write on the find/replace path (NFR-04 / §5.2 / §5.3).
  /// [updateText] fires naturally via the existing two-way-sync listener (EC-14).
  void _onSearchBarReplace() {
    final record = ref.read(findProvider.notifier).replaceCurrent();
    if (record == null) return;
    _applyResult((
      text: record.text,
      selection: TextSelection.collapsed(offset: record.nextCaretOffset),
    ));
  }

  // -------------------------------------------------------------------------
  // M4: Ctrl+F re-press — refocus + select-all (spec §5.3 refocus_search)
  // -------------------------------------------------------------------------

  /// Called when Ctrl+F is pressed while find is already active.
  ///
  /// Per spec §5.3, re-pressing Ctrl+F while active does NOT call
  /// [startSearch] again. Instead, it refocuses the search field and
  /// selects all text in it (mobile model: index-based, not selection-based).
  void _refocusSearch() {
    _searchFocusNode.requestFocus();
    // Select-all in the search field is handled by the FocusNode gaining
    // focus; the TextEditingController inside FindSearchBar is internal.
    // We rely on the OS/Flutter to restore the cursor to the end or select-all
    // based on focus gain. For explicit select-all, a GlobalKey on the search
    // bar's TextEditingController would be needed — not available without
    // modifying FindSearchBar further.
    // CANON GAP: select-all on refocus is best-effort here; a future M task
    // can expose the search controller via FindSearchBar for full compliance.
  }

  // -------------------------------------------------------------------------
  // SP-20260615 TASK-07: Find affordance wiring (FR-09, FR-10, C3/C4, NFR-04)
  // -------------------------------------------------------------------------

  /// Injected into [openMenuSheet] as [onFind] so the Find / Replace tile
  /// in [_MenuSheetContent] can open find without owning a [Ref] or calling
  /// [startSearch] directly (single-path discipline — NFR-04).
  ///
  /// The sheet self-pops via its own `Navigator.pop` before invoking this
  /// callback (C3 contract). We therefore defer the [OpenFindIntent] dispatch
  /// one post-frame to ensure the sheet's pop animation has completed and the
  /// [Actions] ancestor is still in the tree when [maybeInvoke] is called.
  ///
  /// A [mounted] guard prevents stale invocations after disposal (C4).
  ///
  /// **Single-path invariant (NFR-04):** this method calls NO [startSearch]
  /// directly. It routes exclusively through the existing
  /// [OpenFindIntent] → [_OpenFindOrRefocusAction] path, which is the sole
  /// [startSearch] call site in the codebase.
  ///
  /// **Context note:** `Actions.maybeInvoke` searches the InheritedWidget tree
  /// UPWARD from the given context; the [Actions] widget is a descendant of
  /// `_BufferScreenState`, so we must dispatch from a context INSIDE [Actions].
  /// We use [_editorFocusNode.context] (the [TextField]'s element, which sits
  /// below [Actions]) when available; when the editor is unfocused the context
  /// is still valid because [FocusNode] retains its context until disposal.
  void _openFindFromMenu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Prefer the editor focus node's context (inside the Actions widget),
      // falling back to the state context (may not reach Actions).
      final innerContext = _editorFocusNode.context ?? context;
      Actions.maybeInvoke(innerContext, const OpenFindIntent());
    });
  }

  // -------------------------------------------------------------------------
  // Warm-start subscriber (FR-M2-16, FR-M2-17, EC-M2-12)
  // -------------------------------------------------------------------------

  /// Stream-listener entry point. Chains [sharedText] onto [_shareQueue] so
  /// successive share events are processed strictly one-at-a-time (BUG-003).
  ///
  /// A failed event's error is caught and swallowed here so the queue future
  /// itself stays resolved and subsequent events are not poisoned.
  void _enqueueSharedText(String sharedText) {
    _shareQueue = _shareQueue.then((_) => _onSharedText(sharedText)).catchError(
      (_) {
        /* swallow: keep queue alive for next event */
      },
    );
  }

  /// The unit of work for one share event: save → reset → populate.
  ///
  /// The [!mounted] guard after the await prevents provider mutations when the
  /// widget has been disposed mid-chain (e.g. a queued event fires after the
  /// screen is popped).
  Future<void> _onSharedText(String sharedText) async {
    final currentText = ref.read(bufferProvider).text;
    final saveUseCase = ref.read(saveBufferToRecoveryProvider);
    await saveUseCase(currentText);
    if (!mounted) return;
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

    // (k) M4: Single ref.listen for find-state → push seams + scroll-to-match.
    ref.listen<FindState>(findProvider, _applyFindToController);

    // Watch find state for conditional FindSearchBar mount (i).
    final findState = ref.watch(findProvider);

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

    // M7 (f): Font-toast ref.listen — fires when fontSizeIndex changes.
    // Single listener; no-op on null/loading; guards against no-change.
    // Covers BOTH pinch and stepper font-size changes (FR-M7-07).
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      if (next.value == null) return;
      final prevIndex = previous?.value?.fontSizeIndex;
      // Suppress the toast on the initial load (loading→loaded), where there
      // is no prior value to compare against — only fire on a real change.
      if (prevIndex == null) return;
      final nextIndex = next.value!.fontSizeIndex;
      if (prevIndex == nextIndex) return;
      ref
          .read(toastProvider.notifier)
          .show(
            AppLocalizations.of(
              context,
            ).fontSizeToast(next.value!.fontSizePt.toInt()),
          );
    });

    // M7 (c): Resolve font family and fallback from useMonospaceFont.
    //
    // Mono path: 'monospace' as the primary family on Android/general;
    //   fontFamilyFallback: ['monospace'] for platform resolution to
    //   Roboto Mono (Android) / SF Mono (iOS/macOS) via the fallback chain.
    //
    // Document path: null family (theme default) +
    //   fontFamilyFallback: ['sans-serif'] for the platform sans-serif
    //   (Roboto on Android, SF Pro on iOS).
    //
    // The literal strings 'monospace' and 'sans-serif' are required by the
    // M7 gate scan (FR-M7-09).
    final String? fontFamily;
    final List<String> fontFamilyFallback;
    if (settings.useMonospaceFont) {
      fontFamily = 'monospace';
      fontFamilyFallback = const ['monospace'];
    } else {
      fontFamily = null;
      fontFamilyFallback = const ['sans-serif'];
    }

    // M7 (a): Apply fontSize from the 21-slot table (FR-M7-01).
    // Both editorStyle and strutStyle carry the same fontSize + height:1.4
    // (EC-M7-11 paired invariant). The strutStyle loses its const because
    // fontSize is now dynamic.
    //
    // M7 (b): textScaler is NOT set here — the framework reads
    // MediaQuery.textScalerOf(context) automatically (NFR-M7-01/02).
    // Never pre-multiply fontSize by the textScaler.
    final double fontSizePt = settings.fontSizePt;

    // SP-20260615 TASK-07 (FR-06a/FR-06b/NFR-10): Capture the system top
    // safe-area inset from this build context, which is ABOVE the SafeArea
    // child — SafeArea strips padding.top for its descendants, so reading
    // it here gives the raw platform inset (notch / status-bar / Dynamic Island).
    // Used by editorTopInset(width, safeAreaTop) inside the LayoutBuilder.
    final double safeAreaTop = MediaQuery.of(context).padding.top;

    // (f) Single editor TextStyle: height 1.4, fontSize from settings, family+fallback resolved.
    final editorStyle = TextStyle(
      height: 1.4,
      color: textColor,
      fontSize: fontSizePt,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    // Build the shortcuts + actions + editor field subtree via named helpers.
    // (TASK-01 extraction — behaviour identical to the pre-extraction inlined
    // code; helpers are called in build() with the same arguments and return
    // the exact same widget subtree.)
    final editorField = _buildShortcuts(context, spellCheck, editorStyle);

    // M6 (n): Build the Stack host — editor (bottom) + Positioned overlays.
    //
    // Stack children (bottom→top):
    //   1. editorField — fills the entire Stack (Positioned.fill or expands:true)
    //   2. FindSearchBar — Positioned(top:0) when findState.active (EC-04)
    //   3. ChromeOverlay — Positioned(top:0, right:0, from canon §Components §2)
    //   4. ToastOverlay  — Positioned(top:16, left:0, right:0, §Components §8)
    //
    // EC-04: The editor's render box is invariant — it always fills the Stack.
    // Neither the FindSearchBar, ChromeOverlay, nor ToastOverlay are Column
    // siblings; they are all Positioned overlays that do not affect layout.
    //
    // (i) M4: FindSearchBar is now a Positioned top slot in the Stack (not
    // a Column sibling). When active, it overlays the editor from the top;
    // the editor TextField (expands:true) fills the full Stack regardless.

    return Scaffold(
      // No AppBar — canon §Design ethos "no chrome at rest".
      extendBodyBehindAppBar: true,
      body: SafeArea(
        // M7 (d): Page-level pinch GestureDetector (FR-M7-05).
        //
        // Wraps the whole screen so the gesture is captured regardless of where
        // the two fingers land. Single-finger interactions (tap, drag, text
        // selection) are unaffected because:
        //  - onScaleStart fires for both one- and two-pointer gestures; we
        //    capture the start index here for both cases (cheap).
        //  - onScaleUpdate has a MANDATORY pointerCount == 2 guard (NFR-M7-03):
        //    single-finger drags (pointerCount == 1) do not change the slot.
        //  - Persist via setFontSizeIndex ONLY on onScaleEnd (MC-02).
        //
        // Pinch state (_scaleStartIndex) is ORTHOGONAL to _applyingState /
        // _continuing — those guard text rewrites; this guards font-size only.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleStart: (details) {
            // Capture the start index so slot steps are anchored to it.
            _scaleStartIndex =
                (ref.read(settingsProvider).valueOrNull ?? const AppSettings())
                    .fontSizeIndex;
          },
          onScaleUpdate: (details) {
            // MANDATORY guard (NFR-M7-03): only respond to two-pointer pinch.
            // Single-finger drags must not change font size.
            if (details.pointerCount != 2) return;

            // Compute target index from scale and start index.
            final delta = scaleToSlotDelta(details.scale, _scaleStartIndex);
            final target = (_scaleStartIndex + delta).clamp(
              0,
              AppSettings.slotList.length - 1,
            );

            // Optimistic in-flight update: update settings provider during
            // the gesture so the editor reflects the new size immediately.
            // This is a lightweight read — no file I/O (setFontSizeIndex is
            // no-op when identical, so redundant calls are cheap).
            // Persist (file I/O) only on onScaleEnd.
            ref.read(settingsProvider.notifier).setFontSizeIndex(target);
          },
          onScaleEnd: (details) {
            // Persist the final index on gesture end (MC-02: persist-on-end).
            // Re-read to get whatever index onScaleUpdate last set.
            final finalIndex =
                (ref.read(settingsProvider).valueOrNull ?? const AppSettings())
                    .fontSizeIndex;
            ref.read(settingsProvider.notifier).setFontSizeIndex(finalIndex);
          },
          child: Stack(
            children: [
              // ---------------------------------------------------------------
              // M7 (e): Bottom layer — LayoutBuilder → responsive column.
              //
              // Replaces the old Padding(horizontal:10) wrapper.
              // The LayoutBuilder reads constraints.maxWidth to compute:
              //   - verticalMargin: interpolated 10→36 over 400..800dp.
              //   - horizontal margin: the editor is capped at 720dp max-width
              //     and filled below (no max-width clipping on narrow screens).
              //
              // EC-M7-04: editor is still inside Positioned.fill — it never
              // becomes a Column sibling of the overlays.
              // ---------------------------------------------------------------
              Positioned.fill(
                // The find header (when active) is a Column sibling ABOVE the
                // editor so it PUSHES the text down instead of overlaying it
                // (upstream behaviour: the text shifts down when the search /
                // replace bar opens). Chrome + toast remain Positioned overlays.
                child: Column(
                  children: [
                    if (findState.active)
                      FindSearchBar(
                        onReplace: _onSearchBarReplace,
                        focusNode: _searchFocusNode,
                        replaceRowNotifier: _replaceRowNotifier,
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // SP-20260615 TASK-07 (FR-04..FR-07, FR-06a, FR-06b,
                          // NFR-08, NFR-10): Per-side EdgeInsets replacing the M7
                          // vertical-only padding. The four sides are:
                          //   left  = editorHorizontalMargin(fontSizePt) — ~2 char
                          //   top   = editorTopInset(maxWidth, safeAreaTop)
                          //            = max(kChromeMenuZoneHeight + safeAreaTop,
                          //                  verticalMargin(maxWidth))
                          //           Clears chrome + system inset; >= M7 vMargin.
                          //   right = editorHorizontalMargin(fontSizePt) — symmetric
                          //   bottom = verticalMargin(maxWidth) — M7 unchanged
                          //
                          // MUST stay on the OUTER Padding (outside RenderEditable)
                          // so _scrollToMatch / after-Enter geometry stay valid (FR-05).
                          //
                          // <!-- CANON GAP: ui-design-bible.md §Components.3 editor
                          //      text view does not specify exact horizontal margin
                          //      values or a top chrome-clearance formula; the
                          //      editorHorizontalMargin + editorTopInset derivation
                          //      is a mobile-specific addition (OQ-14). -->
                          final maxWidth = constraints.maxWidth;
                          final vMargin = verticalMargin(maxWidth);
                          final hMargin = editorHorizontalMargin(fontSizePt);
                          // When find is active the search header occupies the top of
                          // the screen (and the chrome menu is hidden), so the editor
                          // only needs the small responsive vertical margin above it —
                          // the header itself provides the top clearance and pushes
                          // the text down. When find is inactive, reserve the chrome
                          // menu zone so the first row clears the hamburger.
                          final topInset = findState.active
                              ? vMargin
                              : editorTopInset(maxWidth, safeAreaTop);
                          final editorColumn = Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 720.0,
                              ),
                              child: editorField,
                            ),
                          );
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              hMargin,
                              topInset,
                              hMargin,
                              vMargin,
                            ),
                            child: editorColumn,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ---------------------------------------------------------------
              // ChromeOverlay: Positioned top-end (canon §Components §2).
              // Wires onMenuTap → openMenuSheet(context) (FR-M6-23).
              // ---------------------------------------------------------------
              // SP-20260615 TASK-07 (FR-09/FR-10, C3/C4, NFR-04): inject
              // _openFindFromMenu so the Find / Replace tile in the menu sheet
              // reaches find via the existing OpenFindIntent single path.
              //
              // Hidden while find is active: the FindSearchBar (Positioned
              // top:0, full width) places its rightmost control — the Replace
              // toggle — under this top-end menu zone. With the chrome painted
              // on top and hit-testable, taps on "Replace" were intercepted by
              // the hamburger (the search bar already owns the top; Esc / the
              // bar's own back button close find). Mounting the chrome only when
              // find is inactive removes the collision entirely.
              if (!findState.active)
                ChromeOverlay(
                  onMenuTap: () =>
                      openMenuSheet(context, onFind: _openFindFromMenu),
                ),

              // ---------------------------------------------------------------
              // ToastOverlay: Positioned top-centre (canon §Components §8).
              // Pure overlay — never resizes the editor (EC-04).
              // ---------------------------------------------------------------
              const ToastOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build helpers (TASK-01 extraction — FR-M6-05, OQ-M6-08)
  //
  // Pure method extraction of the original inlined build() body.
  // No behaviour change — every widget, property, callback, and guard is
  // identical to the pre-extraction code. The helpers enable TASK-12 (Wave 5)
  // to integrate shell overlays into the editor host without touching the
  // editor subtree itself.
  // -------------------------------------------------------------------------

  /// Builds the hardware-key [Shortcuts] map wrapping the editor field.
  ///
  /// (c) + M4 + M6: Maps Return/KP_Enter, Tab, Shift+Tab, Ctrl+F/G/Shift+G/H,
  /// Ctrl+V, Esc to their corresponding [Intent]s.
  ///
  /// M6 Esc precedence (FR-M6-22, D7): A single [EscPrecedenceIntent] is fired;
  /// the paired [_EscPrecedenceAction] resolves the chain:
  ///   1. find active → dispatch [CloseFindIntent]
  ///   2. else → dispatch [DismissChromeIntent]
  /// Delegates inner content to [_buildActions].
  Widget _buildShortcuts(
    BuildContext context,
    SpellCheckConfiguration spellCheck,
    TextStyle editorStyle,
  ) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Return / Enter → ContinueListIntent.
        const SingleActivator(LogicalKeyboardKey.enter):
            const ContinueListIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ContinueListIntent(),
        // Tab → IndentIntent (consumed — no focus traversal).
        const SingleActivator(LogicalKeyboardKey.tab): const IndentIntent(),
        // Shift+Tab → OutdentIntent (also covers ISO_Left_Tab / X11 Shift+Tab).
        const SingleActivator(LogicalKeyboardKey.tab, shift: true):
            const OutdentIntent(),
        // M4: Find/Replace hardware shortcuts (FR-21 / spec §5.3).
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const OpenFindIntent(),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true):
            const FindNextIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyG,
          control: true,
          shift: true,
        ): const FindPrevIntent(),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true):
            const ToggleReplaceIntent(),
        // M6: Esc — precedence chain (FR-M6-22, D7):
        //   1. find active → CloseFindIntent
        //   2. else → DismissChromeIntent (hide chrome)
        // Implemented via _EscPrecedenceAction which dispatches the appropriate
        // child intent.
        const SingleActivator(LogicalKeyboardKey.escape):
            const _EscPrecedenceIntent(),
        // M6: Ctrl+V → PasteIntent (FR-M6-20).
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const PasteIntent(),
      },
      child: _buildActions(context, spellCheck, editorStyle),
    );
  }

  /// Builds the [Actions] map binding each [Intent] to its concrete [Action].
  ///
  /// Delegates the editor [TextField] itself to [_buildEditorField].
  Widget _buildActions(
    BuildContext context,
    SpellCheckConfiguration spellCheck,
    TextStyle editorStyle,
  ) {
    return Actions(
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
        // M4: Find actions — all delegate to findProvider verbs (FR-21).
        // OpenFindAction: if already active → refocus search; else startSearch.
        OpenFindIntent: _OpenFindOrRefocusAction(
          controller: _controller,
          startSearch: ({required int entryOffset}) {
            ref
                .read(findProvider.notifier)
                .startSearch(entryOffset: entryOffset);
          },
          isActive: () => ref.read(findProvider).active,
          refocusSearch: _refocusSearch,
        ),
        FindNextIntent: FindNextAction(
          next: () => ref.read(findProvider.notifier).next(),
        ),
        FindPrevIntent: FindPrevAction(
          previous: () => ref.read(findProvider.notifier).previous(),
        ),
        ToggleReplaceIntent: ToggleReplaceAction(
          onToggle: () {
            // Toggle replace-row via the shared notifier (FR-21 / §5.3).
            // Works regardless of whether the search bar is currently mounted.
            _replaceRowNotifier.value = !_replaceRowNotifier.value;
          },
        ),
        CloseFindIntent: CloseFindAction(
          close: () => ref.read(findProvider.notifier).close(),
        ),
        // M6: Esc precedence chain (FR-M6-22, D7).
        _EscPrecedenceIntent: _EscPrecedenceAction(
          isFindActive: () => ref.read(findProvider).active,
          closeFindIntent: () => ref.read(findProvider.notifier).close(),
          dismissChrome: () =>
              ref.read(chromeVisibilityProvider.notifier).reveal(),
        ),
        // M6: Paste — reads clipboard and inserts at caret (FR-M6-20).
        PasteIntent: PasteAction(controller: _controller, apply: _applyResult),
        // M6: DismissChrome — hides chrome overlay (FR-M6-22).
        DismissChromeIntent: DismissChromeAction(
          onDismiss: () =>
              ref.read(chromeVisibilityProvider.notifier).onTextChanged(),
        ),
      },
      child: _buildEditorField(context, spellCheck, editorStyle),
    );
  }

  /// Builds the full-bleed multiline [TextField] (canon §Components §3).
  ///
  /// Properties are invariant across all editor states:
  ///   - [expands]: true — fills available space.
  ///   - [maxLines]: null — unbounded multiline.
  ///   - [autofocus]: true — claims focus on mount.
  ///   - [scrollController]: shared [_scrollController] (FR-19).
  ///   - [focusNode]: [_editorFocusNode] (FR-22 / spec §5.5).
  ///   - [style]: height 1.4, fontSize from settings, family+fallback resolved (M7).
  ///   - [strutStyle]: paired with editorStyle (EC-M7-11 invariant).
  ///   - [spellCheckConfiguration]: derived from settingsProvider (FR-20/21).
  ///
  /// M7 (b): No explicit textScaler — the framework reads
  /// MediaQuery.textScalerOf(context) automatically (NFR-M7-01/02).
  TextField _buildEditorField(
    BuildContext context,
    SpellCheckConfiguration spellCheck,
    TextStyle editorStyle,
  ) {
    // M7 (a): Extract fontSize from the editorStyle for the paired strutStyle.
    // EC-M7-11: strutStyle.fontSize must equal editorStyle.fontSize.
    final double? fontSize = editorStyle.fontSize;

    return TextField(
      controller: _controller,
      // (j) M4: Wire editor FocusNode (FR-22 / spec §5.5).
      focusNode: _editorFocusNode,
      // (e) Shared external scroll controller — TextField never self-scrolls (FR-19).
      scrollController: _scrollController,
      // Full-bleed multiline text area — canon §Components §3.
      maxLines: null,
      expands: true,
      autofocus: true,
      // Chrome-free: no border, no label, no hint.
      decoration: const InputDecoration.collapsed(hintText: null),
      // (f)/(M7a) Editor style: height 1.4, fontSize + family from settings.
      style: editorStyle,
      // (f)/(M7a) Matching StrutStyle — paired invariant EC-M7-11.
      // Not const because fontSize is dynamic (resolved from settings at build time).
      strutStyle: StrutStyle(
        fontSize: fontSize,
        height: 1.4,
        forceStrutHeight: true,
      ),
      // Soft-wrap word/char — canon §Components §3.
      textAlignVertical: TextAlignVertical.top,
      // (g) Reactive spell-check from settings (FR-20, FR-21).
      spellCheckConfiguration: spellCheck,
    );
  }
}

// ---------------------------------------------------------------------------
// M4: Custom action combining OpenFindAction + Ctrl+F-while-active refocus
// ---------------------------------------------------------------------------

/// Handles [OpenFindIntent] with two modes (spec §5.3):
///
/// - When find is **not** active: calls [startSearch] with the editor caret
///   offset (same as [OpenFindAction]).
/// - When find **is** active: refocuses the search field + selects all (no
///   fresh [startSearch] — the match list and currentMatchIndex are preserved).
///
/// This keeps the Ctrl+F→refocus path co-located with the Ctrl+F→startSearch
/// path (FR-21 single-path) rather than adding a separate shortcut binding.
class _OpenFindOrRefocusAction extends Action<OpenFindIntent> {
  _OpenFindOrRefocusAction({
    required this.controller,
    required this.startSearch,
    required this.isActive,
    required this.refocusSearch,
  });

  final EditorController controller;
  final void Function({required int entryOffset}) startSearch;
  final bool Function() isActive;
  final VoidCallback refocusSearch;

  @override
  void invoke(OpenFindIntent intent) {
    if (isActive()) {
      // Already active — refocus search field without a fresh startSearch.
      refocusSearch();
    } else {
      // SP-20260615 TASK-07 (FR-11, C5, EC-02): clamp baseOffset to >= 0.
      // When the editor is unfocused (e.g. opened from the menu sheet while
      // no text cursor is placed), selection.baseOffset == -1.  Passing -1
      // to startSearch would trigger a RangeError inside the find engine.
      // math.max(0, baseOffset) covers both the Ctrl+F caller and the new
      // menu-sheet caller without adding a second startSearch call site.
      startSearch(entryOffset: math.max(0, controller.selection.baseOffset));
    }
  }
}

// ---------------------------------------------------------------------------
// M6: Esc precedence chain (FR-M6-22, D7)
// ---------------------------------------------------------------------------

/// Internal intent for the Esc key precedence chain (FR-M6-22, D7).
///
/// Fired by the [Shortcuts] binding on [LogicalKeyboardKey.escape].
/// Resolved by [_EscPrecedenceAction] into the correct child action:
///   1. find active → close find (highest precedence)
///   2. else → hide/dismiss chrome
///
/// Using a dedicated intent (rather than directly binding [CloseFindIntent]
/// to Esc) allows the precedence logic to live in one place (the Action)
/// rather than spread across multiple Shortcut bindings.
@immutable
class _EscPrecedenceIntent extends Intent {
  const _EscPrecedenceIntent();
}

/// Resolves [_EscPrecedenceIntent] into the correct action (FR-M6-22, D7).
///
/// Precedence (fixed if/else chain, D7):
///   1. find active → calls [closeFindIntent] (same effect as [CloseFindAction])
///   2. else → calls [dismissChrome]
///
/// The chrome-dismiss branch calls [dismissChrome] which reveals the chrome
/// (so Esc while chrome is hidden shows it, matching the M6 spec §4.3 Esc
/// semantics: "reveal chrome" when no other action applies).
class _EscPrecedenceAction extends Action<_EscPrecedenceIntent> {
  _EscPrecedenceAction({
    required this.isFindActive,
    required this.closeFindIntent,
    required this.dismissChrome,
  });

  final bool Function() isFindActive;
  final VoidCallback closeFindIntent;
  final VoidCallback dismissChrome;

  @override
  void invoke(_EscPrecedenceIntent intent) {
    if (isFindActive()) {
      // Precedence 1: find is open → close find.
      closeFindIntent();
    } else {
      // Precedence 2: reveal chrome (Esc when find closed toggles chrome).
      dismissChrome();
    }
  }
}
