// TASK-06: ShareIntentService interface contract tests.
// Spec refs: FR-17, EC-12.
//
// These tests verify:
//   1. A no-op fake implementing ShareIntentService satisfies the full contract
//      (FR-17: any conforming impl can be substituted).
//   2. No receive_sharing_intent type leaks through the interface signatures (EC-12).
//
// No concrete receive_sharing_intent import appears anywhere in this file.
// The interface declares exactly: initialSharedText, sharedTextStream, dispose.

import 'dart:async';

import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// No-op fake — the only implementation allowed in M1.
// Must satisfy the interface with zero imports from receive_sharing_intent.
// ---------------------------------------------------------------------------
class _NoOpShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

void main() {
  group('ShareIntentService contract', () {
    late ShareIntentService service;

    setUp(() {
      service = _NoOpShareIntentService();
    });

    // FR-17: substitutable — any conforming impl must satisfy these.

    test('initialSharedText() completes with null without throwing', () async {
      final result = await service.initialSharedText();
      expect(result, isNull);
    });

    test('sharedTextStream() returns a Stream<String>', () {
      final stream = service.sharedTextStream();
      expect(stream, isA<Stream<String>>());
    });

    test('dispose() is callable without throwing', () {
      expect(() => service.dispose(), returnsNormally);
    });

    // EC-12: interface isolation — the fake uses only dart:async + the interface.
    // This is enforced structurally: _NoOpShareIntentService imports nothing from
    // receive_sharing_intent, and the interface itself (verified below) exposes only
    // Dart-native types (Future<String?>, Stream<String>, void).

    test('fake implements ShareIntentService with no receive_sharing_intent types '
        'in the interface signature', () {
      // Structural proof: _NoOpShareIntentService compiles against the interface
      // without any receive_sharing_intent import, which would fail at compile time
      // if the interface leaked a package type. This test being reachable at runtime
      // is the assertion.
      expect(service, isA<ShareIntentService>());
    });
  });
}
