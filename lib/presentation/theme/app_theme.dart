// AppTheme — light and dark ThemeData derived exclusively from UI Design Bible tokens.
//
// Spec refs: FR-01, FR-02, FR-03, FR-06, EC-14, NFR-01, NFR-03, NFR-05
// Canon source: .claude/docs/canon/ui-design-bible.md
//   §Colour & branding tokens (style.css, metainfo.xml)
//   §Typography tokens (style.css:11-14, editor_text_view.rs)
//
// Token → ThemeData mappings:
//   --view-bg-color  (light #fff / dark #202020)  → ColorScheme.surface
//   --accent-bg-color → ColorScheme.primary (M3-tonal from _brandSeed)
//   --border-color (platform-semantic)              → ColorScheme.outlineVariant
//   Typography line-height 1.4                      → TextTheme height on every style
//
// <!-- CANON GAP: blue re-brand diverges from ui-design-bible §Colour upstream Yellow3/Brown5;
//      UI-bible amendment pending (OQ-15) -->
//
// Sanctioned colour literals (the only THREE permitted after the blue re-brand):
//   #3584E4  → Color(0xFF3584E4)  — GNOME Adwaita "Blue 3", single seed for both schemes
//   #fff     → Color(0xFFFFFFFF)  — theme swatch / --view-bg-color light
//   #202020  → Color(0xFF202020)  — theme swatch / --view-bg-color dark

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // -------------------------------------------------------------------------
  // Sanctioned canon literals — the ONLY hard-coded colour values permitted.
  // Source: .claude/docs/canon/ui-design-bible.md §Colour & branding tokens
  // -------------------------------------------------------------------------

  /// `#3584E4` — GNOME Adwaita "Blue 3".  Single seed for both light and dark
  /// `ColorScheme.fromSeed` calls. [ColorScheme.primary]/[ColorScheme.onPrimary]
  /// are then pinned to this EXACT value + white (the literal Adwaita accent);
  /// M3 tonal derivation resolves only the remaining roles (primaryContainer,
  /// secondaryContainer, etc.) for a harmonised palette.
  ///
  /// <!-- CANON GAP: blue re-brand diverges from ui-design-bible §Colour upstream
  ///      Yellow3 (#f6d32d) / Brown5 (#873000); UI-bible amendment pending (OQ-15) -->
  ///
  /// Source: GNOME Adwaita palette; SP-plan TASK-03 / spec FR-01, NFR-03.
  static const Color _brandSeed = Color(0xFF3584E4);

  /// `#fff` — theme swatch "Light" fill; maps to `--view-bg-color` in light mode.
  /// Source: style.css:58-60; canon §Theme-swatch literal fills.
  static const Color _swatchLight = Color(0xFFFFFFFF);

  /// `#202020` — theme swatch "Dark" fill; maps to `--view-bg-color` in dark mode.
  /// Source: style.css:61-63; canon §Theme-swatch literal fills.
  static const Color _swatchDark = Color(0xFF202020);

  // -------------------------------------------------------------------------
  // --border-color derivation
  //
  // The canon defines --border-color as a libadwaita semantic token used for
  // hairline borders (swatch resting ring). The bible does NOT specify an exact
  // hex value — it is resolved at runtime by the platform theme. The values
  // below are the closest safe approximations derived from the Adwaita palette:
  //   light: a light grey separator (#DEDDDA — Adwaita "shade 1")
  //   dark:  a mid-grey separator (#3D3D3D — roughly midpoint in dark surface)
  //
  // <!-- CANON GAP: --border-color has no explicit hex in ui-design-bible.md.
  //      Value is libadwaita-semantic and platform-resolved at runtime.
  //      Using Adwaita-derived approximations (#DEDDDA light / #3D3D3D dark)
  //      until a concrete value is confirmed from the upstream theme palette.
  //      See .claude/docs/decisions/D-003-border-color-approximation.md -->
  static const Color _borderColorLight = Color(0xFFDEDDDA);
  static const Color _borderColorDark = Color(0xFF3D3D3D);

  // -------------------------------------------------------------------------
  // Canon line-height — style.css:11-14; mirrored in editor_text_view.rs
  // -------------------------------------------------------------------------
  static const double _lineHeight = 1.4;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Returns a light [ThemeData] whose colours and typography derive from
  /// the UI Design Bible tokens.
  ///
  /// Token mappings (light):
  ///   --view-bg-color  → [ColorScheme.surface]  = [_swatchLight] (#fff)
  ///   --accent-bg-color → [ColorScheme.primary] = M3-tonal from [_brandSeed] (#3584E4)
  ///   --border-color   → [ColorScheme.outlineVariant] = [_borderColorLight]
  ///   Typography line-height = 1.4
  ///
  /// The accent role [ColorScheme.primary] is pinned to the EXACT [_brandSeed]
  /// (#3584E4), not the M3-tonal derivation — a faithful GNOME port renders the
  /// literal Adwaita accent (libadwaita `@accent_bg_color`), with white text on
  /// top exactly as GNOME does. fromSeed still derives every other role
  /// (primaryContainer, secondaryContainer, etc.) for a harmonised palette.
  /// White-on-#3584E4 is 3.76:1 — clears WCAG AA for UI components (≥3:1), the
  /// standard for the accent's actual usage (buttons, cursor, selection).
  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _brandSeed,
          brightness: Brightness.light,
        ).copyWith(
          // --accent-bg-color: exact GNOME accent, white foreground
          primary: _brandSeed,
          onPrimary: _swatchLight,
          // --view-bg-color light (#fff)
          surface: _swatchLight,
          // --border-color (hairline ring)
          outlineVariant: _borderColorLight,
        );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.light,
      textTheme: _buildTextTheme(colorScheme.onSurface),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  /// Returns a dark [ThemeData] whose colours and typography derive from
  /// the UI Design Bible tokens.
  ///
  /// Token mappings (dark):
  ///   --view-bg-color  → [ColorScheme.surface]  = [_swatchDark] (#202020)
  ///   --accent-bg-color → [ColorScheme.primary] = M3-tonal from [_brandSeed] (#3584E4)
  ///   --border-color   → [ColorScheme.outlineVariant] = [_borderColorDark]
  ///   Typography line-height = 1.4
  ///
  /// The accent role [ColorScheme.primary] is pinned to the EXACT [_brandSeed]
  /// (#3584E4) in dark mode too — libadwaita keeps `@accent_bg_color` identical
  /// across light/dark, with white text on top. fromSeed still derives every
  /// other role for a harmonised dark palette. White-on-#3584E4 is 3.76:1 —
  /// clears WCAG AA for UI components (≥3:1).
  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _brandSeed,
          brightness: Brightness.dark,
        ).copyWith(
          // --accent-bg-color: exact GNOME accent, white foreground
          primary: _brandSeed,
          onPrimary: _swatchLight,
          // --view-bg-color dark (#202020)
          surface: _swatchDark,
          // --border-color (hairline ring) dark
          outlineVariant: _borderColorDark,
        );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      textTheme: _buildTextTheme(colorScheme.onSurface),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /// Applies the canon line-height of 1.4 to every [TextStyle] in the theme.
  ///
  /// Canon source: style.css:11-14 (`line-height: 1.4`) applied to
  /// `.editor-textview`; the bible mandates this globally for the editor
  /// text surface and as the default typography line-height.
  static TextTheme _buildTextTheme(Color onSurface) {
    return TextTheme(
      displayLarge: TextStyle(height: _lineHeight, color: onSurface),
      displayMedium: TextStyle(height: _lineHeight, color: onSurface),
      displaySmall: TextStyle(height: _lineHeight, color: onSurface),
      headlineLarge: TextStyle(height: _lineHeight, color: onSurface),
      headlineMedium: TextStyle(height: _lineHeight, color: onSurface),
      headlineSmall: TextStyle(height: _lineHeight, color: onSurface),
      titleLarge: TextStyle(height: _lineHeight, color: onSurface),
      titleMedium: TextStyle(height: _lineHeight, color: onSurface),
      titleSmall: TextStyle(height: _lineHeight, color: onSurface),
      bodyLarge: TextStyle(height: _lineHeight, color: onSurface),
      bodyMedium: TextStyle(height: _lineHeight, color: onSurface),
      bodySmall: TextStyle(height: _lineHeight, color: onSurface),
      labelLarge: TextStyle(height: _lineHeight, color: onSurface),
      labelMedium: TextStyle(height: _lineHeight, color: onSurface),
      labelSmall: TextStyle(height: _lineHeight, color: onSurface),
    );
  }
}
