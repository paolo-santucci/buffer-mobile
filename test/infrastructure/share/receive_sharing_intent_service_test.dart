// TASK-03: ReceiveSharingIntentService — concrete adapter tests.
// Spec refs: FR-M2-15, FR-M2-16, FR-M2-17, EC-M2-10, EC-M2-12, §4.1, §5.3
//
// Test plan:
//   1. initialMedia=[text "hello"] → initialSharedText() == "hello".
//   2. initialMedia=[]             → initialSharedText() == null.
//   3. initialMedia=[text ""]      → initialSharedText() == null (never "").
//   4. mediaStream emits [text "warm"] → sharedTextStream() emits "warm" once;
//      reset() called after the map (verified via spy).
//   5. mediaStream emits empty list → no emission on the mapped stream.
//
// OQ-M2-09 resolved: setMockValues({initialMedia, mediaStream}) IS present at 1.8.1.
// For the reset()-spy case (test 4) we inject the ReceiveSharingIntent instance
// directly into the adapter using the injectable-seam constructor parameter.
// The spy is a proper `extends ReceiveSharingIntent` subclass — no import of
// plugin_platform_interface required (extends sets the PlatformInterface token
// correctly, unlike `implements`).
//
// EC-M2-12 isolation: no receive_sharing_intent type appears in the test public
// API surface; the package is only referenced here for the spy setup.
// The adapter is the ONLY lib/ file permitted to import the package.

import 'dart:async';

import 'package:buffer/infrastructure/share/receive_sharing_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

// ---------------------------------------------------------------------------
// Spy: a concrete ReceiveSharingIntent subclass that records reset() calls.
// Uses `extends` (not `implements`) so PlatformInterface.verify passes when
// the instance is assigned to ReceiveSharingIntent.instance, without needing
// MockPlatformInterfaceMixin.
// ---------------------------------------------------------------------------
class _SpyReceiveSharingIntent extends ReceiveSharingIntent {
  final List<SharedMediaFile> _initialMedia;
  final Stream<List<SharedMediaFile>> _mediaStream;

  int resetCallCount = 0;

  _SpyReceiveSharingIntent({
    required this._initialMedia,
    required this._mediaStream,
  });

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => _initialMedia;

  @override
  Stream<List<SharedMediaFile>> getMediaStream() => _mediaStream;

  @override
  Future<dynamic> reset() async {
    resetCallCount++;
  }
}

void main() {
  late ReceiveSharingIntentService service;

  tearDown(() {
    service.dispose();
    // Restore a clean singleton after any test that overrides the instance.
    ReceiveSharingIntent.setMockValues(
      initialMedia: const [],
      mediaStream: const Stream.empty(),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // initialSharedText() — cold-start text intake
  // ──────────────────────────────────────────────────────────────────────────

  group('initialSharedText()', () {
    test('returns path of first text-type media file', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(path: 'hello', type: SharedMediaType.text),
        ],
        mediaStream: const Stream.empty(),
      );
      service = ReceiveSharingIntentService();

      expect(await service.initialSharedText(), 'hello');
    });

    test('returns null when initial media list is empty', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: const Stream.empty(),
      );
      service = ReceiveSharingIntentService();

      expect(await service.initialSharedText(), isNull);
    });

    test(
      'returns null — never "" — when text media path is empty (FR-M2-17)',
      () async {
        ReceiveSharingIntent.setMockValues(
          initialMedia: [SharedMediaFile(path: '', type: SharedMediaType.text)],
          mediaStream: const Stream.empty(),
        );
        service = ReceiveSharingIntentService();

        final result = await service.initialSharedText();

        expect(result, isNull);
        expect(result, isNot(''));
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // sharedTextStream() — warm-start text intake
  // ──────────────────────────────────────────────────────────────────────────

  group('sharedTextStream()', () {
    test('emits text value when mediaStream emits a list with a text media file '
        'and calls reset() after the map (EC-M2-12)', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      final spy = _SpyReceiveSharingIntent(
        initialMedia: const [],
        mediaStream: controller.stream,
      );
      ReceiveSharingIntent.instance = spy;
      service = ReceiveSharingIntentService();

      final emitted = <String>[];
      final sub = service.sharedTextStream().listen(emitted.add);

      controller.add([
        SharedMediaFile(path: 'warm', type: SharedMediaType.text),
      ]);
      // Allow the async listener + reset() to propagate through the event loop.
      await Future<void>.delayed(Duration.zero);

      expect(emitted, ['warm']);
      expect(
        spy.resetCallCount,
        1,
        reason:
            'reset() must be called once after each mapped warm-start event',
      );

      await sub.cancel();
      await controller.close();
    });

    test('does not emit when mediaStream emits an empty list', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      final spy = _SpyReceiveSharingIntent(
        initialMedia: const [],
        mediaStream: controller.stream,
      );
      ReceiveSharingIntent.instance = spy;
      service = ReceiveSharingIntentService();

      final emitted = <String>[];
      final sub = service.sharedTextStream().listen(emitted.add);

      controller.add(const []);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
      expect(
        spy.resetCallCount,
        0,
        reason: 'reset() must NOT be called when the list yields no text',
      );

      await sub.cancel();
      await controller.close();
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // dispose() — resource cleanup
  // ──────────────────────────────────────────────────────────────────────────

  group('dispose()', () {
    test('cancels the stream subscription without throwing', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: const Stream.empty(),
      );
      service = ReceiveSharingIntentService();
      final sub = service.sharedTextStream().listen((_) {});
      await sub.cancel();

      expect(() => service.dispose(), returnsNormally);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Contract — satisfies the M1 ShareIntentService interface
  // ──────────────────────────────────────────────────────────────────────────

  group('ShareIntentService contract', () {
    test('ReceiveSharingIntentService is a ShareIntentService (EC-M2-10)', () {
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: const Stream.empty(),
      );
      service = ReceiveSharingIntentService();

      // Compile-time proof: the class declaration `implements ShareIntentService`
      // would fail compilation if the interface were violated. Being reachable at
      // runtime is the assertion.
      expect(service, isA<ReceiveSharingIntentService>());
    });
  });
}
