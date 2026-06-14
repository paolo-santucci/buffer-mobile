// MenuSheet widget + openMenuSheet helper (TASK-09)
// Extended in TASK-07 (M7): FontSizeStepper hosted between ThemeSelector and
// the first Divider (spec §4.1, FR-M7-06).
//
// Spec refs: FR-M6-08, FR-M6-23, OQ-M6-02, §Mobile-adaptation
//            FR-M7-06 (FontSizeStepper embed)
// Canon ref: .claude/docs/canon/ui-design-bible.md §Mobile-adaptation
//            .claude/docs/canon/ui-design-bible.md §5 "Font-size selector"
//            .claude/docs/canon/ui-design-bible.md §7 "Menu sheet"
//
// The MenuSheet is the SOLE navigation entry point for the app (FR-M6-23).
// It is displayed via showModalBottomSheet and contains:
//   - ThemeSelector (canon §Components §6)
//   - FontSizeStepper (FR-M7-06, canon §5) — placed after ThemeSelector,
//     before the Divider, mirroring the ThemeSelector Padding embed
//   - Preferences tile → /settings
//   - About tile       → /about
//   - Recovery tile    → /recovery
//
// Labels: AppLocalizations.of(context)! — menuPreferences / menuAbout / menuRecovery.
//
// <!-- CANON GAP: OQ-M6-12 — ui-design-bible.md has no bottom-sheet container
//      anatomy (padding, corner radius, drag handle, elevation). Layout below
//      uses Material showModalBottomSheet defaults. Flag for upstream review if
//      fidelity gaps are reported. -->

import 'package:flutter/material.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/shell/theme_selector.dart';
import 'package:buffer/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// openMenuSheet — public entry point called by TASK-12 chrome affordance
// ---------------------------------------------------------------------------

/// Opens the main menu bottom sheet.
///
/// This is the single call-site contract. TASK-12 (`BufferScreen`) calls this
/// from the chrome menu affordance tap handler.
///
/// The sheet is not a named route — it is a `showModalBottomSheet` overlay
/// (§5.1-h, FR-M6-23).
Future<void> openMenuSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // useRootNavigator: false — sheet navigates within the same Navigator
    // so that Navigator.pushNamed from within the sheet routes to the app's
    // named route table, not a separate modal navigator.
    useRootNavigator: false,
    builder: (sheetContext) => _MenuSheetContent(hostContext: context),
  );
}

// ---------------------------------------------------------------------------
// _MenuSheetContent — internal widget rendered inside the bottom sheet
// ---------------------------------------------------------------------------

/// The content widget rendered inside `showModalBottomSheet`.
///
/// Hosts:
///   - [ThemeSelector] (canon §Components §6)
///   - [FontSizeStepper] (FR-M7-06, canon §5)
///   - Preferences tile → Navigator.pushNamed '/settings'
///   - About tile       → Navigator.pushNamed '/about'
///   - Recovery tile    → Navigator.pushNamed '/recovery'
class _MenuSheetContent extends StatelessWidget {
  const _MenuSheetContent({required this.hostContext});

  /// The BuildContext of the screen that opened the sheet.
  ///
  /// Navigation calls go through [hostContext] so that named routes resolve
  /// via the app's root Navigator rather than the sheet's ephemeral context.
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------------------------------------------------------
          // ThemeSelector — three 44dp swatches (canon §Components §6)
          // ---------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: const ThemeSelector(),
          ),

          // ---------------------------------------------------------------
          // FontSizeStepper — decrease / {n}pt / increase (FR-M7-06)
          // Positioned after ThemeSelector, before the Divider, mirroring
          // the ThemeSelector Padding embed pattern (spec §4.1, canon §5).
          // ---------------------------------------------------------------
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: FontSizeStepper(),
          ),

          const Divider(height: 1),

          // ---------------------------------------------------------------
          // Preferences tile → /settings
          // ---------------------------------------------------------------
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.menuPreferences),
            onTap: () {
              // Pop the sheet first, then navigate so the route animation
              // is not stacked on top of the sheet dismiss.
              Navigator.of(context).pop();
              Navigator.of(hostContext).pushNamed('/settings');
            },
          ),

          // ---------------------------------------------------------------
          // About tile → /about
          // ---------------------------------------------------------------
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.menuAbout),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(hostContext).pushNamed('/about');
            },
          ),

          // ---------------------------------------------------------------
          // Recovery tile → /recovery
          // ---------------------------------------------------------------
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: Text(l10n.menuRecovery),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(hostContext).pushNamed('/recovery');
            },
          ),
        ],
      ),
    );
  }
}
