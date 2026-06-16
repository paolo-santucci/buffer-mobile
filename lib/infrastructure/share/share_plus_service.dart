// TASK-06: SharePlusService — EC-M2-13 isolation boundary.
// Spec refs: FR-06, FR-07, NFR-01, EC-03, EC-04, §5.1.2.
//
// This is the ONLY file in lib/ permitted to import package:share_plus.
// No share_plus type — in particular no ShareResult — may appear in any
// public parameter or return-type signature in this file (FR-07).
//
// ShareResult is used ONLY inside the _defaultShare closure, where the
// awaited result is discarded. Callers see only Future<void>.
//
// EC-03 (user cancels): the platform returns a dismissed ShareResult; the
// Future<void> resolves normally — no error is surfaced to the caller.
//
// EC-04 (platform throws): a Dart-native exception propagates through the
// Future<void>. No share_plus type leaks in the error.
//
// NOTE: ShareParams(text: '') throws ArgumentError from inside share_plus
// when text is an empty string. Callers guard via enabled = text.trim().isNotEmpty
// (TASK-09), so shareText is not normally called with empty text. This
// adapter does NOT silently swallow that error — it propagates per EC-04.
//
// OQ-02 resolution: return type is Future<void> (not Future<bool>) because
// the caller has no actionable response to a share-sheet cancellation.
//
// Testability seam: accepts an optional Future<void> Function(String)
// that performs the actual platform call. In production the default
// delegate calls SharePlus.instance.share(). Tests inject a stub
// delegate to intercept platform calls without subclassing SharePlatform.

import 'package:buffer/infrastructure/share/share_target_service.dart';
import 'package:share_plus/share_plus.dart';

Future<void> _defaultShare(String text) async {
  // ShareResult is intentionally discarded here. It must never appear in
  // any parameter or return-type signature of this class (FR-07, EC-M2-13).
  await SharePlus.instance.share(ShareParams(text: text));
}

/// Concrete OS share-dispatch adapter.
///
/// Implements [ShareTargetService] using `share_plus` v12.
/// This is the SOLE `lib/` file that imports `package:share_plus` (EC-M2-13).
final class SharePlusService implements ShareTargetService {
  final Future<void> Function(String) _share;

  /// Creates a [SharePlusService].
  ///
  /// [shareDelegate] is used only in tests to intercept the platform call
  /// without subclassing [SharePlatform]. In production, omit this parameter —
  /// the default delegate calls [SharePlus.instance.share].
  SharePlusService({Future<void> Function(String)? shareDelegate})
    : _share = shareDelegate ?? _defaultShare;

  /// Dispatches [text] to the OS share sheet.
  ///
  /// Awaits the share operation and discards the [ShareResult] — the caller
  /// receives only [Future<void>] (FR-07, OQ-02). A dismissed share sheet
  /// (EC-03) resolves normally. A platform exception (EC-04) propagates
  /// as a Dart-native error.
  @override
  Future<void> shareText(String text) => _share(text);
}
