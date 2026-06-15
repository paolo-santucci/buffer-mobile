// MenuSheet widget + openMenuSheet helper (TASK-09)
// Extended in TASK-07 (M7): FontSizeStepper hosted between ThemeSelector and
// the first Divider (spec §4.1, FR-M7-06).
// Extended in TASK-05 (SP-20260615): Find / Replace tile + onFind injection
// (FR-08, FR-17, NFR-02, NFR-04, contract C3).
//
// Spec refs: FR-M6-08, FR-M6-23, OQ-M6-02, §Mobile-adaptation
//            FR-M7-06 (FontSizeStepper embed)
//            FR-08, FR-17, NFR-02, NFR-04 (Find / Replace tile, TASK-05)
// Canon ref: .claude/docs/canon/ui-design-bible.md §Mobile-adaptation
//            .claude/docs/canon/ui-design-bible.md §5 "Font-size selector"
//            .claude/docs/canon/ui-design-bible.md §7 "Menu sheet"
//            .claude/docs/canon/ui-design-bible.md §Components.2 (chrome menu tiles)
//            .claude/docs/canon/ui-design-bible.md §Iconography (edit-find-symbolic)
//
// The MenuSheet is the SOLE navigation entry point for the app (FR-M6-23).
// It is displayed via showModalBottomSheet and contains:
//   - ThemeSelector (canon §Components §6)
//   - FontSizeStepper (FR-M7-06, canon §5) — placed after ThemeSelector,
//     before the Divider, mirroring the ThemeSelector Padding embed
//   - Find / Replace tile — ONLY when onFind != null (contract C3, FR-08)
//   - Preferences tile → /settings
//   - About tile       → /about
//   - Recovery tile    → /recovery
//
// Labels: AppLocalizations.of(context)! — menuFind / menuPreferences / menuAbout
//         / menuRecovery.
//
// <!-- CANON GAP: OQ-M6-12 — ui-design-bible.md has no bottom-sheet container
//      anatomy (padding, corner radius, drag handle, elevation). Layout below
//      uses Material showModalBottomSheet defaults. Flag for upstream review if
//      fidelity gaps are reported. -->
//
// <!-- CANON GAP: ui-design-bible.md §Components.2 documents the chrome menu
//      tile pattern but does not name a specific icon for the Find entry.
//      Icons.search is used as the canonical Material mapping for the GNOME
//      edit-find-symbolic icon (spec §Iconography). Flag for upstream bible
//      amendment if a different mapping is specified. -->

import 'package:flutter/material.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/shell/theme_selector.dart';
import 'package:buffer/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// openMenuSheet — public entry point called by TASK-12 chrome affordance
// ---------------------------------------------------------------------------

/// Opens the main menu bottom sheet.
///
/// This is the single call-site contract. `BufferScreen` calls this from the
/// chrome menu affordance tap handler.
///
/// The sheet is not a named route — it is a `showModalBottomSheet` overlay
/// (§5.1-h, FR-M6-23).
///
/// [onFind] is an optional callback injected by the caller (contract C3,
/// FR-08, TASK-05). When non-null a "Find / Replace" [ListTile] is rendered
/// in the sheet; when null (the default) the tile is absent. Existing call
/// sites that omit [onFind] are unaffected — the parameter is additive
/// (NFR-04).
Future<void> openMenuSheet(BuildContext context, {VoidCallback? onFind}) {
  return showModalBottomSheet<void>(
    context: context,
    // useRootNavigator: false — sheet navigates within the same Navigator
    // so that Navigator.pushNamed from within the sheet routes to the app's
    // named route table, not a separate modal navigator.
    useRootNavigator: false,
    builder: (sheetContext) =>
        _MenuSheetContent(hostContext: context, onFind: onFind),
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
///   - Find / Replace tile — only when [onFind] != null (contract C3, FR-08)
///   - Preferences tile → Navigator.pushNamed '/settings'
///   - About tile       → Navigator.pushNamed '/about'
///   - Recovery tile    → Navigator.pushNamed '/recovery'
class _MenuSheetContent extends StatelessWidget {
  const _MenuSheetContent({required this.hostContext, this.onFind});

  /// The BuildContext of the screen that opened the sheet.
  ///
  /// Navigation calls go through [hostContext] so that named routes resolve
  /// via the app's root Navigator rather than the sheet's ephemeral context.
  final BuildContext hostContext;

  /// Optional callback injected by the caller (contract C3, FR-08).
  ///
  /// When non-null a "Find / Replace" [ListTile] is rendered after the
  /// [Divider] and before Preferences. The tile pops the sheet then invokes
  /// this callback — it does NOT call any provider or `startSearch` directly
  /// (single-path discipline; the actual find dispatch lives in
  /// `buffer_screen.dart`, TASK-07).
  final VoidCallback? onFind;

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
          // Find / Replace tile — shown ONLY when onFind != null (C3, FR-08)
          //
          // Placement: first tile after the Divider, before Preferences.
          // Icon: Icons.search (GNOME edit-find-symbolic → Material mapping).
          // Touch target: ListTile default min-height = 56dp >= 48dp (NFR-02).
          //
          // Single-path discipline (NFR-04): this tile ONLY pops the sheet
          // and invokes the injected [onFind] callback. It does NOT call any
          // provider or startSearch directly — the actual OpenFindIntent
          // dispatch lives in buffer_screen.dart (TASK-07).
          // ---------------------------------------------------------------
          if (onFind != null)
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.menuFind),
              onTap: () {
                Navigator.of(context).pop();
                onFind!();
              },
            ),

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
