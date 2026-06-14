import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State machine for chrome visibility (FR-M6-06/07, §5.1-e).
///
/// A pure [Notifier<bool>] with three transition inputs:
///   - [onTextChanged]     → hidden (false)
///   - [onUserScroll]      → reverse→hidden, forward→visible, idle→unchanged
///   - [onKeyboardDismissed] → visible (true)
///   - [reveal]            → visible (true)
///
/// **Guard contract (EC-07, D5/R-04):** the [BufferScreen] scroll listener
/// MUST NOT call [onUserScroll] while `_applyingState || _continuing` is true.
/// This controller is guard-AGNOSTIC — it accepts every call unconditionally.
/// The host owns the gate.
class ChromeRevealController extends Notifier<bool> {
  @override
  bool build() => true; // visible at rest

  /// Typing hides the chrome (FR-M6-06).
  void onTextChanged() {
    state = false;
  }

  /// User scroll-up (forward) reveals; scroll-down (reverse) hides; idle no-ops.
  void onUserScroll(ScrollDirection direction) {
    if (direction == ScrollDirection.forward) {
      state = true;
    } else if (direction == ScrollDirection.reverse) {
      state = false;
    }
    // idle → no change
  }

  /// Keyboard dismiss reveals chrome (FR-M6-06).
  void onKeyboardDismissed() {
    state = true;
  }

  /// Explicit reveal — e.g. from a tap or external host trigger.
  void reveal() {
    state = true;
  }
}

/// Non-auto-disposing provider so state survives zero-listener windows
/// between widget builds (mirrors the [bufferProvider] survival contract).
final chromeVisibilityProvider = NotifierProvider<ChromeRevealController, bool>(
  ChromeRevealController.new,
);
