// ThemeSelector widget — TASK-07
//
// Spec refs  : FR-M6-04, EC-09, NFR-M6-05, §Components §6
// Canon ref  : .claude/docs/canon/ui-design-bible.md §6 "Theme selector"
//
// Anatomy (canon §6):
//   Row(spacing:12) of three ThemeSwatch widgets, each ≥44dp circular.
//   Resting ring  : 1px --border-color  (→ ColorScheme.outlineVariant)
//   Checked ring  : 2px --accent-bg-color (→ ColorScheme.primary)
//   Check glyph   : Icons.check, fg --accent-fg-color (→ ColorScheme.onPrimary)
//   Follow fill   : linear-gradient(to bottom-right, #fff 49.99%, #202020 50.01%)
//   Light fill    : #fff
//   Dark fill     : #202020
//
// Token mapping (AppTheme):
//   --border-color    → colorScheme.outlineVariant
//   --accent-bg-color → colorScheme.primary
//   --accent-fg-color → colorScheme.onPrimary
//   #fff              → const Color(0xFFFFFFFF)   [canon-sanctioned literal]
//   #202020           → const Color(0xFF202020)   [canon-sanctioned literal]
//
// Rules enforced here:
//   • No fontSize: in any TextStyle.
//   • Writes through settingsProvider.notifier.setColorScheme (EC-09 — notifier guards no-op).
//   • Each swatch ≥44dp (NFR-M6-05, canon §6 "Swatch min size 44×44 px").
//   • Semantics.label from ARB: themeFollowSystem / themeLight / themeDark.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Canon literal fills — the ONLY hard-coded colour values permitted.
// Source: style.css:55-63; canon §Theme-swatch literal fills.
// ---------------------------------------------------------------------------

/// `#fff` — Light swatch fill and light half of Follow gradient.
/// Canon-sanctioned literal (ui-design-bible.md §Theme-swatch literal fills).
const Color _kLightFill = Color(0xFFFFFFFF);

/// `#202020` — Dark swatch fill and dark half of Follow gradient.
/// Canon-sanctioned literal (ui-design-bible.md §Theme-swatch literal fills).
const Color _kDarkFill = Color(0xFF202020);

// ---------------------------------------------------------------------------
// Canonical swatch size and ring widths (canon §6)
// ---------------------------------------------------------------------------

/// Minimum swatch diameter: 44 dp (canon §6; style.css:41-44).
const double _kSwatchSize = 44.0;

/// Resting border width: 1 px (canon §6 "Resting ring").
const double _kRestingRingWidth = 1.0;

/// Checked border width: 2 px (canon §6 "Checked ring").
const double _kCheckedRingWidth = 2.0;

/// Inter-swatch spacing: 12 px (canon §6; theme_selector.blp:16).
const double _kSwatchSpacing = 12.0;

/// Diameter of the accent-filled "checked" badge pinned to the swatch's
/// bottom-right corner. Sized so the check reads clearly while the badge stays
/// inside the swatch bounds (≈ 40% of the 44dp swatch).
const double _kCheckBadgeSize = 18.0;

/// Check glyph size inside the accent badge.
const double _kCheckGlyphSize = 12.0;

// ---------------------------------------------------------------------------
// ThemeSelector
// ---------------------------------------------------------------------------

/// Three-swatch single-select theme mode picker.
///
/// Reads `settingsProvider` for the current [AppColorScheme].
/// On tap, calls `ref.read(settingsProvider.notifier).setColorScheme(...)`.
/// Redundant taps are no-ops — the notifier guards equal-value writes (EC-09).
///
/// Designed to be embedded in [MenuSheet] (TASK-09) and [SettingsScreen]
/// (TASK-10) without modification.
class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final currentScheme = (settings.value ?? const AppSettings()).colorScheme;

    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: l10n.themeSelectorLabel,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // Inter-swatch spacing: 12 px (canon §6).
        children: [
          ThemeSwatch(
            scheme: AppColorScheme.follow,
            isSelected: currentScheme == AppColorScheme.follow,
            semanticsLabel: l10n.themeFollowSystem,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .setColorScheme(AppColorScheme.follow),
          ),
          const SizedBox(width: _kSwatchSpacing),
          ThemeSwatch(
            scheme: AppColorScheme.light,
            isSelected: currentScheme == AppColorScheme.light,
            semanticsLabel: l10n.themeLight,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .setColorScheme(AppColorScheme.light),
          ),
          const SizedBox(width: _kSwatchSpacing),
          ThemeSwatch(
            scheme: AppColorScheme.dark,
            isSelected: currentScheme == AppColorScheme.dark,
            semanticsLabel: l10n.themeDark,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .setColorScheme(AppColorScheme.dark),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ThemeSwatch
// ---------------------------------------------------------------------------

/// A single circular swatch button in the [ThemeSelector].
///
/// Public so tests can locate it via `find.byType(ThemeSwatch)` and read its
/// [scheme] field to assert ring / check placement.
///
/// Canon §6 anatomy:
///   - Fully circular (border-radius: 9999 px).
///   - Resting ring : 1 px [ColorScheme.outlineVariant] (--border-color).
///   - Checked ring : 2 px [ColorScheme.primary] (--accent-bg-color).
///   - Follow fill  : diagonal linear gradient #fff→#202020.
///   - Light fill   : [_kLightFill].
///   - Dark fill    : [_kDarkFill].
///   - Check glyph  : [Icons.check], fg [ColorScheme.onPrimary] (--accent-fg-color).
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({
    super.key,
    required this.scheme,
    required this.isSelected,
    required this.semanticsLabel,
    required this.onTap,
  });

  /// Which color scheme this swatch represents.
  final AppColorScheme scheme;

  /// Whether this swatch is currently selected.
  final bool isSelected;

  /// Localized accessibility label from ARB
  /// (`themeFollowSystem` / `themeLight` / `themeDark`).
  final String semanticsLabel;

  /// Called when the user taps the swatch.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // --border-color   → outlineVariant
    // --accent-bg-color → primary
    // --accent-fg-color → onPrimary
    final ringColor = isSelected
        ? colorScheme
              .primary // 2px accent ring when checked
        : colorScheme.outlineVariant; // 1px border ring at rest
    final ringWidth = isSelected ? _kCheckedRingWidth : _kRestingRingWidth;

    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: isSelected,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          // Canon §6: swatch min size 44×44 px (style.css:41-44).
          width: _kSwatchSize,
          height: _kSwatchSize,
          child: CustomPaint(
            painter: _SwatchPainter(
              scheme: scheme,
              ringColor: ringColor,
              ringWidth: ringWidth,
            ),
            // Selected indicator: an accent-filled circular badge carrying the
            // check, pinned to the bottom-right of the swatch (matches the
            // upstream GNOME Buffer selector). A bare centred check is invisible
            // on the white Light/Follow fills — the accent disc gives it a
            // guaranteed contrasting backdrop, and the thin surface-coloured
            // outline separates the badge from the swatch fill behind it.
            child: isSelected
                ? Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: _kCheckBadgeSize,
                      height: _kCheckBadgeSize,
                      decoration: BoxDecoration(
                        // --accent-bg-color → primary (the "circle in accent").
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        // Canon §6 "Radio indicator checked" fg → --accent-fg-color.
                        // <!-- CANON GAP: --accent-fg-color exact hex not in bible;
                        //     mapped to ColorScheme.onPrimary per AppTheme convention.
                        //     See .claude/docs/decisions/D-003-border-color-approximation.md -->
                        color: colorScheme.onPrimary,
                        // No fontSize on the icon size parameter — use a dp value.
                        size: _kCheckGlyphSize,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SwatchPainter — CustomPainter for the circular swatch
// ---------------------------------------------------------------------------

/// Paints the circular swatch background (fill) and ring (border).
///
/// Canon §6 fills:
///   Follow: `linear-gradient(to bottom right, #fff 49.99%, #202020 50.01%)`
///   Light : `#fff`
///   Dark  : `#202020`
///
/// Ring is drawn as a stroked circle at [ringWidth] with [ringColor].
/// The stroke sits inset from the outer edge (canvas clip to circle, then stroke
/// inset so the ring stays within the swatch bounds).
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({
    required this.scheme,
    required this.ringColor,
    required this.ringWidth,
  });

  final AppColorScheme scheme;
  final Color ringColor;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final circlePath = Path()..addOval(rect);

    // Clip all subsequent painting to the circle.
    canvas.clipPath(circlePath);

    // Fill
    switch (scheme) {
      case AppColorScheme.follow:
        // Canon §6: linear-gradient(to bottom right, #fff 49.99%, #202020 50.01%)
        final gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [_kLightFill, _kDarkFill],
          stops: const [0.4999, 0.5001],
        );
        final fillPaint = Paint()..shader = gradient.createShader(rect);
        canvas.drawOval(rect, fillPaint);

      case AppColorScheme.light:
        // Canon §6: #fff
        canvas.drawOval(rect, Paint()..color = _kLightFill);

      case AppColorScheme.dark:
        // Canon §6: #202020
        canvas.drawOval(rect, Paint()..color = _kDarkFill);
    }

    // Ring: inset stroke so it sits within the swatch.
    // The clip already bounds us to the circle; we draw the ring at
    // half-ringWidth inset from the edge so the full stroke is inside.
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, radius - ringWidth / 2, ringPaint);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.scheme != scheme ||
      old.ringColor != ringColor ||
      old.ringWidth != ringWidth;
}
