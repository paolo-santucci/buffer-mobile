// T-03: Synchronous recovery-save wiring test.
//
// Verifies that LifecycleBufferHost writes recovery files SYNCHRONOUSLY on the
// paused/detached lifecycle path, so bytes hit disk before
// didChangeAppLifecycleState returns — fixing the on-device defect where the
// OS freezes the isolate before async I/O flushes.
//
// Spec refs: FR-M2-06, FR-M2-07, EC-M2-08, EC-M2-02, NFR-M5-01,
//            BUG-102, BUG-104, plan §T-03.
//
// All lifecycle events are driven by calling [didChangeAppLifecycleState]
// directly on the [LifecycleBufferHostState] object (bypasses platform channels
// — fully synchronous; matches the established pattern in the existing suite).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/domain/recovery/recovery_repository.dart';
import 'package:foglietto/infrastructure/paths/sandbox_path_provider.dart';
import 'package:foglietto/infrastructure/recovery/file_recovery_repository.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/lifecycle/lifecycle_buffer_host.dart';

// ---------------------------------------------------------------------------
// Stub SandboxPathProvider that returns a fixed directory.
// Only the async recoveryDirectory() path is needed (for the async save
// path used by share-intent). saveSync uses syncRecoveryDir directly.
// ---------------------------------------------------------------------------

class _StubPathProvider extends SandboxPathProvider {
  const _StubPathProvider(this._dir);
  final Directory _dir;

  @override
  Future<Directory> recoveryDirectory() async => _dir;
}

// ---------------------------------------------------------------------------
// Throwing repo — simulates FileSystemException from saveSync (EC-M2-08).
// ---------------------------------------------------------------------------

class _ThrowingSyncRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async => File('/tmp/never.txt');

  @override
  File saveSync(String text, {int keep = 10}) =>
      throw const FileSystemException('disk full', '/tmp/recovery');

  @override
  Future<List<RecoveryNote>> list() async => const [];
  @override
  Future<String> read(RecoveryNote note) async => '';
  @override
  Future<void> delete(RecoveryNote note) async {}
  @override
  Future<void> deleteAll() async {}
  @override
  Future<void> trim(int keep) async {}
}

// ---------------------------------------------------------------------------
// Helper: build the testable widget tree.
// ---------------------------------------------------------------------------

/// Builds a minimal testable tree with a real [FileRecoveryRepository]
/// over [recoveryDir] (a temporary directory in the host file system).
///
/// [emergencyRecoveryEnabled] is wired through the production
/// [settingsProvider] default (const AppSettings() → true), so no
/// explicit settings override is needed for the happy-path tests.
Widget _buildSyncTestTree({
  required Directory recoveryDir,
  Widget child = const SizedBox.shrink(),
}) {
  final repo = FileRecoveryRepository(
    pathProvider: _StubPathProvider(recoveryDir),
    syncRecoveryDir: () => recoveryDir,
  );

  return ProviderScope(
    overrides: [
      recoveryRepositoryProvider.overrideWithValue(repo),
      initialSharedTextProvider.overrideWithValue(null),
    ],
    child: MaterialApp(home: LifecycleBufferHost(child: child)),
  );
}

/// Builds a tree where [recoveryRepositoryProvider] is overridden with a
/// [_ThrowingSyncRecoveryRepository] to exercise EC-M2-08 error handling.
Widget _buildThrowingTree() {
  return ProviderScope(
    overrides: [
      recoveryRepositoryProvider.overrideWithValue(
        _ThrowingSyncRecoveryRepository(),
      ),
      initialSharedTextProvider.overrideWithValue(null),
    ],
    child: const MaterialApp(
      home: LifecycleBufferHost(child: SizedBox.shrink()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group(
    'LifecycleBufferHost sync-save — Case 1: paused writes file synchronously',
    () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('recovery_sync_test_');
      });

      tearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      testWidgets(
        'paused: file written BEFORE any microtask pump — synchronous durable write',
        (tester) async {
          await tester.pumpWidget(_buildSyncTestTree(recoveryDir: tempDir));

          // Seed buffer with non-empty text.
          final container = tester.element(find.byType(LifecycleBufferHost));
          final ref = ProviderScope.containerOf(container);
          ref.read(bufferProvider.notifier).populate('draft text');
          await tester.pump();

          final hostState = tester.state<LifecycleBufferHostState>(
            find.byType(LifecycleBufferHost),
          );

          // Drive paused — the synchronous write must complete INSIDE this call.
          hostState.didChangeAppLifecycleState(AppLifecycleState.paused);

          // IMMEDIATELY — before ANY microtask pump — check the filesystem.
          // This is the distinguishing assertion: async saves cannot pass this
          // because they require at least one microtask flush.
          final files = tempDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.txt'))
              .toList();

          expect(
            files,
            hasLength(1),
            reason:
                'Exactly one .txt file must exist before any pump — '
                'synchronous write must complete within didChangeAppLifecycleState',
          );
          expect(
            files.first.readAsStringSync(),
            equals('draft text'),
            reason: 'File must contain the exact buffer text',
          );

          // Pump to confirm no crash or error after the sync write.
          await tester.pump();
        },
      );
    },
  );

  group(
    'LifecycleBufferHost sync-save — Case 2: BUG-102 resumed does not lose saved file',
    () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('recovery_sync_test_');
      });

      tearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      testWidgets(
        'after paused write, resumed resets buffer but does NOT delete the written file',
        (tester) async {
          await tester.pumpWidget(_buildSyncTestTree(recoveryDir: tempDir));

          final container = tester.element(find.byType(LifecycleBufferHost));
          final ref = ProviderScope.containerOf(container);
          ref.read(bufferProvider.notifier).populate('draft text');
          await tester.pump();

          final hostState = tester.state<LifecycleBufferHostState>(
            find.byType(LifecycleBufferHost),
          );

          // Paused: sync write completes.
          hostState.didChangeAppLifecycleState(AppLifecycleState.paused);

          // Confirm file is on disk.
          final filesAfterPause = tempDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.txt'))
              .toList();
          expect(filesAfterPause, hasLength(1));

          // Resumed: buffer must be reset.
          hostState.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();

          // Buffer text is cleared.
          expect(
            ref.read(bufferProvider).text,
            equals(''),
            reason: 'Buffer must be reset on resumed',
          );

          // BUG-102: the durable written file must still exist.
          final filesAfterResume = tempDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.txt'))
              .toList();
          expect(
            filesAfterResume,
            hasLength(1),
            reason:
                'The just-written recovery file must NOT be deleted by resumed',
          );
        },
      );
    },
  );

  group(
    'LifecycleBufferHost sync-save — Case 3: EC-M2-08 FileSystemException swallowed',
    () {
      testWidgets(
        'repo.saveSync throws FileSystemException: host does NOT rethrow — '
        'app does not crash',
        (tester) async {
          await tester.pumpWidget(_buildThrowingTree());

          final container = tester.element(find.byType(LifecycleBufferHost));
          final ref = ProviderScope.containerOf(container);
          ref.read(bufferProvider.notifier).populate('non-empty text');
          await tester.pump();

          final hostState = tester.state<LifecycleBufferHostState>(
            find.byType(LifecycleBufferHost),
          );

          // Must not throw — EC-M2-08 requires backgrounding never to crash.
          expect(
            () =>
                hostState.didChangeAppLifecycleState(AppLifecycleState.paused),
            returnsNormally,
          );

          await tester.pump();
        },
      );
    },
  );
}
