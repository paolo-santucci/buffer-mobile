// Entry point — Buffer mobile (TASK-10 / M2 composition root update)
//
// Spec refs: FR-M2-15, NFR-M2-06, B1/R-14, §4.1, §4.2
//
// T-03 wiring: recoveryRepositoryProvider is overridden here with a
// FileRecoveryRepository that carries a pre-resolved syncRecoveryDir.
// path_provider's getApplicationSupportDirectory() is async-only; resolving
// it once at startup and passing the result as a closure lets saveSync
// operate without any async call during the OS-freeze window.
//
// Composition root:
//   1. Ensure the Flutter engine is initialised before any platform calls.
//   2. Await SharedPreferences.getInstance() AND initialSharedText() in
//      parallel via Future.wait (B1: no synchronous cold-start read; the
//      guarantee is "no blank buffer rendered then replaced", achieved by
//      resolving before runApp).
//   3. Resolve the recovery directory once (for syncRecoveryDir injection).
//   4. Mount a single ProviderScope above everything, injecting:
//        - the real SharedPreferences via sharedPreferencesProvider.overrideWithValue()
//        - the resolved shared text via initialSharedTextProvider.overrideWithValue()
//        - a FileRecoveryRepository with syncRecoveryDir via
//          recoveryRepositoryProvider.overrideWith()
//      All overrides satisfy their respective provider throw-until-overridden seams.
//   5. BufferApp is const — it never rebuilds when the root widget is recreated.
//
// The [bootstrap] function is @visibleForTesting so the composition test can
// inject a fake [ShareIntentService] and assert ordering without touching
// the real platform channel. Its signature is (SharedPreferences, String?)
// (unchanged from the original) — only main() performs the additional
// recovery-dir resolution so the composition test requires no changes.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foglietto/infrastructure/paths/sandbox_path_provider.dart';
import 'package:foglietto/infrastructure/recovery/file_recovery_repository.dart';
import 'package:foglietto/infrastructure/share/receive_sharing_intent_service.dart';
import 'package:foglietto/infrastructure/share/share_intent_service.dart';
import 'package:foglietto/presentation/app.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

/// Awaits [SharedPreferences.getInstance()] and [service.initialSharedText()]
/// in parallel and returns both resolved values as a record.
///
/// Exposed as @visibleForTesting so the composition test can inject a fake
/// [ShareIntentService] and assert that both futures are resolved before
/// [runApp] is called.  Production [main] uses the concrete
/// [ReceiveSharingIntentService].
///
/// The recovery-dir resolution is NOT included here — it would require
/// mocking path_provider in the composition test. Instead, [main] resolves
/// the recovery directory after [bootstrap] returns and before [runApp].
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

  // T-03: resolve the recovery directory once, before runApp, so saveSync
  // can use it as a synchronous closure. path_provider is async-only;
  // resolving it here avoids any platform-channel call during the OS-freeze
  // window that follows AppLifecycleState.paused.
  final Directory recoveryDir = await const SandboxPathProvider()
      .recoveryDirectory();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialSharedTextProvider.overrideWithValue(sharedText),
        // T-03: override the recovery repo with one that carries the
        // pre-resolved sync directory. Tests keep using the default async-path
        // provider from share_providers.dart (or their own override).
        recoveryRepositoryProvider.overrideWith(
          (ref) => FileRecoveryRepository(
            pathProvider: const SandboxPathProvider(),
            syncRecoveryDir: () => recoveryDir,
          ),
        ),
      ],
      child: const BufferApp(),
    ),
  );
}
