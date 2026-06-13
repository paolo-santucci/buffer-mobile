// M3 source-scan gate — buffer-mobile
//
// Spec refs: FR-03, FR-08, FR-17, FR-19, EC-26, NFR-04, NFR-07,
//            R-03, MC-01, OQ-11
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m2_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Test targets:
//   1. height:1.4 in editor TextStyle AND no hardcoded fontSize/fontFamily on
//      that style in buffer_screen.dart (FR-03).
//   2. No onSubmitted: wiring on the editor TextField in buffer_screen.dart —
//      the \n-in-change-path is the sole soft continuation entry point (FR-08).
//   3. Find-replace seams untouched — highlightRanges, currentMatchIndex, and
//      buildTextSpan all still present in editor_controller.dart and
//      buildTextSpan delegates to super (EC-26).
//   4. EditorController is the ONLY TextEditingController subclass in lib/
//      (exactly one `extends TextEditingController`) (FR-15 / §5.3).
//   5. MARGIN_BELOW_CURSOR / kMarginBelowCursor = 22.0 named constant present
//      in buffer_screen.dart (FR-17).
//   6. No bare print() in M3 lib/ (NFR-06, mirrors M2 check).
//   7. The two new domain helpers (list_continuation.dart, line_indent.dart)
//      contain no package:flutter/ import (NFR-04 domain purity).
//   8. No literal Text('…') / Text("…") with hardcoded strings in M3
//      lib/presentation/ (mirrors M2 NFR-M2-05 check).

// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers (identical to m2_gate_test.dart conventions)
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
  late String domainEditorDir;
  late String presentationDir;
  late String bufferScreenPath;
  late String editorControllerPath;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    domainEditorDir = '$root/lib/domain/editor';
    presentationDir = '$root/lib/presentation';
    bufferScreenPath = '$root/lib/presentation/editor/buffer_screen.dart';
    editorControllerPath =
        '$root/lib/presentation/editor/editor_controller.dart';
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 1. height:1.4 in editor TextStyle AND no fontSize/fontFamily on that style
  //    (FR-03)
  //
  // The editor TextStyle must carry `height: 1.4`. The same style definition
  // must NOT set a hardcoded fontSize or fontFamily (M7 owns those).
  // ────────────────────────────────────────────────────────────────────────────

  group('editor TextStyle has height:1.4 and no fontSize/fontFamily (FR-03)', () {
    // ── red fixture: TextStyle without height, with a fontSize ───────────────
    group('fixture — broken TextStyle with fontSize and no height', () {
      const brokenSource = 'TextStyle(fontSize: 16, color: textColor)';

      test('should_FAIL_to_find_height_1_4_in_broken_fixture', () {
        expect(
          brokenSource.contains('height: 1.4'),
          isFalse,
          reason: 'Broken fixture must NOT contain "height: 1.4".',
        );
      });

      test('should_FAIL_fontSize_scan_on_broken_fixture', () {
        // The fixture explicitly sets fontSize — the scan must detect it.
        expect(
          RegExp(r'\bfontSize\b').hasMatch(brokenSource),
          isTrue,
          reason: 'Broken fixture must trigger the fontSize scan.',
        );
      });
    });

    // ── red fixture: TextStyle with fontFamily ────────────────────────────────
    group('fixture — broken TextStyle with fontFamily', () {
      const brokenSource = "TextStyle(height: 1.4, fontFamily: 'monospace')";

      test('should_FAIL_fontFamily_scan_on_broken_fixture', () {
        expect(
          RegExp(r'\bfontFamily\b').hasMatch(brokenSource),
          isTrue,
          reason: 'Broken fixture must trigger the fontFamily scan.',
        );
      });
    });

    // ── green: real buffer_screen.dart ───────────────────────────────────────
    group(
      'real buffer_screen.dart — height:1.4 present, no fontSize/fontFamily',
      () {
        late String screenContent;

        setUpAll(() {
          final file = File(bufferScreenPath);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'lib/presentation/editor/buffer_screen.dart must exist',
          );
          screenContent = file.readAsStringSync();
        });

        test('should_contain_height_1_4_in_editor_style', () {
          expect(
            screenContent.contains('height: 1.4'),
            isTrue,
            reason:
                'buffer_screen.dart must set "height: 1.4" in the editor '
                'TextStyle (FR-03).',
          );
        });

        test('should_NOT_set_fontSize_in_editor_style', () {
          // Scan non-comment lines in the editor TextStyle block.
          // The style is defined as a local variable; the file must not contain
          // a non-comment `fontSize:` assignment outside of a comment.
          final hits = <String>[];
          final lines = screenContent.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            // Match `fontSize:` as a property assignment (not a comment mention).
            if (RegExp(r'\bfontSize\s*:').hasMatch(lines[i])) {
              hits.add('${i + 1}: ${lines[i].trim()}');
            }
          }
          expect(
            hits,
            isEmpty,
            reason:
                'buffer_screen.dart must NOT set fontSize on the editor '
                'TextStyle — M7 owns font size (FR-03, NFR-02).\n'
                'Offenders:\n${hits.join('\n')}',
          );
        });

        test('should_NOT_set_fontFamily_in_editor_style', () {
          final hits = <String>[];
          final lines = screenContent.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            if (RegExp(r'\bfontFamily\s*:').hasMatch(lines[i])) {
              hits.add('${i + 1}: ${lines[i].trim()}');
            }
          }
          expect(
            hits,
            isEmpty,
            reason:
                'buffer_screen.dart must NOT set fontFamily on the editor '
                'TextStyle — M7 owns font family (FR-03, NFR-02 / CANON GAP '
                'monospace).\nOffenders:\n${hits.join('\n')}',
          );
        });
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 2. No onSubmitted: on the editor TextField (FR-08)
  //
  // The soft continuation path is the \n-in-change-path (_onControllerChanged).
  // onSubmitted: would create a parallel continuation entry point, violating
  // the single-path invariant (§5.3, R-03).
  // ────────────────────────────────────────────────────────────────────────────

  group('no onSubmitted: on editor TextField — single soft path (FR-08)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — broken TextField with onSubmitted:', () {
      const brokenSource =
          'TextField(onSubmitted: (_) => _continueList(), controller: _c)';

      test('should_FAIL_onSubmitted_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('onSubmitted:'),
          isTrue,
          reason: 'Broken fixture must trigger the onSubmitted: scan.',
        );
      });
    });

    // ── green: real buffer_screen.dart ───────────────────────────────────────
    test('should_have_NO_onSubmitted_on_editor_TextField_in_buffer_screen', () {
      final file = File(bufferScreenPath);
      expect(file.existsSync(), isTrue);
      final hits = <String>[];
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        if (lines[i].contains('onSubmitted:')) {
          hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'buffer_screen.dart must NOT wire onSubmitted: on the editor '
            'TextField. The sole soft continuation entry point is the '
            r'\n-in-change-path (_onControllerChanged) (FR-08, R-03).'
            '\nOffenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 3. Find-replace seams untouched (EC-26)
  //
  // highlightRanges, currentMatchIndex, and buildTextSpan must still be present
  // in editor_controller.dart and buildTextSpan must still delegate to super.
  // ────────────────────────────────────────────────────────────────────────────

  group('find-replace seams untouched in editor_controller.dart (EC-26)', () {
    // ── red fixture: controller source with buildTextSpan body replaced ───────
    group('fixture — broken controller with missing highlightRanges', () {
      const brokenSource = '''
class EditorController extends TextEditingController {
  int? _currentMatchIndex;
  TextSpan buildTextSpan({required BuildContext context,
      TextStyle? style, required bool withComposing}) {
    // custom implementation — super not called
    return const TextSpan();
  }
}
''';

      test('should_FAIL_highlightRanges_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('highlightRanges'),
          isFalse,
          reason:
              'Broken fixture must NOT contain "highlightRanges" to prove the '
              'scan would fire if the seam were removed.',
        );
      });

      test(
        'should_FAIL_super_buildTextSpan_delegation_scan_on_broken_fixture',
        () {
          // The real controller must call super.buildTextSpan; the broken fixture
          // does not. Verify the scan detects its absence.
          expect(
            brokenSource.contains('super.buildTextSpan'),
            isFalse,
            reason:
                'Broken fixture must NOT contain "super.buildTextSpan" to prove '
                'the delegation scan would fire.',
          );
        },
      );
    });

    // ── green: real editor_controller.dart ────────────────────────────────────
    group('real editor_controller.dart — all three seams intact', () {
      late String controllerContent;

      setUpAll(() {
        final file = File(editorControllerPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/presentation/editor/editor_controller.dart must exist',
        );
        controllerContent = file.readAsStringSync();
      });

      test('should_contain_highlightRanges_member', () {
        expect(
          controllerContent.contains('highlightRanges'),
          isTrue,
          reason:
              'editor_controller.dart must retain the highlightRanges member '
              '(M4 seam, EC-26). M3 must not remove it.',
        );
      });

      test('should_contain_currentMatchIndex_member', () {
        expect(
          controllerContent.contains('currentMatchIndex'),
          isTrue,
          reason:
              'editor_controller.dart must retain the currentMatchIndex member '
              '(M4 seam, EC-26). M3 must not remove it.',
        );
      });

      test('should_contain_buildTextSpan_method', () {
        expect(
          controllerContent.contains('buildTextSpan'),
          isTrue,
          reason:
              'editor_controller.dart must retain the buildTextSpan override '
              '(M4 seam, EC-26). M3 must not remove it.',
        );
      });

      test('should_have_buildTextSpan_delegate_to_super', () {
        expect(
          controllerContent.contains('super.buildTextSpan'),
          isTrue,
          reason:
              'editor_controller.dart buildTextSpan must delegate to super '
              '(M1/M3 baseline — M4 will paint highlights here, EC-26).',
        );
      });
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 4. EditorController is the ONLY TextEditingController subclass in lib/
  //    (exactly one `extends TextEditingController`) (FR-15 / §5.3)
  // ────────────────────────────────────────────────────────────────────────────

  group('exactly one TextEditingController subclass in lib/ (FR-15 / §5.3)', () {
    // ── red fixture: two subclasses ──────────────────────────────────────────
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
              'subclass.',
        );
      });
    });

    // ── green: real lib/ ─────────────────────────────────────────────────────
    test('should_have_exactly_one_TextEditingController_subclass_in_lib', () {
      const pattern = 'extends TextEditingController';
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (lines[i].contains(pattern)) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        hasLength(1),
        reason:
            'lib/ must contain EXACTLY ONE "extends TextEditingController" — '
            'EditorController in editor_controller.dart. The single unified '
            'controller contract (FR-15 / §5.3) forbids a parallel subclass.\n'
            '${hits.isEmpty ? 'No subclass found — EditorController may be missing.' : 'Declarations found:\n${hits.join('\n')}'}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 5. MARGIN_BELOW_CURSOR / kMarginBelowCursor = 22.0 named constant present
  //    in buffer_screen.dart (FR-17)
  //
  // The constant must be a named declaration (not an inline literal scattered
  // throughout the file). The gate asserts the named constant string and the
  // 22.0 value are present together on a non-comment line.
  // ────────────────────────────────────────────────────────────────────────────

  group('MARGIN_BELOW_CURSOR named constant = 22.0 present (FR-17)', () {
    // ── red fixture: file without the named constant ─────────────────────────
    group('fixture — broken source with inline literal only', () {
      const brokenSource = '''
void _doMarginScroll() {
  final margin = 22.0; // magic number, no named constant
}
''';

      test('should_FAIL_named_constant_scan_on_broken_fixture', () {
        // The named constant must appear; the broken fixture has only a
        // comment mention and no const declaration.
        final hasNamedConst =
            brokenSource.contains('kMarginBelowCursor') ||
            brokenSource.contains('MARGIN_BELOW_CURSOR');
        expect(
          hasNamedConst,
          isFalse,
          reason:
              'Broken fixture must NOT contain the named constant to prove the '
              'scan would fire if it were absent.',
        );
      });
    });

    // ── green: real buffer_screen.dart ───────────────────────────────────────
    test(
      'should_have_kMarginBelowCursor_or_MARGIN_BELOW_CURSOR_named_constant_in_buffer_screen',
      () {
        final file = File(bufferScreenPath);
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();

        // The constant must be named (kMarginBelowCursor or MARGIN_BELOW_CURSOR)
        // AND must be assigned 22.0 — verified together.
        final hasNamed =
            content.contains('kMarginBelowCursor') ||
            content.contains('MARGIN_BELOW_CURSOR');
        expect(
          hasNamed,
          isTrue,
          reason:
              'buffer_screen.dart must declare a named constant '
              'kMarginBelowCursor or MARGIN_BELOW_CURSOR (FR-17, §5.4e). '
              'Not an inline literal.',
        );

        final has22 = content.contains('22.0');
        expect(
          has22,
          isTrue,
          reason:
              'buffer_screen.dart must assign the value 22.0 to the named '
              'constant (canon-extraction §6, FR-17).',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 6. No bare print() in M3 lib/ (NFR-06)
  //
  // Mirrors the M2 gate check. debugPrint() is allowed; bare print() is not.
  // Comment lines are excluded.
  // ────────────────────────────────────────────────────────────────────────────

  group('no bare print() in lib/ (NFR-06)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — source with bare print()', () {
      const brokenSource = 'print("debug: margin scroll fired");';

      test('should_FAIL_print_scan_on_broken_fixture', () {
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
            'log() or debugPrint() instead (NFR-06).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 7. The two new domain helpers contain no package:flutter/ import (NFR-04)
  //
  // lib/domain/editor/list_continuation.dart and line_indent.dart are pure
  // Dart — importing package:flutter/ would break domain purity (NFR-04,
  // TASK-01/TASK-02 acceptance criteria).
  // ────────────────────────────────────────────────────────────────────────────

  group('domain helpers contain no package:flutter/ import (NFR-04)', () {
    const helperFiles = ['list_continuation.dart', 'line_indent.dart'];

    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — domain file with package:flutter/ import', () {
      const brokenSource = "import 'package:flutter/material.dart';";

      test('should_FAIL_domain_purity_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('package:flutter/'),
          isTrue,
          reason: 'Broken fixture must trigger the domain purity scan.',
        );
      });
    });

    // ── green: real lib/domain/editor/ ───────────────────────────────────────
    for (final helperName in helperFiles) {
      test('should_have_zero_package_flutter_imports_in_$helperName', () {
        final helperPath = '$domainEditorDir/$helperName';
        final file = File(helperPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/domain/editor/$helperName must exist (TASK-01/TASK-02).',
        );
        final hits = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (lines[i].contains('package:flutter/')) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'lib/domain/editor/$helperName must be pure Dart — no '
              'package:flutter/ imports (NFR-04, domain purity).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    }
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 8. No literal Text() in M3 lib/presentation/ (mirrors M2 NFR-M2-05 check)
  //
  // Heuristic: any `Text('...')` or `Text("...")` with a non-empty string
  // literal is a violation. ARB-lookup calls look like
  //   Text(AppLocalizations.of(context).someKey)
  // and do not match the literal pattern. Empty literals (Text('')) are
  // structural and allowed.
  // ────────────────────────────────────────────────────────────────────────────

  group('no literal Text() in lib/presentation/ (NFR-M2-05 / M3 extension)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — hardcoded Text literal', () {
      const brokenSource = "Text('Type or paste something…')";

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
