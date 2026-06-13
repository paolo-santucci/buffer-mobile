// AppTheme — light and dark ThemeData derived exclusively from UI Design Bible tokens.
//
// Spec refs: FR-06, EC-14, NFR-05
// Canon source: .claude/docs/canon/ui-design-bible.md
//   §Colour & branding tokens (style.css, metainfo.xml)
//   §Typography tokens (style.css:11-14, editor_text_view.rs)
//
// Token → ThemeData mappings:
//   --view-bg-color  (light #fff / dark #202020)  → ColorScheme.surface
//   --accent-bg-color (light #f6d32d / dark #873000) → ColorScheme.primary
//   --border-color (platform-semantic)              → ColorScheme.outlineVariant
//   Typography line-height 1.4                      → TextTheme height on every style
//
// Sanctioned colour literals (the only four permitted by the canon):
//   #f6d32d  → Color(0xFFF6D32D)  — branding primary, light scheme
//   #873000  → Color(0xFF873000)  — branding primary, dark scheme
//   #fff     → Color(0xFFFFFFFF)  — theme swatch / --view-bg-color light
//   #202020  → Color(0xFF202020)  — theme swatch / --view-bg-color dark

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // -------------------------------------------------------------------------
  // Sanctioned canon literals — the ONLY hard-coded colour values permitted.
  // Source: .claude/docs/canon/ui-design-bible.md §Colour & branding tokens
  // -------------------------------------------------------------------------

  /// `#f6d32d` — GNOME "Yellow 3" branding primary (light scheme).
  /// Source: metainfo.xml:42-45; canon §Colour & branding tokens.
  static const Color _brandLight = Color(0xFFF6D32D);

  /// `#873000` — GNOME "Brown 5" branding primary (dark scheme).
  /// Source: metainfo.xml:42-45; canon §Colour & branding tokens.
  static const Color _brandDark = Color(0xFF873000);

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
  ///   --accent-bg-color → [ColorScheme.primary] = [_brandLight]  (#f6d32d)
  ///   --border-color   → [ColorScheme.outlineVariant] = [_borderColorLight]
  ///   Typography line-height = 1.4
  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _brandLight,
          brightness: Brightness.light,
        ).copyWith(
          // --view-bg-color light (#fff)
          surface: _swatchLight,
          // --accent-bg-color light (#f6d32d) — branding/identity token
          primary: _brandLight,
          // on-primary must be legible on #f6d32d (yellow); black satisfies contrast
          // <!-- CANON GAP: --accent-fg-color not mapped to a specific hex in the bible;
          //      using Colors.black (Color(0xFF000000)) for AA contrast on #f6d32d.
          //      See .claude/docs/decisions/D-003-border-color-approximation.md -->
          onPrimary: const Color(0xFF000000),
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
  ///   --accent-bg-color → [ColorScheme.primary] = [_brandDark]  (#873000)
  ///   --border-color   → [ColorScheme.outlineVariant] = [_borderColorDark]
  ///   Typography line-height = 1.4
  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _brandDark,
          brightness: Brightness.dark,
        ).copyWith(
          // --view-bg-color dark (#202020)
          surface: _swatchDark,
          // --accent-bg-color dark (#873000) — branding dark variant
          primary: _brandDark,
          // on-primary for dark brand (#873000); white satisfies AA contrast
          // <!-- CANON GAP: --accent-fg-color dark not specified;
          //      using Colors.white (Color(0xFFFFFFFF)) for AA contrast on #873000.
          //      See .claude/docs/decisions/D-003-border-color-approximation.md -->
          onPrimary: _swatchLight,
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
