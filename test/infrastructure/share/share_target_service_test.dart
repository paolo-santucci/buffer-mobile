// TASK-03: ShareTargetService domain-pure interface contract tests.
// Spec refs: FR-06, FR-07, NFR-01, §5.1.1.
//
// These tests verify:
//   1. A trivial in-test stub implementing ShareTargetService satisfies the
//      full contract: shareText(String) returns Future<void>, awaits to null,
//      and no share_plus type appears in any signature (FR-07, NFR-01).
//   2. The interface source file imports neither share_plus nor flutter
//      (domain-pure, Dart-native types only; FR-06, §5.1.1).
//
// EC-M2-13 isolation invariant: ShareTargetService exposes ONLY Dart-native
// types. No share_plus import, no ShareResult, no Flutter type leaks through
// this interface. The concrete SharePlusService adapter (TASK-06) is the sole
// lib/ file permitted to import share_plus.

import 'dart:io';

import 'package:foglietto/infrastructure/share/share_target_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Trivial in-test stub — implements ShareTargetService using only Dart-native
// types. A compile-time failure here would prove the interface leaked a
// non-native type into its signatures.
// ---------------------------------------------------------------------------
class _StubShareTargetService implements ShareTargetService {
  @override
  Future<void> shareText(String text) async {}
}

void main() {
  group('ShareTargetService contract', () {
    late ShareTargetService service;

    setUp(() {
      service = _StubShareTargetService();
    });

    // FR-07: shareText() signature uses only Dart-native types (String param,
    // Future<void> return). The stub compiles without any share_plus import,
    // proving no package type leaked through the interface.

    test(
      'given a stub impl, when shareText is called, then it returns Future<void>',
      () async {
        // Await completes without error — Future<void> has no resolved value.
        await service.shareText('x');
      },
    );

    test(
      'given a stub impl, when shareText is called with a String, then it accepts the parameter',
      () async {
        // Structural assertion: the parameter is typed String — passing a non-String
        // would fail at compile time if the interface signature drifted.
        await expectLater(service.shareText('hello'), completes);
      },
    );

    test('given a stub impl, it is assignable to ShareTargetService', () {
      // Structural proof: _StubShareTargetService compiles against the interface
      // using only dart:async + dart:core types. This being reachable at runtime
      // proves no share_plus or flutter type leaked into the signatures (FR-07).
      expect(service, isA<ShareTargetService>());
    });

    // FR-06, §5.1.1: domain-pure interface — the interface source file must
    // import neither package:share_plus nor package:flutter/. Verified by
    // reading the source and asserting zero matching import lines.
    //
    // EC-M2-13 isolation: only the concrete adapter (share_plus_service.dart,
    // TASK-06) may import share_plus. The interface file must never do so.

    test(
      'source file imports neither share_plus nor flutter (domain-pure, EC-M2-13)',
      () {
        const interfaceFilePath =
            'lib/infrastructure/share/share_target_service.dart';
        final sourceFile = File(interfaceFilePath);
        expect(
          sourceFile.existsSync(),
          isTrue,
          reason: 'Interface file must exist at $interfaceFilePath',
        );

        final lines = sourceFile.readAsLinesSync();

        final sharePlusImports = lines
            .where((l) => l.startsWith("import 'package:share_plus"))
            .toList();
        expect(
          sharePlusImports,
          isEmpty,
          reason: 'Interface file must not import share_plus (EC-M2-13, FR-06)',
        );

        final flutterImports = lines
            .where((l) => l.startsWith("import 'package:flutter/"))
            .toList();
        expect(
          flutterImports,
          isEmpty,
          reason:
              'Interface file must not import flutter (domain-pure, §5.1.1)',
        );
      },
    );
  });
}
