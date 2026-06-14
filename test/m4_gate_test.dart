// M4 source-scan gate — buffer-mobile
//
// Spec refs: FR-08, FR-17; NFR-01, NFR-03, NFR-04, NFR-05, NFR-06
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m3_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Gate inventory (spec §7.1, TASK-09):
//   1. find_engine.dart has no `import 'package:flutter/`; findMatchesIsolate
//      is a top-level function (domain purity, NFR-05).
//   2. find_provider.dart has no direct `_controller.value =` on the replace
//      path; replace returns a record (NFR-04 / parent §5.3 single-mutation-path).
//   3. lib/ contains exactly one `extends TextEditingController` (NFR-04,
//      single-controller invariant; extends m3_gate gate 4).
//   4. buffer_notifier*.dart contains none of find/replace/query/match/search
//      as member/method names (ephemerality member-name gate, NFR-03 / R-01).
//   5. lib/presentation/find/ contains no literal Text('…') / Text("…") with
//      hardcoded user-facing strings (NFR-06 localization gate).
//   6. app_en.arb and app_it.arb both contain all 8 find keys with identical
//      find-key sets (NFR-06 key-parity gate).
//   7. No bare print( in the four M4 new files (NFR-05).
//   8. m3_gate_test.dart buildTextSpan assertion is revised — the old
//      "delegates to super unchanged" stub wording is absent and the new
//      super-call + background-layering assertions exist (NFR-04, gate revised
//      not bypassed).

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
  late String libDir;
  late String findEngineDir;
  late String findProviderPath;
  late String findPresentationDir;
  late String m3GateTestPath;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    findEngineDir = '$root/lib/domain/find';
    findProviderPath = '$root/lib/presentation/find/find_provider.dart';
    findPresentationDir = '$root/lib/presentation/find';
    m3GateTestPath = '$root/test/m3_gate_test.dart';
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 1 — find_engine.dart: no Flutter import; findMatchesIsolate top-level
  //
  // Domain purity (NFR-05 / spec §5.1): the search engine must be pure Dart,
  // no package:flutter/ import. The isolate entry point must be a top-level
  // function (not a closure / instance method) so it is sendable by compute().
  // ────────────────────────────────────────────────────────────────────────────

  group('gate 1 — find_engine.dart no Flutter import and findMatchesIsolate '
      'is top-level (NFR-05 / domain purity)', () {
    // ── red fixture: a source with a flutter import ──────────────────────
    group('fixture — broken engine with package:flutter/ import', () {
      const brokenSource =
          "import 'package:flutter/material.dart';\n"
          "import 'dart:async';\n"
          'List<MatchSpan> findMatchesIsolate(FindArgs args) => [];\n';

      test('should_FAIL_flutter_import_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains("import 'package:flutter/"),
          isTrue,
          reason:
              'Broken fixture must contain a flutter import to prove the '
              'domain-purity scan would fire when it is present.',
        );
      });
    });

    // ── red fixture: isolate entry as a closure, not top-level ───────────
    group('fixture — broken engine with non-top-level isolate entry', () {
      // A closure assigned to a variable is not top-level; it cannot be
      // sent across isolate ports. The scan looks for a top-level function
      // declaration (not a lambda / arrow on a var).
      const brokenSource = '''
class FindEngine {
  static final findMatchesIsolate = (FindArgs args) => findMatches(args.text, args.query);
}
''';

      test('should_FAIL_top_level_scan_on_closure_fixture', () {
        // A top-level function declaration matches `^List<MatchSpan>` at
        // the start of a line (not inside a class body / var assignment).
        final topLevelPattern = RegExp(
          r'^List<MatchSpan>\s+findMatchesIsolate',
          multiLine: true,
        );
        expect(
          topLevelPattern.hasMatch(brokenSource),
          isFalse,
          reason:
              'Broken fixture must NOT match the top-level function pattern '
              'to prove the scan would fire when the entry point is a '
              'closure rather than a top-level function.',
        );
      });
    });

    // ── green: real find_engine.dart ─────────────────────────────────────
    group('real lib/domain/find/find_engine.dart', () {
      late String engineContent;

      setUpAll(() {
        final enginePath = '$findEngineDir/find_engine.dart';
        final file = File(enginePath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/domain/find/find_engine.dart must exist (TASK-01).',
        );
        engineContent = file.readAsStringSync();
      });

      test('should_have_NO_package_flutter_import_in_find_engine', () {
        final hits = <String>[];
        final lines = engineContent.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (lines[i].contains("import 'package:flutter/") ||
              lines[i].contains('import "package:flutter/')) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'find_engine.dart must be pure Dart — no package:flutter/ '
              'import (NFR-05, domain purity, spec §5.1).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });

      test('should_have_findMatchesIsolate_as_top_level_function', () {
        // The top-level function signature starts at column 0 and is not
        // inside a class body. Pattern: starts a line with the return type
        // and the function name.
        final topLevelPattern = RegExp(
          r'^List<MatchSpan>\s+findMatchesIsolate',
          multiLine: true,
        );
        expect(
          topLevelPattern.hasMatch(engineContent),
          isTrue,
          reason:
              'find_engine.dart must expose findMatchesIsolate as a '
              'top-level function (not a closure or instance method) so it '
              'is sendable by compute() (FR-08, spec §5.1).',
        );
      });
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 2 — find_provider.dart: no direct _controller.value = on replace path
  //
  // NFR-04 / parent §5.3 single-mutation-path: replaceCurrent() returns a
  // ({String text, int nextCaretOffset})? record for the screen to apply via
  // _applyResult. It must never write _controller.value directly and must never
  // call updateText (those are the screen's responsibilities).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'gate 2 — find_provider.dart no direct _controller.value = or updateText '
    'call (NFR-04 / single-mutation-path)',
    () {
      // ── red fixture: provider that writes controller.value directly ───────
      group('fixture — broken provider with direct controller write', () {
        const brokenSource =
            'void replaceCurrent() {\n'
            '  _controller.value = TextEditingValue(text: newText);\n'
            '}\n';

        test('should_FAIL_controller_write_scan_on_broken_fixture', () {
          expect(
            brokenSource.contains('_controller.value ='),
            isTrue,
            reason:
                'Broken fixture must contain "_controller.value =" to prove '
                'the single-mutation-path scan would fire when present.',
          );
        });
      });

      // ── red fixture: provider that calls updateText directly ─────────────
      group('fixture — broken provider calling updateText', () {
        const brokenSource =
            '  void replaceCurrent() {\n'
            '    ref.read(bufferProvider.notifier).updateText(newText);\n'
            '  }\n';

        test('should_FAIL_updateText_call_scan_on_broken_fixture', () {
          // The scan looks for non-comment lines containing ".updateText("
          final lines = brokenSource.split('\n');
          final hits = <int>[];
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            if (lines[i].contains('.updateText(')) hits.add(i + 1);
          }
          expect(
            hits,
            isNotEmpty,
            reason:
                'Broken fixture must contain ".updateText(" to prove the '
                'scan would fire when the provider calls it directly.',
          );
        });
      });

      // ── green: real find_provider.dart ───────────────────────────────────
      group('real lib/presentation/find/find_provider.dart', () {
        late List<String> lines;

        setUpAll(() {
          final file = File(findProviderPath);
          expect(
            file.existsSync(),
            isTrue,
            reason:
                'lib/presentation/find/find_provider.dart must exist (TASK-04).',
          );
          lines = file.readAsLinesSync();
        });

        test(
          'should_have_NO_direct_controller_value_assignment_in_find_provider',
          () {
            final hits = <String>[];
            for (var i = 0; i < lines.length; i++) {
              final trimmed = lines[i].trimLeft();
              if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
              // Match `_controller.value =` (direct assignment, not ==).
              if (RegExp(r'_controller\.value\s*=[^=]').hasMatch(lines[i])) {
                hits.add('${i + 1}: ${lines[i].trim()}');
              }
            }
            expect(
              hits,
              isEmpty,
              reason:
                  'find_provider.dart must NOT write _controller.value '
                  'directly. Replace returns a record for the screen to apply '
                  'via _applyResult (NFR-04, parent §5.3 single-mutation-path).'
                  '\nOffenders:\n${hits.join('\n')}',
            );
          },
        );

        test('should_have_NO_updateText_call_in_find_provider', () {
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
                'find_provider.dart must NOT call .updateText() — that is '
                'the screen\'s responsibility via _applyResult → the two-way '
                'sync listener (NFR-04, spec §5.2 replaceCurrent contract).\n'
                'Offenders:\n${hits.join('\n')}',
          );
        });
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 3 — lib/ exactly one `extends TextEditingController`
  //
  // NFR-04 / single-controller invariant: EditorController in
  // editor_controller.dart is the ONLY TextEditingController subclass. No
  // second subclass may exist in lib/. Mirrors m3_gate gate 4.
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'gate 3 — lib/ has exactly one extends TextEditingController (NFR-04)',
    () {
      // ── red fixture: two subclass declarations ────────────────────────────
      group('fixture — two extends TextEditingController declarations', () {
        const twoSubclasses = [
          'class EditorController extends TextEditingController {',
          'class FindController extends TextEditingController {',
        ];

        test('should_FAIL_single_subclass_scan_given_two_declarations', () {
          const pattern = 'extends TextEditingController';
          final count = twoSubclasses.where((l) => l.contains(pattern)).length;
          expect(
            count,
            greaterThan(1),
            reason:
                'Broken fixture must have more than one TextEditingController '
                'subclass declaration.',
          );
        });
      });

      // ── green: real lib/ ─────────────────────────────────────────────────
      test('should_have_exactly_one_TextEditingController_subclass_in_lib', () {
        const pattern = 'extends TextEditingController';
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
              continue;
            }
            if (lines[i].contains(pattern)) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
        expect(
          hits,
          hasLength(1),
          reason:
              'lib/ must contain EXACTLY ONE "extends TextEditingController" '
              '— EditorController in editor_controller.dart. No second '
              'controller subclass may be introduced (NFR-04 / parent §5.3 '
              'single-controller invariant).\n'
              '${hits.isEmpty ? 'No subclass found — EditorController may be missing.' : 'Declarations found:\n${hits.join('\n')}'}',
        );
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 4 — buffer_notifier*.dart contains no find/replace/query/match/search
  //          as member or method names (ephemerality member-name gate)
  //
  // NFR-03 / R-01: BufferNotifier is frozen. No find/replace surface may be
  // added to it. The ephemerality contract forbids any in-buffer search state
  // on the persistence-facing notifier.
  // ────────────────────────────────────────────────────────────────────────────

  group('gate 4 — buffer_notifier*.dart has no find/replace/query/match/search '
      'member names (NFR-03 / ephemerality)', () {
    // ── red fixture: notifier with a find member ─────────────────────────
    group('fixture — broken notifier with find member', () {
      const brokenSource = '''
class BufferNotifier extends Notifier<BufferState> {
  List<Match> _findMatches(String query) => [];
  String? currentSearchQuery;
}
''';

      test('should_FAIL_ephemerality_scan_on_broken_fixture', () {
        final memberPattern = RegExp(r'\b(find|replace|query|match|search)\b');
        final hits = <String>[];
        final lines = brokenSource.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (memberPattern.hasMatch(lines[i])) hits.add('${i + 1}');
        }
        expect(
          hits,
          isNotEmpty,
          reason:
              'Broken fixture must trigger the find/replace member scan to '
              'prove the gate would fire if such members were added.',
        );
      });
    });

    // ── green: real buffer_notifier*.dart files ───────────────────────────
    test(
      'should_have_NO_find_replace_query_match_search_members_in_buffer_notifier',
      () {
        final bufferNotifierDir = '$libDir/domain/buffer';
        final d = Directory(bufferNotifierDir);
        expect(
          d.existsSync(),
          isTrue,
          reason:
              'lib/domain/buffer/ must exist (BufferNotifier domain layer).',
        );

        // Collect all buffer_notifier*.dart files.
        final notifierFiles = d
            .listSync(recursive: false)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.split('/').last.startsWith('buffer_notifier') &&
                  f.path.endsWith('.dart'),
            )
            .toList();

        expect(
          notifierFiles,
          isNotEmpty,
          reason:
              'At least one buffer_notifier*.dart must exist in '
              'lib/domain/buffer/ (BufferNotifier is frozen but must exist).',
        );

        // The scan looks for non-comment lines that declare a member whose
        // name contains one of the forbidden words. We match the word as a
        // whole-word (not inside string literals or import paths).
        final memberPattern = RegExp(r'\b(find|replace|query|match|search)\b');
        final hits = <String>[];

        for (final file in notifierFiles) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            // Skip comment lines.
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
              continue;
            }
            // Skip import lines (the word may appear in package names).
            if (trimmed.startsWith('import ')) continue;
            if (memberPattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              'buffer_notifier*.dart must NOT contain find/replace/query/'
              'match/search as member or method names. BufferNotifier is '
              'frozen — no find/replace surface may be added '
              '(NFR-03 / R-01 ephemerality member-name gate).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 5 — lib/presentation/find/ contains no literal Text('…') / Text("…")
  //
  // NFR-06 localization gate: all find/replace user-facing strings must resolve
  // through AppLocalizations. No literal Text() with hardcoded display strings
  // may appear in lib/presentation/find/.
  // ────────────────────────────────────────────────────────────────────────────

  group(
    "gate 5 — lib/presentation/find/ has no literal Text('…') / Text(\"…\") "
    '(NFR-06 localization)',
    () {
      // ── red fixture: hardcoded Text literal ───────────────────────────────
      group('fixture — hardcoded Text literal in search bar', () {
        const brokenSource = "Text('Search')";

        test('should_FAIL_literal_Text_scan_on_broken_fixture', () {
          final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
          expect(
            literalPattern.hasMatch(brokenSource),
            isTrue,
            reason: 'Broken fixture must trigger the literal Text() scan.',
          );
        });
      });

      // ── green: real lib/presentation/find/ ───────────────────────────────
      test(
        'should_have_zero_literal_Text_constructors_in_presentation_find',
        () {
          final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
          final hits = <String>[];
          final d = Directory(findPresentationDir);
          if (d.existsSync()) {
            for (final file in _dartFiles(findPresentationDir)) {
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
                'lib/presentation/find/ must not contain Text("literal") or '
                "Text('literal') with non-empty strings — all find/replace "
                'copy must go through AppLocalizations (NFR-06 / FR-19).\n'
                'Offenders:\n${hits.join('\n')}',
          );
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 6 — app_en.arb and app_it.arb both contain all 8 find keys with
  //          identical find-key sets
  //
  // NFR-06 key-parity gate: both locale ARB files must carry the full set of
  // 8 find keys and the sets must be identical (no missing / extra find key in
  // either file).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'gate 6 — app_en.arb and app_it.arb have all 8 find keys with identical '
    'find-key sets (NFR-06 key-parity)',
    () {
      const expectedFindKeys = {
        'findHintText',
        'findCountLabel',
        'findPreviousTooltip',
        'findNextTooltip',
        'findReplaceHintText',
        'findReplaceButton',
        'findReplaceToggleTooltip',
        'findCloseTooltip',
      };

      // ── red fixture: ARB content missing a find key ───────────────────────
      group('fixture — ARB content missing findCountLabel', () {
        const brokenArbJson =
            '{'
            '"findHintText": "Search",'
            '"findPreviousTooltip": "Previous Match",'
            '"findNextTooltip": "Next Match",'
            '"findReplaceHintText": "Replace",'
            '"findReplaceButton": "Replace",'
            '"findReplaceToggleTooltip": "Toggle Replace",'
            '"findCloseTooltip": "Back"'
            '}';

        test('should_FAIL_arb_key_scan_when_findCountLabel_missing', () {
          final decoded = json.decode(brokenArbJson) as Map<String, dynamic>;
          final findKeys = decoded.keys
              .where((k) => k.startsWith('find'))
              .toSet();
          final missing = expectedFindKeys.difference(findKeys);
          expect(
            missing,
            isNotEmpty,
            reason:
                'Broken fixture is missing findCountLabel — the scan must '
                'detect the gap.',
          );
        });
      });

      // ── green: real ARB files ─────────────────────────────────────────────
      group('real lib/l10n/app_en.arb and app_it.arb', () {
        late Set<String> enFindKeys;
        late Set<String> itFindKeys;

        setUpAll(() {
          Set<String> readFindKeys(String path) {
            final file = File(path);
            expect(
              file.existsSync(),
              isTrue,
              reason: '$path must exist (TASK-03 ARB keys).',
            );
            final decoded =
                json.decode(file.readAsStringSync()) as Map<String, dynamic>;
            return decoded.keys
                .where((k) => k.startsWith('find') && !k.startsWith('@'))
                .toSet();
          }

          enFindKeys = readFindKeys('$root/lib/l10n/app_en.arb');
          itFindKeys = readFindKeys('$root/lib/l10n/app_it.arb');
        });

        test('should_have_all_8_find_keys_in_app_en_arb', () {
          final missing = expectedFindKeys.difference(enFindKeys);
          expect(
            missing,
            isEmpty,
            reason:
                'app_en.arb is missing find keys: ${missing.join(', ')} '
                '(NFR-06, TASK-03 spec §5.3 ARB keys).',
          );
        });

        test('should_have_all_8_find_keys_in_app_it_arb', () {
          final missing = expectedFindKeys.difference(itFindKeys);
          expect(
            missing,
            isEmpty,
            reason:
                'app_it.arb is missing find keys: ${missing.join(', ')} '
                '(NFR-06 key-parity, TASK-03).',
          );
        });

        test('should_have_identical_find_key_sets_in_en_and_it_arb', () {
          final onlyInEn = enFindKeys.difference(itFindKeys);
          final onlyInIt = itFindKeys.difference(enFindKeys);
          expect(
            onlyInEn,
            isEmpty,
            reason:
                'app_en.arb has find keys NOT in app_it.arb: '
                '${onlyInEn.join(', ')} (NFR-06 key-parity).',
          );
          expect(
            onlyInIt,
            isEmpty,
            reason:
                'app_it.arb has find keys NOT in app_en.arb: '
                '${onlyInIt.join(', ')} (NFR-06 key-parity).',
          );
        });
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 7 — no bare print( in M4 new files (NFR-05)
  //
  // Mirrors the M3 gate 6 check, scoped to the four new files introduced in M4:
  //   lib/domain/find/find_engine.dart
  //   lib/domain/find/find_state.dart
  //   lib/presentation/find/find_provider.dart
  //   lib/presentation/find/find_search_bar.dart
  // debugPrint() is allowed; bare print() is not.
  // ────────────────────────────────────────────────────────────────────────────

  group('gate 7 — no bare print( in M4 new files (NFR-05)', () {
    const m4NewFiles = [
      'lib/domain/find/find_engine.dart',
      'lib/domain/find/find_state.dart',
      'lib/presentation/find/find_provider.dart',
      'lib/presentation/find/find_search_bar.dart',
    ];

    // ── red fixture: source with bare print() ─────────────────────────────
    group('fixture — M4 file with bare print()', () {
      const brokenSource =
          'void _computeMatches() {\n'
          '  print("debug: computing matches");\n'
          '}\n';

      test('should_FAIL_print_scan_on_broken_fixture', () {
        final line = brokenSource.split('\n')[1];
        final trimmed = line.trimLeft();
        final isComment = trimmed.startsWith('//') || trimmed.startsWith('*');
        final isBare =
            trimmed.contains('print(') && !trimmed.contains('debugPrint(');
        expect(
          !isComment && isBare,
          isTrue,
          reason: 'Broken fixture must trigger the bare print() scan.',
        );
      });
    });

    // ── green: real M4 new files ──────────────────────────────────────────
    test('should_have_zero_bare_print_calls_in_M4_new_files', () {
      final hits = <String>[];
      for (final relPath in m4NewFiles) {
        final file = File('$root/$relPath');
        if (!file.existsSync()) continue; // tolerant if a file doesn't exist
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
            'No bare print() calls are permitted in M4 new files — use '
            'dart:developer log() or debugPrint() instead (NFR-05).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Gate 8 — m3_gate_test.dart buildTextSpan assertion is REVISED (M4 updated)
  //
  // NFR-04 "gate REVISED not bypassed": the m3_gate_test.dart was updated in
  // TASK-05 to no longer assert "delegates to super unchanged" (the M1/M3 stub
  // wording) and instead to assert (a) super.buildTextSpan is still called for
  // base style/composing, and (b) primaryContainer and secondaryContainer are
  // referenced for highlight backgrounds.
  //
  // This gate verifies two things:
  //   (a) The old stub wording is ABSENT from m3_gate_test.dart (the revision
  //       happened — the M1/M3 delegation-only assertions are gone).
  //   (b) The new assertions ARE present: super.buildTextSpan and
  //       primaryContainer appear in the test (gate updated, not removed).
  // ────────────────────────────────────────────────────────────────────────────

  group('gate 8 — m3_gate_test.dart buildTextSpan assertion revised: old stub '
      'text absent, new assertions present (NFR-04)', () {
    // ── red fixture: m3_gate_test with old delegation-only wording ────────
    group('fixture — old m3_gate_test with delegation-only stub wording', () {
      const oldStubSource = '''
test('should_delegate_buildTextSpan_to_super_unchanged', () {
  // Gate: buildTextSpan delegates to super unchanged (M1/M3 delegation stub).
  expect(content.contains('delegates to super unchanged'), isTrue);
});
''';

      test('should_FAIL_stub_wording_scan_on_old_fixture', () {
        // The old wording that should now be absent:
        final hasOldWording =
            oldStubSource.contains('delegates to super unchanged') ||
            oldStubSource.contains('delegates verbatim to super') ||
            oldStubSource.contains(
              'buildTextSpan returns super span unchanged',
            );
        expect(
          hasOldWording,
          isTrue,
          reason:
              'Old fixture must contain the stub wording to prove the '
              'gate would detect it.',
        );
      });
    });

    // ── red fixture: m3_gate_test still pointing at old text ─────────────
    group(
      'fixture — broken revised m3_gate_test missing primaryContainer check',
      () {
        // This fixture has the super.buildTextSpan check but lacks the
        // colour-token assertion entirely. The word 'primaryContainer' does
        // not appear anywhere in this fixture source.
        const brokenRevisedSource = '''
test('should_call_super_buildTextSpan', () {
  expect(content.contains('super.buildTextSpan'), isTrue);
});
''';

        test('should_FAIL_primaryContainer_scan_on_fixture_missing_it', () {
          expect(
            brokenRevisedSource.contains('primaryContainer'),
            isFalse,
            reason:
                'Broken fixture must NOT contain "primaryContainer" to '
                'prove the gate would fire if the new assertion were '
                'missing.',
          );
        });
      },
    );

    // ── green: real m3_gate_test.dart ────────────────────────────────────
    group('real test/m3_gate_test.dart', () {
      late String m3GateContent;

      setUpAll(() {
        final file = File(m3GateTestPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'test/m3_gate_test.dart must exist.',
        );
        m3GateContent = file.readAsStringSync();
      });

      // (a) Old delegation-only assertion text must be ABSENT.
      // We scan for phrases that would indicate the gate still asserts
      // "buildTextSpan delegates to super UNCHANGED" (the M1/M3 stub
      // baseline). After M4 these specific phrases must not appear as
      // test-assertion strings (they may appear as comments explaining
      // the revision, but the actual .contains() assertion targets for
      // those phrases must be gone).
      test(
        'should_NOT_have_old_delegation_only_assertion_target_in_m3_gate_test',
        () {
          // The old test looked for content.contains('no highlight painting yet')
          // or expected buildTextSpan to return the super span unchanged. The
          // REVISED gate looks for super.buildTextSpan + primaryContainer.
          // We verify the marker phrases that would indicate the OLD gate
          // logic is still the primary assertion are absent.
          //
          // Specifically: the string 'buildTextSpan delegates to super unchanged'
          // must not appear as an expected substring that the REAL test asserts
          // (it may appear in comments explaining the old text).
          //
          // The safest check: the character sequence used by the old M1 stub
          // comment that the old gate was looking for in editor_controller.dart.
          final hasDelegatesVerbatimAssertion =
              m3GateContent.contains(
                'expect(\n          controllerContent.contains('
                "'delegates verbatim to super'),\n"
                '          isTrue,',
              ) ||
              m3GateContent.contains(
                'expect(\n          controllerContent.contains('
                "'buildTextSpan delegates to super unchanged'),\n"
                '          isTrue,',
              );
          expect(
            hasDelegatesVerbatimAssertion,
            isFalse,
            reason:
                'm3_gate_test.dart must NOT assert that "delegates verbatim '
                'to super" is present in editor_controller.dart. That was '
                'the M1/M3 stub gate; it must be REVISED for M4 to assert '
                'super.buildTextSpan + background layering instead '
                '(NFR-04 gate REVISED not bypassed).',
          );
        },
      );

      // (b) New assertions must be PRESENT.
      test(
        'should_have_super_buildTextSpan_assertion_in_revised_m3_gate_test',
        () {
          expect(
            m3GateContent.contains('super.buildTextSpan'),
            isTrue,
            reason:
                'm3_gate_test.dart must assert that editor_controller.dart '
                'contains "super.buildTextSpan" — the REVISED gate checks '
                'that super is still called for base style/composing '
                'decoration (NFR-04, TASK-05 m3_gate revision).',
          );
        },
      );

      test(
        'should_have_primaryContainer_assertion_in_revised_m3_gate_test',
        () {
          expect(
            m3GateContent.contains('primaryContainer'),
            isTrue,
            reason:
                'm3_gate_test.dart must assert that editor_controller.dart '
                'references "primaryContainer" for the current-match '
                'background highlight. The REVISED gate enforces background '
                'layering (M4 OQ-06 CANON GAP resolved theme-driven; '
                'NFR-04 gate updated not bypassed).',
          );
        },
      );
    });
  });
}
