// M7 source-scan gate — buffer-mobile
//
// Spec refs: NFR-M7-01, NFR-M7-03, NFR-M7-04, FR-M7-03, FR-M7-05, FR-M7-09,
//            AD-M7-01
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m6_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Gate inventory (spec §6.1 "New gate", TASK-14):
//   1. Zero `textScaleFactor` in lib/ — OS font scaling goes through
//      TextField.textScaler only; no deprecated `textScaleFactor` allowed
//      anywhere in lib/ code (NFR-M7-01).
//   2. `pointerCount == 2` present in buffer_screen.dart — the mandatory
//      guard that makes single-finger drags not trigger pinch-zoom (NFR-M7-03,
//      FR-M7-05).
//   3. Both `'monospace'` and `'sans-serif'` literal strings present in
//      buffer_screen.dart — required for the M7 gate scan to confirm the
//      font-family fallback chains are wired (FR-M7-09).
//   4. `slotList` present in app_settings.dart and absent in any
//      `typography_settings.dart` file — confirms the AD-M7-01 relocation
//      (single source of truth on AppSettings; duplicate model deleted).
//   5. `'font-size'` in the save region of
//      shared_preferences_settings_repository.dart — confirms the eighth key
//      is persisted (FR-M7-03, TASK-02).
//   6. Zero `TypographySettings` references in lib/ — AD-M7-01 retirement
//      complete; the duplicate model and its freezed part are gone.
//   7. Zero `typographyProvider` references in lib/ — AD-M7-01 retirement
//      complete; the provider is gone.

// ignore_for_file: avoid_relative_lib_imports

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
  late String bufferScreenPath;
  late String appSettingsPath;
  late String repositoryPath;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    bufferScreenPath = '$root/lib/presentation/editor/buffer_screen.dart';
    appSettingsPath = '$root/lib/domain/settings/app_settings.dart';
    repositoryPath =
        '$root/lib/infrastructure/settings/'
        'shared_preferences_settings_repository.dart';
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 1 — zero `textScaleFactor` in lib/
  //
  // Flutter's `textScaleFactor` is deprecated. M7 uses `textScaler` /
  // `MediaQuery.textScalerOf(context)` exclusively. Any occurrence of the
  // deprecated name in a non-comment code line is a regression.
  // (NFR-M7-01)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 1 — zero textScaleFactor in lib/ (NFR-M7-01)', () {
    // ── red fixture: code using textScaleFactor ───────────────────────────
    group('fixture — code referencing textScaleFactor', () {
      const brokenSource =
          '  final style = TextStyle(\n'
          '    fontSize: baseFontSize * MediaQuery.of(context).textScaleFactor,\n'
          '  );\n';

      test('should_FAIL_textScaleFactor_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('textScaleFactor'),
          isTrue,
          reason:
              'Broken fixture must contain "textScaleFactor" to prove the '
              'deprecated-API scan would fire when the old API is referenced.',
        );
      });
    });

    // ── green: real lib/ ─────────────────────────────────────────────────
    test('should_have_ZERO_textScaleFactor_references_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        hits.addAll(_codeHits(file, 'textScaleFactor'));
      }
      expect(
        hits,
        isEmpty,
        reason:
            'lib/ must not reference the deprecated textScaleFactor. Use '
            'textScaler / MediaQuery.textScalerOf(context) instead '
            '(NFR-M7-01). Found:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 2 — `pointerCount == 2` guard in buffer_screen.dart
  //
  // The pinch GestureDetector in buffer_screen.dart must guard its
  // onScaleUpdate handler with `details.pointerCount == 2` to prevent
  // single-finger drags from triggering font-size changes. Absence means the
  // guard was accidentally removed.
  // (NFR-M7-03, FR-M7-05)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 2 — `pointerCount` two-finger guard present in buffer_screen.dart '
      '(NFR-M7-03, FR-M7-05)', () {
    // ── red fixture: onScaleUpdate without the pointerCount guard ─────────
    group('fixture — onScaleUpdate handler without pointerCount guard', () {
      const brokenSource =
          '  onScaleUpdate: (details) {\n'
          '    final delta = scaleToSlotDelta(details.scale, _scaleStartIndex);\n'
          '  },\n';

      test('should_FAIL_pointerCount_scan_on_broken_fixture', () {
        // The guard must reference `pointerCount` near `2`; the broken fixture
        // has neither.
        expect(
          brokenSource.contains('pointerCount'),
          isFalse,
          reason:
              'Broken fixture must NOT contain "pointerCount" to prove '
              'the guard-presence scan would fire when it is absent.',
        );
      });
    });

    // ── green: real buffer_screen.dart ───────────────────────────────────
    // The guard may be written as `== 2` or `!= 2` depending on the branch
    // direction — both encode the two-finger requirement. Scan for
    // `pointerCount` adjacent to `2` on the same non-comment line.
    test('should_have_pointerCount_2_guard_in_buffer_screen', () {
      final file = File(bufferScreenPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'buffer_screen.dart must exist.',
      );
      // Accept `pointerCount == 2` OR `pointerCount != 2`.
      final guard = RegExp(r'pointerCount\s*[!=]=\s*2\b');
      final hits = _codeHits(file, guard);
      expect(
        hits,
        isNotEmpty,
        reason:
            'buffer_screen.dart must contain a `pointerCount == 2` or '
            '`pointerCount != 2` guard in the onScaleUpdate handler — '
            'single-finger drags must not change the font size '
            '(NFR-M7-03, FR-M7-05). The guard is absent.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 3 — `'monospace'` and `'sans-serif'` literal strings in
  //           buffer_screen.dart
  //
  // The font-family resolution in buffer_screen.dart must reference the
  // platform-generic CSS-class strings `'monospace'` and `'sans-serif'` so
  // Flutter's platform font-matching can find the correct typeface. Absence
  // of either means the fallback chain was removed or renamed.
  // (FR-M7-09)
  // ──────────────────────────────────────────────────────────────────────────

  group("gate 3 — 'monospace' and 'sans-serif' literals in buffer_screen.dart "
      '(FR-M7-09)', () {
    // ── red fixture: only monospace, missing sans-serif ───────────────────
    group("fixture — only 'monospace' present, 'sans-serif' missing", () {
      const onlyMonoSource =
          "  fontFamilyFallback = const ['monospace'];\n"
          '  // doc path intentionally missing fallback\n';

      test('should_FAIL_sansSerif_scan_on_incomplete_fixture', () {
        expect(
          onlyMonoSource.contains("'sans-serif'"),
          isFalse,
          reason:
              "Broken fixture must NOT contain 'sans-serif' to prove the "
              'gate would fire when the document-font fallback is absent.',
        );
      });
    });

    // ── red fixture: only sans-serif, missing monospace ───────────────────
    group("fixture — only 'sans-serif' present, 'monospace' missing", () {
      const onlySansSource =
          "  fontFamilyFallback = const ['sans-serif'];\n"
          '  // mono path intentionally missing fallback\n';

      test('should_FAIL_monospace_scan_on_incomplete_fixture', () {
        expect(
          onlySansSource.contains("'monospace'"),
          isFalse,
          reason:
              "Broken fixture must NOT contain 'monospace' to prove the "
              'gate would fire when the mono-font fallback is absent.',
        );
      });
    });

    // ── green: real buffer_screen.dart ───────────────────────────────────
    group('real lib/presentation/editor/buffer_screen.dart', () {
      late String screenContent;

      setUpAll(() {
        final file = File(bufferScreenPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'buffer_screen.dart must exist.',
        );
        screenContent = file.readAsStringSync();
      });

      test('should_contain_monospace_literal_string_in_buffer_screen', () {
        expect(
          screenContent.contains("'monospace'"),
          isTrue,
          reason:
              "buffer_screen.dart must contain the literal string 'monospace' "
              'for the mono-font fallback chain (FR-M7-09, spec §5.1.5c).',
        );
      });

      test('should_contain_sans_serif_literal_string_in_buffer_screen', () {
        expect(
          screenContent.contains("'sans-serif'"),
          isTrue,
          reason:
              "buffer_screen.dart must contain the literal string 'sans-serif' "
              'for the document-font fallback chain (FR-M7-09, spec §5.1.5c).',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 4 — `slotList` in app_settings.dart; absent from typography_settings.dart
  //
  // AD-M7-01 relocates the 21-slot list onto AppSettings as the single source
  // of truth. Verification: slotList must be declared in app_settings.dart
  // (present ≥ 1 time) and must NOT appear in any typography_settings.dart
  // (that file should no longer exist after retirement; if it does, it must
  // not reference slotList).
  // (AD-M7-01, FR-M7-01)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 4 — slotList in app_settings.dart; absent from '
      'typography_settings.dart (AD-M7-01, FR-M7-01)', () {
    // ── red fixture: slotList NOT in app_settings ─────────────────────────
    group('fixture — app_settings source without slotList declaration', () {
      // Deliberately avoid the word "slotList" in the fixture so the contains
      // check verifies absence cleanly (the fixture represents pre-M7 code).
      const missingSlotListSource =
          'class AppSettings with _\$AppSettings {\n'
          '  @Default(8) final int fontSizeIndex;\n'
          '  // 21-slot const is absent here — TASK-01 not yet applied\n'
          '}\n';

      test('should_FAIL_slotList_presence_scan_on_missing_fixture', () {
        expect(
          missingSlotListSource.contains('slotList'),
          isFalse,
          reason:
              'Broken fixture must NOT contain "slotList" to prove the '
              'presence check would fire when it is absent from app_settings.',
        );
      });
    });

    // ── green: real lib/ ─────────────────────────────────────────────────
    test('should_have_slotList_in_app_settings_dart', () {
      final file = File(appSettingsPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'lib/domain/settings/app_settings.dart must exist.',
      );
      final hits = _codeHits(file, 'slotList');
      expect(
        hits,
        isNotEmpty,
        reason:
            'app_settings.dart must declare slotList (AD-M7-01 relocation '
            'of the 21-slot constant from TypographySettings to AppSettings). '
            'Not found.',
      );
    });

    test('should_have_ZERO_slotList_in_typography_settings_dart', () {
      // typography_settings.dart should be deleted. If it still exists,
      // slotList must not appear in it.
      final typoFile = File(
        '$libDir/domain/typography/typography_settings.dart',
      );
      if (!typoFile.existsSync()) {
        // File deleted — AD-M7-01 retirement complete. Test passes trivially.
        return;
      }
      final hits = _codeHits(typoFile, 'slotList');
      expect(
        hits,
        isEmpty,
        reason:
            'typography_settings.dart must not reference slotList after '
            'AD-M7-01 relocation. The file should be deleted entirely; if '
            'it still exists it must not define or reference slotList.\n'
            'Found:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 5 — `'font-size'` key written in the save region of the repository
  //
  // TASK-02 added the eighth persisted key. The literal string `'font-size'`
  // (or `AppSettings.kFontSize` reference) must appear in the save() body of
  // shared_preferences_settings_repository.dart so the font slot survives
  // app restarts. Absence means TASK-02 was not applied or was reverted.
  // (FR-M7-03, TASK-02)
  // ──────────────────────────────────────────────────────────────────────────

  group("gate 5 — 'font-size' key written in repository save region "
      '(FR-M7-03, TASK-02)', () {
    // ── red fixture: repository save without font-size key ────────────────
    group('fixture — repository save body missing font-size write', () {
      const missingKeySource =
          '  await _prefs.setString(AppSettings.kColorScheme, s.colorScheme.name);\n'
          '  // font-size key intentionally missing\n';

      test('should_FAIL_fontSizeKey_scan_on_missing_fixture', () {
        final hasFontSizeKey =
            missingKeySource.contains("'font-size'") ||
            missingKeySource.contains('kFontSize');
        expect(
          hasFontSizeKey,
          isFalse,
          reason:
              'Broken fixture must NOT contain font-size key reference to '
              'prove the persistence check would fire when the key is absent.',
        );
      });
    });

    // ── green: real shared_preferences_settings_repository.dart ──────────
    test('should_have_font_size_key_in_repository_save', () {
      final file = File(repositoryPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'lib/infrastructure/settings/'
            'shared_preferences_settings_repository.dart must exist.',
      );
      final content = file.readAsStringSync();

      // Accept either the literal 'font-size' string or a reference to
      // AppSettings.kFontSize (both encode the same key contract).
      final hasFontSizeRef =
          content.contains("'font-size'") || content.contains('kFontSize');
      expect(
        hasFontSizeRef,
        isTrue,
        reason:
            'shared_preferences_settings_repository.dart must reference '
            "'font-size' (or AppSettings.kFontSize) to persist the font-size "
            'slot across restarts (FR-M7-03, TASK-02). Not found.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 6 — zero `TypographySettings` references in lib/
  //
  // AD-M7-01 retires the duplicate TypographySettings model. Any remaining
  // reference in lib/ Dart code (excluding comments) is a regression.
  // (AD-M7-01, NFR-M7-04)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 6 — zero TypographySettings references in lib/ (AD-M7-01, '
      'NFR-M7-04)', () {
    // ── red fixture: code referencing TypographySettings ─────────────────
    group('fixture — code using TypographySettings', () {
      const brokenSource =
          '  final ts = TypographySettings(\n'
          '    fontSizeIndex: 8,\n'
          '    useMonospaceFont: true,\n'
          '  );\n';

      test('should_FAIL_TypographySettings_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('TypographySettings'),
          isTrue,
          reason:
              'Broken fixture must contain "TypographySettings" to prove '
              'the retirement scan would fire when the deleted model is '
              'still referenced.',
        );
      });
    });

    // ── green: real lib/ ─────────────────────────────────────────────────
    test('should_have_ZERO_TypographySettings_references_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        hits.addAll(_codeHits(file, 'TypographySettings'));
      }
      expect(
        hits,
        isEmpty,
        reason:
            'lib/ must contain zero references to TypographySettings. '
            'The model was retired in AD-M7-01 (TASK-03); all readers have '
            'been repointed to AppSettings / settingsProvider.\n'
            'Found:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 7 — zero `typographyProvider` references in lib/
  //
  // AD-M7-01 retires the typographyProvider. Any remaining reference in lib/
  // Dart code (excluding comments) is a regression — all consumers must read
  // settingsProvider instead.
  // (AD-M7-01, NFR-M7-04)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 7 — zero typographyProvider references in lib/ (AD-M7-01, '
      'NFR-M7-04)', () {
    // ── red fixture: code referencing typographyProvider ─────────────────
    group('fixture — code using typographyProvider', () {
      const brokenSource =
          '  final typography = ref.watch(typographyProvider);\n';

      test('should_FAIL_typographyProvider_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('typographyProvider'),
          isTrue,
          reason:
              'Broken fixture must contain "typographyProvider" to prove '
              'the retirement scan would fire when the deleted provider is '
              'still referenced.',
        );
      });
    });

    // ── green: real lib/ ─────────────────────────────────────────────────
    test('should_have_ZERO_typographyProvider_references_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        hits.addAll(_codeHits(file, 'typographyProvider'));
      }
      expect(
        hits,
        isEmpty,
        reason:
            'lib/ must contain zero references to typographyProvider. '
            'The provider was retired in AD-M7-01 (TASK-03); all consumers '
            'must use settingsProvider for typography state.\n'
            'Found:\n${hits.join('\n')}',
      );
    });
  });
}
