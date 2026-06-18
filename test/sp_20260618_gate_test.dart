// SP-20260618 source-scan gate — buffer-mobile
//
// Spec refs: FR-07, FR-12, FR-17, FR-18, EC-05, EC-12, NFR-07, OQ-16
// Plan refs: TASK-01..TASK-06 (Waves 1–3)
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Pattern: each gate first proves RED on a deliberately-broken inline fixture
// string, then wires to the real lib/ tree. This "red-then-green" discipline
// mirrors sp_20260617_gate_test.dart (OQ-16).
//
// Gate inventory:
//   1. Three chrome-spacing constants present as `const double` == 16.0 in
//      editor_layout.dart (kChromeTopGap, kChromeBottomGap, kChromeSideMargin).
//   2. searchBarRadius defined as Radius.circular(24.0) in glass_surface.dart.
//   3. FindBackPill mounted via Align/Alignment.topLeft in buffer_screen.dart
//      and contains NO Positioned(top:0,left:0 pattern.
//   4. Zero Duration.zero on animated-property lines (AnimatedAlign / AnimatedSize
//      / AnimatedSwitcher / duration: with Duration.zero) in buffer_screen.dart.
//   5. Exactly one find_search_bar_test.dart under test/ (G8 consolidation).
//   6. findProvider.notifier).close() literal count in buffer_screen.dart == 2.
//   7. Regression: zero raw hex-color literals on non-comment code lines in lib/
//      (OQ-16 mirror of Gate-2 in sp_20260617_gate_test.dart).
//   8. Regression: BottomToolbar is Ref-free in bottom_toolbar.dart
//      (OQ-16 mirror of Gate-7 in sp_20260617_gate_test.dart).

// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers (mirrors sp_20260617_gate_test.dart)
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

/// Returns the project root. `flutter test` sets cwd to the package root.
String get _root => Directory.current.path;

/// Returns true if [line] is a comment line (single-line `//` / `///` or
/// block-comment `*`). Does NOT handle inline trailing comments — those are
/// handled per-gate by splitting on `//`.
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

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 1. Three chrome-spacing constants in editor_layout.dart (TASK-01)
  //
  // kChromeTopGap, kChromeBottomGap, kChromeSideMargin must each appear as
  // `const double <name> = 16.0;` on a non-comment code line in
  // lib/presentation/editor/editor_layout.dart.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 1 — three chrome-spacing const doubles == 16.0 (TASK-01)', () {
    const editorLayoutPath = 'lib/presentation/editor/editor_layout.dart';

    // ── red fixture: only one constant, wrong value ──────────────────────────
    group('fixture — missing constants / wrong value', () {
      const brokenSource = '''
const double kChromeTopGap = 8.0;
// kChromeBottomGap and kChromeSideMargin are missing
''';

      test('fixture_lacks_three_16_constants_proves_detector_fires', () {
        final pattern = RegExp(r'const double kChrome\w+ = 16\.0;');
        final count = brokenSource
            .split('\n')
            .where((l) => !_isCommentLine(l) && pattern.hasMatch(l))
            .length;
        expect(
          count,
          isNot(equals(3)),
          reason:
              'Broken fixture must NOT have three matching const double = 16.0 '
              'lines to prove the detector is meaningful.',
        );
      });
    });

    // ── green: all three constants present at 16.0 ──────────────────────────
    test(
      'should_have_kChromeTopGap_kChromeBottomGap_kChromeSideMargin_at_16_0',
      () {
        final file = File('$root/$editorLayoutPath');
        expect(
          file.existsSync(),
          isTrue,
          reason: '$editorLayoutPath must exist (TASK-01 delivery).',
        );

        final pattern = RegExp(r'const double kChrome\w+ = 16\.0;');
        final hits = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (pattern.hasMatch(codePart)) {
            hits.add('line ${i + 1}: ${lines[i].trim()}');
          }
        }

        // Exactly three chrome-spacing constants at 16.0.
        expect(
          hits,
          hasLength(3),
          reason:
              'Exactly three `const double kChrome* = 16.0;` constants must exist '
              'in $editorLayoutPath (TASK-01: kChromeTopGap, kChromeBottomGap, '
              'kChromeSideMargin). Found ${hits.length}:\n${hits.join('\n')}',
        );

        // Each must contain the expected name.
        final source = file.readAsStringSync();
        for (final name in [
          'kChromeTopGap',
          'kChromeBottomGap',
          'kChromeSideMargin',
        ]) {
          expect(
            source.contains(name),
            isTrue,
            reason: '$name must be present in $editorLayoutPath.',
          );
        }
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 2. searchBarRadius == Radius.circular(24.0) in glass_surface.dart (TASK-02)
  //
  // The GlassTokens.searchBarRadius must be set to Radius.circular(24.0) —
  // distinct from pillRadius (32) and popoverRadius (16).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'Gate 2 — searchBarRadius Radius.circular(24.0) in glass_surface.dart (TASK-02)',
    () {
      const glassSurfacePath = 'lib/presentation/theme/glass_surface.dart';

      // ── red fixture: searchBarRadius at wrong value ──────────────────────────
      group('fixture — searchBarRadius still at pillRadius (wrong)', () {
        const brokenSource =
            'searchBarRadius: BorderRadius.all(Radius.circular(32.0)),';

        test('fixture_has_32_not_24_proves_detector_catches_wrong_value', () {
          expect(
            brokenSource.contains('Radius.circular(32.0)'),
            isTrue,
            reason:
                'Broken fixture must contain Radius.circular(32.0) (wrong value) '
                'to prove the detector can differentiate.',
          );
          expect(
            brokenSource.contains('Radius.circular(24.0)'),
            isFalse,
            reason: 'Broken fixture must NOT contain Radius.circular(24.0).',
          );
        });
      });

      // ── green: searchBarRadius is 24.0 ──────────────────────────────────────
      test(
        'should_have_searchBarRadius_Radius_circular_24_in_glass_surface_dart',
        () {
          final file = File('$root/$glassSurfacePath');
          expect(
            file.existsSync(),
            isTrue,
            reason: '$glassSurfacePath must exist.',
          );

          final source = file.readAsStringSync();
          expect(
            source.contains('searchBarRadius'),
            isTrue,
            reason:
                'GlassTokens must declare searchBarRadius field ($glassSurfacePath).',
          );

          // The kDefaultGlassTokens initialisation must assign Radius.circular(24.0).
          final pattern = RegExp(
            r'searchBarRadius\s*:\s*BorderRadius\.all\(Radius\.circular\(24\.0\)\)',
          );
          expect(
            pattern.hasMatch(source),
            isTrue,
            reason:
                'searchBarRadius in kDefaultGlassTokens must be '
                'BorderRadius.all(Radius.circular(24.0)) — '
                'the find-bar radius, distinct from pillRadius (32dp) and '
                'popoverRadius (16dp) (TASK-02).',
          );
        },
      );

      // ── proof: searchBarRadius != pillRadius ─────────────────────────────────
      test(
        'searchBarRadius_is_different_from_pillRadius_in_glass_surface_dart',
        () {
          final file = File('$root/$glassSurfacePath');
          expect(file.existsSync(), isTrue);

          final source = file.readAsStringSync();
          // pillRadius is 32.0; searchBarRadius is 24.0 — different values.
          final pillPattern = RegExp(
            r'pillRadius\s*:\s*BorderRadius\.all\(Radius\.circular\(32\.0\)\)',
          );
          final searchPattern = RegExp(
            r'searchBarRadius\s*:\s*BorderRadius\.all\(Radius\.circular\(24\.0\)\)',
          );
          expect(
            pillPattern.hasMatch(source),
            isTrue,
            reason: 'pillRadius must remain at 32.0 (unchanged).',
          );
          expect(
            searchPattern.hasMatch(source),
            isTrue,
            reason: 'searchBarRadius must be 24.0 (new distinct value).',
          );
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 3. FindBackPill via Align/Alignment.topLeft, NOT Positioned(top:0,left:0)
  //    in buffer_screen.dart (TASK-06)
  //
  // a) Align(alignment: Alignment.topLeft) must appear in buffer_screen.dart.
  // b) Positioned(top: 0, left: 0 must NOT appear (the retired twin-mirror
  //    pattern must not have crept in for this element).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'Gate 3 — FindBackPill via Align(topLeft), not Positioned(top:0,left:0) (TASK-06)',
    () {
      const bufferScreenPath = 'lib/presentation/editor/buffer_screen.dart';

      // ── red fixture: Positioned(top:0,left:0) pattern ────────────────────────
      group('fixture — FindBackPill mounted via Positioned(top:0,left:0)', () {
        const brokenSource = '''
if (findState.active)
  Positioned(
    top: 0,
    left: 0,
    child: FindBackPill(onClose: _closeFind),
  ),
''';

        test('fixture_contains_Positioned_top0_left0_proves_detector_fires', () {
          final pattern = RegExp(
            r'Positioned\(\s*top\s*:\s*0\s*,\s*left\s*:\s*0',
          );
          expect(
            pattern.hasMatch(brokenSource),
            isTrue,
            reason:
                'Broken fixture must contain Positioned(top:0,left:0) to prove '
                'the detector works.',
          );
        });
      });

      // ── green (a): Alignment.topLeft present ────────────────────────────────
      test('should_have_Alignment_topLeft_in_buffer_screen_dart', () {
        final file = File('$root/$bufferScreenPath');
        expect(
          file.existsSync(),
          isTrue,
          reason: '$bufferScreenPath must exist.',
        );

        var found = false;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (codePart.contains('Alignment.topLeft')) {
            found = true;
            break;
          }
        }
        expect(
          found,
          isTrue,
          reason:
              '$bufferScreenPath must contain `Alignment.topLeft` on a non-comment '
              'code line (FindBackPill is mounted via Align/Padding, not '
              'Positioned(top:0,left:0) — TASK-06).',
        );
      });

      // ── green (b): no Positioned(top:0,left:0) ──────────────────────────────
      test('should_have_NO_Positioned_top0_left0_in_buffer_screen_dart', () {
        final file = File('$root/$bufferScreenPath');
        expect(file.existsSync(), isTrue);

        final pattern = RegExp(
          r'Positioned\(\s*top\s*:\s*0\s*,\s*left\s*:\s*0',
        );
        final hits = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (pattern.hasMatch(codePart)) {
            hits.add('line ${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'No Positioned(top:0,left:0) must appear on code lines in '
              '$bufferScreenPath. FindBackPill must be mounted via '
              'Align(topLeft)+Padding with non-zero insets (TASK-06).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      });

      // ── additional fixture: Align+Padding pattern does NOT match Positioned ─
      group(
        'fixture — Align+Padding mount does not look like Positioned(top:0)',
        () {
          const goodSource = '''
if (findState.active)
  Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: EdgeInsets.only(top: kChromeTopGap + safeAreaTop, left: kChromeSideMargin),
      child: FindBackPill(onClose: _closeFind),
    ),
  ),
''';

          test('fixture_Align_Padding_does_not_match_Positioned_pattern', () {
            final pattern = RegExp(
              r'Positioned\(\s*top\s*:\s*0\s*,\s*left\s*:\s*0',
            );
            expect(
              pattern.hasMatch(goodSource),
              isFalse,
              reason:
                  'Align+Padding mount must NOT match the Positioned(top:0,left:0) '
                  'pattern — the two patterns are distinct.',
            );
          });
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 4. Zero Duration.zero on animated-property lines in buffer_screen.dart
  //    (TASK-06 morph slot)
  //
  // Lines that contain AnimatedAlign, AnimatedSize, AnimatedSwitcher, or
  // `duration:` together with `Duration.zero` are forbidden.
  // The reduce-motion fallback must use Duration(milliseconds: 1), never
  // Duration.zero (RenderAnimatedSize asserts on zero duration).
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 4 — zero Duration.zero on animated-property lines (TASK-06)', () {
    const bufferScreenPath = 'lib/presentation/editor/buffer_screen.dart';

    // ── red fixture: Duration.zero on an animated widget line ────────────────
    group('fixture — AnimatedSize with Duration.zero', () {
      const brokenSource = '''
AnimatedSize(
  duration: Duration.zero,
  child: collapsedChild,
),
''';

      test('fixture_contains_Duration_zero_proves_scan_fires', () {
        final hasDurationZero = brokenSource
            .split('\n')
            .any(
              (l) =>
                  !_isCommentLine(l) &&
                  (l.contains('AnimatedAlign') ||
                      l.contains('AnimatedSize') ||
                      l.contains('AnimatedSwitcher') ||
                      l.contains('duration:')) &&
                  l.contains('Duration.zero'),
            );
        expect(
          hasDurationZero,
          isTrue,
          reason:
              'Broken fixture must have Duration.zero on an animation-related '
              'line to prove the scan is meaningful.',
        );
      });
    });

    // ── green: no Duration.zero on animated lines ────────────────────────────
    test(
      'should_have_zero_Duration_zero_on_animated_property_lines_in_buffer_screen',
      () {
        final file = File('$root/$bufferScreenPath');
        expect(
          file.existsSync(),
          isTrue,
          reason: '$bufferScreenPath must exist.',
        );

        final animatedTokens = [
          'AnimatedAlign',
          'AnimatedSize',
          'AnimatedSwitcher',
          'duration:',
        ];
        final hits = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          final hasAnimated = animatedTokens.any(
            (tok) => codePart.contains(tok),
          );
          if (hasAnimated && codePart.contains('Duration.zero')) {
            hits.add('line ${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          hits,
          isEmpty,
          reason:
              'No `Duration.zero` must appear on lines containing animated-widget '
              'tokens in $bufferScreenPath. The reduce-motion fallback must use '
              'Duration(milliseconds: 1) to avoid RenderAnimatedSize assertion '
              '(TASK-06 morph-slot reduce-motion contract).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 5. Exactly one find_search_bar_test.dart under test/ (G8 consolidation)
  //
  // After the G8 consolidation, the old test/find/find_search_bar_test.dart
  // must be deleted. Only test/presentation/find/find_search_bar_test.dart
  // must remain.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 5 — exactly one find_search_bar_test.dart under test/ (G8)', () {
    // ── scan test/ for all find_search_bar_test.dart files ──────────────────
    test('should_have_exactly_one_find_search_bar_test_dart_under_test', () {
      final testDir = Directory('$root/test');
      expect(
        testDir.existsSync(),
        isTrue,
        reason: 'test/ directory must exist.',
      );

      final files = testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('find_search_bar_test.dart'))
          .toList();

      expect(
        files,
        hasLength(1),
        reason:
            'Exactly ONE find_search_bar_test.dart must exist under test/ '
            '(G8 consolidation: test/find/find_search_bar_test.dart must be '
            'deleted; only test/presentation/find/find_search_bar_test.dart '
            'must remain).\n'
            'Found ${files.length} file(s):\n'
            '${files.map((f) => f.path).join('\n')}',
      );

      // And it must be the canonical location.
      expect(
        files.first.path,
        contains('presentation/find/find_search_bar_test.dart'),
        reason:
            'The surviving find_search_bar_test.dart must be at '
            'test/presentation/find/find_search_bar_test.dart '
            '(not the retired test/find/ location).',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 6. findProvider.notifier).close() literal count == 2 in buffer_screen.dart
  //    (NFR-07)
  //
  // Two call sites are the verified baseline (CloseFindAction + _EscPrecedenceAction).
  // FindBackPill dispatches CloseFindIntent — it adds ZERO new close() literals.
  // Gate asserts the count remains exactly 2 after TASK-06.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 6 — findProvider.notifier).close() count == 2 (NFR-07)', () {
    const bufferScreenPath = 'lib/presentation/editor/buffer_screen.dart';

    // ── red fixture: three close() call sites ────────────────────────────────
    group('fixture — three findProvider.notifier).close() sites', () {
      const brokenSources = [
        '  ref.read(findProvider.notifier).close(); // site 1',
        '  ref.read(findProvider.notifier).close(); // site 2',
        '  ref.read(findProvider.notifier).close(); // site 3 — extra',
      ];

      test(
        'fixture_has_three_close_calls_proves_detector_catches_count_three',
        () {
          const pattern = 'findProvider.notifier).close()';
          final count = brokenSources
              .where((l) => !_isCommentLine(l) && l.contains(pattern))
              .length;
          expect(
            count,
            equals(3),
            reason:
                'Broken fixture must have 3 close() call sites to prove '
                'that a count != 2 is detectable.',
          );
        },
      );
    });

    // ── green: exactly 2 close() call sites ──────────────────────────────────
    test('should_have_exactly_2_close_call_sites_in_buffer_screen_dart', () {
      final file = File('$root/$bufferScreenPath');
      expect(
        file.existsSync(),
        isTrue,
        reason: '$bufferScreenPath must exist.',
      );

      const pattern = 'findProvider.notifier).close()';
      final hits = <String>[];
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_isCommentLine(lines[i])) continue;
        final commentIdx = lines[i].indexOf('//');
        final codePart = commentIdx >= 0
            ? lines[i].substring(0, commentIdx)
            : lines[i];
        if (codePart.contains(pattern)) {
          hits.add('line ${i + 1}: ${lines[i].trim()}');
        }
      }

      // Verified baseline: exactly 2 call sites.
      //   1. CloseFindAction (the keyboard-shortcut + Esc handler).
      //   2. _EscPrecedenceAction (the precedence-chain handler).
      // FindBackPill dispatches CloseFindIntent — zero new close() literals.
      expect(
        hits,
        hasLength(2),
        reason:
            'Exactly TWO `findProvider.notifier).close()` call sites must exist '
            'in $bufferScreenPath (NFR-07). FindBackPill must NOT add a third '
            'call site — it dispatches CloseFindIntent instead.\n'
            'Found ${hits.length} site(s):\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 7. Regression: zero raw hex-color literals on non-comment code lines (OQ-16)
  //
  // Mirror of Gate-2 in sp_20260617_gate_test.dart. Ensures the SP-20260618
  // wave has not introduced any new #XXXXXX hex literals on code lines.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 7 — hex-literal regression: 0 on non-comment lines (OQ-16)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — bare #3584E4 hex on a code line', () {
      const brokenLine =
          "  static const Color _accent = Color.fromHex('#3584E4');";

      test('fixture_contains_hash_hex_literal_proves_scan_fires', () {
        expect(
          RegExp(r'#[0-9a-fA-F]{6}').hasMatch(brokenLine),
          isTrue,
          reason: 'Broken fixture must contain a #XXXXXX literal.',
        );
      });
    });

    // ── green: real lib/ — zero #XXXXXX on code lines ───────────────────────
    test('should_have_zero_hash_hex_literals_on_non_comment_code_lines', () {
      final pattern = RegExp(r'#[0-9a-fA-F]{6}');
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_isCommentLine(lines[i])) continue;
          final commentIdx = lines[i].indexOf('//');
          final codePart = commentIdx >= 0
              ? lines[i].substring(0, commentIdx)
              : lines[i];
          if (pattern.hasMatch(codePart)) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'Zero #XXXXXX hex literals on non-comment code lines in lib/. '
            'All colours must use Color(0xFF…) — regression guard (OQ-16).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 8. Regression: BottomToolbar is Ref-free (OQ-16)
  //
  // Mirror of Gate-7 in sp_20260617_gate_test.dart. SP-20260618 must not have
  // accidentally added Riverpod wiring back into bottom_toolbar.dart.
  // ────────────────────────────────────────────────────────────────────────────

  group('Gate 8 — BottomToolbar Ref-free regression (OQ-16)', () {
    const bottomToolbarPath = 'lib/presentation/shell/bottom_toolbar.dart';

    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — toolbar with ref.watch', () {
      const brokenSource = '''
class BottomToolbar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(chromeVisibilityProvider);
    return v ? Row() : SizedBox.shrink();
  }
}
''';

      test('fixture_contains_ConsumerWidget_ref_watch_proves_scan_works', () {
        expect(brokenSource.contains('ConsumerWidget'), isTrue);
        expect(brokenSource.contains('ref.watch'), isTrue);
      });
    });

    // ── green: real bottom_toolbar.dart — zero Ref symbols ──────────────────
    test('should_have_zero_Ref_symbols_in_bottom_toolbar_dart', () {
      final file = File('$root/$bottomToolbarPath');
      expect(
        file.existsSync(),
        isTrue,
        reason: '$bottomToolbarPath must exist.',
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
        for (final tok in forbidden) {
          if (codePart.contains(tok)) {
            hits.add('${file.path}:${i + 1} [$tok]: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'bottom_toolbar.dart must remain Ref-free. No Riverpod symbols '
            'on code lines (OQ-16 regression guard).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });
}
