// SP-20260615 source-scan gate — buffer-mobile
//
// Spec refs: NFR-03, NFR-04, NFR-07, NFR-09
// Plan ref: .claude/docs/plans/sp-20260615-ui-accent-margins-find-rownumbers-plan.md
//           TASK-09 (verification gate — wave 5)
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m7_gate_test.dart style: each gate first proves itself on a
// deliberately-broken in-test fixture string, then wires the assertion against
// the real project tree.  This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Gate inventory (spec §7.1 source scans, TASK-09):
//
//   1. Single-seed scan (NFR-03):
//        - grep lib/ for old yellow/brown hex:
//          #F6D32D | 0xFFF6D32D | #f6d32d | 0xFFf6d32d
//          #873000 | 0xFF873000
//          → ZERO matches on non-comment code lines.
//        - grep lib/ for new seed: 3584E4 / 3584e4
//          → EXACTLY ONE match on non-comment code lines.
//
//   2. Single-path scan (NFR-04):
//        Count `.startSearch(entryOffset:` on non-comment code lines in lib/.
//        The leading dot distinguishes the PROVIDER invocation from:
//          a) the injected-callback field call in _OpenFindOrRefocusAction
//             (`startSearch(entryOffset: ...)` — no leading dot).
//          b) the callback field declaration / doc comments in editor_actions.dart.
//        Expected count: EXACTLY ONE (in buffer_screen.dart, the wiring site).
//
//   3. ARB parity (NFR-07):
//        Both `menuFind` and `settingsLineNumbers` keys present and non-empty
//        in app_en.arb AND app_it.arb.
//
//   4. Ephemerality scan (NFR-09):
//        The new editor files (line_number_gutter.dart and the SP-20260615
//        edits to buffer_screen.dart / editor_actions.dart / menu_sheet.dart)
//        must add ZERO buffer-text persistence calls:
//          - no `writeAsString(` or `writeAsStringSync(` in lib/presentation/
//          - no `setString(`/`setBool(`/`setInt(`/`setDouble(` in lib/presentation/
//        Settings-repository calls in lib/infrastructure/ are expected and excluded.

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

/// Returns true if [line] is a comment line (starts with // or * after
/// optional whitespace).
bool _isCommentLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*');
}

/// Collects non-comment lines from [file] matching [pattern].
List<String> _codeHits(File file, Pattern pattern) {
  final hits = <String>[];
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    if (_isCommentLine(lines[i])) continue;
    final line = lines[i];
    final isMatch = pattern is RegExp
        ? pattern.hasMatch(line)
        : line.contains(pattern as String);
    if (isMatch) hits.add('${file.path}:${i + 1}: ${line.trim()}');
  }
  return hits;
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  late String root;
  late String libDir;
  late String presentationDir;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    presentationDir = '$root/lib/presentation';
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 1 — Single-seed scan (NFR-03)
  //
  // After TASK-03 the two old accent literals (#F6D32D / #873000) must be
  // gone from lib/ code lines.  Exactly one occurrence of #3584E4 (the new
  // GNOME Adwaita "Blue 3" seed) must appear — in app_theme.dart only.
  // Comment lines are excluded so doc comments that mention the old colours
  // as historical reference do not trigger false positives.
  // ──────────────────────────────────────────────────────────────────────────

  group(
    'gate 1 — single-seed scan: zero old hex, exactly one 3584E4 (NFR-03)',
    () {
      // Patterns for old accent hex values (both upper and lower case).
      final oldHexPattern = RegExp(
        r'(#[Ff]6[Dd]32[Dd]|0x[Ff][Ff][Ff]6[Dd]32[Dd]|#873000|0xFF873000)',
      );
      // Pattern for the new seed (case-insensitive).
      final newSeedPattern = RegExp(r'3584[Ee]4');

      // ── red fixture: code still containing the old yellow accent ─────────
      group('fixture — code still referencing old yellow hex #F6D32D', () {
        const brokenSource =
            'static const Color _brandLight = Color(0xFFF6D32D);\n'
            'static const Color _brandDark  = Color(0xFF873000);\n';

        test('should_FAIL_old_hex_scan_on_broken_fixture', () {
          expect(
            oldHexPattern.hasMatch(brokenSource),
            isTrue,
            reason:
                'Broken fixture must contain old accent hex to prove the '
                'single-seed scan would fire when the old literals are present.',
          );
        });

        test('should_FAIL_new_seed_absent_on_broken_fixture', () {
          expect(
            newSeedPattern.hasMatch(brokenSource),
            isFalse,
            reason:
                'Broken fixture must NOT contain 3584E4 to prove the '
                'new-seed presence check would fire when the seed is absent.',
          );
        });
      });

      // ── green: real lib/ — zero old hex, exactly one new seed ────────────
      test('should_have_ZERO_old_accent_hex_on_code_lines_in_lib', () {
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          hits.addAll(_codeHits(file, oldHexPattern));
        }
        expect(
          hits,
          isEmpty,
          reason:
              'lib/ must contain zero code-line references to the old accent '
              'hex (#F6D32D / #873000 and their 0xFF variants). Found:\n'
              '${hits.join('\n')}',
        );
      });

      test('should_have_EXACTLY_ONE_new_seed_3584E4_on_code_lines_in_lib', () {
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          hits.addAll(_codeHits(file, newSeedPattern));
        }
        expect(
          hits,
          hasLength(1),
          reason:
              'lib/ must contain exactly one code-line reference to 3584E4 '
              '(the single accent seed in app_theme.dart — NFR-03). '
              'Found ${hits.length}:\n${hits.join('\n')}',
        );
      });
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 2 — Single-path scan (NFR-04)
  //
  // There must be exactly ONE provider-level call to startSearch in lib/.
  // The discriminating pattern is `.startSearch(entryOffset:` (with a leading
  // dot), which matches the method call on the findProvider notifier.
  //
  // This is DIFFERENT from:
  //   a) `startSearch(entryOffset: ...)` WITHOUT a leading dot — that is the
  //      injected-callback field invocation inside _OpenFindOrRefocusAction
  //      (buffer_screen.dart:1506) and OpenFindAction.invoke
  //      (editor_actions.dart:339) — both calling the FIELD, not the provider.
  //   b) `final void Function(...) startSearch` — field declaration lines.
  //   c) Doc comment lines — excluded by _isCommentLine.
  //
  // After TASK-07 the single provider call site is buffer_screen.dart:1376:
  //   `ref.read(findProvider.notifier).startSearch(entryOffset: entryOffset);`
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 2 — single-path scan: exactly one provider .startSearch( call '
      '(NFR-04)', () {
    // Pattern: a dot immediately before startSearch( — the provider call.
    // The callback-field calls (`startSearch(` with no preceding dot) are
    // intentionally NOT matched.
    const providerCallPattern = '.startSearch(entryOffset:';

    // ── red fixture: code with a second provider startSearch call ─────────
    group('fixture — code with two provider .startSearch( invocations', () {
      const brokenSource =
          '  ref.read(findProvider.notifier).startSearch(entryOffset: 0);\n'
          '  // second call site — violates NFR-04\n'
          '  ref.read(findProvider.notifier).startSearch(entryOffset: pos);\n';

      test('should_FAIL_single_path_scan_on_broken_fixture', () {
        // Strip comment lines manually (the fixture multi-line string is not
        // processed line-by-line by the production helper here — the fixture
        // proves that the pattern fires at all).
        final nonCommentLines = brokenSource
            .split('\n')
            .where((l) => !_isCommentLine(l))
            .toList();
        final count = nonCommentLines
            .where((l) => l.contains(providerCallPattern))
            .length;
        expect(
          count,
          greaterThan(1),
          reason:
              'Broken fixture must trigger the single-path scan by '
              'containing more than one provider .startSearch(entryOffset: '
              'invocation on non-comment lines.',
        );
      });
    });

    // ── green: real lib/ — exactly one provider .startSearch( ────────────
    test('should_have_EXACTLY_ONE_provider_startSearch_call_site_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        hits.addAll(_codeHits(file, providerCallPattern));
      }
      expect(
        hits,
        hasLength(1),
        reason:
            'lib/ must contain exactly one provider .startSearch(entryOffset: '
            'call site (NFR-04 single-path). The menu path dispatches '
            'OpenFindIntent — it does NOT call startSearch directly. '
            'Found ${hits.length}:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 3 — ARB parity: menuFind + settingsLineNumbers in EN + IT (NFR-07)
  //
  // Both ARB keys must be present in app_en.arb and app_it.arb with non-empty
  // values.  This is a targeted sub-parity check; the full key-set parity is
  // already covered by m6_gate_test.dart gate 2.
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 3 — ARB parity: menuFind + settingsLineNumbers in EN and IT '
      '(NFR-07, FR-17, FR-18)', () {
    const spKeys = {'menuFind', 'settingsLineNumbers'};

    // ── red fixture: ARB content missing settingsLineNumbers ──────────────
    group('fixture — ARB JSON missing settingsLineNumbers key', () {
      const brokenArbJson =
          '{'
          '"menuFind": "Find / Replace"'
          '}'; // settingsLineNumbers intentionally absent

      test('should_FAIL_arb_parity_when_settingsLineNumbers_missing', () {
        final decoded = json.decode(brokenArbJson) as Map<String, dynamic>;
        final keys = decoded.keys.where((k) => !k.startsWith('@')).toSet();
        final missing = spKeys.difference(keys);
        expect(
          missing,
          isNotEmpty,
          reason:
              'Broken fixture must show a missing SP key to prove the ARB '
              'parity scan fires when settingsLineNumbers is absent.',
        );
      });
    });

    // ── red fixture: ARB content with empty menuFind value ────────────────
    group('fixture — ARB JSON with empty menuFind value', () {
      const brokenArbJson =
          '{'
          '"menuFind": "",'
          '"settingsLineNumbers": "Show line numbers"'
          '}';

      test('should_FAIL_arb_parity_when_menuFind_value_is_empty', () {
        final decoded = json.decode(brokenArbJson) as Map<String, dynamic>;
        final emptyKeys = spKeys.where((k) {
          final v = decoded[k];
          return v == null || (v as String).isEmpty;
        }).toSet();
        expect(
          emptyKeys,
          isNotEmpty,
          reason:
              'Broken fixture must trigger the empty-value check to prove '
              'the parity scan fires when a key value is an empty string.',
        );
      });
    });

    // ── green: real ARB files ─────────────────────────────────────────────
    group('real lib/l10n/app_en.arb and app_it.arb', () {
      late Map<String, dynamic> enDecoded;
      late Map<String, dynamic> itDecoded;

      setUpAll(() {
        Map<String, dynamic> decodeArb(String path) {
          final file = File(path);
          expect(
            file.existsSync(),
            isTrue,
            reason: '$path must exist (SP ARB parity gate).',
          );
          return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
        }

        enDecoded = decodeArb('$root/lib/l10n/app_en.arb');
        itDecoded = decodeArb('$root/lib/l10n/app_it.arb');
      });

      test('should_have_menuFind_key_in_app_en_arb_with_non_empty_value', () {
        expect(
          enDecoded.containsKey('menuFind'),
          isTrue,
          reason: 'app_en.arb must contain key "menuFind" (FR-17, NFR-07).',
        );
        expect(
          (enDecoded['menuFind'] as String).isNotEmpty,
          isTrue,
          reason: 'app_en.arb["menuFind"] must be non-empty (FR-17, NFR-07).',
        );
      });

      test('should_have_menuFind_key_in_app_it_arb_with_non_empty_value', () {
        expect(
          itDecoded.containsKey('menuFind'),
          isTrue,
          reason: 'app_it.arb must contain key "menuFind" (FR-17, NFR-07).',
        );
        expect(
          (itDecoded['menuFind'] as String).isNotEmpty,
          isTrue,
          reason: 'app_it.arb["menuFind"] must be non-empty (FR-17, NFR-07).',
        );
      });

      test(
        'should_have_settingsLineNumbers_key_in_app_en_arb_with_non_empty_value',
        () {
          expect(
            enDecoded.containsKey('settingsLineNumbers'),
            isTrue,
            reason:
                'app_en.arb must contain key "settingsLineNumbers" '
                '(FR-18, NFR-07).',
          );
          expect(
            (enDecoded['settingsLineNumbers'] as String).isNotEmpty,
            isTrue,
            reason:
                'app_en.arb["settingsLineNumbers"] must be non-empty '
                '(FR-18, NFR-07).',
          );
        },
      );

      test(
        'should_have_settingsLineNumbers_key_in_app_it_arb_with_non_empty_value',
        () {
          expect(
            itDecoded.containsKey('settingsLineNumbers'),
            isTrue,
            reason:
                'app_it.arb must contain key "settingsLineNumbers" '
                '(FR-18, NFR-07).',
          );
          expect(
            (itDecoded['settingsLineNumbers'] as String).isNotEmpty,
            isTrue,
            reason:
                'app_it.arb["settingsLineNumbers"] must be non-empty '
                '(FR-18, NFR-07).',
          );
        },
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 4 — Ephemerality scan (NFR-09)
  //
  // The SP-20260615 changes (accent, margins, find affordance, line-number
  // gutter) must add ZERO buffer-text persistence calls in lib/presentation/.
  // Settings-level booleans (setShowLineNumbers) write to SharedPreferences
  // via lib/infrastructure/settings/ — that is expected and excluded.
  //
  // Scanned patterns in lib/presentation/ non-comment code lines:
  //   a) `writeAsString(` or `writeAsStringSync(` — file writes
  //   b) `setString(`  — SharedPreferences string write
  //   c) `setBool(`    — SharedPreferences bool write
  //   d) `setInt(`     — SharedPreferences int write
  //   e) `setDouble(`  — SharedPreferences double write
  //
  // None of these should appear in the presentation layer.  The recovery
  // writes are in lib/infrastructure/recovery/ (file_recovery_repository.dart)
  // and the settings writes are in lib/infrastructure/settings/
  // (shared_preferences_settings_repository.dart) — both outside the scan
  // scope.
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 4 — ephemerality scan: zero persistence writes in '
      'lib/presentation/ (NFR-09)', () {
    final persistencePattern = RegExp(
      r'(writeAsString\(|writeAsStringSync\(|setString\(|setBool\(|setInt\(|setDouble\()',
    );

    // ── red fixture: presentation code that writes to SharedPreferences ────
    group('fixture — presentation widget directly calling setBool(', () {
      const brokenSource =
          '  // bad: presentation layer directly persisting buffer text\n'
          '  await prefs.setBool("bufferText", _controller.text.isNotEmpty);\n';

      test('should_FAIL_ephemerality_scan_on_broken_fixture', () {
        final nonCommentLines = brokenSource
            .split('\n')
            .where((l) => !_isCommentLine(l))
            .toList();
        final hits = nonCommentLines
            .where((l) => persistencePattern.hasMatch(l))
            .toList();
        expect(
          hits,
          isNotEmpty,
          reason:
              'Broken fixture must trigger the ephemerality scan to prove '
              'it fires when a presentation file calls a persistence verb.',
        );
      });
    });

    // ── green: real lib/presentation/ — zero persistence writes ──────────
    test('should_have_ZERO_persistence_write_calls_in_lib_presentation', () {
      final hits = <String>[];
      for (final file in _dartFiles(presentationDir)) {
        hits.addAll(_codeHits(file, persistencePattern));
      }
      expect(
        hits,
        isEmpty,
        reason:
            'lib/presentation/ must contain zero persistence write calls '
            '(writeAsString, setString, setBool, setInt, setDouble). '
            'Buffer-text writes belong in lib/infrastructure/recovery/; '
            'settings writes belong in lib/infrastructure/settings/. '
            'NFR-09 ephemerality invariant. Found:\n${hits.join('\n')}',
      );
    });
  });
}
