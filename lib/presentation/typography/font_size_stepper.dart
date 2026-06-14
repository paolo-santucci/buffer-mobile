// FontSizeStepper widget — TASK-05
//
// Spec refs  : FR-M7-06, FR-M7-12, NFR-M7-05, NFR-M7-07
// Canon ref  : .claude/docs/canon/ui-design-bible.md §5 "Font-size selector"
//
// Anatomy (canon §5):
//   horizontal Box, inner spacing 12, margin-start/end 18:
//   Decrease Button (list-remove-symbolic / Icons.remove), circular, a11y "Zoom Out"
//   Label ({n}pt, hexpand)
//   Increase Button (list-add-symbolic / Icons.add), circular, a11y "Zoom In"
//
// Mobile adaptation (canon §5 recommendation):
//   Two circular IconButtons (Icons.remove / Icons.add) flanking the {n}pt label,
//   each ≥48 dp. Stepping moves one slot; buttons disable at scale ends.
//
// Token mapping:
//   spacing 12 → const _kSpacing = 12.0 (canon §5 "inner box spacing 12")
//   margin-start/end 18 → const _kHorizontalInset = 18.0 (canon §5
//       "Font-size selector outer insets 18 px")
//   circular button → shape: CircleBorder()
//   ≥48 dp target → minimumSize: Size(48, 48)
//
// <!-- CANON GAP: FontSizeStepper button style — bible §5 says circular ≥48dp
//     (recommendation); Flutter ButtonStyle.minimumSize not specified -->
//
// Accessibility:
//   decrease Semantics.label → l10n.a11yZoomOut ("Decrease font size")
//   increase Semantics.label → l10n.a11yZoomIn  ("Increase font size")
//
// Provider contract:
//   Reads settingsProvider (AsyncNotifierProvider<SettingsNotifier, AppSettings>).
//   Falls back to const AppSettings() on loading/error — never crashes.
//   Writes through ref.read(settingsProvider.notifier).setFontSizeIndex(int).
//
// Dual-host: no host-specific constructor params. Embed directly in both
// MenuSheet and SettingsScreen without modification.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Layout constants (canon §5 / §Spacing)
// ---------------------------------------------------------------------------

/// Outer horizontal inset: 18 px (canon §5; font_size_selector.blp:11-12).
const double _kHorizontalInset = 18.0;

/// Inner button↔label spacing: 12 px (canon §5; font_size_selector.blp:10).
const double _kSpacing = 12.0;

/// Minimum circular button hit target: 48 dp (canon §5 mobile adaptation;
/// NFR-M7-05; Material 48dp / iOS HIG 44pt — we use the higher value for
/// cross-platform parity).
///
/// <!-- CANON GAP: FontSizeStepper button style — bible §5 says circular ≥48dp
///     (recommendation); Flutter ButtonStyle.minimumSize not specified -->
const double _kMinButtonSize = 48.0;

// ---------------------------------------------------------------------------
// FontSizeStepper
// ---------------------------------------------------------------------------

/// Shared font-size stepper: decrease / {n}pt label / increase.
///
/// Reads [settingsProvider]; disables the decrease button at index 0 and
/// the increase button at index 20 (ends of the 21-slot scale). Otherwise
/// calls [SettingsNotifier.setFontSizeIndex] with `currentIndex ∓ 1`.
///
/// Designed to be embedded in both [MenuSheet] and [SettingsScreen] without
/// any host-specific props. Falls back to [AppSettings] defaults when the
/// provider is loading or in error state.
class FontSizeStepper extends ConsumerWidget {
  const FontSizeStepper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final l10n = AppLocalizations.of(context);

    final index = settings.fontSizeIndex;
    final maxIndex = AppSettings.slotList.length - 1; // 20
    final ptLabel = '${AppSettings.slotList[index]}pt';

    final notifier = ref.read(settingsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHorizontalInset),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ----------------------------------------------------------------
          // Decrease button — Icons.remove / "Zoom Out"
          // ----------------------------------------------------------------
          Semantics(
            label: l10n.a11yZoomOut,
            button: true,
            excludeSemantics: true,
            child: IconButton(
              // <!-- CANON GAP: FontSizeStepper button style — bible §5 says
              //     circular ≥48dp (recommendation); Flutter
              //     ButtonStyle.minimumSize not specified -->
              style: IconButton.styleFrom(
                minimumSize: const Size(_kMinButtonSize, _kMinButtonSize),
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.remove),
              onPressed: index <= 0
                  ? null
                  : () => notifier.setFontSizeIndex(index - 1),
            ),
          ),
          const SizedBox(width: _kSpacing),
          // ----------------------------------------------------------------
          // {n}pt label (hexpand equivalent: Flexible)
          // ----------------------------------------------------------------
          Text(ptLabel),
          const SizedBox(width: _kSpacing),
          // ----------------------------------------------------------------
          // Increase button — Icons.add / "Zoom In"
          // ----------------------------------------------------------------
          Semantics(
            label: l10n.a11yZoomIn,
            button: true,
            excludeSemantics: true,
            child: IconButton(
              // <!-- CANON GAP: FontSizeStepper button style — bible §5 says
              //     circular ≥48dp (recommendation); Flutter
              //     ButtonStyle.minimumSize not specified -->
              style: IconButton.styleFrom(
                minimumSize: const Size(_kMinButtonSize, _kMinButtonSize),
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.add),
              onPressed: index >= maxIndex
                  ? null
                  : () => notifier.setFontSizeIndex(index + 1),
            ),
          ),
        ],
      ),
    );
  }
}
