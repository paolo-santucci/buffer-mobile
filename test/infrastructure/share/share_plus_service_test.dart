// TASK-06: SharePlusService adapter contract tests.
// Spec refs: FR-06, FR-07, NFR-01, EC-03, EC-04, §5.1.2.
//
// These tests verify:
//   1. SharePlusService() is a ShareTargetService; shareText('x') returns
//      Future<void>. (FR-06)
//   2. Source-scan — share_plus_service.dart implements ShareTargetService,
//      and the token ShareResult appears ONLY inside the method body (or not
//      at all), never in a parameter or return signature. (FR-07)
//   3. EC-03 cancel — share delegate faked to return normally (simulating a
//      dismissed share) → shareText resolves normally (no throw). (EC-03)
//   4. EC-04 throw — share delegate faked to throw → awaited Future<void>
//      propagates a Dart-native exception (not a share_plus type). (EC-04)
//
// Seam: SharePlusService accepts an optional shareDelegate function that
// performs the platform call. Tests inject a stub function to intercept the
// call without subclassing SharePlatform or importing
// share_plus_platform_interface as a direct dependency.
//
// EC-M2-13 isolation invariant: ShareResult must not appear in any parameter
// or return-type signature in share_plus_service.dart.

import 'dart:io';

import 'package:buffer/infrastructure/share/share_plus_service.dart';
import 'package:buffer/infrastructure/share/share_target_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharePlusService', () {
    // -----------------------------------------------------------------------
    // 1. Implements-interface — structural type assertion.
    // FR-06: SharePlusService must implement ShareTargetService.
    // -----------------------------------------------------------------------
    group('implements-interface', () {
      test('given default construction, it is a ShareTargetService', () {
        final service = SharePlusService();
        expect(service, isA<ShareTargetService>());
      });

      test('given default construction, shareText returns Future<void>', () {
        // Compile-time proof: if shareText returned anything other than
        // Future<void> this assignment would be a type error.
        final ShareTargetService service = SharePlusService(
          shareDelegate: (_) async {}, // stub to avoid real platform call
        );
        final Future<void> result = service.shareText('x');
        result.ignore();
      });
    });

    // -----------------------------------------------------------------------
    // 2. Source-scan — isolation invariant (EC-M2-13, FR-07).
    // -----------------------------------------------------------------------
    group('source-scan', () {
      const adapterPath = 'lib/infrastructure/share/share_plus_service.dart';

      test('adapter file exists', () {
        expect(
          File(adapterPath).existsSync(),
          isTrue,
          reason: 'Adapter must exist at $adapterPath',
        );
      });

      test('file contains "implements ShareTargetService"', () {
        final source = File(adapterPath).readAsStringSync();
        expect(
          source,
          contains('implements ShareTargetService'),
          reason:
              'Adapter must declare "implements ShareTargetService" (FR-06)',
        );
      });

      test(
        'file imports package:share_plus (sole share_plus importer in lib/)',
        () {
          final source = File(adapterPath).readAsStringSync();
          expect(
            source,
            contains("import 'package:share_plus/share_plus.dart'"),
            reason: 'Adapter must import share_plus (EC-M2-13 — sole importer)',
          );
        },
      );

      test('ShareResult does not appear in any parameter or return signature '
          '(confined to method body or absent — FR-07, EC-M2-13)', () {
        final lines = File(adapterPath).readAsLinesSync();

        // ShareResult must never appear as a return type or parameter type
        // in any signature. Acceptable uses: inside an async method body
        // (on a line containing "await" or as part of a comment).
        // The implementation discards the ShareResult silently via await,
        // so the token may not appear at all — also acceptable.
        final violations = <String>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
          if (!trimmed.contains('ShareResult')) continue;

          // Acceptable body usage: the line also contains "await" (discard
          // assignment) or is a comment suffix (inline "//").
          final isAcceptableBodyUsage =
              trimmed.contains('await') || trimmed.contains('//');
          if (!isAcceptableBodyUsage) {
            violations.add(line);
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'ShareResult must appear only in method-body await/discard '
              'lines, never in a signature. Violations: $violations '
              '(FR-07, EC-M2-13)',
        );
      });
    });

    // -----------------------------------------------------------------------
    // 3. EC-03 — user cancels/dismisses → Future<void> resolves normally.
    // The share delegate completes without throwing; no value is surfaced.
    // -----------------------------------------------------------------------
    group('EC-03 cancel/dismiss', () {
      test('when share delegate returns normally (dismiss), shareText resolves '
          'normally', () async {
        // Simulate a dismissed share: the delegate returns without error.
        var called = false;
        final service = SharePlusService(
          shareDelegate: (text) async {
            called = true;
            // No throw — simulates a user dismissing the share sheet (EC-03).
          },
        );

        await expectLater(service.shareText('hello'), completes);
        expect(called, isTrue);
      });

      test('when share delegate returns normally for any text, shareText '
          'resolves without surfacing a value', () async {
        final service = SharePlusService(shareDelegate: (_) async {});

        // Future<void> — the await completes with no returned value.
        await expectLater(service.shareText('any text'), completes);
      });
    });

    // -----------------------------------------------------------------------
    // 4. EC-04 — platform throws → Future<void> propagates the exception.
    // The error is a plain Dart exception, not a share_plus type.
    // -----------------------------------------------------------------------
    group('EC-04 platform throw', () {
      test(
        'when share delegate throws a StateError, shareText propagates it',
        () async {
          final service = SharePlusService(
            shareDelegate: (_) async => throw StateError('channel error'),
          );

          await expectLater(
            service.shareText('hello'),
            throwsA(isA<StateError>()),
          );
        },
      );

      test('when share delegate throws an Exception, shareText propagates '
          'it as-is', () async {
        final testException = Exception('platform failure');

        final service = SharePlusService(
          shareDelegate: (_) async => throw testException,
        );

        await expectLater(
          service.shareText('hello'),
          throwsA(same(testException)),
        );
      });

      test('when share delegate throws, the error is not wrapped in a '
          'share_plus type', () async {
        // Verify that the raw exception propagates without wrapping.
        final originalError = ArgumentError('empty text guard');

        final service = SharePlusService(
          shareDelegate: (_) async => throw originalError,
        );

        Object? caughtError;
        try {
          await service.shareText('hello');
        } catch (e) {
          caughtError = e;
        }

        // The caught error is the exact same object — no wrapping in a
        // share_plus type occurred (EC-04, FR-07).
        expect(caughtError, same(originalError));
      });
    });
  });
}
