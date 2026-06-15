// SettingsScreen — TASK-10 (M6) + TASK-06 (M7) + TASK-06 (SP-20260615)
//
// Spec refs (M6): FR-M6-09, FR-M6-13, NFR-M6-01, D8, §Components §7
// Spec refs (M7): FR-M7-06, FR-M7-08, FR-M7-12, NFR-M7-05, NFR-M7-07
// Spec refs (SP-20260615): FR-12, FR-13, FR-18, NFR-02, NFR-05
// Canon ref      : .claude/docs/canon/ui-design-bible.md §7 "Preferences dialog"
//
// Layout (canon §7 mobile adaptation):
//   Full Settings screen with grouped rows.
//
//   Appearance group (settingsAppearance):
//     ThemeSelector (TASK-07 / M6)
//     FontSizeStepper with settingsFontSize label header (TASK-06 / M7)
//     SwitchListTile: settingsMonospaceFont (TASK-06 / M7)
//     SwitchListTile: settingsLineNumbers (TASK-06 / SP-20260615) — default OFF
//
//   Behavior group (settingsBehavior):
//     SwitchListTile: settingsRecoveryEnabled — reuses emergency-recovery-files
//       10/0 integer-proxy via setEmergencyRecoveryEnabled (D8/FR-M6-13).
//     SwitchListTile: settingsSpellCheck — reuses spellingEnabled via
//       setSpellingEnabled.
//
// Explicitly excluded (D8, FR-M6-13):
//   - NO line-length row (vestigial proxy, D8).
//   - NO desktop-only rows (Quit Only Closes Current Window, etc.).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/shell/theme_selector.dart';
import 'package:buffer/presentation/typography/font_size_stepper.dart';

/// Settings screen at logical route `/settings`.
///
/// Two grouped sections:
///   - **Appearance** — theme-mode selection via [ThemeSelector],
///     font-size stepper via [FontSizeStepper], monospace toggle, and
///     show-line-numbers toggle (default OFF, SP-20260615 FR-12).
///   - **Behavior** — recovery-enabled toggle + spell-check toggle.
///
/// All labels sourced from ARB via [AppLocalizations].
/// No line-length row, no desktop-only rows.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final current = settings.value ?? const AppSettings();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // ----------------------------------------------------------------
          // Appearance group
          // ----------------------------------------------------------------
          _SectionHeader(title: l10n.settingsAppearance),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Text(
                  l10n.settingsThemeMode,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 16.0),
                const ThemeSelector(),
              ],
            ),
          ),

          // Font-size stepper row — canon §5 / FR-M7-06
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Text(
              l10n.settingsFontSize,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const FontSizeStepper(),

          // Monospace font toggle — canon §7 "Use Monospace Font" / FR-M7-08
          SwitchListTile(
            title: Text(l10n.settingsMonospaceFont),
            value: current.useMonospaceFont,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setUseMonospaceFont(value),
          ),

          // Show line numbers toggle — SP-20260615 FR-12 / FR-13
          // Default OFF (AppSettings.showLineNumbers @Default(false)).
          // Wires to the existing setShowLineNumbers notifier (C6 consumer,
          // NFR-05 — no new persistence key or model field introduced).
          // Touch target: SwitchListTile material default minVerticalPadding
          // yields ≥ 56dp height, exceeding the ≥ 48dp NFR-02 floor.
          //
          // <!-- CANON GAP: canon §Components.7 documents Appearance SwitchRows
          //      with on-state thumb using ColorScheme.primary. Flutter
          //      SwitchListTile inherits activeColor from Theme; the blue
          //      #3584E4 seed (TASK-03) supplies primary automatically.
          //      No explicit activeColor override needed — canon intent met. -->
          SwitchListTile(
            title: Text(l10n.settingsLineNumbers),
            value: current.showLineNumbers,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setShowLineNumbers(value),
          ),

          // ----------------------------------------------------------------
          // Behavior group
          // ----------------------------------------------------------------
          _SectionHeader(title: l10n.settingsBehavior),

          // Recovery-enabled toggle — reuses emergency-recovery-files
          // 10/0 integer-proxy: on→10, off→0 (D8 / FR-M6-13).
          SwitchListTile(
            title: Text(l10n.settingsRecoveryEnabled),
            value: current.emergencyRecoveryEnabled,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setEmergencyRecoveryEnabled(value),
          ),

          // Spell-check toggle — reuses spellingEnabled via setSpellingEnabled.
          SwitchListTile(
            title: Text(l10n.settingsSpellCheck),
            value: current.spellingEnabled,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setSpellingEnabled(value),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header — a styled label marking each group.
// ---------------------------------------------------------------------------

/// Renders a group section header in the style of Adw.PreferencesGroup title.
///
/// <!-- CANON GAP: canon §7 uses libadwaita Adw.PreferencesGroup title styling
///      (e.g. overline-weight text at 14sp, subtle accent). The exact token
///      has no hex/dp value in the UI Design Bible. Mapped here to
///      Theme.of(context).textTheme.labelLarge + primary color as a
///      reasonable approximation. Flag for M7 Typography review. -->
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
