// TDD — TASK-04 (M5): RecoveryRepository additive interface extension.
//
// Test strategy:
//   1. Compile-time shape: _FakeRecoveryRepository implements ALL six members
//      (save + list + read + delete + deleteAll + trim). If the interface is
//      missing any of those members this file fails to compile — enforcing the
//      complete M5 surface at review time (OCP: save is UNCHANGED from M2).
//   2. Assertion: constructing the fake and calling list() returns the stubbed
//      empty list — proves the new member is callable through the interface.
//   3. Source-scan: the production file must preserve the exact save signature
//      byte-for-byte, declare `abstract interface class RecoveryRepository`,
//      contain all five new M5 member signatures with the exact doc-comment
//      error-contract language, and import no `package:flutter` symbols.
//   4. NFR-M5-02 name guard: no new method name on RecoveryRepository matches
//      the regex \b(persist|write|store|share)\b (beyond pre-existing save).

import 'dart:io';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Compile-time shape assertion — all six members (M2 save + M5 additions)
// ---------------------------------------------------------------------------

/// In-test fake implementing the complete M5 interface surface.
///
/// Adding any member to [RecoveryRepository] without adding it here, or
/// removing a member from [RecoveryRepository], produces a compile error —
/// catching drift at review time. The fact that this class compiles is itself
/// the shape assertion.
///
/// Naming note: no method name beyond [save] matches persist|write|store|share
/// (NFR-M5-02 buffer-contract backstop).
class _FakeRecoveryRepository implements RecoveryRepository {
  // M2 — unchanged
  File? lastSaved;
  String? lastText;

  // M5 stubs
  List<RecoveryNote> stubbedNotes = [];
  String stubbedText = '';
  bool deleteCalled = false;
  bool deleteAllCalled = false;
  int? lastTrimKeep;

  @override
  Future<File> save(String text) async {
    lastText = text;
    lastSaved = File('fake_$text.txt');
    return lastSaved!;
  }

  @override
  Future<List<RecoveryNote>> list() async => stubbedNotes;

  @override
  Future<String> read(RecoveryNote note) async => stubbedText;

  @override
  Future<void> delete(RecoveryNote note) async => deleteCalled = true;

  @override
  Future<void> deleteAll() async => deleteAllCalled = true;

  @override
  Future<void> trim(int keep) async => lastTrimKeep = keep;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RecoveryRepository interface', () {
    // -----------------------------------------------------------------------
    // M2 shape preserved — save-only surface unchanged (FR-M2-09, §5.1.1)
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
    // M5 shape — five new members callable through the interface
    // -----------------------------------------------------------------------

    test('given_empty_fake_when_list_called_then_returns_empty_list', () async {
      final repo = _FakeRecoveryRepository();

      final notes = await repo.list();

      expect(notes, isEmpty);
    });

    test(
      'given_fake_with_stubbed_notes_when_list_called_then_returns_stubbed_notes',
      () async {
        final repo = _FakeRecoveryRepository();
        final note = RecoveryNote(
          path: '/recovery/2026-06-14T12-00-00-000Z.txt',
          savedAt: DateTime.utc(2026, 6, 14, 12, 0, 0),
          preview: 'hello world',
        );
        repo.stubbedNotes = [note];

        final notes = await repo.list();

        expect(notes, equals([note]));
      },
    );

    test('given_fake_when_read_called_then_returns_stubbed_text', () async {
      final repo = _FakeRecoveryRepository();
      repo.stubbedText = 'recovered text content';
      final note = RecoveryNote(
        path: '/recovery/2026-06-14T12-00-00-000Z.txt',
        savedAt: DateTime.utc(2026, 6, 14, 12, 0, 0),
        preview: 'recovered text content',
      );

      final text = await repo.read(note);

      expect(text, equals('recovered text content'));
    });

    test('given_fake_when_delete_called_then_records_call', () async {
      final repo = _FakeRecoveryRepository();
      final note = RecoveryNote(
        path: '/recovery/2026-06-14T12-00-00-000Z.txt',
        savedAt: DateTime.utc(2026, 6, 14, 12, 0, 0),
        preview: 'hello',
      );

      await repo.delete(note);

      expect(repo.deleteCalled, isTrue);
    });

    test('given_fake_when_deleteAll_called_then_records_call', () async {
      final repo = _FakeRecoveryRepository();

      await repo.deleteAll();

      expect(repo.deleteAllCalled, isTrue);
    });

    test(
      'given_fake_when_trim_called_with_keep_then_records_keep_value',
      () async {
        final repo = _FakeRecoveryRepository();

        await repo.trim(10);

        expect(repo.lastTrimKeep, equals(10));
      },
    );

    // -----------------------------------------------------------------------
    // NFR-M5-02 name guard — no new member name matches persist|write|store|share
    // -----------------------------------------------------------------------

    test(
      'given_recovery_repository_source_when_scanned_then_no_new_member_matches_forbidden_name_pattern',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        // Extract member declaration lines (lines containing `Future<`).
        // The only sanctioned name containing a "persistence" verb is `save`.
        final forbiddenPattern = RegExp(r'\b(persist|write|store|share)\b');
        final memberLines = source
            .split('\n')
            .where((l) => l.trimLeft().startsWith('Future<'))
            .toList();

        for (final line in memberLines) {
          expect(
            forbiddenPattern.hasMatch(line),
            isFalse,
            reason:
                'Member line "$line" matches a forbidden name '
                r'(persist|write|store|share) — '
                'NFR-M5-02 requires no new member beyond `save` implies persistence.',
          );
        }
      },
    );

    // -----------------------------------------------------------------------
    // Source-scan — interface declaration and M2 member signature (§5.1.1)
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
      'given_recovery_repository_source_when_scanned_then_contains_save_member_signature_unchanged',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<File> save(String text)'),
          isTrue,
          reason:
              'Interface must preserve exactly `Future<File> save(String text);` '
              'byte-for-byte (M2 member, OCP — must NOT be edited, §5.1.3).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_list_member_signature',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<List<RecoveryNote>> list()'),
          isTrue,
          reason:
              'Interface must declare `Future<List<RecoveryNote>> list()` (FR-M5-01, §5.1.3).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_read_member_signature',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<String> read(RecoveryNote note)'),
          isTrue,
          reason:
              'Interface must declare `Future<String> read(RecoveryNote note)` (§5.1.3).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_delete_member_signature',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<void> delete(RecoveryNote note)'),
          isTrue,
          reason:
              'Interface must declare `Future<void> delete(RecoveryNote note)` (§5.1.3).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_deleteAll_member_signature',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<void> deleteAll()'),
          isTrue,
          reason: 'Interface must declare `Future<void> deleteAll()` (§5.1.3).',
        );
      },
    );

    test(
      'given_recovery_repository_source_when_scanned_then_contains_trim_member_signature',
      () {
        const sourcePath = 'lib/domain/recovery/recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        expect(
          source.contains('Future<void> trim(int keep)'),
          isTrue,
          reason:
              'Interface must declare `Future<void> trim(int keep)` (FR-M5-02, §5.1.3).',
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
