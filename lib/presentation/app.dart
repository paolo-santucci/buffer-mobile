// BufferApp — MaterialApp shell (TASK-16, updated TASK-11)
//
// Spec refs: FR-05, FR-M2-01, FR-M2-02, EC-M2-14, NFR-04, NFR-05, §4.1
// Canon ref: .claude/docs/canon/ui-design-bible.md
//   §Design ethos   — content-is-everything; no chrome at rest
//   §Components §1  — App shell: Adw.ToolbarView + Overlay stack
//
// Compliance notes:
//   - Route '/' now renders BufferScreen (TASK-11) — chrome-free full-bleed
//     editor, satisfying canon §Design ethos and §Components §1.
//   - Routes '/recovery', '/settings', '/about' remain on _EmptyScreen until
//     M3/M5 fill them.
//   - NO literal user-facing strings in this file — only AppLocalizations keys
//     (NFR-04). The only string is `appTitle` via l10n.
//   - ThemeMode.system follows platform brightness by default, matching
//     canon §Colour §Scheme matrix (Follow system is the gschema default).
//   - LifecycleBufferHost is mounted via MaterialApp.builder so it wraps ALL
//     routed content ABOVE the Navigator and never unmounts on route changes
//     (EC-M2-14, OQ-M2-03).
//
// <!-- CANON GAP: The canon §Components §1 "App shell" specifies a Stack-based
//      Overlay (editor + chrome overlay + toast). That structure belongs to
//      the editor screen and later milestones. This file provides only the
//      MaterialApp skeleton shell that wraps it; M3–M6 tasks fill the
//      content layer. No chrome is added here per canon §Design ethos. -->

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/lifecycle/lifecycle_buffer_host.dart';
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
      // builder: wraps ALL routed content above the Navigator (EC-M2-14,
      // OQ-M2-03). LifecycleBufferHost registers as a WidgetsBindingObserver
      // and must survive route changes — mounting it here guarantees it is
      // never unmounted by a route push or pop.
      // -----------------------------------------------------------------------
      builder: (context, child) =>
          LifecycleBufferHost(child: child ?? const SizedBox.shrink()),

      // -----------------------------------------------------------------------
      // Route table (FR-05, FR-M2-01).
      //
      // Named routes:
      //   "/"          — buffer editor (BufferScreen, TASK-11/M2)
      //   "/recovery"  — recovery list (M3 — placeholder)
      //   "/settings"  — settings screen (M5 — placeholder)
      //   "/about"     — about screen (M5 — placeholder)
      //
      // Canon §Design ethos: no chrome is added at '/'; the editor is
      // chrome-free at rest.  Placeholder routes use _EmptyScreen
      // (SizedBox.shrink body) until M3–M5 fill them.
      // -----------------------------------------------------------------------
      routes: {
        '/': (_) => const BufferScreen(),
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
