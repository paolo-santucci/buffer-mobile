// BufferApp — MaterialApp skeleton (TASK-16)
//
// Spec refs: FR-05, NFR-04, NFR-05
// Canon ref: .claude/docs/canon/ui-design-bible.md
//   §Design ethos   — content-is-everything; no chrome at rest
//   §Components §1  — App shell: Adw.ToolbarView + Overlay stack
//
// Compliance notes:
//   - All route placeholder bodies are const empty surfaces (SizedBox.shrink),
//     matching the canon §Components §1 mandate that M2–M6 fill the shell.
//   - NO literal user-facing strings in this file — only AppLocalizations keys
//     are used (NFR-04). The only string is `appTitle` via l10n.
//   - ThemeMode.system follows platform brightness by default, matching the
//     canon §Colour §Scheme matrix (Follow system is the gschema default).
//
// <!-- CANON GAP: The canon §Components §1 "App shell" specifies a Stack-based
//      Overlay (editor + chrome overlay + toast). That structure belongs to the
//      buffer editor screen (M2/TASK-2x). This file provides only the
//      MaterialApp skeleton shell that wraps it; M2–M6 tasks fill in the
//      content layer. No chrome is added here per canon §Design ethos. -->

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/theme/app_theme.dart';

/// Root widget of the application.
///
/// [navigatorKey] is optional; tests pass a [GlobalKey<NavigatorState>] to
/// drive route assertions imperatively.  Production callers omit it.
class BufferApp extends StatelessWidget {
  const BufferApp({super.key, this.navigatorKey});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // -----------------------------------------------------------------------
      // Theming — canon §Colour §Scheme matrix:
      //   light  → AppTheme.light()   (#fff surface, #f6d32d brand)
      //   dark   → AppTheme.dark()    (#202020 surface, #873000 brand)
      //   Follow = ThemeMode.system   (the upstream gschema default)
      // -----------------------------------------------------------------------
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,

      // -----------------------------------------------------------------------
      // Localisation — NFR-04 / TASK-09 ARBs (en + it)
      // All user-facing strings route through AppLocalizations.
      // -----------------------------------------------------------------------
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,

      // -----------------------------------------------------------------------
      // Navigator key — optional seam for widget tests.
      // -----------------------------------------------------------------------
      navigatorKey: navigatorKey,

      // -----------------------------------------------------------------------
      // Route table (FR-05).
      //
      // Each placeholder renders a const empty surface per canon §Components §1:
      // "content-is-everything; no chrome beyond the shell container that M2–M6
      // fill."  The Scaffold body is SizedBox.shrink() — zero pixels, no chrome.
      //
      // Named routes:
      //   "/"          — buffer editor (M2)
      //   "/recovery"  — recovery list (M3)
      //   "/settings"  — settings screen (M5)
      //   "/about"     — about screen (M5)
      // -----------------------------------------------------------------------
      routes: {
        '/': (_) => const _EmptyScreen(),
        '/recovery': (_) => const _EmptyScreen(),
        '/settings': (_) => const _EmptyScreen(),
        '/about': (_) => const _EmptyScreen(),
      },
      // Fallback for any route not in the table — prevents a crash on an
      // unregistered path (FR-05 negative).
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const _EmptyScreen(),
      ),
      initialRoute: '/',
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder screen — used by every route until M2–M6 fill it.
//
// Canon §Components §1: "content-is-everything; no chrome beyond the shell
// container that M2–M6 fill."  The body is intentionally empty.
// No user-facing strings are used here (NFR-04).
// ---------------------------------------------------------------------------
class _EmptyScreen extends StatelessWidget {
  const _EmptyScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}
