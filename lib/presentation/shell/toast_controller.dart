import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Value object — the payload held in toastProvider state.
// Immutable; equality and hash are identity-based on [text].
// ---------------------------------------------------------------------------
@immutable
class ToastMessage {
  const ToastMessage(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ToastMessage && other.text == text);

  @override
  int get hashCode => text.hashCode;
}

// ---------------------------------------------------------------------------
// Controller — the M7 seam (FR-M6-14, D2).
//
// M6 defines the mechanism; M7 is the first caller.
// Single-Timer discipline: a new show() cancels the prior timer (EC-05).
// ref.onDispose guarantees timer cancellation on container teardown.
// ---------------------------------------------------------------------------
class ToastController extends Notifier<ToastMessage?> {
  Timer? _timer;

  @override
  ToastMessage? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Show [text]; auto-dismiss after [duration] (default 3 s).
  ///
  /// A second call before the prior timer fires cancels the prior timer (EC-05).
  void show(String text, {Duration duration = const Duration(seconds: 3)}) {
    _timer?.cancel();
    state = ToastMessage(text);
    _timer = Timer(duration, () => state = null);
  }

  /// Immediately hide the toast and cancel any pending timer.
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

// ---------------------------------------------------------------------------
// Provider — non-auto-disposing (the M7 seam must survive zero-listener
// windows without being torn down and losing the pending timer reference).
// ---------------------------------------------------------------------------
final toastProvider = NotifierProvider<ToastController, ToastMessage?>(
  ToastController.new,
);
