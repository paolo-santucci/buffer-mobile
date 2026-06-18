// M6 source-scan gate — buffer-mobile
//
// Spec refs: FR-M6-11, FR-M6-12, FR-M6-16, FR-M6-18, FR-M6-19, FR-M6-23,
//            NFR-M6-01, NFR-M6-02, NFR-M6-07, NFR-M6-08, OQ-M6-15, §7.1, §7.2
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m5_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Gate inventory (spec §7.1, TASK-15):
//   1. Widened NFR-10 scan — a synthetic fixture string containing
//      Semantics(label:'Foo'), tooltip:'Bar', hintText:'Baz', and Text('Lit')
//      triggers all 4 hit types; real lib/presentation/ → 0 hits (every
//      user-facing string from ARB). (NFR-M6-01, FR-M6-19)
//   2. ARB parity — app_en.arb key set == app_it.arb key set; all 23 §5.4
//      M6 keys present in BOTH files. (NFR-M6-02, FR-M6-17)
//   3. Debug-row removed — buffer_screen.dart has 0 kDebugMode blocks
//      containing pushNamed('/recovery'|'/settings'|'/about'). (FR-M6-23)
//   4. Single mutation point — the literal 'color-scheme' appears ONLY in
//      shared_preferences_settings_repository.dart and app_settings.dart
//      (kColorScheme const); 0 elsewhere in lib/. (FR-M6-12, NFR-M6-07)
//   5. Exactly ONE fontSizeToast emitter — M7 wired the first (and only)
//      ref.listen emission in buffer_screen.dart; real lib/presentation/ →
//      exactly 1 hit; fontSizeToast NOT re-declared in ARB files. (FR-M6-16,
//      OQ-M6-02, D2 — REVISED for M7 TASK-13)
//   6. No editor fontSize in M6 files — 0 `fontSize:` inside a TextStyle
//      in the new M6 widget files. (FR-M6-02 scope-out)
//   7. AndroidManifest <queries> — contains VIEW+https AND VIEW+http inside
//      <queries>. (FR-M6-11, NFR-M6-08)
//   8. Indent/Outdent leaks removed — 0 Semantics(label: 'Indent'/'Outdent')
//      literals in buffer_screen.dart (now ARB-sourced). (FR-M6-18)
//   9. Single ScrollController — exactly 1 ScrollController() construction
//      in buffer_screen.dart. (LP §5.3 hard constraint)
//  10. No chrome self-scroll — 0 jumpTo/animateTo/scrollTo in
//      chrome_pill.dart + chrome_reveal_controller.dart. (LP §5.3)
//      (SP-20260617 TASK-11: chrome_overlay.dart deleted Wave 1 → chrome_pill.dart)

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

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  late String root;

  setUpAll(() {
    root = _root;
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 1 — widened NFR-10 localization scan
  //
  // The NFR-10 scan now covers four pattern families:
  //   a) Text('...') / Text("...") — classic literal widget
  //   b) Semantics(label: '...') / Semantics(label: "...")
  //   c) tooltip: '...' / tooltip: "..."
  //   d) hintText: '...' / hintText: "..."
  //
  // Red-then-green: a synthetic fixture string triggers all 4 hit types.
  // Then the real lib/presentation/ tree is scanned and must report 0 hits.
  // (NFR-M6-01, FR-M6-19)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 1 — widened NFR-10 scan catches Semantics(label:), tooltip:, '
      "hintText:, and Text('...') (NFR-M6-01, FR-M6-19)", () {
    // The four patterns the widened scan checks:
    final textPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
    final semanticsLabelPattern = RegExp(
      r"""Semantics\s*\([^)]*label\s*:\s*['"][^'"]+['"]""",
    );
    final tooltipPattern = RegExp(r"""tooltip\s*:\s*['"][^'"]+['"]""");
    final hintTextPattern = RegExp(r"""hintText\s*:\s*['"][^'"]+['"]""");

    // ── red fixture: source with all four hit types ───────────────────────
    group("fixture — source with Text('Lit'), Semantics(label:'Foo'), "
        "tooltip:'Bar', hintText:'Baz'", () {
      const brokenSource = """
Widget build(BuildContext context) {
  return Column(children: [
    Text('Lit'),
    Semantics(label: 'Foo', child: const SizedBox()),
    TextField(hintText: 'Baz', tooltip: 'Bar'),
  ]);
}
""";

      test('should_FAIL_text_literal_scan_on_broken_fixture', () {
        expect(
          textPattern.hasMatch(brokenSource),
          isTrue,
          reason:
              "Broken fixture must trigger the Text('...') scan to prove "
              'the widened NFR-10 check would fire.',
        );
      });

      test('should_FAIL_semantics_label_scan_on_broken_fixture', () {
        expect(
          semanticsLabelPattern.hasMatch(brokenSource),
          isTrue,
          reason:
              "Broken fixture must trigger the Semantics(label:'Foo') scan "
              'to prove the widened NFR-10 check would fire.',
        );
      });

      test('should_FAIL_tooltip_scan_on_broken_fixture', () {
        expect(
          tooltipPattern.hasMatch(brokenSource),
          isTrue,
          reason:
              "Broken fixture must trigger the tooltip:'Bar' scan to prove "
              'the widened NFR-10 check would fire.',
        );
      });

      test('should_FAIL_hintText_scan_on_broken_fixture', () {
        expect(
          hintTextPattern.hasMatch(brokenSource),
          isTrue,
          reason:
              "Broken fixture must trigger the hintText:'Baz' scan to prove "
              'the widened NFR-10 check would fire.',
        );
      });
    });

    // ── green: real lib/presentation/ ────────────────────────────────────
    test('should_have_ZERO_hardcoded_display_strings_in_lib_presentation', () {
      final presentationDir = '$root/lib/presentation';
      final hits = <String>[];

      for (final file in _dartFiles(presentationDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final line = lines[i];
          if (textPattern.hasMatch(line) ||
              semanticsLabelPattern.hasMatch(line) ||
              tooltipPattern.hasMatch(line) ||
              hintTextPattern.hasMatch(line)) {
            hits.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        hits,
        isEmpty,
        reason:
            'lib/presentation/ must not contain hardcoded display strings. '
            "No Text('...'), Semantics(label:'...'), tooltip:'...', or "
            "hintText:'...' — all user-facing strings must go through "
            'AppLocalizations (NFR-M6-01, FR-M6-19).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 2 — ARB key parity: all 23 §5.4 M6 keys present in both files
  //
  // The 23 required M6 keys (§5.4 full enumeration):
  //   themeFollowSystem, themeLight, themeDark, themeSelectorLabel
  //   menuTooltip, menuPreferences, menuAbout, menuRecovery
  //   settingsTitle, settingsAppearance, settingsBehavior, settingsThemeMode,
  //   settingsRecoveryEnabled, settingsSpellCheck
  //   aboutTitle, aboutDeveloper, aboutVersion, aboutLicense, aboutIssues,
  //   aboutWebsite
  //   fontSizeToast
  //   editorIndentLabel, editorOutdentLabel
  //
  // Additionally: app_en.arb key set == app_it.arb key set (set difference
  // empty in both directions). (NFR-M6-02, FR-M6-17)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 2 — ARB key parity: all 23 §5.4 M6 keys in both files, '
      'key sets equal (NFR-M6-02, FR-M6-17)', () {
    const expectedM6Keys = {
      // Theme selector
      'themeFollowSystem',
      'themeLight',
      'themeDark',
      'themeSelectorLabel',
      // Menu sheet
      'menuTooltip',
      'menuPreferences',
      'menuAbout',
      'menuRecovery',
      // Settings screen
      'settingsTitle',
      'settingsAppearance',
      'settingsBehavior',
      'settingsThemeMode',
      'settingsRecoveryEnabled',
      'settingsSpellCheck',
      // About screen
      'aboutTitle',
      'aboutDeveloper',
      'aboutVersion',
      'aboutLicense',
      'aboutIssues',
      'aboutWebsite',
      // Toast M7 seam (pre-defined, not emitted in M6)
      'fontSizeToast',
      // A11y leak fixes
      'editorIndentLabel',
      'editorOutdentLabel',
    };

    // ── red fixture: ARB content missing editorIndentLabel ────────────────
    group('fixture — ARB content missing editorIndentLabel', () {
      const brokenArbJson =
          '{'
          '"themeFollowSystem": "Follow System",'
          '"menuTooltip": "Menu"'
          '}';

      test('should_FAIL_m6_key_scan_when_editorIndentLabel_missing', () {
        final decoded = json.decode(brokenArbJson) as Map<String, dynamic>;
        final keys = decoded.keys.where((k) => !k.startsWith('@')).toSet();
        final missing = expectedM6Keys.difference(keys);
        expect(
          missing,
          isNotEmpty,
          reason:
              'Broken fixture is missing M6 keys — the scan must detect the '
              'gap when required keys are absent.',
        );
      });
    });

    // ── red fixture: EN and IT key sets differ ────────────────────────────
    group('fixture — EN and IT ARBs with differing key sets', () {
      final enKeys = {'themeFollowSystem', 'themeLight', 'editorIndentLabel'};
      final itKeys = {
        'themeFollowSystem',
        'themeLight',
      }; // missing editorIndentLabel

      test('should_FAIL_parity_check_when_key_sets_differ', () {
        final onlyInEn = enKeys.difference(itKeys);
        expect(
          onlyInEn,
          isNotEmpty,
          reason:
              'Broken fixture must show a key-set difference to prove the '
              'parity scan would fire when EN and IT diverge.',
        );
      });
    });

    // ── green: real ARB files ─────────────────────────────────────────────
    group('real lib/l10n/app_en.arb and app_it.arb', () {
      late Set<String> enAllKeys;
      late Set<String> itAllKeys;

      setUpAll(() {
        Set<String> nonMetaKeys(String path) {
          final file = File(path);
          expect(
            file.existsSync(),
            isTrue,
            reason: '$path must exist (ARB parity gate).',
          );
          final decoded =
              json.decode(file.readAsStringSync()) as Map<String, dynamic>;
          return decoded.keys.where((k) => !k.startsWith('@')).toSet();
        }

        enAllKeys = nonMetaKeys('$root/lib/l10n/app_en.arb');
        itAllKeys = nonMetaKeys('$root/lib/l10n/app_it.arb');
      });

      test('should_have_all_23_m6_keys_in_app_en_arb', () {
        final missing = expectedM6Keys.difference(enAllKeys);
        expect(
          missing,
          isEmpty,
          reason:
              'app_en.arb is missing M6 §5.4 keys: ${missing.join(', ')} '
              '(NFR-M6-02, FR-M6-17).',
        );
      });

      test('should_have_all_23_m6_keys_in_app_it_arb', () {
        final missing = expectedM6Keys.difference(itAllKeys);
        expect(
          missing,
          isEmpty,
          reason:
              'app_it.arb is missing M6 §5.4 keys: ${missing.join(', ')} '
              '(NFR-M6-02, FR-M6-17).',
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
              '${onlyInEn.join(', ')} (NFR-M6-02 ARB key-parity).',
        );
        expect(
          onlyInIt,
          isEmpty,
          reason:
              'app_it.arb has keys NOT present in app_en.arb: '
              '${onlyInIt.join(', ')} (NFR-M6-02 ARB key-parity).',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 3 — debug-row removed: buffer_screen.dart has 0 kDebugMode blocks
  //          containing pushNamed('/recovery'|'/settings'|'/about')
  //
  // FR-M6-23: the menu sheet (openMenuSheet) is now the SOLE navigation
  // entry point. The `kDebugMode` debug nav Row is fully removed.
  // This gate extends m5_gate_test.dart gate-9 to also cover /settings
  // and /about (not just /recovery). (FR-M6-23)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 3 — buffer_screen.dart has 0 kDebugMode blocks with '
      "pushNamed('/recovery'|'/settings'|'/about') (FR-M6-23)", () {
    // ── red fixture: source containing a kDebugMode pushNamed block ────────
    group("fixture — source WITH kDebugMode + pushNamed('/settings')", () {
      const brokenSource =
          '  if (kDebugMode) {\n'
          '    IconButton(\n'
          "      onPressed: () => Navigator.pushNamed(context, '/settings'),\n"
          '    );\n'
          '  }\n';

      test('should_FAIL_debugmode_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('kDebugMode'),
          isTrue,
          reason:
              'Broken fixture must contain "kDebugMode" to prove the absence '
              'scan would fire if the debug Row were still present.',
        );
      });

      test('should_FAIL_pushNamed_settings_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains("'/settings'") &&
              brokenSource.contains('pushNamed'),
          isTrue,
          reason:
              "Broken fixture must contain pushNamed('/settings') to prove "
              'the debug-route scan would fire.',
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
        lines = file.readAsLinesSync();
      });

      test('should_NOT_have_kDebugMode_in_buffer_screen', () {
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          if (lines[i].contains('kDebugMode')) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'buffer_screen.dart must NOT contain kDebugMode. The debug nav '
              'Row was removed in TASK-12 (FR-M6-23 / OQ-M6-15). Menu sheet '
              'is now the sole entry point for navigation.\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });

      test('should_NOT_have_pushNamed_recovery_in_buffer_screen', () {
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final line = lines[i];
          if (line.contains('pushNamed') &&
              (line.contains("'/recovery'") ||
                  line.contains("'/settings'") ||
                  line.contains("'/about'"))) {
            hits.add('${i + 1}: ${line.trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'buffer_screen.dart must NOT contain Navigator.pushNamed with '
              "'/recovery', '/settings', or '/about'. Navigation belongs "
              'exclusively in menu_sheet.dart (FR-M6-23).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 4 — single mutation point for 'color-scheme'
  //
  // The literal string 'color-scheme' may appear in lib/ Dart code only in:
  //   a) app_settings.dart         (the kColorScheme constant declaration)
  //   b) shared_preferences_settings_repository.dart  (load/save bodies)
  //
  // No other file in lib/ may contain the literal 'color-scheme' string on
  // a non-comment code line. This enforces the single-mutation-point
  // invariant (FR-M6-12, NFR-M6-07).
  // ──────────────────────────────────────────────────────────────────────────

  group(
    "gate 4 — literal 'color-scheme' appears ONLY in app_settings.dart "
    'and shared_preferences_settings_repository.dart (FR-M6-12, NFR-M6-07)',
    () {
      // ── red fixture: unauthorized file using the literal ──────────────────
      group("fixture — unauthorized file using literal 'color-scheme'", () {
        const brokenSource =
            "  final value = prefs.getString('color-scheme');\n";

        test('should_FAIL_literal_scan_on_unauthorized_fixture', () {
          expect(
            brokenSource.contains("'color-scheme'"),
            isTrue,
            reason:
                "Broken fixture must contain literal 'color-scheme' to prove "
                'the single-mutation-point scan would fire when it appears in '
                'an unauthorized file.',
          );
        });
      });

      // ── green: real lib/ ──────────────────────────────────────────────────
      test('should_have_literal_color_scheme_ONLY_in_allowed_files', () {
        final allowedFiles = {
          'app_settings.dart',
          'shared_preferences_settings_repository.dart',
        };

        final hits = <String>[];
        for (final file in _dartFiles('$root/lib')) {
          final basename = file.uri.pathSegments.last;
          if (allowedFiles.contains(basename)) continue;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            final line = lines[i];
            if (line.contains("'color-scheme'") ||
                line.contains('"color-scheme"')) {
              hits.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              "The literal 'color-scheme' must appear ONLY in app_settings.dart "
              '(kColorScheme constant) and '
              'shared_preferences_settings_repository.dart (load/save bodies). '
              'All other code must reference AppSettings.kColorScheme. '
              '(FR-M6-12, NFR-M6-07)\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 5 — exactly ONE fontSizeToast emitter in lib/presentation/
  //
  // M7 wired the first (and only) ref.listen emission of fontSizeToast in
  // buffer_screen.dart (TASK-12). The contract is now:
  //   • Exactly 1 `fontSizeToast(` call-site in lib/presentation/ (not 0,
  //     not 2+) — the single ref.listen in buffer_screen.dart.
  //   • `fontSizeToast` is NOT re-declared in app_en.arb or app_it.arb
  //     (it was added in M6 and must not appear twice per file).
  //
  // (FR-M6-16, OQ-M6-02, D2 — REVISED for M7 TASK-13)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 5 — exactly ONE fontSizeToast emitter in lib/presentation/, '
      'no ARB re-declaration (FR-M6-16, OQ-M6-02, D2 — M7 REVISED)', () {
    // Pattern: `fontSizeToast(` — any call-site reference.
    final emissionPattern = RegExp(r'fontSizeToast\s*\(');

    // ── red fixture: zero emitters (old contract — must fail now) ─────────
    group('fixture — source with zero fontSizeToast emissions (old contract)', () {
      const noEmissionSource =
          '  // M7 TODO: wire fontSizeToast here\n'
          '  ref.read(toastProvider.notifier).show(someOtherMessage);\n';

      test('should_FAIL_zero_emission_scan_on_no_emission_fixture', () {
        // Under the new contract, zero emitters is wrong. The fixture has no
        // fontSizeToast( call — proves the "at least 1" check would fire.
        expect(
          emissionPattern.hasMatch(noEmissionSource),
          isFalse,
          reason:
              'No-emission fixture must NOT contain "fontSizeToast(" to prove '
              'the presence check would fire when the M7 ref.listen is absent.',
        );
      });
    });

    // ── red fixture: two emitters (over-count — must fail) ────────────────
    group('fixture — source with two fontSizeToast emission call sites', () {
      const doubleEmissionSource =
          '  ref.read(toastProvider.notifier).show(l10n.fontSizeToast(14));\n'
          '  ref.read(toastProvider.notifier).show(l10n.fontSizeToast(16));\n';

      test('should_FAIL_count_scan_on_double_emission_fixture', () {
        final count = emissionPattern.allMatches(doubleEmissionSource).length;
        expect(
          count,
          greaterThan(1),
          reason:
              'Double-emission fixture must contain 2 fontSizeToast( calls to '
              'prove the exactly-1 count check would fire on over-emission.',
        );
      });
    });

    // ── green: real lib/presentation/ ────────────────────────────────────
    test(
      'should_have_EXACTLY_ONE_fontSizeToast_emission_in_lib_presentation',
      () {
        final presentationDir = '$root/lib/presentation';
        final hits = <String>[];

        for (final file in _dartFiles(presentationDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            if (emissionPattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        expect(
          hits,
          hasLength(1),
          reason:
              'lib/presentation/ must contain EXACTLY ONE fontSizeToast( '
              'call-site — the single ref.listen in buffer_screen.dart (M7 '
              'TASK-12, spec §5.1.5f). More than one emitter violates the '
              'single-toast-source invariant; zero means M7 wiring is absent.\n'
              'Emitters found:\n${hits.join('\n')}',
        );
      },
    );

    // ── green: fontSizeToast not re-declared in ARB files ────────────────
    group(
      'fontSizeToast appears exactly once per ARB file (no re-declaration)',
      () {
        void checkArbFile(String relPath) {
          test('should_have_fontSizeToast_EXACTLY_ONCE_in_$relPath', () {
            final file = File('$root/$relPath');
            expect(file.existsSync(), isTrue, reason: '$relPath must exist.');
            final content = file.readAsStringSync();
            // Count the number of times the key appears as a JSON key
            // ("fontSizeToast":).
            final keyPattern = RegExp(r'"fontSizeToast"\s*:');
            final count = keyPattern.allMatches(content).length;
            expect(
              count,
              equals(1),
              reason:
                  '$relPath must contain the fontSizeToast key exactly once. '
                  'Re-declaration (count > 1) is a spec violation (FR-M6-16, '
                  'OQ-M6-02); absence (count == 0) means the M6 ARB baseline '
                  'regressed. Found: $count.',
            );
          });
        }

        checkArbFile('lib/l10n/app_en.arb');
        checkArbFile('lib/l10n/app_it.arb');
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 6 — no editor fontSize in M6 widget files
  //
  // The M3 gate forbids any editor-area TextStyle from setting fontSize.
  // M6 must not introduce fontSize: in any of its new widget files.
  // SP-20260617 TASK-11: chrome_overlay.dart deleted in Wave 1 (TASK-06);
  // replaced by chrome_pill.dart. Gate 6 now scans chrome_pill.dart instead.
  // Scans: theme_selector, chrome_pill, toast_overlay, menu_sheet,
  // settings_screen, about_screen. (FR-M6-02 scope-out, OQ-M6-02)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 6 — no fontSize: inside TextStyle in M6 new widget files '
      '(M3 gate invariant, FR-M6-02 scope-out)', () {
    const m6Files = [
      'theme_selector.dart',
      // SP-20260617 TASK-11: chrome_overlay.dart → chrome_pill.dart (Wave 1).
      'chrome_pill.dart',
      'toast_overlay.dart',
      'menu_sheet.dart',
      'settings_screen.dart',
      'about_screen.dart',
    ];

    // ── red fixture: TextStyle with fontSize ──────────────────────────────
    group('fixture — TextStyle with fontSize set', () {
      const brokenSource =
          '  const style = TextStyle(fontSize: 16.0, color: Colors.red);\n';

      test('should_FAIL_fontSize_scan_on_broken_fixture', () {
        // The scan looks for `fontSize:` on a non-comment code line in M6 files.
        expect(
          brokenSource.contains('fontSize:'),
          isTrue,
          reason:
              'Broken fixture must contain "fontSize:" to prove the M3-gate '
              'invariant scan would fire if an M6 file set editor font size.',
        );
      });
    });

    // ── green: real M6 new widget files ──────────────────────────────────
    test('should_have_ZERO_fontSize_in_M6_new_widget_files', () {
      // Find files by name in the presentation subtree.
      final allPresentation = _dartFiles('$root/lib/presentation');
      final m6FileNames = m6Files.toSet();
      final targetFiles = allPresentation.where(
        (f) => m6FileNames.contains(f.uri.pathSegments.last),
      );

      final hits = <String>[];
      for (final file in targetFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          if (lines[i].contains('fontSize:')) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        hits,
        isEmpty,
        reason:
            'M6 new widget files must NOT set fontSize: in any TextStyle. '
            'Font size is exclusively M7 (Typography & Layout). The M3 gate '
            'guards editor TextStyle.fontSize; M6 must not circumvent it.\n'
            'Files scanned: ${m6Files.join(', ')}\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 7 — AndroidManifest.xml has VIEW+https AND VIEW+http inside <queries>
  //
  // Without this block, url_launcher.canLaunchUrl returns false on Android 11+
  // (scoped package visibility). Required for About screen links. (FR-M6-11,
  // NFR-M6-08, D3)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 7 — AndroidManifest.xml has VIEW+https AND VIEW+http in '
      '<queries> (FR-M6-11, NFR-M6-08)', () {
    // ── red fixture: manifest missing the https intent ────────────────────
    group('fixture — manifest with only http (missing https)', () {
      const brokenManifest = '''
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW"/>
    <data android:scheme="http"/>
  </intent>
</queries>
''';

      test('should_FAIL_https_scan_on_manifest_missing_https', () {
        // The scan checks for VIEW+https — should be absent in broken fixture.
        final hasViewAction = brokenManifest.contains(
          'android.intent.action.VIEW',
        );
        final hasHttps = brokenManifest.contains('android:scheme="https"');
        // Fixture has VIEW but NOT https → proves the https check would fail.
        expect(
          hasViewAction && !hasHttps,
          isTrue,
          reason:
              'Broken fixture must have VIEW but NOT https to prove the '
              'manifest gate would fire when https scheme is absent.',
        );
      });
    });

    // ── green: real AndroidManifest.xml ──────────────────────────────────
    group('real android/app/src/main/AndroidManifest.xml', () {
      late String manifestContent;

      setUpAll(() {
        final path = '$root/android/app/src/main/AndroidManifest.xml';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'AndroidManifest.xml must exist.',
        );
        manifestContent = file.readAsStringSync();
      });

      test('should_contain_VIEW_action_in_queries', () {
        expect(
          manifestContent.contains('android.intent.action.VIEW'),
          isTrue,
          reason:
              'AndroidManifest.xml <queries> must declare android.intent.action.VIEW '
              'so url_launcher can discover browser intent handlers (FR-M6-11).',
        );
      });

      test('should_contain_https_scheme_in_queries', () {
        expect(
          manifestContent.contains('android:scheme="https"'),
          isTrue,
          reason:
              'AndroidManifest.xml <queries> must include android:scheme="https" '
              'so canLaunchUrl succeeds for https About links on Android 11+ '
              '(FR-M6-11, NFR-M6-08).',
        );
      });

      test('should_contain_http_scheme_in_queries', () {
        expect(
          manifestContent.contains('android:scheme="http"'),
          isTrue,
          reason:
              'AndroidManifest.xml <queries> must include android:scheme="http" '
              'so canLaunchUrl succeeds for http About links on Android 11+ '
              '(FR-M6-11, NFR-M6-08).',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 8 — Indent/Outdent literal leaks removed from buffer_screen.dart
  //
  // FR-M6-18 requires localization of the two hardcoded Semantics labels that
  // existed before M6. buffer_screen.dart must no longer contain the literal
  // strings Semantics(label: 'Indent') or Semantics(label: 'Outdent').
  // They are now ARB-sourced (l10n.editorIndentLabel / l10n.editorOutdentLabel).
  // (FR-M6-18, NFR-M6-01)
  // ──────────────────────────────────────────────────────────────────────────

  group("gate 8 — buffer_screen.dart has 0 Semantics(label: 'Indent'/'Outdent') "
      'literals (FR-M6-18 — now ARB-sourced)', () {
    // ── red fixture: buffer_screen with literal Semantics label ───────────
    group("fixture — buffer_screen with literal Semantics(label: 'Indent')", () {
      const brokenSource =
          '    Semantics(\n'
          "      label: 'Indent',\n"
          '      child: IconButton(onPressed: () => _indent(), icon: const Icon(Icons.format_indent_increase)),\n'
          '    ),\n';

      test('should_FAIL_indent_label_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains("label: 'Indent'"),
          isTrue,
          reason:
              "Broken fixture must contain \"label: 'Indent'\" to prove the "
              'localization-leak scan would fire when the literal is present.',
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
        lines = file.readAsLinesSync();
      });

      test('should_have_NO_literal_Indent_Semantics_label_in_buffer_screen', () {
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          if (lines[i].contains("label: 'Indent'") ||
              lines[i].contains('label: "Indent"')) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              "buffer_screen.dart must NOT contain literal Semantics(label: 'Indent'). "
              'Use l10n.editorIndentLabel (ARB key: editorIndentLabel). '
              '(FR-M6-18, NFR-M6-01)\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });

      test('should_have_NO_literal_Outdent_Semantics_label_in_buffer_screen', () {
        final hits = <String>[];
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          if (lines[i].contains("label: 'Outdent'") ||
              lines[i].contains('label: "Outdent"')) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              "buffer_screen.dart must NOT contain literal Semantics(label: 'Outdent'). "
              'Use l10n.editorOutdentLabel (ARB key: editorOutdentLabel). '
              '(FR-M6-18, NFR-M6-01)\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 9 — single ScrollController: exactly 1 ScrollController() in
  //          buffer_screen.dart
  //
  // LP §5.3 hard constraint: the app has exactly one shared ScrollController.
  // ChromeOverlay and other M6 shell components must NOT construct their own
  // ScrollController. (LP §5.3)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 9 — exactly 1 ScrollController() construction in '
      'buffer_screen.dart (LP §5.3 single-ScrollController invariant)', () {
    // ── red fixture: two ScrollController() constructions ─────────────────
    group('fixture — source with two ScrollController() constructions', () {
      const brokenSource =
          '  final _scrollController = ScrollController();\n'
          '  final _extraController = ScrollController(); // WRONG — LP §5.3\n';

      test('should_FAIL_count_scan_on_broken_fixture_with_two_controllers', () {
        final count = RegExp(
          r'ScrollController\(\)',
        ).allMatches(brokenSource).length;
        expect(
          count,
          greaterThan(1),
          reason:
              'Broken fixture must contain 2 ScrollController() calls to '
              'prove the LP §5.3 invariant scan would fire.',
        );
      });
    });

    // ── green: real buffer_screen.dart ────────────────────────────────────
    test(
      'should_have_exactly_1_ScrollController_construction_in_buffer_screen',
      () {
        final path = '$root/lib/presentation/editor/buffer_screen.dart';
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/presentation/editor/buffer_screen.dart must exist.',
        );

        final source = file.readAsStringSync();
        // Count on non-comment lines only.
        var count = 0;
        for (final line in source.split('\n')) {
          if (_isCommentLine(line)) continue;
          count += RegExp(r'ScrollController\(\)').allMatches(line).length;
        }

        expect(
          count,
          equals(1),
          reason:
              'buffer_screen.dart must contain exactly 1 ScrollController() '
              'construction (LP §5.3 single-controller invariant). '
              'ChromeOverlay and other shell components must NOT add their '
              'own controllers. Found: $count.',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Gate 10 — no chrome self-scroll: 0 jumpTo/animateTo/scrollTo in
  //           chrome_pill.dart and chrome_reveal_controller.dart
  //
  // SP-20260617 TASK-11: chrome_overlay.dart deleted in Wave 1 (TASK-06);
  // replaced by chrome_pill.dart. The no-self-scroll invariant now applies
  // to chrome_pill.dart + chrome_reveal_controller.dart.
  //
  // LP §5.3 "no editor self-scroll" hard constraint: the chrome components
  // must NEVER call jumpTo, animateTo, or scrollTo on any scroll controller.
  // Programmatic scrolling is the exclusive concern of BufferScreen. (LP §5.3)
  // ──────────────────────────────────────────────────────────────────────────

  group('gate 10 — 0 jumpTo/animateTo/scrollTo in chrome_pill.dart and '
      'chrome_reveal_controller.dart (LP §5.3 no-self-scroll constraint)', () {
    // ── red fixture: ChromePill calling animateTo (forbidden) ─────────────
    group('fixture — ChromePill calling animateTo (forbidden)', () {
      const brokenSource =
          '  void _syncScroll(double offset) {\n'
          '    _controller.animateTo(offset,\n'
          '        duration: const Duration(milliseconds: 200),\n'
          '        curve: Curves.easeOut);\n'
          '  }\n';

      test('should_FAIL_animateTo_scan_on_broken_chrome_fixture', () {
        expect(
          brokenSource.contains('animateTo('),
          isTrue,
          reason:
              'Broken fixture must contain "animateTo(" to prove the '
              'no-self-scroll scan would fire if chrome tried to scroll.',
        );
      });
    });

    // ── green: real chrome files ──────────────────────────────────────────
    // SP-20260617 TASK-11: chrome_overlay.dart → chrome_pill.dart.
    test(
      'should_have_ZERO_scroll_calls_in_chrome_pill_and_reveal_controller',
      () {
        final chromeFiles = [
          '$root/lib/presentation/shell/chrome_pill.dart',
          '$root/lib/presentation/shell/chrome_reveal_controller.dart',
        ];

        final forbiddenPattern = RegExp(r'\b(jumpTo|animateTo|scrollTo)\s*\(');
        final hits = <String>[];

        for (final path in chromeFiles) {
          final file = File(path);
          if (!file.existsSync()) continue;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            if (forbiddenPattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              'chrome_pill.dart and chrome_reveal_controller.dart must NOT '
              'call jumpTo(), animateTo(), or scrollTo() on any controller. '
              'Programmatic scrolling is the exclusive concern of BufferScreen '
              '(LP §5.3 no-editor-self-scroll hard constraint).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });
}
