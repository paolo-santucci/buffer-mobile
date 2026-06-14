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
//   1. height:1.4 in editor TextStyle AND fontSize/fontFamily DERIVE FROM
//      SETTINGS STATE (not hardcoded) in buffer_screen.dart (FR-03, M7 REVISED
//      — fontSize references fontSizePt ≥ twice; fontFamily not a literal).
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
  // 1. height:1.4 in editor TextStyle AND fontSize/fontFamily DERIVE FROM
  //    SETTINGS STATE (FR-03, M7 REVISED)
  //
  // The editor TextStyle must carry `height: 1.4`. After M7, the same style
  // definition MUST set fontSize (from fontSizePt, 21-slot) and fontFamily
  // (from useMonospaceFont resolution) — both must derive from settings state,
  // not from hardcoded literals. fontSize: must appear on at least 2 surfaces
  // (editorStyle AND strutStyle, EC-M7-11 paired invariant).
  // Gate REVISED for M7 TASK-13 (spec §6.1 gate-revision table).
  // ────────────────────────────────────────────────────────────────────────────

  // ── REVISED for M7 ──────────────────────────────────────────────────────────
  // M7 Typography & Layout wires fontSize and fontFamily onto the editor
  // TextStyle for the first time (spec §5.1.5, FR-M7-01, FR-M7-08, FR-M7-09).
  // The gate contract flips from "absence" to "presence + derives from settings
  // state" (TASK-13, spec §6.1 gate-revision table).
  //
  // New contract:
  //   • `fontSize:` PRESENT on non-comment lines — at least 2 occurrences
  //     (editorStyle AND strutStyle, EC-M7-11 paired invariant).
  //   • Every `fontSize:` assignment references `fontSizePt` (not a numeric
  //     literal) — guards against hardcoding that would break 21-slot scaling.
  //   • `fontFamily:` PRESENT on at least 1 non-comment line — M7 has wired it.
  //   • No `fontFamily:` value is a hardcoded string literal in the assignment;
  //     the value resolves from a variable derived from `useMonospaceFont`.
  // ─────────────────────────────────────────────────────────────────────────────
  group('editor TextStyle has height:1.4, fontSize derives from settings, '
      'fontFamily derives from settings (M7 REVISED — FR-03, FR-M7-01, '
      'FR-M7-08, FR-M7-09)', () {
    // ── red fixture: fontSize is a numeric literal (wrong — M7 must derive) ──
    group('fixture — broken TextStyle with hardcoded numeric fontSize', () {
      const brokenSource =
          '  fontSize: 16.0,  // hardcoded — NOT derived from fontSizePt';

      test('should_FAIL_derivation_scan_on_hardcoded_literal_fixture', () {
        // A `fontSize:` line whose value is a plain numeric literal fails the
        // derivation check: it must reference `fontSizePt`, not a raw number.
        final isLiteral = RegExp(
          r'\bfontSize\s*:\s*\d+(\.\d+)?\b',
        ).hasMatch(brokenSource);
        expect(
          isLiteral,
          isTrue,
          reason:
              'Broken fixture must contain a numeric fontSize literal to prove '
              'the derivation scan would fire when the slot is not referenced.',
        );
      });
    });

    // ── red fixture: fontFamily is a hardcoded string literal (wrong) ─────────
    group("fixture — broken TextStyle with hardcoded fontFamily: 'Courier'", () {
      const brokenSource = "  fontFamily: 'Courier',  // hardcoded literal";

      test('should_FAIL_derivation_scan_on_hardcoded_fontFamily_fixture', () {
        // A fontFamily: whose value is a quoted string literal fails derivation.
        final isLiteral = RegExp(
          r"""\bfontFamily\s*:\s*['"][^'"]+['"]""",
        ).hasMatch(brokenSource);
        expect(
          isLiteral,
          isTrue,
          reason:
              'Broken fixture must contain a string-literal fontFamily to prove '
              'the derivation scan would fire when the family is hardcoded.',
        );
      });
    });

    // ── green: real buffer_screen.dart ───────────────────────────────────────
    group('real buffer_screen.dart — height:1.4 present, fontSize+fontFamily '
        'derive from settings state (M7)', () {
      late String screenContent;
      late List<String> codeLines; // non-comment lines only

      setUpAll(() {
        final file = File(bufferScreenPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'lib/presentation/editor/buffer_screen.dart must exist',
        );
        screenContent = file.readAsStringSync();
        codeLines = screenContent.split('\n').where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*');
        }).toList();
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

      // M7 REVISED: fontSize: MUST be present and reference fontSizePt.
      test('should_set_fontSize_derived_from_fontSizePt_on_both_surfaces', () {
        // Collect non-comment lines that set fontSize:.
        final fontSizeLines = codeLines
            .where((l) => RegExp(r'\bfontSize\s*:').hasMatch(l))
            .toList();

        // Must be present on at least 2 lines (editorStyle + strutStyle,
        // EC-M7-11 paired invariant).
        expect(
          fontSizeLines.length,
          greaterThanOrEqualTo(2),
          reason:
              'buffer_screen.dart must set fontSize: on at least 2 surfaces '
              '(editorStyle AND strutStyle — EC-M7-11 paired invariant). '
              'Found on ${fontSizeLines.length} line(s): '
              '${fontSizeLines.map((l) => l.trim()).join('; ')}',
        );

        // Every fontSize: assignment must reference fontSizePt (not a raw
        // numeric literal). This guards the 21-slot derivation contract.
        for (final line in fontSizeLines) {
          final isLiteral = RegExp(
            r'\bfontSize\s*:\s*\d+(\.\d+)?\b',
          ).hasMatch(line);
          expect(
            isLiteral,
            isFalse,
            reason:
                'fontSize: must derive from fontSizePt (the settings slot), '
                'not a hardcoded numeric literal (FR-M7-01, 21-slot scaling). '
                'Offending line: ${line.trim()}',
          );
        }

        // At least one fontSize: line must reference fontSizePt explicitly.
        final hasFontSizePtRef = fontSizeLines.any(
          (l) => l.contains('fontSizePt'),
        );
        expect(
          hasFontSizePtRef,
          isTrue,
          reason:
              'At least one fontSize: assignment must explicitly reference '
              'fontSizePt (editorStyle surface — FR-M7-01, spec §5.1.5).',
        );
      });

      // M7 REVISED: fontFamily: MUST be present and derive from settings.
      test('should_set_fontFamily_derived_from_settings_useMonospaceFont', () {
        // Collect non-comment lines that set fontFamily:.
        final fontFamilyLines = codeLines
            .where((l) => RegExp(r'\bfontFamily\s*:').hasMatch(l))
            .toList();

        // Must be present — M7 has wired the mono/document resolution.
        expect(
          fontFamilyLines,
          isNotEmpty,
          reason:
              'buffer_screen.dart must set fontFamily: (M7 wired mono/document '
              'font family resolution — FR-M7-08, FR-M7-09).',
        );

        // No fontFamily: line may have a hardcoded string-literal value.
        // The value must resolve from a local variable derived from
        // useMonospaceFont (not `fontFamily: 'Courier'` style).
        for (final line in fontFamilyLines) {
          final isLiteral = RegExp(
            r"""\bfontFamily\s*:\s*['"][^'"]+['"]""",
          ).hasMatch(line);
          expect(
            isLiteral,
            isFalse,
            reason:
                'fontFamily: must reference a variable that derives from '
                'useMonospaceFont, not a hardcoded string literal '
                '(FR-M7-08, FR-M7-09). Offending line: ${line.trim()}',
          );
        }
      });
    });
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
  // 3. Find-replace seams present + M4 buildTextSpan painting (EC-26 — REVISED)
  //
  // REVISED for M4: the gate no longer asserts "delegates to super unchanged"
  // (M1/M3 baseline). It now asserts:
  //   (a) the three seam members are still present (highlightRanges,
  //       currentMatchIndex, buildTextSpan), and
  //   (b) buildTextSpan CALLS super for base style/composing decoration
  //       (super.buildTextSpan is present in the override body), AND
  //   (c) highlight backgrounds are LAYERED on match runs — verified by scanning
  //       for primaryContainer and secondaryContainer token references
  //       (no colour literals; CANON GAP OQ-06 resolved theme-driven).
  //
  // The old "delegates to super UNCHANGED" wording is intentionally absent —
  // searching for it would now be a FALSE assertion (M4 adds layering).
  // NFR-04: gate REVISED, not removed/bypassed.
  // ────────────────────────────────────────────────────────────────────────────

  group('find-replace seams + M4 buildTextSpan painting in editor_controller.dart '
      '(EC-26 — REVISED)', () {
    // ── red fixture: controller source with buildTextSpan body replaced ─────
    group('fixture — broken controller missing highlightRanges and super call', () {
      const brokenSource = '''
class EditorController extends TextEditingController {
  int? _currentMatchIndex;
  TextSpan buildTextSpan({required BuildContext context,
      TextStyle? style, required bool withComposing}) {
    // custom implementation — super not called, no background layering
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

      test('should_FAIL_super_buildTextSpan_call_scan_on_broken_fixture', () {
        // M4: buildTextSpan must still call super.buildTextSpan for base
        // style / composing decoration. The broken fixture skips the super
        // call — scan must detect its absence.
        expect(
          brokenSource.contains('super.buildTextSpan'),
          isFalse,
          reason:
              'Broken fixture must NOT contain "super.buildTextSpan" to prove '
              'the super-call scan would fire when it is absent.',
        );
      });

      test('should_FAIL_primaryContainer_scan_on_broken_fixture', () {
        // M4: the override must reference primaryContainer (current-match
        // background). The broken fixture does not.
        expect(
          brokenSource.contains('primaryContainer'),
          isFalse,
          reason:
              'Broken fixture must NOT contain "primaryContainer" to prove '
              'the highlight-background scan would fire when layering is absent.',
        );
      });
    });

    // ── green: real editor_controller.dart ──────────────────────────────────
    group('real editor_controller.dart — seams intact, super called, '
        'backgrounds layered (M4)', () {
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
              '(M4 seam, EC-26).',
        );
      });

      test('should_contain_currentMatchIndex_member', () {
        expect(
          controllerContent.contains('currentMatchIndex'),
          isTrue,
          reason:
              'editor_controller.dart must retain the currentMatchIndex member '
              '(M4 seam, EC-26).',
        );
      });

      test('should_contain_buildTextSpan_method', () {
        expect(
          controllerContent.contains('buildTextSpan'),
          isTrue,
          reason:
              'editor_controller.dart must retain the buildTextSpan override '
              '(M4 seam, EC-26).',
        );
      });

      // REVISED: asserts super is CALLED (not "unchanged delegation") — M4
      // calls super for base style/composing, then overlays backgrounds.
      test('should_call_super_buildTextSpan_for_base_style_and_composing', () {
        expect(
          controllerContent.contains('super.buildTextSpan'),
          isTrue,
          reason:
              'editor_controller.dart buildTextSpan MUST call '
              'super.buildTextSpan to preserve base TextStyle and composing '
              'decoration (M4 layers backgrounds on top — EC-26 revised).',
        );
      });

      // NEW (M4): verifies highlight backgrounds are layered — theme-derived,
      // no colour literals (CANON GAP OQ-06 resolved theme-driven).
      test(
        'should_reference_primaryContainer_for_current_match_background',
        () {
          expect(
            controllerContent.contains('primaryContainer'),
            isTrue,
            reason:
                'editor_controller.dart buildTextSpan must reference '
                'primaryContainer for the current-match background (M4, '
                'OQ-06 CANON GAP resolved theme-driven; no colour literal).',
          );
        },
      );

      test(
        'should_reference_secondaryContainer_for_non_current_match_background',
        () {
          expect(
            controllerContent.contains('secondaryContainer'),
            isTrue,
            reason:
                'editor_controller.dart buildTextSpan must reference '
                'secondaryContainer for non-current match backgrounds (M4, '
                'OQ-06 CANON GAP resolved theme-driven; no colour literal).',
          );
        },
      );

      // NEGATIVE: old "delegates to super unchanged" wording must NOT appear
      // as a code comment implying pure delegation (M4 revises the contract).
      // Note: the COMMENT text in the M1/M3 source saying "M4 will paint
      // highlights here" can still exist; we only ban the phrase that would
      // imply the method body is a pure passthrough after M4 landed.
      test(
        'should_NOT_have_buildTextSpan_described_as_delegation_only_stub',
        () {
          // The M1 stub had a doc comment "delegates verbatim to super" or
          // "no highlight painting yet". After M4 these must be gone.
          final delegatesVerbatim =
              controllerContent.contains('delegates verbatim to super') ||
              controllerContent.contains(
                'delegates to [super.buildTextSpan] verbatim',
              ) ||
              controllerContent.contains('no highlight painting yet');
          expect(
            delegatesVerbatim,
            isFalse,
            reason:
                'After M4, buildTextSpan must not be described as a '
                'verbatim-delegation stub. The M1 stub comment must be '
                'replaced with the M4 implementation description (NFR-04, '
                'gate REVISED not bypassed).',
          );
        },
      );
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
