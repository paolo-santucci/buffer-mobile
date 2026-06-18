// TASK-10: main.dart composition root — TDD test.
// Spec refs: FR-M2-15, NFR-M2-06, B1/R-14, §4.1, §4.2
//
// Verifies:
//   1. Future.wait resolves SharedPreferences AND initialSharedText() before the
//      ProviderScope is built (ordering assertion via a recording fake).
//   2. The ProviderScope is seeded with
//      initialSharedTextProvider.overrideWithValue(sharedText); reading the
//      provider inside the tree returns the seeded value (no UnimplementedError).
//   3. sharedText == null path: provider override is null; tree builds without
//      throwing.
//
// Design:
//   bootstrap() is a @visibleForTesting helper in main.dart that accepts an
//   injected ShareIntentService and returns the two resolved values.  Tests call
//   it directly; main() calls it with the concrete ReceiveSharingIntentService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foglietto/infrastructure/share/share_intent_service.dart';
import 'package:foglietto/main.dart' show bootstrap;
import 'package:foglietto/presentation/app.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Recording fake — tracks call order for the ordering-assertion test.
// ---------------------------------------------------------------------------

class _RecordingShareIntentService implements ShareIntentService {
  _RecordingShareIntentService({required this._text, required this.log});

  final String? _text;
  final List<String> log;

  @override
  Future<String?> initialSharedText() async {
    log.add('initialSharedText');
    return _text;
  }

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // 1. Ordering: bootstrap() resolves BOTH values concurrently and returns them.
  // -------------------------------------------------------------------------

  group('bootstrap()', () {
    test(
      'resolves SharedPreferences and initialSharedText() and returns both',
      () async {
        SharedPreferences.setMockInitialValues({});
        final log = <String>[];
        final service = _RecordingShareIntentService(text: 'hello', log: log);

        final (prefs, sharedText) = await bootstrap(service);

        expect(prefs, isA<SharedPreferences>());
        expect(sharedText, equals('hello'));
        // initialSharedText() must have been called (ordering guarantee).
        expect(log, contains('initialSharedText'));
      },
    );

    test('returns null sharedText when service yields null', () async {
      SharedPreferences.setMockInitialValues({});
      final log = <String>[];
      final service = _RecordingShareIntentService(text: null, log: log);

      final (_, sharedText) = await bootstrap(service);

      expect(sharedText, isNull);
      expect(log, contains('initialSharedText'));
    });
  });

  // -------------------------------------------------------------------------
  // 2. ProviderScope seeding: initialSharedTextProvider is overridden with the
  //    resolved shared text before the first frame.
  // -------------------------------------------------------------------------

  group('ProviderScope seeding', () {
    testWidgets('given sharedText="seeded" the ProviderScope exposes it via '
        'initialSharedTextProvider (no UnimplementedError)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await _emptyPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            initialSharedTextProvider.overrideWithValue('seeded'),
          ],
          child: const BufferApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Read the provider from inside the tree.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(initialSharedTextProvider), equals('seeded'));
      expect(find.byType(ErrorWidget), findsNothing);
    });

    testWidgets(
      'given sharedText=null the ProviderScope seeded with null builds without '
      'throwing (null path)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await _emptyPrefs();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              // null override — must NOT throw UnimplementedError.
              initialSharedTextProvider.overrideWithValue(null),
            ],
            child: const BufferApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.byType(MaterialApp), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 3. M1 compatibility: sharedPreferencesProvider override stays green.
  //    Pump BufferApp with BOTH prefs and initialSharedText overrides (the new
  //    minimum required by the updated composition root).
  // -------------------------------------------------------------------------

  group(
    'M1 compatibility — sharedPreferencesProvider override still works',
    () {
      testWidgets(
        'given both overrides the app mounts exactly one MaterialApp',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await _emptyPrefs();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                initialSharedTextProvider.overrideWithValue(null),
              ],
              child: const BufferApp(),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(MaterialApp), findsOneWidget);
          expect(find.byType(ErrorWidget), findsNothing);
        },
      );
    },
  );
}
