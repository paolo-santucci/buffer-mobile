// BufferApp — MaterialApp shell (TASK-16: ConsumerWidget + themeModeProvider
//             + real screen routes; TASK-11 M2/M5 lifecycle host wrap)
//
// Spec refs: FR-05, FR-M2-01, FR-M2-02, EC-M2-14, NFR-04, NFR-05, §4.1
//            FR-M5-05, FR-M5-17
//            FR-M6-03, FR-M6-09, FR-M6-10, FR-M6-23, EC-08
// Canon ref: .claude/docs/canon/ui-design-bible.md
//   §Design ethos   — content-is-everything; no chrome at rest
//   §Components §1  — App shell: Adw.ToolbarView + Overlay stack
//
// Compliance notes:
//   - Route '/' renders BufferScreen — chrome-free full-bleed editor,
//     satisfying canon §Design ethos and §Components §1.
//   - Route '/recovery' renders RecoveryScreen (TASK-11 M5, FR-M5-05).
//   - Route '/settings' renders SettingsScreen (TASK-16, FR-M6-09).
//   - Route '/about' renders AboutScreen (TASK-16, FR-M6-10).
//   - NO literal user-facing strings in this file — only AppLocalizations keys
//     (NFR-04). The only string is `appTitle` via l10n.
//   - ThemeMode is derived from themeModeProvider (EC-08: never requireValue;
//     falls back to ThemeMode.system under AsyncLoading).
//   - LifecycleBufferHost is mounted via MaterialApp.builder so it wraps ALL
//     routed content ABOVE the Navigator and never unmounts on route changes
//     (EC-M2-14, OQ-M2-03).
//
// <!-- CANON GAP: The canon §Components §1 "App shell" specifies a Stack-based
//      Overlay (editor + chrome overlay + toast). That structure belongs to
//      the editor screen (TASK-12). This file provides only the MaterialApp
//      skeleton shell that wraps it. No chrome is added here per canon
//      §Design ethos. -->

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/about/about_screen.dart';
import 'package:foglietto/presentation/editor/buffer_screen.dart';
import 'package:foglietto/presentation/lifecycle/lifecycle_buffer_host.dart';
import 'package:foglietto/presentation/recovery/recovery_screen.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';
import 'package:foglietto/presentation/settings/settings_screen.dart';
import 'package:foglietto/presentation/theme/app_theme.dart';

/// Root widget of the application.
///
/// [navigatorKey] is optional; tests pass a [GlobalKey<NavigatorState>] to
/// drive route assertions imperatively.  Production callers omit it.
///
/// Extends [ConsumerWidget] to wire [MaterialApp.themeMode] to
/// [themeModeProvider] (FR-M6-03, EC-08 — no [requireValue] usage).
class BufferApp extends ConsumerWidget {
  const BufferApp({super.key, this.navigatorKey});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // EC-08: themeModeProvider already guards against AsyncLoading via
    // `state.value ?? const AppSettings()` — always yields a ThemeMode.
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      // -----------------------------------------------------------------------
      // Theming — canon §Colour §Scheme matrix:
      //   light  → AppTheme.light()   (#fff surface, #f6d32d brand)
      //   dark   → AppTheme.dark()    (#202020 surface, #873000 brand)
      //   Follow = ThemeMode.system   (the upstream gschema default)
      // themeMode is derived from themeModeProvider (FR-M6-03, EC-08).
      // -----------------------------------------------------------------------
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,

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
      // Route table (FR-05, FR-M2-01, FR-M5-05, FR-M6-09, FR-M6-10).
      //
      // Named routes:
      //   "/"          — buffer editor (BufferScreen, TASK-11/M2)
      //   "/recovery"  — recovery list (RecoveryScreen, TASK-11/M5)
      //   "/settings"  — settings screen (SettingsScreen, TASK-16/M6)
      //   "/about"     — about screen (AboutScreen, TASK-16/M6)
      //
      // Canon §Design ethos: no chrome is added at '/'; the editor is
      // chrome-free at rest.
      // -----------------------------------------------------------------------
      routes: {
        '/': (_) => const BufferScreen(),
        '/recovery': (_) => const RecoveryScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/about': (_) => const AboutScreen(),
      },
      // Fallback for any route not in the table — prevents a crash on an
      // unregistered path (FR-05 negative).
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: SizedBox.shrink()),
      ),
      initialRoute: '/',
    );
  }
}
