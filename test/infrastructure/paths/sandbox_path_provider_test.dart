// TASK-08: SandboxPathProvider test — RED phase.
//
// This file will not compile until the implementation at
// lib/infrastructure/paths/sandbox_path_provider.dart exists.
// That is the expected state: tests first, implementation next.
//
// ---------------------------------------------------------------------------
// Injectable seam assumed by these tests
// ---------------------------------------------------------------------------
//
// The implementation must accept a base-dir resolver via constructor injection:
//
//   typedef AppSupportDirResolver = Future<Directory> Function();
//
//   class SandboxPathProvider {
//     const SandboxPathProvider({AppSupportDirResolver? resolver})
//         : _resolver = resolver ?? getApplicationSupportDirectory;
//
//     final AppSupportDirResolver _resolver;
//
//     Future<Directory> recoveryDirectory() async { ... }
//   }
//
// The default resolver is `getApplicationSupportDirectory` from path_provider.
// Tests inject a stub resolver so no platform channel is invoked.
//
// ---------------------------------------------------------------------------
// Spec refs: FR-11, EC-03, EC-09
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:buffer/infrastructure/paths/sandbox_path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart'
    show MissingPlatformDirectoryException;

void main() {
  // -------------------------------------------------------------------------
  // Helper: build a SandboxPathProvider whose resolver returns a Directory at
  // the given [basePath] without any platform channel call.
  // -------------------------------------------------------------------------
  SandboxPathProvider withBase(String basePath) {
    return SandboxPathProvider(resolver: () async => Directory(basePath));
  }

  // -------------------------------------------------------------------------
  // FR-11 / EC-09 happy path — no trailing slash on base
  // -------------------------------------------------------------------------

  group('SandboxPathProvider.recoveryDirectory — path composition', () {
    test(
      'given_base_without_trailing_slash_when_recoveryDirectory_called_then_path_has_exactly_one_separator_before_recovery',
      () async {
        const base = '/data/user/0/com.example/files';
        final provider = withBase(base);

        final result = await provider.recoveryDirectory();

        expect(result.path, equals('/data/user/0/com.example/files/recovery'));
      },
    );

    // -----------------------------------------------------------------------
    // EC-09 edge — trailing slash on base must not double the separator
    // -----------------------------------------------------------------------

    test(
      'given_base_with_trailing_slash_when_recoveryDirectory_called_then_path_has_exactly_one_separator_before_recovery',
      () async {
        const base = '/data/user/0/com.example/files/';
        final provider = withBase(base);

        final result = await provider.recoveryDirectory();

        // p.join strips the redundant separator; must NOT produce
        // "/data/user/0/com.example/files//recovery".
        expect(result.path, equals('/data/user/0/com.example/files/recovery'));
        expect(result.path, isNot(contains('//')));
      },
    );
  });

  // -------------------------------------------------------------------------
  // EC-03 — MissingPlatformDirectoryException propagates unchanged
  // -------------------------------------------------------------------------

  group('SandboxPathProvider.recoveryDirectory — error propagation', () {
    test(
      'given_resolver_throws_MissingPlatformDirectoryException_when_recoveryDirectory_called_then_exception_propagates_unchanged',
      () async {
        final provider = SandboxPathProvider(
          resolver: () async => throw MissingPlatformDirectoryException(
            'Mocked missing platform directory',
          ),
        );

        // The exception must propagate — no swallow, no null return,
        // no fabricated fallback path.
        expect(
          () => provider.recoveryDirectory(),
          throwsA(isA<MissingPlatformDirectoryException>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // M1 composition-only — no directory creation / file I/O
  //
  // Verify that recoveryDirectory() does NOT call Directory.create() or any
  // file-system mutation.  We achieve this by confirming the returned
  // Directory object points at a path that does not exist on the test host
  // file system — if create() had been called it would either succeed
  // (path now exists, assertion fails) or throw.
  //
  // Using a path under a tmp prefix that is guaranteed not to exist at test
  // time gives us a simple no-create assertion without mocking dart:io.
  // -------------------------------------------------------------------------

  group('SandboxPathProvider.recoveryDirectory — M1 composition only', () {
    test(
      'given_non_existent_base_path_when_recoveryDirectory_called_then_no_directory_creation_occurs',
      () async {
        // A path that does not exist and will not be created by the provider.
        const base = '/nonexistent_buffer_test_base_dir_do_not_create';
        final provider = withBase(base);

        final result = await provider.recoveryDirectory();

        // The call must complete (composition succeeds).
        expect(
          result.path,
          equals('/nonexistent_buffer_test_base_dir_do_not_create/recovery'),
        );

        // The directory must NOT have been created on the file system
        // (M1 = composition only; no directory creation / file I/O).
        expect(
          result.existsSync(),
          isFalse,
          reason: 'SandboxPathProvider must not create the directory in M1',
        );
      },
    );
  });
}
