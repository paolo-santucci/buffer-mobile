// TASK-09: BufferScreen — blank chrome-free editor surface.
//
// Spec refs: FR-M2-01, FR-M2-02, FR-M2-03, FR-M2-04, FR-M2-15, FR-M2-16,
//            FR-M2-17, EC-M2-01, EC-M2-03, EC-M2-04, EC-M2-05, EC-M2-10,
//            EC-M2-11, EC-M2-12, NFR-M2-05, NFR-M2-06, §4.1, §5.1.5
//
// Canon refs: .claude/docs/canon/ui-design-bible.md
//   §Design ethos — "chrome-free at rest"; content fills the screen.
//   §Components §1 — App shell: Scaffold body = full-bleed editor.
//   §Components §3 — Editor text view: full-bleed, maxLines:null, no border,
//                    line-height 1.4, monospace, dynamic margins.
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:buffer/presentation/editor/share_providers.dart';

// <!-- CANON GAP: §Components §3 specifies a monospace font family resolved
//      from the platform's system monospace font (Roboto Mono / SF Mono).
//      Flutter's TextField does not auto-resolve a monospace font by default.
//      The font family is not wired here until the TypographySettings /
//      Settings screen integration (M3/M5). For now the TextField inherits
//      the theme's default font. This gap is pre-existing and tracked in
//      D-003 and the typography spec open questions. -->

// <!-- CANON GAP: §Components §3 specifies dynamic margin interpolation
//      (MINIMUM_MARGIN=10 to BASE_MARGIN=36 over viewport widths 400..800).
//      The padding is hardcoded here to the minimum (10) for M2.
//      A LayoutBuilder-based interpolation will be wired in a later milestone
//      per the LP plan §4 "line-width / responsive max-width". -->

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

class _BufferScreenState extends ConsumerState<BufferScreen> {
  late final EditorController _controller;
  late final ScrollController _scrollController;
  StreamSubscription<String>? _shareSubscription;

  /// Whether the controller listener is currently in a state→controller
  /// assignment, used to suppress the echo-loop's re-triggering of
  /// controller→state.
  bool _applyingState = false;

  @override
  void initState() {
    super.initState();

    _controller = EditorController();
    _scrollController = ScrollController();

    // Cold-start seed (NFR-M2-06, B1/R-14):
    // Read the initial shared text BEFORE first frame. If non-null, seed the
    // controller synchronously (satisfies "no empty text on first frame") and
    // schedule the provider state mutation after the first frame (Riverpod
    // disallows provider mutation during initState/build).
    final seed = ref.read(initialSharedTextProvider);
    if (seed != null) {
      // Set controller text now — the first built frame shows seeded text.
      _controller.text = seed;
      // Sync provider state after the first frame to avoid the
      // "modify provider during build" assertion.
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
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scrollController.dispose();
    _shareSubscription?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // controller→state (EC-M2-01, echo-loop guard EC-M2-03)
  // -------------------------------------------------------------------------

  void _onControllerChanged() {
    if (_applyingState) return; // suppress echo-loop
    final currentText = ref.read(bufferProvider).text;
    if (_controller.text != currentText) {
      ref.read(bufferProvider.notifier).updateText(_controller.text);
    }
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
    // Save current buffer text before resetting (save→reset→populate order).
    final currentText = ref.read(bufferProvider).text;
    final saveUseCase = ref.read(saveBufferToRecoveryProvider);
    await saveUseCase(currentText); // no-op if currentText.trim().isEmpty
    ref.read(bufferProvider.notifier).reset();
    ref.read(bufferProvider.notifier).populate(sharedText);
  }

  // -------------------------------------------------------------------------
  // Selection clamping utility (EC-M2-05)
  //
  // Returns a [TextSelection] whose base and extent offsets are clamped to
  // [maxOffset]. Never throws a RangeError.
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

    final textColor = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      // No AppBar — canon §Design ethos "no chrome at rest".
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Padding(
          // Dynamic margin: M2 uses MINIMUM_MARGIN (10dp) per §Spacing.
          // <!-- CANON GAP: full interpolated margin (10→36 over 400..800px)
          //      deferred to later milestone. -->
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            controller: _controller,
            scrollController: _scrollController,
            // Full-bleed multiline text area — canon §Components §3.
            maxLines: null,
            expands: true,
            autofocus: true,
            // Chrome-free: no border, no label, no hint.
            decoration: const InputDecoration.collapsed(hintText: null),
            // Text colour from theme, never hardcoded — canon §Colour.
            style: TextStyle(color: textColor),
            // Soft-wrap word/char — canon §Components §3.
            textAlignVertical: TextAlignVertical.top,
          ),
        ),
      ),
    );
  }
}
