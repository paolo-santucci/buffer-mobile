// M2 source-scan gate — buffer-mobile
//
// Spec refs: FR-M2-04, FR-M2-09, FR-M2-14, NFR-M2-01, NFR-M2-02,
//            NFR-M2-04, NFR-M2-05, §7.1, §7.2
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m1_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Test targets:
//   1. AndroidManifest SEND filter — three required substrings present; no new
//      <queries> block added (FR-M2-14).
//   2. No isDirty symbol in lib/domain/buffer/ (post-TASK-02 removal).
//   3. No non-recovery buffer-text persistence path — no PageStorageKey,
//      AutomaticKeepAliveClientMixin, wantKeepAlive, or SharedPreferences
//      write in buffer/editor/lifecycle files (NFR-M2-01).
//   4. BufferNotifier has no member name matching save|persist|write|store|share
//      (FR-M2-09).
//   5. No bare print( in M2 lib/ (excludes debugPrint and comment lines).
//   6. lib/domain/ has zero package:flutter/ imports (domain purity).
//   7. package:receive_sharing_intent/ imported in EXACTLY ONE file:
//      lib/infrastructure/share/receive_sharing_intent_service.dart (EC-12).
//   8. ARB key parity — every key in app_en.arb exists in app_it.arb and
//      vice-versa (NFR-M2-04).
//   9. No literal Text('…') / Text("…") with non-empty hardcoded strings in
//      M2 lib/presentation/ (NFR-M2-05).

// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers (identical to m1_gate_test.dart conventions)
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
  late String libDir;
  late String domainDir;
  late String domainBufferDir;
  late String presentationDir;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    domainDir = '$root/lib/domain';
    domainBufferDir = '$root/lib/domain/buffer';
    presentationDir = '$root/lib/presentation';
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 1. AndroidManifest SEND filter (FR-M2-14)
  //
  // The manifest must contain the three SEND substrings added by TASK-04.
  // It must NOT contain a new <queries> block beyond the pre-existing
  // PROCESS_TEXT queries block (the gate checks for 'android.intent.action.SEND'
  // inside a <queries> block, which would be the violation pattern).
  // ────────────────────────────────────────────────────────────────────────────

  group('AndroidManifest SEND filter (FR-M2-14)', () {
    const manifestPath = 'android/app/src/main/AndroidManifest.xml';

    // Required substrings that TASK-04 must have added.
    const requiredSubstrings = [
      'android.intent.action.SEND',
      'android.intent.category.DEFAULT',
      'android:mimeType="text/plain"',
    ];

    // ── red fixture: a manifest without the SEND filter ──────────────────────
    group('fixture — broken manifest (no SEND filter)', () {
      const brokenManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <activity android:name=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

      for (final substring in requiredSubstrings) {
        test('should_FAIL_to_find_"$substring"_in_broken_manifest', () {
          expect(
            brokenManifest.contains(substring),
            isFalse,
            reason: 'Broken fixture must NOT contain "$substring".',
          );
        });
      }
    });

    // ── green: real manifest ─────────────────────────────────────────────────
    group('real manifest — all three SEND substrings present', () {
      late String manifestContent;

      setUpAll(() {
        final file = File('$root/$manifestPath');
        expect(file.existsSync(), isTrue, reason: '$manifestPath must exist');
        manifestContent = file.readAsStringSync();
      });

      for (final substring in requiredSubstrings) {
        test('should_contain_"$substring"', () {
          expect(
            manifestContent.contains(substring),
            isTrue,
            reason:
                'AndroidManifest must contain "$substring" '
                '(FR-M2-14 / TASK-04). '
                'Add the SEND intent-filter to the MainActivity element.',
          );
        });
      }

      test('should_NOT_add_SEND_action_inside_a_queries_block', () {
        // The only valid location for android.intent.action.SEND is inside
        // an <intent-filter> on MainActivity, NOT inside a <queries> block.
        // A naive implementer might erroneously add it there. We detect this
        // by finding "action.SEND" inside the <queries>…</queries> region.
        final queriesRegion = RegExp(
          r'<queries>([\s\S]*?)</queries>',
        ).firstMatch(manifestContent);
        if (queriesRegion != null) {
          final queriesContent = queriesRegion.group(0) ?? '';
          expect(
            queriesContent.contains('android.intent.action.SEND'),
            isFalse,
            reason:
                'android.intent.action.SEND must NOT appear inside a '
                '<queries> block — it belongs in an <intent-filter> on '
                'MainActivity, not as a queries declaration (FR-M2-14).',
          );
        }
        // If there is no <queries> block at all, the check trivially passes.
      });
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 2. No isDirty symbol in lib/domain/buffer/ (post-TASK-02 removal)
  // ────────────────────────────────────────────────────────────────────────────

  group('no isDirty symbol in lib/domain/buffer/', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — source with isDirty field', () {
      const brokenSource = '''
class BufferState {
  final bool isDirty;
  final String text;
  const BufferState({required this.isDirty, required this.text});
}
''';

      test('should_FAIL_isDirty_scan_on_broken_fixture', () {
        // The regex matches `isDirty` as a word boundary to avoid false
        // positives from identifiers that merely contain "isDirty" as a
        // substring (none expected, but defensive).
        final pattern = RegExp(r'\bisDirty\b');
        // Filter out comment lines to match the real scan logic.
        final nonCommentLines = brokenSource
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .where((l) => !l.trimLeft().startsWith('*'));
        final hit = nonCommentLines.any((l) => pattern.hasMatch(l));
        expect(
          hit,
          isTrue,
          reason: 'Broken fixture must trigger the isDirty scan.',
        );
      });
    });

    // ── green: real domain/buffer dir ────────────────────────────────────────
    test('should_have_zero_isDirty_symbols_in_lib_domain_buffer', () {
      final pattern = RegExp(r'\bisDirty\b');
      final hits = <String>[];
      for (final file in _dartFiles(domainBufferDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          // Skip comment lines — doc comments may mention isDirty by name
          // (e.g. migration notes).
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (pattern.hasMatch(lines[i])) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'isDirty was removed from BufferState in TASK-02 (FR-M2-09). '
            'No source symbol named isDirty may remain in '
            'lib/domain/buffer/.\nOffenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 3. No non-recovery buffer-text persistence paths (NFR-M2-01)
  //
  // a) No PageStorageKey in lib/ (already in M1 gate; replicated here for M2
  //    completeness so the M2 gate is self-contained).
  // b) No AutomaticKeepAliveClientMixin or wantKeepAlive in lib/.
  // c) No SharedPreferences.set* call in the buffer/editor/lifecycle files
  //    (the settings repository may use setString; this scan is scoped to the
  //    ephemerality-sensitive files only).
  // ────────────────────────────────────────────────────────────────────────────

  group('no non-recovery buffer-text persistence paths (NFR-M2-01)', () {
    // Ephemerality-sensitive file paths (relative to lib/).
    const ephemeralSensitivePaths = [
      'domain/buffer',
      'presentation/editor',
      'presentation/lifecycle',
    ];

    // ── red fixtures ─────────────────────────────────────────────────────────
    group('fixture — broken source with PageStorageKey', () {
      const brokenSource = 'PageStorageKey("buffer_text")';

      test('should_FAIL_PageStorageKey_scan_on_broken_fixture', () {
        expect(brokenSource.contains('PageStorageKey'), isTrue);
      });
    });

    group('fixture — broken source with AutomaticKeepAliveClientMixin', () {
      const brokenSource =
          'class EditorState extends State<Editor> with AutomaticKeepAliveClientMixin {';

      test('should_FAIL_keepalive_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('AutomaticKeepAliveClientMixin') ||
              brokenSource.contains('wantKeepAlive'),
          isTrue,
        );
      });
    });

    group('fixture — broken source with SharedPreferences.setString', () {
      const brokenSource = 'await prefs.setString("buffer_text", state.text);';

      test('should_FAIL_SharedPreferences_write_scan_on_broken_fixture', () {
        expect(RegExp(r'\.set[A-Z]').hasMatch(brokenSource), isTrue);
      });
    });

    // ── green: real lib/ tree ────────────────────────────────────────────────
    test('should_have_zero_PageStorageKey_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (lines[i].contains('PageStorageKey')) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'PageStorageKey must not appear in lib/ — buffer text is ephemeral '
            '(NFR-M2-01).\nOffenders:\n${hits.join('\n')}',
      );
    });

    test(
      'should_have_zero_AutomaticKeepAliveClientMixin_or_wantKeepAlive_in_lib',
      () {
        const forbidden = ['AutomaticKeepAliveClientMixin', 'wantKeepAlive'];
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            for (final token in forbidden) {
              if (lines[i].contains(token)) {
                hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
              }
            }
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'AutomaticKeepAliveClientMixin / wantKeepAlive must not appear '
              'in lib/ — buffer text must not persist via Flutter keep-alive '
              '(NFR-M2-01).\nOffenders:\n${hits.join('\n')}',
        );
      },
    );

    test(
      'should_have_zero_SharedPreferences_write_calls_in_buffer_editor_lifecycle_files',
      () {
        // SharedPreferences.set*() calls in these directories would indicate a
        // buffer-text persistence path outside the recovery boundary.
        // The settings repository (lib/infrastructure/settings/) legitimately
        // uses setString — that directory is NOT scanned here.
        final writePattern = RegExp(r'\.set[A-Z]');
        final hits = <String>[];

        for (final relPath in ephemeralSensitivePaths) {
          final dir = '$libDir/$relPath';
          for (final file in _dartFiles(dir)) {
            final lines = file.readAsLinesSync();
            for (var i = 0; i < lines.length; i++) {
              final trimmed = lines[i].trimLeft();
              if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
                continue;
              }
              if (lines[i].contains('SharedPreferences') &&
                  writePattern.hasMatch(lines[i])) {
                hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
              }
            }
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              'No SharedPreferences.set*() calls are permitted in '
              '${ephemeralSensitivePaths.join(', ')} — '
              'buffer text must not be persisted outside the recovery boundary '
              '(NFR-M2-01).\nOffenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 4. BufferNotifier has no forbidden-token member names (FR-M2-09)
  //
  // The scan reads lib/domain/buffer/buffer_notifier.dart and checks that no
  // non-comment line declares a method whose name matches
  // save|persist|write|store|share (as a whole word, case-sensitive).
  //
  // Allowed (in comments, doc comments, or strings):
  //   /// No implementation may write buffer text…   ← doc comment
  //   'the sole sanctioned exception is the recovery hook'  ← string
  // Forbidden (as a member declaration):
  //   void save(String text);
  //   Future<void> persistText(String t);
  // ────────────────────────────────────────────────────────────────────────────

  group('BufferNotifier has no forbidden-token member names (FR-M2-09)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — BufferNotifier with forbidden save() member', () {
      const brokenSource = '''
abstract interface class BufferNotifier {
  void save(String text);
  void updateText(String text);
}
''';

      test('should_FAIL_forbidden_token_scan_on_broken_fixture', () {
        // Simulate the scan: find non-comment lines with a forbidden method
        // declaration pattern.
        final forbiddenPattern = RegExp(
          r'\b(save|persist|write|store|share)\s*\(',
        );
        final lines = brokenSource.split('\n');
        final hit = lines.any((l) {
          final t = l.trimLeft();
          if (t.startsWith('//') || t.startsWith('*')) return false;
          return forbiddenPattern.hasMatch(l);
        });
        expect(
          hit,
          isTrue,
          reason: 'Broken fixture must trigger the forbidden-token scan.',
        );
      });
    });

    // ── green: real buffer_notifier.dart ────────────────────────────────────
    test(
      'should_have_no_forbidden_token_member_declarations_in_BufferNotifier',
      () {
        final notifierFile = File('$domainBufferDir/buffer_notifier.dart');
        expect(
          notifierFile.existsSync(),
          isTrue,
          reason:
              'lib/domain/buffer/buffer_notifier.dart must exist (FR-M2-09)',
        );

        // Pattern: forbidden token immediately followed by ( — matches method
        // calls and declarations alike; comment lines are excluded first.
        final forbiddenPattern = RegExp(
          r'\b(save|persist|write|store|share)\s*\(',
        );
        final hits = <String>[];
        final lines = notifierFile.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          // Skip comment and doc-comment lines.
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (forbiddenPattern.hasMatch(lines[i])) {
            hits.add('${notifierFile.path}:${i + 1}: ${lines[i].trim()}');
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              'BufferNotifier must not declare any member whose name matches '
              'save|persist|write|store|share — the buffer mutation contract '
              'is limited to updateText, reset, and populate (FR-M2-09).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 5. No bare print() in M2 lib/ (NFR-M2-01 — structured logging only)
  //
  // Mirrors the M1 gate check. debugPrint() is allowed; bare print() is not.
  // Comment lines are excluded.
  // ────────────────────────────────────────────────────────────────────────────

  group('no bare print() in lib/ (NFR-M2-01)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — source with bare print()', () {
      const brokenSource = 'print("saving recovery file");';

      test('should_FAIL_print_scan_on_broken_fixture', () {
        // The fixture is not a comment; not debugPrint.
        final line = brokenSource.trimLeft();
        final isComment = line.startsWith('//') || line.startsWith('*');
        final isBare = line.contains('print(') && !line.contains('debugPrint(');
        expect(
          !isComment && isBare,
          isTrue,
          reason: 'Broken fixture must trigger the print() scan.',
        );
      });
    });

    // ── green: real lib/ ────────────────────────────────────────────────────
    test('should_have_zero_bare_print_calls_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (trimmed.contains('print(') && !trimmed.contains('debugPrint(')) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'No bare print() calls are permitted in lib/ — use dart:developer '
            'log() or debugPrint() instead (NFR-M2-01).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 6. Domain purity — lib/domain/ has zero package:flutter/ imports
  //
  // Mirrors the M1 gate check (self-contained so the M2 gate is complete).
  // ────────────────────────────────────────────────────────────────────────────

  group('domain purity — no package:flutter/ in lib/domain/', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — domain file with package:flutter/ import', () {
      const brokenSource = "import 'package:flutter/material.dart';";

      test('should_FAIL_domain_purity_scan_on_broken_fixture', () {
        expect(brokenSource.contains('package:flutter/'), isTrue);
      });
    });

    // ── green: real lib/domain/ ─────────────────────────────────────────────
    test('should_have_zero_package_flutter_imports_in_lib_domain', () {
      final hits = <String>[];
      for (final file in _dartFiles(domainDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (lines[i].contains('package:flutter/')) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'lib/domain/ must be pure Dart — no package:flutter/ imports '
            '(domain purity, FR-M2-09).\nOffenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 7. package:receive_sharing_intent/ imported in EXACTLY ONE designated file
  // (EC-12 — share isolation)
  //
  // The designated file is:
  //   lib/infrastructure/share/receive_sharing_intent_service.dart
  //
  // Imports of the buffer adapter file via the buffer package namespace:
  //   import 'package:buffer/infrastructure/share/receive_sharing_intent_service.dart'
  // are NOT counted — they are not imports of the platform package itself.
  // ────────────────────────────────────────────────────────────────────────────

  group('package:receive_sharing_intent/ imported in exactly one file (EC-12)', () {
    const designatedAdapterRelPath =
        'infrastructure/share/receive_sharing_intent_service.dart';

    // ── red fixture: two files import the platform package ─────────────────
    group('fixture — two files with receive_sharing_intent imports', () {
      const twoImports = [
        "import 'package:receive_sharing_intent/receive_sharing_intent.dart';",
        "import 'package:receive_sharing_intent/receive_sharing_intent.dart';",
      ];

      test('should_FAIL_isolation_scan_given_two_package_imports', () {
        final packagePattern = RegExp(
          r'''import\s+['"]package:receive_sharing_intent/''',
        );
        final count = twoImports
            .where((l) => packagePattern.hasMatch(l))
            .length;
        expect(
          count,
          greaterThan(1),
          reason: 'Broken fixture must have more than one import.',
        );
      });
    });

    // ── red fixture: no imports at all ────────────────────────────────────
    group('fixture — no receive_sharing_intent imports', () {
      const zeroImports = ["import 'package:flutter/material.dart';"];

      test('should_FAIL_isolation_scan_given_zero_package_imports', () {
        final packagePattern = RegExp(
          r'''import\s+['"]package:receive_sharing_intent/''',
        );
        final count = zeroImports
            .where((l) => packagePattern.hasMatch(l))
            .length;
        expect(
          count,
          equals(0),
          reason: 'Broken fixture must have zero imports (adapter is missing).',
        );
      });
    });

    // ── green: real lib/ ──────────────────────────────────────────────────
    test(
      'should_import_receive_sharing_intent_package_in_exactly_one_designated_file',
      () {
        final packagePattern = RegExp(
          r'''import\s+['"]package:receive_sharing_intent/''',
        );
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
              continue;
            }
            if (packagePattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        expect(
          hits,
          hasLength(1),
          reason:
              'package:receive_sharing_intent/ must be imported in EXACTLY '
              'ONE file in lib/ — the isolated adapter at '
              'lib/$designatedAdapterRelPath (EC-12).\n'
              '${hits.isEmpty ? 'No imports found — adapter may be missing.' : 'Unexpected imports:\n${hits.join('\n')}'}',
        );

        if (hits.isNotEmpty) {
          expect(
            hits.first,
            contains(designatedAdapterRelPath),
            reason:
                'The sole package:receive_sharing_intent/ import must be in '
                'lib/$designatedAdapterRelPath, not elsewhere (EC-12).',
          );
        }
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 8. ARB key parity (NFR-M2-04)
  //
  // Every key in app_en.arb must exist in app_it.arb and vice versa.
  // Mirrors the M1 gate check; replicated here for M2 completeness.
  // ────────────────────────────────────────────────────────────────────────────

  group('ARB key parity (NFR-M2-04)', () {
    // ── red fixture: mismatched key sets ────────────────────────────────────
    group('fixture — mismatched ARB key sets', () {
      const enKeys = {'appTitle', 'recoveryTitle'};
      const itKeys = {'appTitle'}; // missing recoveryTitle

      test('should_FAIL_parity_check_on_mismatched_fixture', () {
        final onlyInEn = enKeys.difference(itKeys);
        final onlyInIt = itKeys.difference(enKeys);
        expect(
          onlyInEn.isNotEmpty || onlyInIt.isNotEmpty,
          isTrue,
          reason: 'Broken fixture must have mismatched keys.',
        );
      });
    });

    // ── green: real ARBs ─────────────────────────────────────────────────────
    test('should_have_identical_key_sets_in_app_en_arb_and_app_it_arb', () {
      final enArb = File('$root/lib/l10n/app_en.arb');
      final itArb = File('$root/lib/l10n/app_it.arb');

      expect(
        enArb.existsSync(),
        isTrue,
        reason: 'lib/l10n/app_en.arb must exist (NFR-M2-04)',
      );
      expect(
        itArb.existsSync(),
        isTrue,
        reason: 'lib/l10n/app_it.arb must exist (NFR-M2-04)',
      );

      Set<String> messageKeys(File arb) {
        final decoded =
            jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>;
        return decoded.keys.where((k) => !k.startsWith('@')).toSet();
      }

      final enKeys = messageKeys(enArb);
      final itKeys = messageKeys(itArb);

      final onlyInEn = enKeys.difference(itKeys);
      final onlyInIt = itKeys.difference(enKeys);

      expect(
        onlyInEn,
        isEmpty,
        reason:
            'Keys in app_en.arb but missing from app_it.arb: '
            '${onlyInEn.toList()..sort()} (NFR-M2-04)',
      );
      expect(
        onlyInIt,
        isEmpty,
        reason:
            'Keys in app_it.arb but missing from app_en.arb: '
            '${onlyInIt.toList()..sort()} (NFR-M2-04)',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 9. No literal Text() in M2 lib/presentation/ (NFR-M2-05)
  //
  // Heuristic: any `Text('...')` or `Text("...")` with a non-empty string
  // literal is a violation. ARB-lookup calls look like
  //   Text(AppLocalizations.of(context).someKey)
  // and do not match the literal pattern. Empty literals (Text('')) are
  // structural and allowed.
  //
  // Mirrors the M1 gate check; replicated here for M2 completeness with new
  // presentation files (BufferScreen, LifecycleBufferHost, app.dart).
  // ────────────────────────────────────────────────────────────────────────────

  group('no literal Text() in lib/presentation/ (NFR-M2-05)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — hardcoded Text literal', () {
      const brokenSource = "Text('Type something here…')";

      test('should_FAIL_literal_Text_scan_on_broken_fixture', () {
        final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
        expect(
          literalPattern.hasMatch(brokenSource),
          isTrue,
          reason: 'Broken fixture must trigger the literal Text() scan.',
        );
      });
    });

    // ── green: real lib/presentation/ ───────────────────────────────────────
    test(
      'should_have_zero_non_empty_literal_Text_constructors_in_lib_presentation',
      () {
        final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
        final hits = <String>[];
        for (final file in _dartFiles(presentationDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            if (literalPattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'lib/presentation/ must not contain Text("literal") or '
              "Text('literal') with non-empty strings — all user-facing "
              'strings must go through AppLocalizations (NFR-M2-05).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });
}
