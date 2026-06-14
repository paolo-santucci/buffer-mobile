// M5 source-scan gate — buffer-mobile
//
// Spec refs: NFR-M5-01, NFR-M5-02, NFR-M5-03, NFR-M5-04, NFR-M5-05,
//            FR-M5-03, FR-M5-07, FR-M5-17
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m4_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Gate inventory (spec §7.1, TASK-14):
//   1. RecoveryRepository additive shape — save(String text): Future<File>
//      present AND 5 new members list/read/delete/deleteAll/trim present.
//   2. No `requireValue` in lifecycle_buffer_host.dart (NFR-M5-03).
//   3. No lastModifiedSync/lastModified/statSync/.changed/mtime in
//      file_recovery_repository.dart (NFR-M5-01 — trim sorts by filename only).
//   4. No literal Text('...')/Text("...") in lib/presentation/recovery/
//      (NFR-M5-05 — all strings via AppLocalizations).
//   5. recovery_screen.dart calls populate( and has NO updateText( and NO
//      _controller.value = on the restore path (restore via populate only).
//   6. save_buffer_to_recovery.dart calls trim(10) (FR-M5-03, §5.1.4).
//   7. No persist|write|store|share member/method names in
//      recovery_list_provider.dart and recovery_repository.dart beyond save
//      (NFR-M5-02).
//   8. ARB key parity — app_en.arb and app_it.arb key sets are equal AND all
//      18 recovery keys are present in both (NFR-M5-05 / FR-M5-04).
//   9. INVERTED (OQ-M6-15 / TASK-12 M6): buffer_screen.dart must NOT contain
//      kDebugMode or pushNamed('/recovery') — menu sheet is sole nav entry.

// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Returns all `.dart` files under [dir] recursively.
List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// Returns the project root.
///
/// `flutter test` sets the working directory to the package root, so
/// [Directory.current] is always the project root.
String get _root => Directory.current.path;

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  late String root;

  setUpAll(() {
    root = _root;
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 1 — RecoveryRepository additive shape
  //
  // The M2 member save(String text): Future<File> must remain present (no
  // breaking change). The 5 new M5 members — list, read, delete, deleteAll,
  // trim — must also be present in the abstract interface. This asserts OCP:
  // the interface was extended additively, not modified destructively.
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 1 — RecoveryRepository has save (M2) + 5 new M5 members '
      '(additive shape, OCP)', () {
    // ── red fixture: interface missing the trim member ───────────────────
    group('fixture — interface missing trim', () {
      const brokenSource = '''
abstract interface class RecoveryRepository {
  Future<File> save(String text);
  Future<List<RecoveryNote>> list();
  Future<String> read(RecoveryNote note);
  Future<void> delete(RecoveryNote note);
  Future<void> deleteAll();
}
''';

      test('should_FAIL_trim_member_scan_on_fixture_missing_it', () {
        // The scan looks for `Future<void> trim(` on a non-comment line.
        final lines = brokenSource.split('\n');
        final hasTrip = lines.any((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              l.contains('trim(');
        });
        expect(
          hasTrip,
          isFalse,
          reason:
              'Broken fixture must NOT contain "trim(" to prove the '
              'scan would fire when the member is absent.',
        );
      });
    });

    // ── green: real recovery_repository.dart ─────────────────────────────
    group('real lib/domain/recovery/recovery_repository.dart', () {
      late List<String> lines;

      setUpAll(() {
        final path = '$root/lib/domain/recovery/recovery_repository.dart';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/domain/recovery/recovery_repository.dart must exist.',
        );
        lines = file.readAsLinesSync();
      });

      // Helper: non-comment non-import lines only.
      bool isCodeLine(String line) {
        final t = line.trimLeft();
        return !t.startsWith('//') &&
            !t.startsWith('*') &&
            !t.startsWith('import ');
      }

      test('should_have_save_String_text_Future_File_member', () {
        final hit = lines.any(
          (l) =>
              isCodeLine(l) &&
              l.contains('Future<File>') &&
              l.contains('save('),
        );
        expect(
          hit,
          isTrue,
          reason:
              'RecoveryRepository must declare '
              '"Future<File> save(String text)" (M2 member, additive OCP). '
              'Member not found in recovery_repository.dart.',
        );
      });

      test('should_have_list_member', () {
        final hit = lines.any((l) => isCodeLine(l) && l.contains('list('));
        expect(
          hit,
          isTrue,
          reason:
              'RecoveryRepository must declare "list()" (M5 additive member).',
        );
      });

      test('should_have_read_member', () {
        final hit = lines.any((l) => isCodeLine(l) && l.contains('read('));
        expect(
          hit,
          isTrue,
          reason:
              'RecoveryRepository must declare "read(RecoveryNote note)" '
              '(M5 additive member).',
        );
      });

      test('should_have_delete_member', () {
        // Match `delete(` that is NOT `deleteAll(`
        final hit = lines.any((l) {
          if (!isCodeLine(l)) return false;
          return RegExp(r'\bdelete\(').hasMatch(l) && !l.contains('deleteAll(');
        });
        expect(
          hit,
          isTrue,
          reason:
              'RecoveryRepository must declare "delete(RecoveryNote note)" '
              '(M5 additive member — separate from deleteAll).',
        );
      });

      test('should_have_deleteAll_member', () {
        final hit = lines.any((l) => isCodeLine(l) && l.contains('deleteAll('));
        expect(
          hit,
          isTrue,
          reason:
              'RecoveryRepository must declare "deleteAll()" '
              '(M5 additive member).',
        );
      });

      test('should_have_trim_member', () {
        final hit = lines.any((l) => isCodeLine(l) && l.contains('trim('));
        expect(
          hit,
          isTrue,
          reason:
              'RecoveryRepository must declare "trim(int keep)" '
              '(M5 additive member — trim-to-10 boundary).',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 2 — no `requireValue` in lifecycle_buffer_host.dart (NFR-M5-03)
  //
  // NFR-M5-03 / EC-08 forbids requireValue: if settings are still loading on
  // first background, requireValue would throw. The lifecycle host reads
  // settings defensively with `.value ?? const AppSettings()` (default-ON
  // fallback), so the save always fires during AsyncLoading.
  // ──────────────────────────────────────────────────────────────────────────

  group(
    'gate 2 — lifecycle_buffer_host.dart has no requireValue (NFR-M5-03)',
    () {
      // ── red fixture: host using requireValue ──────────────────────────────
      group('fixture — lifecycle host using requireValue', () {
        const brokenSource =
            '  void _onPaused() {\n'
            '    final settings = ref.read(settingsProvider).requireValue;\n'
            '    if (!settings.emergencyRecoveryEnabled) return;\n'
            '  }\n';

        test('should_FAIL_requireValue_scan_on_broken_fixture', () {
          expect(
            brokenSource.contains('requireValue'),
            isTrue,
            reason:
                'Broken fixture must contain "requireValue" to prove the '
                'crash-safety scan would fire if it were present.',
          );
        });
      });

      // ── green: real lifecycle_buffer_host.dart ─────────────────────────────
      group('real lib/presentation/lifecycle/lifecycle_buffer_host.dart', () {
        late List<String> lines;

        setUpAll(() {
          final path =
              '$root/lib/presentation/lifecycle/lifecycle_buffer_host.dart';
          final file = File(path);
          expect(
            file.existsSync(),
            isTrue,
            reason:
                'lib/presentation/lifecycle/lifecycle_buffer_host.dart must '
                'exist.',
          );
          lines = file.readAsLinesSync();
        });

        test('should_have_NO_requireValue_in_lifecycle_buffer_host', () {
          final hits = <String>[];
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            if (lines[i].contains('requireValue')) {
              hits.add('${i + 1}: ${lines[i].trim()}');
            }
          }
          expect(
            hits,
            isEmpty,
            reason:
                'lifecycle_buffer_host.dart must NOT call requireValue — '
                'settings must be read defensively with ".value ?? const '
                'AppSettings()" to prevent crashes when settings are still '
                'loading on first background (NFR-M5-03 / EC-08).\n'
                'Offenders:\n${hits.join('\n')}',
          );
        });
      });
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 3 — no mtime-based sorting in file_recovery_repository.dart
  //          (NFR-M5-01)
  //
  // trim() must sort by LEXICOGRAPHIC FILENAME only (fixed-width UTC ISO-8601
  // names guarantee name order == chronological order). Using lastModified,
  // lastModifiedSync, statSync, .changed, or any mtime variant would violate
  // NFR-M5-01 and is forbidden.
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 3 — file_recovery_repository.dart has no mtime-based sort '
      '(NFR-M5-01)', () {
    // ── red fixture: repository using lastModifiedSync ────────────────────
    group('fixture — repository using lastModifiedSync for sort', () {
      const brokenSource =
          '  Future<void> trim(int keep) async {\n'
          '    files.sort((a, b) =>\n'
          '        a.lastModifiedSync().compareTo(b.lastModifiedSync()));\n'
          '  }\n';

      test('should_FAIL_mtime_sort_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('lastModifiedSync'),
          isTrue,
          reason:
              'Broken fixture must contain "lastModifiedSync" to prove '
              'the NFR-M5-01 mtime scan would fire when it is used.',
        );
      });
    });

    // ── green: real file_recovery_repository.dart ─────────────────────────
    group('real lib/infrastructure/recovery/file_recovery_repository.dart', () {
      late List<String> lines;

      setUpAll(() {
        final path =
            '$root/lib/infrastructure/recovery/file_recovery_repository.dart';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'lib/infrastructure/recovery/file_recovery_repository.dart '
              'must exist.',
        );
        lines = file.readAsLinesSync();
      });

      test('should_have_NO_mtime_based_sort_in_file_recovery_repository', () {
        // Forbidden terms: lastModifiedSync, lastModified, statSync,
        // .changed, mtime — any of these indicate filesystem-metadata-based
        // sort rather than lexicographic filename sort (NFR-M5-01).
        final forbiddenPattern = RegExp(
          r'\b(lastModifiedSync|lastModified|statSync|mtime)\b|\.changed\b',
        );
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (forbiddenPattern.hasMatch(lines[i])) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'file_recovery_repository.dart must NOT use mtime-based sort '
              '(lastModifiedSync / lastModified / statSync / .changed / '
              'mtime). trim() must sort by lexicographic filename only — '
              'fixed-width UTC ISO-8601 names ensure name order equals '
              'chronological order (NFR-M5-01).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 4 — lib/presentation/recovery/ has no literal Text('…') / Text("…")
  //          (NFR-M5-05 localization gate)
  //
  // All recovery-screen user-facing strings must go through AppLocalizations.
  // No hardcoded Text() constructors with non-empty string literals may appear
  // in lib/presentation/recovery/. Mirrors the M4 gate-5 check for find/.
  // ──────────────────────────────────────────────────────────────────────────

  group("gate 4 — lib/presentation/recovery/ has no literal Text('…') / "
      'Text("…") (NFR-M5-05 localization)', () {
    // ── red fixture: hardcoded Text literal in recovery screen ────────────
    group('fixture — hardcoded Text literal in recovery row', () {
      const brokenSource = "Text('No recovery notes')";

      test('should_FAIL_literal_Text_scan_on_broken_fixture', () {
        final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
        expect(
          literalPattern.hasMatch(brokenSource),
          isTrue,
          reason:
              'Broken fixture must trigger the literal Text() scan to '
              'prove it would fire if hardcoded strings were used.',
        );
      });
    });

    // ── green: real lib/presentation/recovery/ ─────────────────────────
    test(
      'should_have_zero_literal_Text_constructors_in_presentation_recovery',
      () {
        final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
        final recoveryPresentationDir = '$root/lib/presentation/recovery';
        final hits = <String>[];
        final d = Directory(recoveryPresentationDir);
        if (d.existsSync()) {
          for (final file in _dartFiles(recoveryPresentationDir)) {
            final lines = file.readAsLinesSync();
            for (var i = 0; i < lines.length; i++) {
              final trimmed = lines[i].trimLeft();
              if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
                continue;
              }
              if (literalPattern.hasMatch(lines[i])) {
                hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
              }
            }
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'lib/presentation/recovery/ must not contain Text("literal") '
              "or Text('literal') with non-empty strings — all recovery "
              'screen copy must go through AppLocalizations (NFR-M5-05).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 5 — recovery_screen.dart uses populate( and has no updateText( or
  //          _controller.value = on the restore path (FR-M5-07 / NFR-M5-02)
  //
  // The restore flow must write to the buffer via BufferNotifier.populate()
  // only — never via updateText() or direct _controller.value assignment.
  // This enforces the single-write-path contract (NFR-M5-02 / parent §5.3).
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 5 — recovery_screen.dart calls populate( and has NO updateText( '
      'or _controller.value = (FR-M5-07 / NFR-M5-02 single-write-path)', () {
    // ── red fixture: screen using updateText on restore path ──────────────
    group('fixture — broken screen using updateText instead of populate', () {
      const brokenSource =
          '  Future<void> _onRestore(RecoveryNote note) async {\n'
          '    final text = await ref.read(recoveryListProvider.notifier).restore(note);\n'
          '    ref.read(bufferProvider.notifier).updateText(text);\n'
          '  }\n';

      test('should_FAIL_updateText_scan_on_broken_restore_fixture', () {
        expect(
          brokenSource.contains('.updateText('),
          isTrue,
          reason:
              'Broken fixture must contain ".updateText(" to prove the '
              'single-write-path scan would fire when it is used.',
        );
      });
    });

    // ── red fixture: screen missing populate ──────────────────────────────
    group('fixture — broken screen with no populate call', () {
      const brokenSource =
          '  Future<void> _onRestore(RecoveryNote note) async {\n'
          '    Navigator.of(context).pop();\n'
          '  }\n';

      test('should_FAIL_populate_scan_on_fixture_missing_it', () {
        expect(
          brokenSource.contains('populate('),
          isFalse,
          reason:
              'Broken fixture must NOT contain "populate(" to prove the '
              'scan would fire when the restore call is absent.',
        );
      });
    });

    // ── green: real recovery_screen.dart ──────────────────────────────────
    group('real lib/presentation/recovery/recovery_screen.dart', () {
      late List<String> lines;

      setUpAll(() {
        final path = '$root/lib/presentation/recovery/recovery_screen.dart';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/presentation/recovery/recovery_screen.dart must exist.',
        );
        lines = file.readAsLinesSync();
      });

      test('should_call_populate_in_recovery_screen', () {
        final hit = lines.any((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              l.contains('populate(');
        });
        expect(
          hit,
          isTrue,
          reason:
              'recovery_screen.dart must call ".populate(text)" to write '
              'the restored note to the buffer (FR-M5-07 single-write-path, '
              'NFR-M5-02).',
        );
      });

      test('should_have_NO_updateText_call_in_recovery_screen', () {
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (lines[i].contains('.updateText(')) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'recovery_screen.dart must NOT call ".updateText()" — the '
              'restore path must use ".populate(text)" as the sole '
              'buffer-write entry point (NFR-M5-02 / FR-M5-07 restore '
              'via populate only).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });

      test('should_have_NO_controller_value_assignment_in_recovery_screen', () {
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (RegExp(r'_controller\.value\s*=[^=]').hasMatch(lines[i])) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'recovery_screen.dart must NOT write "_controller.value" '
              'directly — restore must go via bufferProvider.notifier.'
              'populate() (NFR-M5-02 / FR-M5-07).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 6 — save_buffer_to_recovery.dart calls trim(10) (FR-M5-03, §5.1.4)
  //
  // SaveBufferToRecovery.call() must invoke _repository.trim(10) after every
  // successful save to ensure the recovery directory never holds more than 10
  // files.
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 6 — save_buffer_to_recovery.dart calls trim(10) '
      '(FR-M5-03 / §5.1.4 trim-to-10)', () {
    // ── red fixture: use case missing the trim(10) call ───────────────────
    group('fixture — use case without trim(10)', () {
      const brokenSource =
          '  Future<File?> call(String text) async {\n'
          '    if (text.trim().isEmpty) return null;\n'
          '    return _repository.save(text);\n'
          '  }\n';

      test('should_FAIL_trim10_scan_on_fixture_missing_it', () {
        expect(
          brokenSource.contains('trim(10)'),
          isFalse,
          reason:
              'Broken fixture must NOT contain "trim(10)" to prove the '
              'scan would fire when the trim call is absent.',
        );
      });
    });

    // ── green: real save_buffer_to_recovery.dart ──────────────────────────
    group('real lib/domain/recovery/save_buffer_to_recovery.dart', () {
      late List<String> lines;

      setUpAll(() {
        final path = '$root/lib/domain/recovery/save_buffer_to_recovery.dart';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'lib/domain/recovery/save_buffer_to_recovery.dart must exist.',
        );
        lines = file.readAsLinesSync();
      });

      test('should_call_trim_10_in_save_buffer_to_recovery', () {
        final hit = lines.any((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              l.contains('trim(10)');
        });
        expect(
          hit,
          isTrue,
          reason:
              'save_buffer_to_recovery.dart must call "_repository.trim(10)" '
              'after every successful save to enforce the 10-file cap '
              '(FR-M5-03 / §5.1.4 trim-to-10). Call not found.',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 7 — no persist|write|store|share member/method names in
  //          recovery_list_provider.dart and recovery_repository.dart
  //          beyond the pre-existing `save` (NFR-M5-02)
  //
  // The verb surface of both files must not use persist, write, store, or
  // share as member/method names. `save` in recovery_repository.dart is the
  // sole pre-existing exception. This gate enforces the naming contract from
  // the M5 spec (NFR-M5-02).
  // ──────────────────────────────────────────────────────────────────────────

  group(
    'gate 7 — recovery_list_provider.dart and recovery_repository.dart have '
    'no persist|write|store|share member names (NFR-M5-02)',
    () {
      // ── red fixture: provider with a "store" method ───────────────────────
      group('fixture — provider with forbidden "persist" method', () {
        // The regex uses word-boundary matching (\b), so the method must be
        // named exactly `persist` (or `write`/`store`/`share`) — not
        // `persistNote` (which would not match `\bpersist\b`).
        const brokenSource = '''
class RecoveryListNotifier extends AsyncNotifier<List<RecoveryNote>> {
  Future<void> persist(RecoveryNote note) async { /* ... */ }
}
''';

        test('should_FAIL_forbidden_verb_scan_on_broken_fixture', () {
          final forbiddenPattern = RegExp(r'\b(persist|write|store|share)\b');
          final lines = brokenSource.split('\n');
          final hits = <int>[];
          for (var i = 0; i < lines.length; i++) {
            final t = lines[i].trimLeft();
            if (t.startsWith('//') || t.startsWith('*')) continue;
            if (t.startsWith('import ')) continue;
            if (forbiddenPattern.hasMatch(lines[i])) hits.add(i + 1);
          }
          expect(
            hits,
            isNotEmpty,
            reason:
                'Broken fixture must trigger the forbidden-verb scan when '
                '"persist" appears as an exact method name (word-boundary '
                'match: \\bpersist\\b matches "persist(" not "persistNote").',
          );
        });
      });

      // ── green: real files ─────────────────────────────────────────────────
      test('should_have_NO_persist_write_store_share_member_names_in_'
          'recovery_provider_and_repository', () {
        final scanPaths = [
          '$root/lib/presentation/recovery/recovery_list_provider.dart',
          '$root/lib/domain/recovery/recovery_repository.dart',
        ];

        // Pattern matches the forbidden verb tokens as whole words.
        final forbiddenPattern = RegExp(r'\b(persist|write|store|share)\b');
        final hits = <String>[];

        for (final path in scanPaths) {
          final file = File(path);
          if (!file.existsSync()) continue;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            // Skip comment lines.
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
              continue;
            }
            // Skip import lines (package/path names may contain the words).
            if (trimmed.startsWith('import ')) continue;
            // Skip string literals that happen to contain the words.
            // We focus on identifiers, not doc comment bodies.
            if (forbiddenPattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              'recovery_list_provider.dart and recovery_repository.dart '
              'must NOT use persist/write/store/share as member or method '
              'names. The only sanctioned persistence verb is "save" in '
              'RecoveryRepository (NFR-M5-02 / spec §5.3 verb-surface '
              'gate).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 8 — ARB key parity: app_en.arb and app_it.arb have identical key
  //          sets AND all 18 recovery keys are present in both
  //          (NFR-M5-05 / FR-M5-04 localization key-parity gate)
  //
  // The 18 required recovery keys (TASK-09 set):
  //   recoveryTitle, recoveryEmpty, recoveryRestoreTooltip,
  //   recoveryDeleteTooltip, recoveryDeleteAllTooltip,
  //   recoveryRestoreDialogTitle, recoveryRestoreDialogBody,
  //   recoveryRestoreDialogConfirm, recoveryDeleteDialogTitle,
  //   recoveryDeleteDialogBody, recoveryDeleteDialogConfirm,
  //   recoveryDeleteAllDialogTitle, recoveryDeleteAllDialogBody,
  //   recoveryDeleteAllDialogConfirm, recoveryDialogCancel,
  //   recoveryBackTooltip, recoveryToggleLabel, recoveryToggleTooltip
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 8 — app_en.arb and app_it.arb have identical total key sets AND '
      'all 18 recovery keys are present in both (NFR-M5-05 key-parity)', () {
    const expectedRecoveryKeys = {
      'recoveryTitle',
      'recoveryEmpty',
      'recoveryRestoreTooltip',
      'recoveryDeleteTooltip',
      'recoveryDeleteAllTooltip',
      'recoveryRestoreDialogTitle',
      'recoveryRestoreDialogBody',
      'recoveryRestoreDialogConfirm',
      'recoveryDeleteDialogTitle',
      'recoveryDeleteDialogBody',
      'recoveryDeleteDialogConfirm',
      'recoveryDeleteAllDialogTitle',
      'recoveryDeleteAllDialogBody',
      'recoveryDeleteAllDialogConfirm',
      'recoveryDialogCancel',
      'recoveryBackTooltip',
      'recoveryToggleLabel',
      'recoveryToggleTooltip',
    };

    // ── red fixture: ARB content missing recoveryEmpty ────────────────────
    group('fixture — ARB content missing recoveryEmpty', () {
      const brokenArbJson =
          '{'
          '"recoveryTitle": "Recovery",'
          '"recoveryRestoreTooltip": "Restore"'
          '}';

      test('should_FAIL_arb_key_scan_when_recoveryEmpty_missing', () {
        final decoded = json.decode(brokenArbJson) as Map<String, dynamic>;
        final recoveryKeys = decoded.keys
            .where((k) => k.startsWith('recovery'))
            .toSet();
        final missing = expectedRecoveryKeys.difference(recoveryKeys);
        expect(
          missing,
          isNotEmpty,
          reason:
              'Broken fixture is missing recovery keys — the scan must '
              'detect the gap when keys are absent.',
        );
      });
    });

    // ── green: real ARB files ─────────────────────────────────────────────
    group('real lib/l10n/app_en.arb and app_it.arb', () {
      late Set<String> enAllKeys;
      late Set<String> itAllKeys;
      late Set<String> enRecoveryKeys;
      late Set<String> itRecoveryKeys;

      setUpAll(() {
        Set<String> nonMetaKeys(String path) {
          final file = File(path);
          expect(
            file.existsSync(),
            isTrue,
            reason: '$path must exist (TASK-09 ARB keys).',
          );
          final decoded =
              json.decode(file.readAsStringSync()) as Map<String, dynamic>;
          return decoded.keys.where((k) => !k.startsWith('@')).toSet();
        }

        enAllKeys = nonMetaKeys('$root/lib/l10n/app_en.arb');
        itAllKeys = nonMetaKeys('$root/lib/l10n/app_it.arb');
        enRecoveryKeys = enAllKeys
            .where((k) => k.startsWith('recovery'))
            .toSet();
        itRecoveryKeys = itAllKeys
            .where((k) => k.startsWith('recovery'))
            .toSet();
      });

      test('should_have_all_18_recovery_keys_in_app_en_arb', () {
        final missing = expectedRecoveryKeys.difference(enRecoveryKeys);
        expect(
          missing,
          isEmpty,
          reason:
              'app_en.arb is missing recovery keys: ${missing.join(', ')} '
              '(NFR-M5-05, TASK-09).',
        );
      });

      test('should_have_all_18_recovery_keys_in_app_it_arb', () {
        final missing = expectedRecoveryKeys.difference(itRecoveryKeys);
        expect(
          missing,
          isEmpty,
          reason:
              'app_it.arb is missing recovery keys: ${missing.join(', ')} '
              '(NFR-M5-05, TASK-09).',
        );
      });

      test('should_have_identical_recovery_key_sets_in_en_and_it_arb', () {
        final onlyInEn = enRecoveryKeys.difference(itRecoveryKeys);
        final onlyInIt = itRecoveryKeys.difference(enRecoveryKeys);
        expect(
          onlyInEn,
          isEmpty,
          reason:
              'app_en.arb has recovery keys NOT in app_it.arb: '
              '${onlyInEn.join(', ')} (NFR-M5-05 key-parity).',
        );
        expect(
          onlyInIt,
          isEmpty,
          reason:
              'app_it.arb has recovery keys NOT in app_en.arb: '
              '${onlyInIt.join(', ')} (NFR-M5-05 key-parity).',
        );
      });

      test('should_have_identical_total_key_sets_in_en_and_it_arb', () {
        final onlyInEn = enAllKeys.difference(itAllKeys);
        final onlyInIt = itAllKeys.difference(enAllKeys);
        expect(
          onlyInEn,
          isEmpty,
          reason:
              'app_en.arb has keys NOT present in app_it.arb: '
              '${onlyInEn.join(', ')} (ARB global key-parity).',
        );
        expect(
          onlyInIt,
          isEmpty,
          reason:
              'app_it.arb has keys NOT present in app_en.arb: '
              '${onlyInIt.join(', ')} (ARB global key-parity).',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 9 — INVERTED (OQ-M6-15 / TASK-12 M6 Wave 5)
  //
  // Original gate (M5): asserted that buffer_screen.dart wraps
  // Navigator.pushNamed('/recovery') inside a kDebugMode block.
  //
  // Inversion (M6): TASK-12 removed the kDebugMode debug nav Row from
  // buffer_screen.dart (FR-M6-23). The menu sheet (openMenuSheet) is now
  // the SOLE navigation entry point. buffer_screen.dart must NOT contain
  // any kDebugMode-wrapped Navigator.pushNamed block for /recovery.
  //
  // The gate now asserts ABSENCE:
  //   1. No non-comment line in buffer_screen.dart contains `kDebugMode`.
  //   2. No non-comment line in buffer_screen.dart contains `'/recovery'`
  //      as a pushNamed call (the route string may appear in comments).
  //
  // Note: '/recovery' IS present in menu_sheet.dart (the modal bottom sheet
  // tile). That is correct and does NOT cause this gate to fire because this
  // gate only scans buffer_screen.dart.
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 9 — buffer_screen.dart has NO kDebugMode nav Row '
      '(OQ-M6-15 / FR-M6-23 menu-sheet-only nav)', () {
    // ── red fixture: source containing a kDebugMode block ─────────────────
    group('fixture — source WITH kDebugMode guard', () {
      const brokenSource =
          '  if (kDebugMode) {\n'
          '    IconButton(\n'
          '      onPressed: () {\n'
          "        Navigator.pushNamed(context, '/recovery');\n"
          '      },\n'
          '    );\n'
          '  }\n';

      test('should_FAIL_absence_scan_on_broken_fixture', () {
        // Verify the broken fixture actually contains kDebugMode so the
        // gate's absence check would correctly fire against it.
        expect(
          brokenSource.contains('kDebugMode'),
          isTrue,
          reason:
              'Broken fixture MUST contain "kDebugMode" to prove the '
              'absence-scan would fire if the debug Row were still present.',
        );
      });
    });

    // ── green: real buffer_screen.dart ────────────────────────────────────
    group('real lib/presentation/editor/buffer_screen.dart', () {
      late List<String> lines;

      setUpAll(() {
        final path = '$root/lib/presentation/editor/buffer_screen.dart';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/presentation/editor/buffer_screen.dart must exist.',
        );
        lines = file.readAsStringSync().split('\n');
      });

      test('should_NOT_have_kDebugMode_in_buffer_screen', () {
        final hasDebugMode = lines.any((l) {
          final t = l.trimLeft();
          // Ignore comment lines (single-line // comments and doc /** lines).
          if (t.startsWith('//') || t.startsWith('*')) return false;
          return l.contains('kDebugMode');
        });
        expect(
          hasDebugMode,
          isFalse,
          reason:
              'buffer_screen.dart must NOT contain kDebugMode. '
              'The kDebugMode debug nav Row was removed in TASK-12 (OQ-M6-15 / '
              'FR-M6-23). Navigation is now exclusively via openMenuSheet().',
        );
      });

      test('should_NOT_have_kDebugMode_wrapped_pushNamed_recovery', () {
        // Check that no non-comment line is a pushNamed('/recovery') call
        // that would indicate the old debug Row is still present.
        // Note: '/recovery' legitimately appears in menu_sheet.dart (the
        // route tile), NOT in buffer_screen.dart. This gate is scoped to
        // buffer_screen.dart only.
        final hasPushNamedRecovery = lines.any((l) {
          final t = l.trimLeft();
          if (t.startsWith('//') || t.startsWith('*')) return false;
          return l.contains("'/recovery'") && l.contains('pushNamed');
        });
        expect(
          hasPushNamedRecovery,
          isFalse,
          reason:
              "buffer_screen.dart must NOT contain Navigator.pushNamed('/recovery'). "
              'Recovery navigation belongs in menu_sheet.dart (FR-M6-23).',
        );
      });

      test(
        'should_NOT_have_kDebugMode_wrapped_nav_Row_in_buffer_screen_source',
        () {
          // Belt-and-suspenders: verify there is no `if (kDebugMode)` block
          // in the non-comment source (same logic as above — redundant but
          // explicit for gate audit clarity).
          final hasKDebugBlock = lines.any((l) {
            final t = l.trimLeft();
            if (t.startsWith('//') || t.startsWith('*')) return false;
            return l.contains('kDebugMode');
          });
          expect(
            hasKDebugBlock,
            isFalse,
            reason:
                'buffer_screen.dart must not contain any kDebugMode conditional '
                '(OQ-M6-15). The entire debug nav block was removed in TASK-12.',
          );
        },
      );
    });
  });
}
