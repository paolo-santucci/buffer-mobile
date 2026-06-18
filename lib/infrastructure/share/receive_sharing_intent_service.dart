// TASK-03: ReceiveSharingIntentService — concrete adapter.
// Spec refs: FR-M2-15, FR-M2-16, FR-M2-17, EC-M2-10, EC-M2-12, §4.1, §5.3
//
// EC-M2-12 isolation: this is the ONLY file in lib/ permitted to import
// 'package:receive_sharing_intent/...'. No receive_sharing_intent type
// escapes past this boundary into domain or presentation layers.

import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:foglietto/infrastructure/share/share_intent_service.dart';

/// Concrete implementation of [ShareIntentService] backed by the
/// `receive_sharing_intent` package.
///
/// Isolation contract (EC-M2-12): all `SharedMediaFile` values are mapped
/// to [String] or `null` inside this class; no package type is exposed in
/// any public signature.
///
/// Empty-string guard (FR-M2-17): the adapter never emits or returns `""`.
/// An empty `path` on the incoming [SharedMediaFile] is treated the same as
/// a missing file — both resolve to `null` / no emission.
///
/// Reset on warm-start (EC-M2-12): [ReceiveSharingIntent.reset] is called
/// internally after each warm-start event is mapped, so a repeated identical
/// share is not re-delivered as stale.
class ReceiveSharingIntentService implements ShareIntentService {
  StreamSubscription<List<SharedMediaFile>>? _mediaSubscription;

  @override
  Future<String?> initialSharedText() async {
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    return _textFromFiles(files);
  }

  @override
  Stream<String> sharedTextStream() {
    // Use an async* generator so we can call reset() after each emission
    // and avoid delivering stale repeated shares (EC-M2-12).
    final controller = StreamController<String>();

    _mediaSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) async {
        final text = _textFromFiles(files);
        if (text != null) {
          controller.add(text);
          // Reset after mapping so a repeated identical share is not
          // re-delivered as stale (EC-M2-12).
          await ReceiveSharingIntent.instance.reset();
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    return controller.stream;
  }

  @override
  void dispose() {
    _mediaSubscription?.cancel();
    _mediaSubscription = null;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts the text from the first text-type [SharedMediaFile] in [files].
  ///
  /// Returns `null` if [files] is empty, if no file has [SharedMediaType.text],
  /// or if the matching file's [SharedMediaFile.path] is empty (FR-M2-17).
  String? _textFromFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return null;
    for (final file in files) {
      if (file.type == SharedMediaType.text && file.path.isNotEmpty) {
        return file.path;
      }
    }
    return null;
  }
}
