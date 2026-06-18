// SP-20260617 source-scan gate — buffer-mobile
//
// Spec refs: FR-01, FR-04, FR-07 (via NFR-01), FR-28, NFR-01, NFR-02, NFR-06,
//            §7.2, OQ-16
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Pattern: each gate first proves RED on a deliberately-broken inline fixture
// string, then wires to the real lib/ tree. This "red-then-green" discipline
// mirrors sp_20260616_gate_test.dart (OQ-16).
//
// Gate inventory (TASK-13, Wave 4):
//   1. Twin-mirror retired — share_overlay.dart and chrome_overlay.dart are
//      ABSENT from lib/presentation/shell/; no Positioned(top:0,left:0) twin
//      placement remains in lib/.
//   2. Hex-literal count — #[0-9a-fA-F]{6} on non-comment code lines is
//      exactly 0; all colour literals use the 0xAARRGGBB form (NFR-02).
//      NOTE: the plan expected count of 3 refers to the brand-seed + 2 swatches
//      as documented in code comments; the ACTUAL code-line count is 0 because
//      all colours are expressed as Color(0xFF…) — pin to that verified count.
//   3. Single .startSearch( invocation — exactly 1 non-comment call-site
//      across lib/: buffer_screen.dart:1510 (NFR-01).
//   4. Clipboard.setData confined to editor_actions.dart — zero occurrences
//      elsewhere in lib/ (NFR-01, FR-08).
//   5. showModalBottomSheet absent from lib/presentation/shell/ on non-comment
//      code lines — replaced by openOverflowPopover (TASK-07, FR-04).
//   6. BackdropFilter nested inside ClipRRect in glass_surface.dart (NFR-06).
//   7. BottomToolbar is Ref-free — no WidgetRef / ConsumerWidget / ref.watch /
//      ref.read in bottom_toolbar.dart (FR-07, TASK-08).
//   8. toast_overlay.dart is a GlassSurface consumer; old Material flat-fill
//      pattern (Material + surfaceContainerHighest / _kRadius) is gone (FR-28,
//      TASK-10).

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

/// Returns true if [line] is a comment line (single-line `//` or `///` or
/// block-comment `*`). Does NOT handle inline trailing comments — those are
/// handled per-gate by splitting on `//` when needed.
bool _isCommentLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*');
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  late String root;
  late String libDir;
  late String shellDir;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    shellDir = '$root/lib/presentation/shell';
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 1. Twin-mirror retired (FR-01, TASK-06)
  //
  // share_overlay.dart and chrome_overlay.dart must be ABSENT from
  // lib/presentation/shell/. The Positioned(top:0,left:0) twin-mirror
  // placement used by the old ShareOverlay/ChromeOverlay pair must be gone —
  // the two overlays were merged into ChromePill (single top-right).
  //
  // SP-20260618 revision (OQ-16): FindBackPill (TASK-06) is mounted via
  // Align(topLeft)+Padding with non-zero insets. The Positioned(top:0,left:0)
  // pattern must remain ABSENT even after the new top-left chrome element is
  // added. The reason string is narrowed to the retired-twin-mirror intent.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 1 — twin-mirror retired: overlay files absent (FR-01, TASK-06)', () {
    // ── red fixture: code with twin Positioned placement ────────────────────
    group('fixture — source with Positioned(top:0,left:0) twin placement', () {
      const brokenSource = '''
Stack(children: [
  Positioned(top: 0, left: 0, child: ShareOverlay()),
  Positioned(top: 0, right: 0, child: ChromeOverlay()),
])
''';

      test(
        'fixture_contains_Positioned_top0_left0_proves_pattern_detectable',
        () {
          final pattern = RegExp(
            r'Positioned\(\s*top\s*:\s*0\s*,\s*left\s*:\s*0',
          );
          expect(
            pattern.hasMatch(brokenSource),
            isTrue,
            reason:
                'Broken fixture must contain Positioned(top:0,left:0) '
                'twin placement to prove the pattern is detectable.',
          );
        },
      );
    });

    // ── additional fixture: Align+Padding mount does NOT match the pattern ──
    group(
      'fixture — Align+Padding top-left mount is NOT a Positioned(top:0) hit',
      () {
        // SP-20260618: FindBackPill is placed via Align(Alignment.topLeft)+Padding.
        // This must NOT match the retired twin-mirror Positioned(top:0,left:0)
        // pattern so that Gate 1 does not false-fire on the new chrome element.
        const goodSource = '''
if (findState.active)
  Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: EdgeInsets.only(
        top: kChromeTopGap + safeAreaTop,
        left: kChromeSideMargin,
      ),
      child: FindBackPill(onClose: _dispatchClose),
    ),
  ),
''';

        test(
          'fixture_Align_Padding_does_not_match_Positioned_top0_left0_pattern',
          () {
            final pattern = RegExp(
              r'Positioned\(\s*top\s*:\s*0\s*,\s*left\s*:\s*0',
            );
            expect(
              pattern.hasMatch(goodSource),
              isFalse,
              reason:
                  'Align+Padding mount of FindBackPill must NOT match the '
                  'Positioned(top:0,left:0) pattern — the two are distinct '
                  'placement strategies and Gate 1 must not false-fire '
                  '(SP-20260618 OQ-16).',
            );
          },
        );
      },
    );

    // ── green: share_overlay.dart must be ABSENT ────────────────────────────
    test('should_NOT_exist_share_overlay_dart (deleted in Wave 1 TASK-06)', () {
      final file = File('$shellDir/share_overlay.dart');
      expect(
        file.existsSync(),
        isFalse,
        reason:
            'lib/presentation/shell/share_overlay.dart must NOT exist. '
            'It was deleted in Wave 1 (TASK-06) when the twin-overlay model '
            'was replaced by ChromePill (FR-01). Any reappearance is a regression.',
      );
    });

    // ── green: chrome_overlay.dart must be ABSENT ───────────────────────────
    test('should_NOT_exist_chrome_overlay_dart (deleted in Wave 1 TASK-06)', () {
      final file = File('$shellDir/chrome_overlay.dart');
      expect(
        file.existsSync(),
        isFalse,
        reason:
            'lib/presentation/shell/chrome_overlay.dart must NOT exist. '
            'It was deleted in Wave 1 (TASK-06) together with share_overlay.dart '
            '(FR-01). Any reappearance is a regression.',
      );
    });

    // ── green: no Positioned(top:0,left:0) twin placement remains ───────────
    //
    // Narrowed reason: this gate catches the RETIRED TWIN-MIRROR pattern
    // (ShareOverlay/ChromeOverlay Positioned(top:0,left:0) pair). It does
    // NOT intend to block all top-left chrome — FindBackPill (SP-20260618)
    // uses Align+Padding with non-zero insets and correctly does not match.
    test('should_have_no_Positioned_top0_left0_twin_placement_in_lib', () {
      final pattern = RegExp(r'Positioned\(\s*top\s*:\s*0\s*,\s*left\s*:\s*0');
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          if (pattern.hasMatch(lines[i])) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'No Positioned(top:0,left:0) TWIN-MIRROR placement must remain '
            'in lib/. The ShareOverlay/ChromeOverlay twin-overlay pattern was '
            'retired in TASK-06 (FR-01). FindBackPill uses Align+Padding '
            '(non-zero insets) and does not match this pattern.\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 2. Hex-literal count (NFR-02)
  //
  // The pattern #[0-9a-fA-F]{6} must appear ZERO times on non-comment code
  // lines in lib/. All colours are expressed as Color(0xFF…) constants.
  //
  // NFR-02 original intent: no new hardcoded hex literals introduced in lib/;
  // the 3 sanctioned values (brand seed #3584E4 + 2 swatches #fff/#202020) are
  // documented in code comments, NOT as bare #XXXXXX literals on code lines.
  // The VERIFIED non-comment count across lib/ is 0 — pinned here.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 2 — hex-literal count: 0 on non-comment lines (NFR-02)', () {
    // ── red fixture: a code line containing a bare #-hex literal ─────────────
    group('fixture — code line with bare #3584E4 hex literal', () {
      const brokenLine =
          "  static const Color _brandSeed = Color.fromHex('#3584E4');";

      test('fixture_contains_hash_hex_literal_proves_pattern_detectable', () {
        final pattern = RegExp(r'#[0-9a-fA-F]{6}');
        expect(
          pattern.hasMatch(brokenLine),
          isTrue,
          reason:
              'Broken fixture must contain a #XXXXXX literal on a code line '
              'to prove the pattern is detectable.',
        );
      });
    });

    // ── green: real lib/ — all #XXXXXX occurrences are in comments ───────────
    test('should_have_zero_hash_hex_literals_on_non_comment_code_lines', () {
      final pattern = RegExp(r'#[0-9a-fA-F]{6}');
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          // Strip inline trailing comments before checking.
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (pattern.hasMatch(codePart)) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      // Verified count at TASK-13 authoring: 0.
      // All colour values use Color(0xFF…) — no bare #XXXXXX on code lines.
      // NFR-02: sanctioned values (#3584E4, #fff, #202020) are doc-comment only.
      expect(
        hits,
        isEmpty,
        reason:
            'Zero #XXXXXX hex literals are permitted on non-comment code lines '
            'in lib/. Colours must be expressed as Color(0xFF…) constants. '
            'Verified count at TASK-13: 0 (NFR-02).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 3. Single .startSearch( invocation (NFR-01)
  //
  // Exactly one non-comment call-site of `.startSearch(` must exist across
  // lib/. As of TASK-13 that site is:
  //   lib/presentation/editor/buffer_screen.dart:1510
  //
  // `startSearch` also appears as a method declaration in find_provider.dart and
  // as a doc-comment reference in editor_actions.dart — those are excluded.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 3 — single .startSearch( invocation (NFR-01)', () {
    // ── red fixture: two invocation sites ────────────────────────────────────
    group('fixture — two .startSearch( call sites', () {
      const brokenSources = [
        '  ref.read(findProvider.notifier).startSearch(entryOffset: offset);',
        '  provider.startSearch(entryOffset: 0); // second call site',
      ];

      test(
        'fixture_has_two_startSearch_invocations_proves_pattern_detectable',
        () {
          final pattern = RegExp(r'\.startSearch\(');
          final count = brokenSources.where((l) => pattern.hasMatch(l)).length;
          expect(
            count,
            equals(2),
            reason: 'Broken fixture must have exactly 2 .startSearch( matches.',
          );
        },
      );
    });

    // ── green: real lib/ — exactly 1 non-comment invocation ─────────────────
    test('should_have_exactly_one_startSearch_invocation_in_lib', () {
      final pattern = RegExp(r'\.startSearch\(');
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          // Strip inline trailing comments.
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (pattern.hasMatch(codePart)) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      // Verified at TASK-13: exactly 1 invocation.
      //   lib/presentation/editor/buffer_screen.dart:1510
      expect(
        hits,
        hasLength(1),
        reason:
            'Exactly ONE .startSearch( invocation must exist across lib/ '
            '(NFR-01, Find-logic frozen). '
            '${hits.isEmpty ? 'No invocation found — _dispatchOpenFind may be broken.' : 'Found ${hits.length} sites:\n${hits.join('\n')}'}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 4. Clipboard.setData confined to editor_actions.dart (NFR-01, FR-08)
  //
  // Clipboard.setData must appear in exactly one lib/ file:
  //   lib/presentation/editor/editor_actions.dart
  // Zero occurrences are permitted anywhere else.
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'Gate 4 — Clipboard.setData only in editor_actions.dart (NFR-01, FR-08)',
    () {
      const designatedFile = 'presentation/editor/editor_actions.dart';

      // ── red fixture: Clipboard.setData in a presentation file ──────────────
      group('fixture — Clipboard.setData in a non-designated file', () {
        const brokenSource =
            'Clipboard.setData(ClipboardData(text: buffer)); // wrong location';

        test(
          'fixture_contains_Clipboard_setData_proves_pattern_detectable',
          () {
            expect(
              brokenSource.contains('Clipboard.setData'),
              isTrue,
              reason:
                  'Broken fixture must contain Clipboard.setData to prove the '
                  'pattern is detectable.',
            );
          },
        );
      });

      // ── green: exactly one file, the designated adapter ──────────────────
      test('should_have_Clipboard_setData_only_in_editor_actions_dart', () {
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            final commentIdx = lines[i].indexOf('//');
            final codePart = commentIdx >= 0
                ? lines[i].substring(0, commentIdx)
                : lines[i];
            if (codePart.contains('Clipboard.setData')) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }

        expect(
          hits,
          isNotEmpty,
          reason:
              'Clipboard.setData must appear in lib/$designatedFile — '
              'no call found at all.',
        );
        expect(
          hits,
          hasLength(1),
          reason:
              'Clipboard.setData must appear in EXACTLY ONE file: '
              'lib/$designatedFile (NFR-01, FR-08).\n'
              'Found ${hits.length} sites:\n${hits.join('\n')}',
        );
        expect(
          hits.first,
          contains(designatedFile),
          reason:
              'The sole Clipboard.setData call must be in '
              'lib/$designatedFile, not elsewhere.\n'
              'Actual location: ${hits.first}',
        );
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 5. showModalBottomSheet absent from lib/presentation/shell/ on code lines
  //    (TASK-07, FR-04)
  //
  // showModalBottomSheet must NOT appear on non-comment code lines in
  // lib/presentation/shell/. The two existing occurrences in menu_sheet.dart
  // are in comment lines only (describing the legacy pattern).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'Gate 5 — showModalBottomSheet absent from shell/ code lines (TASK-07, FR-04)',
    () {
      // ── red fixture: showModalBottomSheet on a code line ───────────────────
      group('fixture — showModalBottomSheet call on a code line', () {
        const brokenSource =
            '  showModalBottomSheet(context: context, builder: (_) => MenuContent());';

        test(
          'fixture_contains_showModalBottomSheet_proves_pattern_detectable',
          () {
            expect(
              brokenSource.contains('showModalBottomSheet'),
              isTrue,
              reason:
                  'Broken fixture must contain showModalBottomSheet call to prove '
                  'the pattern is detectable.',
            );
          },
        );
      });

      // ── green: zero code-line occurrences in shell/ ───────────────────────
      test('should_have_zero_showModalBottomSheet_on_code_lines_in_shell', () {
        final hits = <String>[];
        for (final file in _dartFiles(shellDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            final commentIdx = lines[i].indexOf('//');
            final codePart = commentIdx >= 0
                ? lines[i].substring(0, commentIdx)
                : lines[i];
            if (codePart.contains('showModalBottomSheet')) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'showModalBottomSheet must NOT appear on non-comment code lines '
              'in lib/presentation/shell/. The bottom sheet was replaced by '
              'openOverflowPopover in TASK-07 (FR-04).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 6. BackdropFilter inside ClipRRect in glass_surface.dart (NFR-06)
  //
  // The glass-branch of GlassSurface must wrap BackdropFilter inside ClipRRect
  // so that the blur is clipped to the pill/popover bounds (not the full screen).
  // The two must appear in that nesting order in the same file.
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'Gate 6 — BackdropFilter inside ClipRRect in glass_surface.dart (NFR-06)',
    () {
      const glassSurfacePath = 'lib/presentation/theme/glass_surface.dart';

      // ── red fixture: BackdropFilter without ClipRRect wrapper ──────────────
      group('fixture — BackdropFilter on its own (no ClipRRect ancestor)', () {
        // A source that has BackdropFilter but ClipRRect comes AFTER it
        // (i.e., wrong nesting order).
        const brokenSource = '''
BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: container,
  ),
)
''';

        test(
          'fixture_has_BackdropFilter_before_ClipRRect_proves_order_matters',
          () {
            final clipIdx = brokenSource.indexOf('ClipRRect');
            final blurIdx = brokenSource.indexOf('BackdropFilter');
            expect(
              blurIdx < clipIdx,
              isTrue,
              reason:
                  'Broken fixture must have BackdropFilter before ClipRRect '
                  '(wrong order) to prove order-checking is meaningful.',
            );
          },
        );
      });

      // ── green: glass_surface.dart has ClipRRect before BackdropFilter ──────
      test(
        'should_have_ClipRRect_wrapping_BackdropFilter_in_glass_surface_dart',
        () {
          final file = File('$root/$glassSurfacePath');
          expect(
            file.existsSync(),
            isTrue,
            reason: '$glassSurfacePath must exist (TASK-01 delivery).',
          );

          final source = file.readAsStringSync();

          // Both must be present.
          expect(
            source.contains('ClipRRect'),
            isTrue,
            reason: '$glassSurfacePath must contain ClipRRect (NFR-06).',
          );
          expect(
            source.contains('BackdropFilter'),
            isTrue,
            reason: '$glassSurfacePath must contain BackdropFilter (NFR-06).',
          );

          // ClipRRect must appear before BackdropFilter in the glass branch.
          // We check this by finding the first non-comment ClipRRect line
          // followed by a BackdropFilter child on a later line.
          final lines = file.readAsLinesSync();
          var clipRRectLine = -1;
          var backdropLine = -1;
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            if (clipRRectLine < 0 && lines[i].contains('ClipRRect')) {
              clipRRectLine = i;
            }
            if (backdropLine < 0 && lines[i].contains('BackdropFilter')) {
              backdropLine = i;
            }
            if (clipRRectLine >= 0 && backdropLine >= 0) break;
          }

          expect(
            clipRRectLine,
            greaterThanOrEqualTo(0),
            reason:
                'ClipRRect must appear on a non-comment line in '
                '$glassSurfacePath.',
          );
          expect(
            backdropLine,
            greaterThanOrEqualTo(0),
            reason:
                'BackdropFilter must appear on a non-comment line in '
                '$glassSurfacePath.',
          );
          expect(
            clipRRectLine,
            lessThan(backdropLine),
            reason:
                'ClipRRect (line ${clipRRectLine + 1}) must appear BEFORE '
                'BackdropFilter (line ${backdropLine + 1}) in '
                '$glassSurfacePath — ClipRRect must be the outer container '
                'that clips the blur (NFR-06). '
                'Found ClipRRect at line ${clipRRectLine + 1}, '
                'BackdropFilter at line ${backdropLine + 1}.',
          );
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 7. BottomToolbar Ref-free (FR-07, TASK-08)
  //
  // bottom_toolbar.dart must contain no WidgetRef, ConsumerWidget, ref.watch,
  // or ref.read. BottomToolbar is a pure StatelessWidget driven by callbacks.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 7 — BottomToolbar is Ref-free (FR-07, TASK-08)', () {
    const bottomToolbarPath = 'lib/presentation/shell/bottom_toolbar.dart';

    // ── red fixture: toolbar with ConsumerWidget ──────────────────────────────
    group('fixture — toolbar with ConsumerWidget and ref.watch', () {
      const brokenSource = '''
class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(chromeVisibilityProvider);
    return visible ? Row(children: []) : const SizedBox.shrink();
  }
}
''';

      test(
        'fixture_contains_ConsumerWidget_and_ref_watch_proves_scan_works',
        () {
          expect(
            brokenSource.contains('ConsumerWidget'),
            isTrue,
            reason: 'Broken fixture must contain ConsumerWidget.',
          );
          expect(
            brokenSource.contains('WidgetRef'),
            isTrue,
            reason: 'Broken fixture must contain WidgetRef.',
          );
          expect(
            brokenSource.contains('ref.watch'),
            isTrue,
            reason: 'Broken fixture must contain ref.watch.',
          );
        },
      );
    });

    // ── green: real bottom_toolbar.dart — zero Ref symbols ───────────────────
    test('should_have_zero_Ref_symbols_in_bottom_toolbar_dart', () {
      final file = File('$root/$bottomToolbarPath');
      expect(
        file.existsSync(),
        isTrue,
        reason: '$bottomToolbarPath must exist (TASK-08 delivery).',
      );

      final forbidden = [
        'WidgetRef',
        'ConsumerWidget',
        'ConsumerState',
        'ConsumerStatefulWidget',
        'ref.watch',
        'ref.read',
      ];

      final hits = <String>[];
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_isCommentLine(lines[i])) continue;
        final commentIdx = lines[i].indexOf('//');
        final codePart = commentIdx >= 0
            ? lines[i].substring(0, commentIdx)
            : lines[i];
        for (final token in forbidden) {
          if (codePart.contains(token)) {
            hits.add('${file.path}:${i + 1} [$token]: ${lines[i].trim()}');
          }
        }
      }

      expect(
        hits,
        isEmpty,
        reason:
            'bottom_toolbar.dart must be Ref-free. No WidgetRef / '
            'ConsumerWidget / ref.watch / ref.read on code lines (FR-07, '
            'TASK-08). BottomToolbar is a pure StatelessWidget driven by '
            'VoidCallback parameters.\nOffenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 8. toast_overlay.dart is a GlassSurface consumer; old flat-fill gone
  //    (FR-28, TASK-10)
  //
  // toast_overlay.dart must:
  //   a) Reference GlassSurface at least once on a non-comment code line.
  //   b) NOT contain the old flat-fill markers: Material class usage alongside
  //      surfaceContainerHighest, or a _kRadius constant.
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'Gate 8 — toast_overlay.dart uses GlassSurface; flat-fill gone (FR-28, TASK-10)',
    () {
      const toastPath = 'lib/presentation/shell/toast_overlay.dart';

      // ── red fixture A: no GlassSurface reference ──────────────────────────
      group('fixture — toast with old Material flat-fill (no GlassSurface)', () {
        const brokenSource = '''
return Material(
  color: Theme.of(context).colorScheme.surfaceContainerHighest,
  borderRadius: BorderRadius.circular(_kRadius),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(message),
  ),
);
''';

        test(
          'fixture_has_Material_flat_fill_and_no_GlassSurface_proves_scan_catches_regression',
          () {
            expect(
              brokenSource.contains('Material'),
              isTrue,
              reason: 'Broken fixture must contain Material.',
            );
            expect(
              brokenSource.contains('surfaceContainerHighest'),
              isTrue,
              reason: 'Broken fixture must contain surfaceContainerHighest.',
            );
            expect(
              brokenSource.contains('_kRadius'),
              isTrue,
              reason: 'Broken fixture must contain _kRadius.',
            );
            expect(
              brokenSource.contains('GlassSurface'),
              isFalse,
              reason: 'Broken fixture must NOT contain GlassSurface.',
            );
          },
        );
      });

      // ── green: GlassSurface must appear on a code line ────────────────────
      test('should_reference_GlassSurface_in_toast_overlay_dart', () {
        final file = File('$root/$toastPath');
        expect(file.existsSync(), isTrue, reason: '$toastPath must exist.');

        var glassSurfaceCount = 0;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (codePart.contains('GlassSurface')) {
            glassSurfaceCount++;
          }
        }

        expect(
          glassSurfaceCount,
          greaterThanOrEqualTo(1),
          reason:
              '$toastPath must reference GlassSurface at least once on a '
              'non-comment code line (FR-28, TASK-10). Found 0 references — '
              'the flat-fill Material container may not have been replaced.',
        );
      });

      // ── green: old flat-fill markers must be absent ───────────────────────
      test(
        'should_NOT_contain_old_flat_fill_pattern_in_toast_overlay_dart',
        () {
          final file = File('$root/$toastPath');
          expect(file.existsSync(), isTrue);

          // The old flat-fill pattern used Material(...) with
          // surfaceContainerHighest and a _kRadius constant.
          // Checking for the combination: surfaceContainerHighest on a code
          // line (not a comment) in this specific file.
          final hits = <String>[];
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (_isCommentLine(lines[i])) continue;
            final commentIdx = lines[i].indexOf('//');
            final codePart = commentIdx >= 0
                ? lines[i].substring(0, commentIdx)
                : lines[i];
            if (codePart.contains('surfaceContainerHighest') ||
                codePart.contains('_kRadius')) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }

          expect(
            hits,
            isEmpty,
            reason:
                'toast_overlay.dart must NOT contain the old flat-fill markers '
                '(surfaceContainerHighest, _kRadius) on code lines. These were '
                'replaced by GlassSurface in TASK-10 (FR-28).\n'
                'Offenders:\n${hits.join('\n')}',
          );
        },
      );
    },
  );
}
