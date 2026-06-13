// Entry point — Buffer mobile (TASK-10 / M2 composition root update)
//
// Spec refs: FR-M2-15, NFR-M2-06, B1/R-14, §4.1, §4.2
//
// Composition root:
//   1. Ensure the Flutter engine is initialised before any platform calls.
//   2. Await SharedPreferences.getInstance() AND initialSharedText() in
//      parallel via Future.wait (B1: no synchronous cold-start read; the
//      guarantee is "no blank buffer rendered then replaced", achieved by
//      resolving before runApp).
//   3. Mount a single ProviderScope above everything, injecting:
//        - the real SharedPreferences via sharedPreferencesProvider.overrideWithValue()
//        - the resolved shared text via initialSharedTextProvider.overrideWithValue()
//      Both overrides satisfy their respective provider throw-until-overridden seams.
//   4. BufferApp is const — it never rebuilds when the root widget is recreated.
//
// The [bootstrap] function is @visibleForTesting so the composition test can
// inject a fake [ShareIntentService] and assert ordering without touching
// the real platform channel.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/infrastructure/share/receive_sharing_intent_service.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

/// Awaits [SharedPreferences.getInstance()] and [service.initialSharedText()]
/// in parallel and returns both resolved values as a record.
///
/// Exposed as @visibleForTesting so the composition test can inject a fake
/// [ShareIntentService] and assert that both futures are resolved before
/// [runApp] is called.  Production [main] uses the concrete
/// [ReceiveSharingIntentService].
@visibleForTesting
Future<(SharedPreferences, String?)> bootstrap(
  ShareIntentService service,
) async {
  final results = await Future.wait<Object?>([
    SharedPreferences.getInstance(),
    service.initialSharedText(),
  ]);
  return (results[0] as SharedPreferences, results[1] as String?);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final service = ReceiveSharingIntentService();
  final (prefs, sharedText) = await bootstrap(service);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialSharedTextProvider.overrideWithValue(sharedText),
      ],
      child: const BufferApp(),
    ),
  );
}
