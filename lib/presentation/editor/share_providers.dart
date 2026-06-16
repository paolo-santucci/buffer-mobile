// TASK-07: share_providers — Riverpod provider composition seam.
// Spec refs: FR-M2-15 (seam), §5.1.4
//
// This file is the SINGLE import point for Wave-4/5 tasks (TASK-08, TASK-09,
// TASK-10). Keeping the four providers here avoids file overlap across parallel
// waves.
//
// No widget code. No literal user-facing strings.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:buffer/infrastructure/paths/sandbox_path_provider.dart';
import 'package:buffer/infrastructure/recovery/file_recovery_repository.dart';
import 'package:buffer/infrastructure/share/receive_sharing_intent_service.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/infrastructure/share/share_plus_service.dart';
import 'package:buffer/infrastructure/share/share_target_service.dart';

// ---------------------------------------------------------------------------
// 1. initialSharedTextProvider — throws until overridden at the ProviderScope
//    root in main.dart (TASK-10), mirroring the sharedPreferencesProvider
//    pattern. This guarantees a compile-time failure if a consumer forgets to
//    seed the value before the first frame (FR-M2-15, NFR-M2-06).
// ---------------------------------------------------------------------------
final initialSharedTextProvider = Provider<String?>(
  (ref) => throw UnimplementedError(
    'initialSharedTextProvider must be overridden at the ProviderScope root '
    'in main.dart with the value resolved before runApp.',
  ),
);

// ---------------------------------------------------------------------------
// 2. shareIntentServiceProvider — concrete adapter for the platform share
//    channel. Overridable in tests with a fake [ShareIntentService].
// ---------------------------------------------------------------------------
final shareIntentServiceProvider = Provider<ShareIntentService>((ref) {
  final service = ReceiveSharingIntentService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// 3. recoveryRepositoryProvider — concrete filesystem-backed repository.
//    Overridable in tests with a fake [RecoveryRepository].
// ---------------------------------------------------------------------------
final recoveryRepositoryProvider = Provider<RecoveryRepository>(
  (ref) => FileRecoveryRepository(pathProvider: SandboxPathProvider()),
);

// ---------------------------------------------------------------------------
// 4. saveBufferToRecoveryProvider — use case wired over the repository above.
//    Overridable in tests by overriding recoveryRepositoryProvider.
// ---------------------------------------------------------------------------
final saveBufferToRecoveryProvider = Provider<SaveBufferToRecovery>(
  (ref) => SaveBufferToRecovery(ref.watch(recoveryRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// 5. shareTargetServiceProvider — composition-root seam for the OS share
//    dispatch adapter. Resolves to [SharePlusService] by default (the only
//    lib/ file that imports share_plus). Overridable in tests with a fake
//    [ShareTargetService] (FR-08, §5.1.3, §5.3).
// ---------------------------------------------------------------------------
final shareTargetServiceProvider = Provider<ShareTargetService>(
  (ref) => SharePlusService(),
);
