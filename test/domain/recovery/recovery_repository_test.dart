// TDD — TASK-01 (M2): RecoveryRepository domain interface.
//
// Test strategy:
//   1. Compile-time shape: a _FakeRecoveryRepository that implements
//      RecoveryRepository with exactly one method `Future<File> save(String text)`
//      must compile. If the interface ever gains a second member without a
//      corresponding implementation here, this file will fail to compile —
//      enforcing the save-only M2 surface at review time.
//   2. Source-scan: the production file must declare
//      `abstract interface class RecoveryRepository` and contain the member
//      signature `Future<File> save(String text);`. This guards against the
//      interface accidentally using `abstract class` (which allows `extends`,
//      violating DIP) or drifting to a different member signature.

import 'dart:io';

import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Compile-time shape assertion
// ---------------------------------------------------------------------------

/// In-test save-only fake.
///
/// The fact that this class compiles with exactly one public method is proof
/// that [RecoveryRepository] exposes exactly `Future<File> save(String text)`
/// for M2. Adding any member to the interface without adding it here will
/// produce a compile error, catching the drift at review time.
class _FakeRecoveryRepository implements RecoveryRepository {
  File? lastSaved;
  String? lastText;

  @override
  Future<File> save(String text) async {
    lastText = text;
    lastSaved = File('fake_$text.txt');
    return lastSaved!;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RecoveryRepository interface', () {
    // -----------------------------------------------------------------------
    // Compile-time shape — save-only surface (FR-M2-09, §5.1.1)
    // -----------------------------------------------------------------------

    test(
      'given_a_fake_implementor_when_compiled_with_exactly_save_then_interface_surface_is_save_only',
      () async {
        // The compile-time check IS the shape assertion. Reaching this line
        // without compile error confirms the interface has exactly one M2
        // member: Future<File> save(String text).
        final repo = _FakeRecoveryRepository();

        final file = await repo.save('hello');

        expect(file.path, equals('fake_hello.txt'));
        expect(repo.lastText, equals('hello'));
      },
    );

    // -----------------------------------------------------------------------
    // Source-scan — interface declaration and member signature (§5.1.1)
    // -----------------------------------------------------------------------

    test(
      'given_recovery_repository_source_when_scanned_then_declares_abstract_interface_class',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('abstract interface class RecoveryRepository'),
          isTrue,
          reason:
              'File must declare `abstract interface class RecoveryRepository` '
              '(Dart 3 interface modifier prevents extends, enforcing DIP).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_save_member_signature',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<File> save(String text)'),
          isTrue,
          reason:
              'Interface must declare exactly `Future<File> save(String text);` '
              'as its sole M2 member (FR-M2-09, §5.1.1).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_no_package_flutter_import',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains("import 'package:flutter/"),
          isFalse,
          reason:
              'Domain files must not import package:flutter/ '
              '(domain-purity rule, NFR-M2-04).',
        );
      },
    );
  });
}
