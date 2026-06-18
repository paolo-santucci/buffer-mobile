// M1 source-scan gate — buffer-mobile
//
// Spec refs: FR-07, FR-17, NFR-04, NFR-09, EC-08, EC-11, EC-12, MC-02, MC-03
//
// Enforces the source-level audits that are fully deterministic under
// `flutter test` (no device, no shell commands needed).  The complementary
// bash gate (tool/m1_gate.sh) adds the flutter-analyze / dart-format /
// print()-scan checks that require the Flutter toolchain at runtime.
//
// Test targets (platform: all):
//   1. Domain purity     — lib/domain/ has 0 `package:flutter/` imports   (FR-07)
//   2. Ephemerality      — lib/ has 0 `PageStorageKey` occurrences         (NFR-09/EC-08)
//   3. Share isolation   — receive_sharing_intent imported in EXACTLY ONE
//                          designated file (FR-17/EC-12)
//                          [§6 plan-change 2026-06-13: M1 "zero imports"
//                           relaxed to "one file" to accommodate TASK-03]
//   4. No literal Text() — lib/presentation/ has 0 `Text('…')` / `Text("…")`
//                          constructors with non-empty literals             (NFR-04)
//   5. ARB key parity    — app_en.arb and app_it.arb have identical key sets (EC-11/NFR-04)
//   6. Sign-off files    — D-001, D-002 + three §5.3 contracts exist       (MC-02/MC-03)

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
/// `flutter test` sets the working directory to the package root (the directory
/// containing `pubspec.yaml`), so `Directory.current` is the project root.
String get _root => Directory.current.path;

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  // Locate directories relative to the project root.
  late String root;
  late String libDir;
  late String domainDir;
  late String presentationDir;

  setUpAll(() {
    root = _root;
    libDir = '$root/lib';
    domainDir = '$root/lib/domain';
    presentationDir = '$root/lib/presentation';
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 1. Domain purity — no package:flutter/ imports in lib/domain/  (FR-07)
  // ──────────────────────────────────────────────────────────────────────────

  group('domain purity (FR-07)', () {
    test('should_have_zero_package_flutter_imports_in_lib_domain', () {
      final hits = <String>[];
      for (final file in _dartFiles(domainDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('package:flutter/')) {
            hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'lib/domain/ must be pure Dart — no package:flutter/ imports.\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. Ephemerality backstop — no PageStorageKey in lib/  (NFR-09/EC-08)
  // ──────────────────────────────────────────────────────────────────────────

  group('ephemerality backstop (NFR-09/EC-08)', () {
    test('should_have_zero_PageStorageKey_in_lib', () {
      final hits = <String>[];
      for (final file in _dartFiles(libDir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
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
            'and must not persist through Flutter page storage (NFR-09/EC-08).\n'
            'Offenders:\n${hits.join('\n')}',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. Share isolation — receive_sharing_intent imported in EXACTLY ONE
  // designated file (FR-17/EC-12)
  //
  // M1 assertion (zero imports in lib/) relaxed in §6 plan-change 2026-06-13:
  // TASK-03 (M2 Wave 1) legitimately added the isolated adapter at
  // lib/infrastructure/share/receive_sharing_intent_service.dart. Permitting
  // exactly one import in that file preserves the isolation contract while
  // allowing the M2 adapter to co-exist.  The M2 gate (m2_gate_test.dart)
  // carries the same EC-12 assertion.
  //
  // Comment references are allowed; only actual import statements are checked.
  // ──────────────────────────────────────────────────────────────────────────

  group('share isolation (FR-17/EC-12)', () {
    const designatedShareAdapterRelPath =
        'infrastructure/share/receive_sharing_intent_service.dart';

    test(
      'should_import_receive_sharing_intent_in_exactly_one_designated_file',
      () {
        // Match imports of the `receive_sharing_intent` pub package itself:
        //   import 'package:receive_sharing_intent/...'
        // This is distinct from imports of the buffer adapter file
        // (receive_sharing_intent_service.dart) which appear as
        //   import 'package:foglietto/infrastructure/share/...'
        // and must NOT be counted here.
        final packageImportPattern = RegExp(
          r'''import\s+['"]package:receive_sharing_intent/''',
        );
        final hits = <String>[];
        for (final file in _dartFiles(libDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            // Skip comment lines — the package name may legitimately appear in
            // doc comments (e.g. share_intent_service.dart header).
            final trimmed = line.trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
            if (packageImportPattern.hasMatch(line)) {
              hits.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }

        // Exactly one hit is expected — the designated adapter file.
        expect(
          hits,
          hasLength(1),
          reason:
              'package:receive_sharing_intent/ must be imported in EXACTLY ONE '
              'file in lib/ — the isolated adapter at '
              'lib/$designatedShareAdapterRelPath (FR-17/EC-12). '
              '${hits.isEmpty ? 'No imports found — adapter may be missing.' : 'Unexpected imports:\n${hits.join('\n')}'}',
        );

        if (hits.isNotEmpty) {
          expect(
            hits.first,
            contains(designatedShareAdapterRelPath),
            reason:
                'The sole package:receive_sharing_intent/ import must be in '
                'lib/$designatedShareAdapterRelPath, not elsewhere (EC-12).',
          );
        }
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. No literal Text() widgets in lib/presentation/  (NFR-04)
  //
  // Heuristic: any `Text('...')` or `Text("...")` with a non-empty string
  // literal is a violation.  ARB-lookup calls look like
  //   Text(AppLocalizations.of(context).someKey)
  // so they don't match the literal pattern.
  //
  // The pattern intentionally excludes:
  //   - Empty-string literals: Text('') — acceptable for structural widgets.
  //   - Text with a variable: Text(someVar) — no quotes.
  // ──────────────────────────────────────────────────────────────────────────

  group('no literal Text() widgets in presentation (NFR-04)', () {
    test(
      'should_have_zero_non_empty_literal_Text_constructors_in_lib_presentation',
      () {
        // Match Text(' at least one char ') or Text(" at least one char ").
        // We accept Text('') as structural; the empty-literal form has no user
        // content.
        final literalPattern = RegExp(r"""Text\(['"][^'"]+['"]\)""");
        final hits = <String>[];
        for (final file in _dartFiles(presentationDir)) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            // Skip comment lines.
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
              'lib/presentation/ must not contain Text("literal") or Text(\'literal\') '
              'with non-empty strings — all user-facing strings must go through '
              'AppLocalizations (NFR-04).\n'
              'Offenders:\n${hits.join('\n')}',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. ARB key parity — app_en.arb and app_it.arb have identical key sets
  // (EC-11/NFR-04)
  //
  // Metadata keys (prefixed with `@`) and `@@locale` are excluded.
  // ──────────────────────────────────────────────────────────────────────────

  group('ARB key parity (EC-11/NFR-04)', () {
    test('should_have_identical_key_sets_in_app_en_arb_and_app_it_arb', () {
      final enArb = File('$root/lib/l10n/app_en.arb');
      final itArb = File('$root/lib/l10n/app_it.arb');

      expect(
        enArb.existsSync(),
        isTrue,
        reason: 'lib/l10n/app_en.arb must exist (EC-11)',
      );
      expect(
        itArb.existsSync(),
        isTrue,
        reason: 'lib/l10n/app_it.arb must exist (EC-11)',
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
            'Keys present in app_en.arb but missing from app_it.arb: '
            '${onlyInEn.toList()..sort()} (EC-11)',
      );
      expect(
        onlyInIt,
        isEmpty,
        reason:
            'Keys present in app_it.arb but missing from app_en.arb: '
            '${onlyInIt.toList()..sort()} (EC-11)',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 6. Sign-off files present  (MC-02/MC-03)
  //
  // Confirms that all three §5.3 cross-cutting contracts and the two OQ
  // decision docs exist.  These are the inputs required for M1 sign-off.
  // ──────────────────────────────────────────────────────────────────────────

  group('sign-off inputs present (MC-02/MC-03)', () {
    // §5.3 source contracts — shipped in the repo, asserted unconditionally.
    const contractRelPaths = [
      'lib/domain/buffer/buffer_provider.dart',
      'lib/domain/buffer/buffer_notifier_impl.dart',
      'lib/presentation/editor/editor_controller.dart',
      'lib/infrastructure/paths/sandbox_path_provider.dart',
    ];

    for (final relPath in contractRelPaths) {
      test('should_exist_${relPath.replaceAll(RegExp(r'[/.]'), '_')}', () {
        final file = File('$root/$relPath');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Sign-off input missing: $relPath — required for M1 milestone '
              'sign-off (MC-02/MC-03).',
        );
      });
    }

    // OQ decision docs live under `.claude/`, which is gitignored (local
    // planning artifacts, not shipped product). They are present in the dev
    // working tree but absent from a clean CI checkout, so assert them only
    // when the decisions directory exists — strict locally, skipped in CI.
    const decisionRelPaths = [
      // OQ-14 resolution (D-001) — MC-03
      '.claude/docs/decisions/D-001-oq14-share-intent.md',
      // Who-owns-scrolling decision (D-002) — MC-02
      '.claude/docs/decisions/D-002-who-owns-scrolling.md',
    ];
    // Computed at collection time (before setUpAll), so use the _root getter
    // rather than the late `root` field, which is not yet initialized here.
    final decisionsDirPresent = Directory(
      '$_root/.claude/docs/decisions',
    ).existsSync();

    for (final relPath in decisionRelPaths) {
      test(
        'should_exist_${relPath.replaceAll(RegExp(r'[/.]'), '_')}',
        () {
          final file = File('$root/$relPath');
          expect(
            file.existsSync(),
            isTrue,
            reason:
                'Sign-off input missing: $relPath — required for M1 milestone '
                'sign-off (MC-02/MC-03).',
          );
        },
        skip: decisionsDirPresent
            ? false
            : '.claude/ is gitignored — decision docs unavailable in this '
                  'checkout (e.g. CI); local-only sign-off gate.',
      );
    }
  });
}
