// TASK-11 (M6): AboutScreen widget tests — TDD red phase written first.
//
// Spec refs: FR-M6-10, FR-M6-11, EC-03, EC-10, NFR-M6-06
// Canon ref: .claude/docs/canon/ui-design-bible.md
//
// Strategy: inject PackageInfoSeam + UrlLauncherSeam fakes so real platform
// channels are never hit in widget tests.
//
// Upstream URLs (from canon/spec/appearance-and-shell.md §51):
//   issue tracker: https://gitlab.gnome.org/cheywood/buffer/-/issues
//   website:       https://gitlab.gnome.org/cheywood/buffer/
//
// All tests expected to fail (red) until lib/presentation/about/about_screen.dart
// is implemented.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/about/about_screen.dart';

// ---------------------------------------------------------------------------
// Fake seams
// ---------------------------------------------------------------------------

class _FakePackageInfoSeam implements PackageInfoSeam {
  const _FakePackageInfoSeam({required this.version});

  final String version;

  @override
  Future<String> appVersion() async => version;
}

class _FakeLauncherSeam implements UrlLauncherSeam {
  _FakeLauncherSeam({required this.enabled});

  final bool enabled;
  final List<Uri> launched = [];

  @override
  Future<bool> canLaunch(Uri uri) async => enabled;

  @override
  Future<void> launch(Uri uri) async {
    launched.add(uri);
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Pumps [AboutScreen] wrapped in a minimal app that loads the given locale.
Future<void> _pumpAboutScreen(
  WidgetTester tester, {
  required PackageInfoSeam packageInfoSeam,
  required UrlLauncherSeam launcherSeam,
  String localeCode = 'en',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(localeCode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('it')],
      home: AboutScreen(
        packageInfoSeam: packageInfoSeam,
        launcherSeam: launcherSeam,
      ),
    ),
  );
  // Allow the async FutureBuilder (version load) to complete.
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AboutScreen', () {
    // -------------------------------------------------------------------------
    // 1. Happy-path: all metadata rendered correctly
    // -------------------------------------------------------------------------
    testWidgets(
      'renders app name, developer, version, GPL-3.0, issues label, website label '
      '(version 1.2.3)',
      (tester) async {
        await _pumpAboutScreen(
          tester,
          packageInfoSeam: const _FakePackageInfoSeam(version: '1.2.3'),
          launcherSeam: _FakeLauncherSeam(enabled: true),
        );

        // App name "Buffer" from ARB aboutTitle (or as literal name row).
        expect(find.text('Buffer'), findsAtLeastNWidgets(1));

        // Developer name — aboutDeveloper ARB key resolves to 'Chris Heywood'.
        expect(find.text('Chris Heywood'), findsOneWidget);

        // Version: '1.2.3' appears somewhere on screen.
        expect(find.textContaining('1.2.3'), findsOneWidget);

        // License: GPL-3.0 — must come from aboutLicense ARB, not a literal.
        // The ARB value is 'GPL-3.0', so the text 'GPL-3.0' must appear.
        expect(find.text('GPL-3.0'), findsOneWidget);

        // Issues row — aboutIssues ARB label ('Report an issue').
        expect(find.text('Report an issue'), findsOneWidget);

        // Website row — aboutWebsite ARB label ('Website').
        expect(find.text('Website'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // 2. EC-10: empty version renders without throwing; other fields present
    // -------------------------------------------------------------------------
    testWidgets(
      'EC-10: empty version — renders without throw; other rows visible',
      (tester) async {
        await _pumpAboutScreen(
          tester,
          packageInfoSeam: const _FakePackageInfoSeam(version: ''),
          launcherSeam: _FakeLauncherSeam(enabled: true),
        );

        // No exception — if we reach here, EC-10 is satisfied.
        expect(find.text('Buffer'), findsAtLeastNWidgets(1));
        expect(find.text('Chris Heywood'), findsOneWidget);
        expect(find.text('GPL-3.0'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // 3. canLaunchUrl→true: tap website row → launchUrl called with correct URL
    // -------------------------------------------------------------------------
    testWidgets(
      'canLaunchUrl=true: tap website row → launchUrl called with correct URL',
      (tester) async {
        final launcher = _FakeLauncherSeam(enabled: true);

        await _pumpAboutScreen(
          tester,
          packageInfoSeam: const _FakePackageInfoSeam(version: '1.2.3'),
          launcherSeam: launcher,
        );

        await tester.tap(find.text('Website'));
        await tester.pumpAndSettle();

        expect(launcher.launched, hasLength(1));
        expect(
          launcher.launched.first.toString(),
          equals('https://buffer.paolosantucci.com/'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // 4. EC-03: canLaunchUrl→false → row disabled/no-op; no exception; rest renders
    // -------------------------------------------------------------------------
    testWidgets(
      'EC-03: canLaunchUrl=false — rows disabled, no exception, rest renders',
      (tester) async {
        final launcher = _FakeLauncherSeam(enabled: false);

        await _pumpAboutScreen(
          tester,
          packageInfoSeam: const _FakePackageInfoSeam(version: '1.2.3'),
          launcherSeam: launcher,
        );

        // Tapping the disabled website row must NOT throw and must NOT call launch.
        await tester.tap(find.text('Website'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(launcher.launched, isEmpty);

        // Other fields still rendered (screen as a whole is not broken).
        expect(find.text('Buffer'), findsAtLeastNWidgets(1));
        expect(find.text('GPL-3.0'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // 5. Italian locale: labels resolve from app_it.arb
    // -------------------------------------------------------------------------
    testWidgets('it locale: labels resolve from app_it.arb (not English)', (
      tester,
    ) async {
      await _pumpAboutScreen(
        tester,
        packageInfoSeam: const _FakePackageInfoSeam(version: '2.0.0'),
        launcherSeam: _FakeLauncherSeam(enabled: true),
        localeCode: 'it',
      );

      // IT translations for about keys:
      //   aboutTitle → 'Informazioni su Buffer'
      //   aboutIssues → 'Segnala un problema'
      //   aboutWebsite → 'Sito web'
      expect(find.text('Informazioni su Buffer'), findsOneWidget);
      expect(find.text('Segnala un problema'), findsOneWidget);
      expect(find.text('Sito web'), findsOneWidget);

      // Must NOT show English labels.
      expect(find.text('Report an issue'), findsNothing);
      expect(find.text('Website'), findsNothing);
    });
  });
}
