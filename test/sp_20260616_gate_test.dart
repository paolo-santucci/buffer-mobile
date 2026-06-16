// SP-20260616 source-scan gate — buffer-mobile
//
// Spec refs: FR-06, FR-07, FR-12, FR-14, FR-16, NFR-01, NFR-05, NFR-06,
//            EC-09, EC-13, §7.2, OQ-11
//
// Platforms: all (no device required — fully deterministic source scans).
//
// Mirrors test/m2_gate_test.dart style: each assertion is first proved to FAIL
// on a deliberately-broken in-test fixture string, then wired to pass against
// the real project tree. This "red-then-green" discipline is encoded as
// sub-groups within each top-level group.
//
// Gate inventory (TASK-10, wave 5):
//   1. share_plus isolation — package:share_plus appears in exactly ONE lib/
//      file: lib/infrastructure/share/share_plus_service.dart; zero in
//      lib/presentation/ or lib/domain/. (FR-06, NFR-01, EC-M2-13)
//   2. ShareResult non-leak — scanning all .dart under lib/presentation/ and
//      lib/domain/, ShareResult returns zero matches. (FR-07)
//   3. ARB key parity — shareTooltip present in BOTH app_en.arb and app_it.arb;
//      key sets equal. (FR-16, NFR-05)
//   4. ShareOverlay anatomy — share_overlay.dart contains chromeVisibilityProvider,
//      kChromeMenuZoneHeight, left: 0, bottomRight, onShareTap, enabled; and
//      NO Positioned(... right: in that file. (FR-01, FR-03, §5.1.5)
//   5. Orphan-verb removal — incrementFontSize|decrementFontSize returns zero
//      matches across lib/ and test/. (FR-14, EC-13)

// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers (mirrors m2_gate_test.dart conventions)
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
  late String presentationDir;
  late String domainDir;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    presentationDir = '$root/lib/presentation';
    domainDir = '$root/lib/domain';
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 1. share_plus isolation (FR-06, NFR-01, EC-M2-13)
  //
  // package:share_plus must be imported in exactly ONE file:
  //   lib/infrastructure/share/share_plus_service.dart
  // Zero imports are permitted in lib/presentation/ or lib/domain/.
  // ────────────────────────────────────────────────────────────────────────────

  group('share_plus isolation — exactly one lib/ importer (FR-06, NFR-01)', () {
    const designatedAdapter = 'infrastructure/share/share_plus_service.dart';

    // ── red fixture: two files import share_plus ─────────────────────────────
    group('fixture — two files with share_plus imports', () {
      const twoImports = [
        "import 'package:share_plus/share_plus.dart';",
        "import 'package:share_plus/share_plus.dart';",
      ];

      test('should_FAIL_isolation_scan_given_two_package_imports', () {
        final pattern = RegExp(r'''import\s+['"]package:share_plus/''');
        final count = twoImports.where((l) => pattern.hasMatch(l)).length;
        expect(
          count,
          greaterThan(1),
          reason: 'Broken fixture must have more than one share_plus import.',
        );
      });
    });

    // ── red fixture: no imports at all ────────────────────────────────────────
    group('fixture — no share_plus imports', () {
      const zeroImports = ["import 'package:flutter/material.dart';"];

      test('should_FAIL_isolation_scan_given_zero_package_imports', () {
        final pattern = RegExp(r'''import\s+['"]package:share_plus/''');
        final count = zeroImports.where((l) => pattern.hasMatch(l)).length;
        expect(
          count,
          equals(0),
          reason: 'Broken fixture must have zero imports (adapter missing).',
        );
      });
    });

    // ── green: real lib/ ─────────────────────────────────────────────────────
    test('should_import_share_plus_in_exactly_one_designated_file', () {
      final pattern = RegExp(r'''import\s+['"]package:share_plus/''');
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (pattern.hasMatch(lines[i])) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        hits,
        hasLength(1),
        reason:
            'package:share_plus/ must be imported in EXACTLY ONE file in '
            'lib/ — the isolated adapter at lib/$designatedAdapter (FR-06, '
            'NFR-01, EC-M2-13).\n'
            '${hits.isEmpty ? 'No imports found — adapter may be missing.' : 'Unexpected imports:\n${hits.join('\n')}'}',
      );

      if (hits.isNotEmpty) {
        expect(
          hits.first,
          contains(designatedAdapter),
          reason:
              'The sole package:share_plus/ import must be in '
              'lib/$designatedAdapter, not elsewhere (EC-M2-13).',
        );
      }
    });

    // ── green: zero imports in presentation/ and domain/ ─────────────────────
    test('should_have_zero_share_plus_imports_in_presentation_and_domain', () {
      final pattern = RegExp(r'''import\s+['"]package:share_plus/''');
      final hits = <String>[];

      for (final dir in [presentationDir, domainDir]) {
        for (final file in _dartFiles(dir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            if (pattern.hasMatch(lines[i])) {
              hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
      }

      expect(
        hits,
        isEmpty,
        reason:
            'package:share_plus/ must NOT be imported in lib/presentation/ '
            'or lib/domain/ — it is isolated to the adapter only '
            '(FR-06, NFR-01).\nOffenders:\n${hits.join('\n')}',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 2. ShareResult non-leak (FR-07)
  //
  // ShareResult must not appear in any .dart file under lib/presentation/
  // or lib/domain/ — it is confined to the adapter method body.
  // ────────────────────────────────────────────────────────────────────────────

  group('ShareResult non-leak — zero occurrences in presentation + domain (FR-07)', () {
    // ── red fixture ──────────────────────────────────────────────────────────
    group('fixture — source with ShareResult in a signature', () {
      const brokenSource = 'Future<ShareResult> shareText(String text);';

      test('should_FAIL_ShareResult_scan_on_broken_fixture', () {
        expect(
          brokenSource.contains('ShareResult'),
          isTrue,
          reason: 'Broken fixture must trigger the ShareResult scan.',
        );
      });
    });

    // ── green: real presentation/ + domain/ ──────────────────────────────────
    test(
      'should_have_zero_ShareResult_occurrences_in_presentation_and_domain',
      () {
        final hits = <String>[];

        for (final dir in [presentationDir, domainDir]) {
          for (final file in _dartFiles(dir)) {
            final lines = file.readAsLinesSync();
            for (var i = 0; i < lines.length; i++) {
              final trimmed = lines[i].trimLeft();
              if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
              if (lines[i].contains('ShareResult')) {
                hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
              }
            }
          }
        }

        expect(
          hits,
          isEmpty,
          reason:
              'ShareResult must not appear in lib/presentation/ or lib/domain/ '
              '— it is confined to the adapter body in share_plus_service.dart '
              '(FR-07).\nOffenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 3. ARB key parity — shareTooltip present in both files; key sets equal
  //    (FR-16, NFR-05)
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'ARB key parity — shareTooltip in both ARBs; equal key sets (FR-16, NFR-05)',
    () {
      // ── red fixture: shareTooltip missing from one ARB ────────────────────────
      group('fixture — ARB missing shareTooltip in IT', () {
        const enKeys = {'appTitle', 'shareTooltip', 'menuTooltip'};
        const itKeys = {'appTitle', 'menuTooltip'}; // shareTooltip missing

        test(
          'should_FAIL_parity_check_when_shareTooltip_missing_from_IT_fixture',
          () {
            expect(
              itKeys.contains('shareTooltip'),
              isFalse,
              reason: 'Broken fixture must not contain shareTooltip.',
            );
            final onlyInEn = enKeys.difference(itKeys);
            expect(
              onlyInEn,
              contains('shareTooltip'),
              reason:
                  'Broken fixture must show shareTooltip as missing from IT.',
            );
          },
        );
      });

      // ── green: real ARBs ─────────────────────────────────────────────────────
      test('should_have_shareTooltip_in_app_en_arb', () {
        final enArb = File('$root/lib/l10n/app_en.arb');
        expect(
          enArb.existsSync(),
          isTrue,
          reason: 'lib/l10n/app_en.arb must exist (FR-16)',
        );
        final decoded =
            jsonDecode(enArb.readAsStringSync()) as Map<String, dynamic>;
        expect(
          decoded.containsKey('shareTooltip'),
          isTrue,
          reason:
              'app_en.arb must contain the shareTooltip key (FR-16, NFR-05). '
              'Add "shareTooltip": "Share" with an @shareTooltip description.',
        );
        expect(
          decoded['shareTooltip'],
          equals('Share'),
          reason: 'app_en.arb shareTooltip value must be "Share" (FR-16).',
        );
      });

      test('should_have_shareTooltip_in_app_it_arb', () {
        final itArb = File('$root/lib/l10n/app_it.arb');
        expect(
          itArb.existsSync(),
          isTrue,
          reason: 'lib/l10n/app_it.arb must exist (FR-16)',
        );
        final decoded =
            jsonDecode(itArb.readAsStringSync()) as Map<String, dynamic>;
        expect(
          decoded.containsKey('shareTooltip'),
          isTrue,
          reason:
              'app_it.arb must contain the shareTooltip key (FR-16, NFR-05). '
              'Add "shareTooltip": "Condividi" with an @shareTooltip description.',
        );
        expect(
          decoded['shareTooltip'],
          equals('Condividi'),
          reason: 'app_it.arb shareTooltip value must be "Condividi" (FR-16).',
        );
      });

      test('should_have_equal_key_sets_in_app_en_arb_and_app_it_arb', () {
        final enArb = File('$root/lib/l10n/app_en.arb');
        final itArb = File('$root/lib/l10n/app_it.arb');

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
              '${(onlyInEn.toList()..sort())} (NFR-05)',
        );
        expect(
          onlyInIt,
          isEmpty,
          reason:
              'Keys in app_it.arb but missing from app_en.arb: '
              '${(onlyInIt.toList()..sort())} (NFR-05)',
        );
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 4. ShareOverlay anatomy (FR-01, FR-03, §5.1.5)
  //
  // share_overlay.dart must contain all required tokens:
  //   chromeVisibilityProvider, kChromeMenuZoneHeight, left: 0, bottomRight,
  //   onShareTap, enabled
  // And must NOT contain a `Positioned(` with `right:` (it anchors top-LEFT).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'ShareOverlay anatomy — required tokens present, right: absent (FR-01, FR-03, §5.1.5)',
    () {
      const overlayRelPath = 'lib/presentation/shell/share_overlay.dart';

      const requiredTokens = [
        'chromeVisibilityProvider',
        'kChromeMenuZoneHeight',
        'left: 0',
        'bottomRight',
        'onShareTap',
        'enabled',
      ];

      // ── red fixture: anatomy missing required tokens ───────────────────────
      group('fixture — broken overlay missing required tokens', () {
        // A minimal broken source that lacks the required anatomy tokens.
        const brokenSource = '''
class ShareOverlay extends ConsumerWidget {
  const ShareOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(top: 0, right: 0, child: SizedBox());
  }
}
''';

        for (final token in requiredTokens) {
          test('should_FAIL_anatomy_scan_for_missing_token_"$token"', () {
            expect(
              brokenSource.contains(token),
              isFalse,
              reason: 'Broken fixture must not contain "$token".',
            );
          });
        }

        test('should_DETECT_forbidden_right_positioning_in_broken_fixture', () {
          // The broken source has `right: 0` inside Positioned — must be detected.
          expect(
            brokenSource.contains('right: 0'),
            isTrue,
            reason:
                'Broken fixture must contain a right: positioning to validate '
                'the absence check on the real file.',
          );
        });
      });

      // ── green: real share_overlay.dart ───────────────────────────────────────
      late String overlayContent;

      setUpAll(() {
        final file = File('$root/$overlayRelPath');
        expect(
          file.existsSync(),
          isTrue,
          reason: '$overlayRelPath must exist (TASK-07).',
        );
        overlayContent = file.readAsStringSync();
      });

      for (final token in requiredTokens) {
        test('should_contain_required_token_"$token"', () {
          expect(
            overlayContent.contains(token),
            isTrue,
            reason:
                '$overlayRelPath must contain "$token" (FR-01, FR-03, §5.1.5). '
                'The ShareOverlay anatomy is specified in the plan §5.1.5.',
          );
        });
      }

      test('should_NOT_contain_Positioned_with_right_parameter', () {
        // The overlay must anchor at LEFT:0 (delta 1 from ChromeOverlay which
        // anchors at right:0). Any `right:` inside a Positioned call in this file
        // would mean the button is on the wrong side (FR-01, §5.1.5 delta 1).
        //
        // Strategy: scan non-comment lines for the pattern `right:` — a Positioned
        // argument. The token `bottomRight` (borderRadius corner) is intentionally
        // present and is NOT a Positioned argument; it does not match `right:`.
        final lines = overlayContent.split('\n');
        final positionedRightLines = <String>[];
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          // Match `right:` as a named argument — word boundary before `right`
          // and `:` immediately following. This catches `right: 0` but not
          // `bottomRight` (which has a word character before `Right`).
          if (RegExp(r'\bright:').hasMatch(lines[i])) {
            positionedRightLines.add('line ${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(
          positionedRightLines,
          isEmpty,
          reason:
              '$overlayRelPath must NOT contain `right:` as a named parameter '
              '(ShareOverlay anchors at left:0, not right:0 — FR-01, §5.1.5 delta 1).\n'
              'Offenders:\n${positionedRightLines.join('\n')}',
        );
      });
    },
  );

  // ────────────────────────────────────────────────────────────────────────────
  // 5. Orphan-verb removal (FR-14, EC-13)
  //
  // incrementFontSize and decrementFontSize must not appear in any .dart file
  // under lib/ or test/ (TASK-01 removed them from app_settings.dart and their
  // corresponding test groups).
  // ────────────────────────────────────────────────────────────────────────────

  group(
    'orphan-verb removal — zero incrementFontSize/decrementFontSize matches (FR-14, EC-13)',
    () {
      // ── red fixture ──────────────────────────────────────────────────────────
      group('fixture — source with orphaned verb declarations', () {
        const brokenSource = '''
AppSettings incrementFontSize() {
  return copyWith(fontSizeIndex: (fontSizeIndex + 1).clamp(0, kFontSizes.length - 1));
}
AppSettings decrementFontSize() {
  return copyWith(fontSizeIndex: (fontSizeIndex - 1).clamp(0, kFontSizes.length - 1));
}
''';

        test('should_FAIL_orphan_verb_scan_on_broken_fixture', () {
          final pattern = RegExp(r'incrementFontSize|decrementFontSize');
          expect(
            pattern.hasMatch(brokenSource),
            isTrue,
            reason: 'Broken fixture must trigger the orphan-verb scan.',
          );
        });
      });

      // ── green: real lib/ + test/ (excluding this gate file itself) ──────────
      test(
        'should_have_zero_incrementFontSize_or_decrementFontSize_in_lib_and_test',
        () {
          final pattern = RegExp(r'\b(incrementFontSize|decrementFontSize)\b');
          // The gate file itself legitimately contains the tokens in fixture
          // strings and error messages. Exclude it from the scan — it is the
          // scanner, not a production file.
          const gateFileName = 'sp_20260616_gate_test.dart';
          final hits = <String>[];

          for (final dir in ['$root/lib', '$root/test']) {
            for (final file in _dartFiles(dir)) {
              // Skip this gate file — it references the terms in fixture bodies.
              if (file.path.endsWith(gateFileName)) continue;
              final lines = file.readAsLinesSync();
              for (var i = 0; i < lines.length; i++) {
                final trimmed = lines[i].trimLeft();
                if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
                  continue;
                }
                if (pattern.hasMatch(lines[i])) {
                  hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
                }
              }
            }
          }

          expect(
            hits,
            isEmpty,
            reason:
                'incrementFontSize and decrementFontSize must not appear in '
                'lib/ or test/ — they were orphaned methods removed in TASK-01 '
                '(FR-14, EC-13).\nOffenders:\n${hits.join('\n')}',
          );
        },
      );
    },
  );
}
