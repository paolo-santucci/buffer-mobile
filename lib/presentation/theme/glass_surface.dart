// GlassSurface — central glass primitive for the Liquid Glass chrome.
//
// Spec refs: FR-19, FR-20, FR-21, FR-27, NFR-02, NFR-03, NFR-05, NFR-06
// Plan refs: TASK-01 (Wave 1), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// <!-- CANON GAP: glass surface (fill alpha light/dark, blur sigma, shadow spec, radii)
//      The ui-design-bible.md does not define anatomy for glass surfaces.
//      This implementation binds to cross-cutting tokens only:
//        surface / outlineVariant / onSurface — from colorScheme (no hex literals)
//        reduce-motion → Duration.zero
//        ≥48dp tap targets (enforced by consumers, not this widget)
//      Per-component anatomy gaps are routed to the bible via OQ-02. -->
//
// Behavioural contract:
//   Glass branch (highContrast == false):
//     ClipRRect(borderRadius) wrapping BackdropFilter(ImageFilter.blur(σ)) behind
//     a colorScheme.surface.withValues(alpha: fillAlpha[brightness]) fill +
//     Border.all(outlineVariant, borderWidth) + soft BoxShadow (shadow token).
//     fillAlpha >= 0.90 light / >= 0.80 dark (NFR-05).
//
//   Opaque branch (highContrast == true, FR-20):
//     NO BackdropFilter; fill is colorScheme.surface at alpha 1.0; border + shadow retained.
//
//   Clip discipline (NFR-06):
//     The BackdropFilter is ALWAYS inside the ClipRRect — clipped to the surface bounds,
//     never full-screen.
//
//   Unmount-at-zero (NFR-06):
//     When opacity == 0, the entire BackdropFilter subtree is conditionally ABSENT from
//     the tree (not merely transparent). Callers that animate visibility pass opacity here
//     or wrap in AnimatedOpacity whose 0 frame yields an unmounted filter.
//
//   Reduce-motion (FR-27):
//     Any internal transition uses
//       MediaQuery.disableAnimationsOf(context) ? Duration.zero : _kTransitionDuration.

import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// GlassTokens — ThemeExtension (C1b, single source of truth, NFR-03)
//
// Pinned fill-alpha constants (NFR-05 alpha-drift guards):
//   _kFillAlphaLight = 0.92  (>= 0.90 floor; change here + app_theme_test.dart together)
//   _kFillAlphaDark  = 0.82  (>= 0.80 floor; change here + app_theme_test.dart together)
//
// <!-- CANON GAP: fill alpha light/dark, blur sigma, shadow spec, radii — no hex values
//      in ui-design-bible.md for glass surfaces; values chosen to meet NFR-05 floor and
//      provide legible contrast over the editor. -->
// ---------------------------------------------------------------------------

const double _kFillAlphaLight = 0.92;
const double _kFillAlphaDark = 0.82;
const double _kBlurSigma = 12.0;
const double _kBorderWidth = 0.8;

// Internal transition duration for reduce-motion gate (FR-27).
// Not exposed as a token — callers control opacity.
const Duration _kTransitionDuration = Duration(milliseconds: 200);

/// Named glass tokens as a registered [ThemeExtension].
///
/// Single source of truth for all glass-surface values.
/// Registered in [AppTheme.light()] and [AppTheme.dark()].
///
/// <!-- CANON GAP: glass surface (fill alpha light/dark, blur sigma, shadow spec, radii) -->
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.fillAlphaLight,
    required this.fillAlphaDark,
    required this.blurSigma,
    required this.borderWidth,
    required this.pillRadius,
    required this.popoverRadius,
    required this.searchBarRadius,
    required this.shadow,
  });

  /// Fill alpha for light-mode glass surface. Pinned at [_kFillAlphaLight] (0.92).
  /// Must be >= 0.90 per NFR-05.
  final double fillAlphaLight;

  /// Fill alpha for dark-mode glass surface. Pinned at [_kFillAlphaDark] (0.82).
  /// Must be >= 0.80 per NFR-05.
  final double fillAlphaDark;

  /// BackdropFilter ImageFilter.blur sigma (both x and y).
  final double blurSigma;

  /// Hairline border width for the glass surface outline.
  final double borderWidth;

  /// Corner radius for the pill shape (top pill, bottom toolbar, find pill, toast pill).
  final BorderRadius pillRadius;

  /// Corner radius for the anchored popover bubble.
  final BorderRadius popoverRadius;

  /// Corner radius for the full-width floating search box (find bar).
  ///
  /// Set to 24dp — distinct from [pillRadius] (32dp stadium pill) and
  /// [popoverRadius] (16dp card bubble). Consumers wire this to the
  /// find-search-bar container; this token must never be [BorderRadius.zero].
  final BorderRadius searchBarRadius;

  /// Soft drop shadow for the glass surface container.
  final List<BoxShadow> shadow;

  /// Convenience accessor — returns null if not registered in the theme.
  static GlassTokens? of(BuildContext context) {
    return Theme.of(context).extension<GlassTokens>();
  }

  @override
  GlassTokens copyWith({
    double? fillAlphaLight,
    double? fillAlphaDark,
    double? blurSigma,
    double? borderWidth,
    BorderRadius? pillRadius,
    BorderRadius? popoverRadius,
    BorderRadius? searchBarRadius,
    List<BoxShadow>? shadow,
  }) {
    return GlassTokens(
      fillAlphaLight: fillAlphaLight ?? this.fillAlphaLight,
      fillAlphaDark: fillAlphaDark ?? this.fillAlphaDark,
      blurSigma: blurSigma ?? this.blurSigma,
      borderWidth: borderWidth ?? this.borderWidth,
      pillRadius: pillRadius ?? this.pillRadius,
      popoverRadius: popoverRadius ?? this.popoverRadius,
      searchBarRadius: searchBarRadius ?? this.searchBarRadius,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      fillAlphaLight:
          lerpDouble(fillAlphaLight, other.fillAlphaLight, t) ?? fillAlphaLight,
      fillAlphaDark:
          lerpDouble(fillAlphaDark, other.fillAlphaDark, t) ?? fillAlphaDark,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t) ?? blurSigma,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t) ?? borderWidth,
      pillRadius:
          BorderRadius.lerp(pillRadius, other.pillRadius, t) ?? pillRadius,
      popoverRadius:
          BorderRadius.lerp(popoverRadius, other.popoverRadius, t) ??
          popoverRadius,
      searchBarRadius:
          BorderRadius.lerp(searchBarRadius, other.searchBarRadius, t) ??
          searchBarRadius,
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? shadow,
    );
  }
}

// ---------------------------------------------------------------------------
// Default GlassTokens instances — constructed in AppTheme and registered via
// ThemeData.extensions. Exposed as package-level constants so AppTheme can
// reference them without creating ad-hoc literals.
// ---------------------------------------------------------------------------

/// Default [GlassTokens] instance used by [AppTheme.light()] and [AppTheme.dark()].
///
/// <!-- CANON GAP: glass surface (fill alpha light/dark, blur sigma, shadow spec, radii) -->
const GlassTokens kDefaultGlassTokens = GlassTokens(
  fillAlphaLight: _kFillAlphaLight,
  fillAlphaDark: _kFillAlphaDark,
  blurSigma: _kBlurSigma,
  borderWidth: _kBorderWidth,
  // Pill: large fully-rounded radius (stadium-like pill shape)
  pillRadius: BorderRadius.all(Radius.circular(32.0)),
  // Popover: slightly less rounded — a card-like bubble
  popoverRadius: BorderRadius.all(Radius.circular(16.0)),
  // Search bar: full-width floating find box; 24dp — between pill and popover
  searchBarRadius: BorderRadius.all(Radius.circular(24.0)),
  shadow: [
    BoxShadow(
      // Color derived inline from black with opacity — no hex literal.
      // 0x1A = 10% opacity on black; acceptable inline since it is a
      // shadow spec (no foreground or brand colour).
      color: Color(0x1A000000),
      blurRadius: 16.0,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 4.0,
      offset: Offset(0, 1),
      spreadRadius: 0,
    ),
  ],
);

// ---------------------------------------------------------------------------
// GlassSurface widget (C1)
// ---------------------------------------------------------------------------

/// Central glass-surface primitive.
///
/// Renders a near-opaque themed fill + real background blur + hairline border
/// + soft drop shadow. Automatically degrades to a fully opaque, blur-free fill
/// under [MediaQuery.highContrastOf] (FR-20).
///
/// ### Usage
/// ```dart
/// GlassSurface(
///   borderRadius: GlassTokens.of(context)!.pillRadius,
///   child: Row(children: [...]),
/// )
/// ```
///
/// ### Contract (C1)
/// - **Glass branch** (`highContrast == false`): `ClipRRect` wrapping
///   `BackdropFilter(ImageFilter.blur)` behind a `colorScheme.surface` fill at
///   `fillAlpha[brightness]` + `Border.all(outlineVariant, borderWidth)` + shadow.
///   The `BackdropFilter` is ALWAYS a descendant of the `ClipRRect` (NFR-06).
/// - **Opaque branch** (`highContrast == true`): NO `BackdropFilter`; fill alpha 1.0;
///   border + shadow retained (FR-20).
/// - **Unmount-at-zero**: when [opacity] == 0 the `BackdropFilter` subtree is
///   ABSENT (not just transparent) so no off-screen blurring occurs (NFR-06).
/// - **Reduce-motion**: internal transitions collapse to `Duration.zero` when
///   `MediaQuery.disableAnimationsOf(context)` is true (FR-27).
///
/// <!-- CANON GAP: glass surface (fill alpha light/dark, blur sigma, shadow spec, radii) -->
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.borderRadius,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.opacity = 1.0,
    super.key,
  });

  /// The corner radius of the glass surface. Use `GlassTokens.of(context)!.pillRadius`
  /// or `.popoverRadius` as appropriate.
  final BorderRadius borderRadius;

  /// The widget inside the glass container.
  final Widget child;

  /// Optional inner padding between the glass border and the child. Defaults to zero.
  final EdgeInsetsGeometry padding;

  /// Opacity of the glass surface. When 0.0 the `BackdropFilter` subtree is
  /// unmounted entirely (NFR-06). Callers that animate visibility drive this
  /// parameter (or wrap in `AnimatedOpacity` whose 0 frame yields the unmount).
  ///
  /// OQ-13: `GlassSurface` owns the `opacity → unmount` decision; callers that
  /// need a fade animation use `AnimatedOpacity` around `GlassSurface`.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context) ?? kDefaultGlassTokens;
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final highContrast = MediaQuery.highContrastOf(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    // Fill alpha: brightness-aware from token (NFR-05).
    final fillAlpha = brightness == Brightness.light
        ? tokens.fillAlphaLight
        : tokens.fillAlphaDark;

    // The decoration is shared between both branches (border + shadow).
    // Fill differs: glass branch is semi-transparent, opaque branch is alpha 1.0.
    final fillColor = highContrast
        ? colorScheme
              .surface // fully opaque (FR-20)
        : colorScheme.surface.withValues(alpha: fillAlpha);

    final decoration = BoxDecoration(
      color: fillColor,
      borderRadius: borderRadius,
      border: Border.all(
        color: colorScheme.outlineVariant,
        width: tokens.borderWidth,
      ),
      boxShadow: tokens.shadow,
    );

    // Transition duration for any internal animation respects reduce-motion.
    final transitionDuration = disableAnimations
        ? Duration.zero
        : _kTransitionDuration;

    // When opacity == 0, unmount the entire BackdropFilter subtree (NFR-06).
    // Use an exact equality check — callers control this value.
    final absent = opacity == 0.0;

    Widget surface;

    if (highContrast || absent) {
      // Opaque branch: no BackdropFilter.
      // Also used when opacity == 0 to ensure no off-screen blur sampling.
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      );
    } else {
      // Glass branch: BackdropFilter inside ClipRRect (NFR-06 clip discipline).
      //
      // Layer order (bottom → top):
      //   1. BackdropFilter (blurs what is behind the clip region)
      //   2. DecoratedBox fill (semi-transparent surface + border + shadow)
      //   3. Padding + child
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: tokens.blurSigma,
            sigmaY: tokens.blurSigma,
          ),
          child: DecoratedBox(
            decoration: decoration,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }

    // If opacity is neither 0 nor 1, wrap in AnimatedOpacity so callers that
    // drive partial opacity get a smooth transition respecting reduce-motion.
    // (opacity == 1.0 is the common case — no wrapping overhead.)
    if (opacity == 1.0 || absent) {
      return surface;
    }

    return AnimatedOpacity(
      opacity: opacity,
      duration: transitionDuration,
      child: surface,
    );
  }
}
