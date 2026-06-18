// TASK-10 (M5): RecoveryScreen — in-app recovery list screen.
//
// Spec refs: FR-M5-05, FR-M5-06, FR-M5-07, FR-M5-08, FR-M5-10, FR-M5-11,
//            FR-M5-13, FR-M5-14, NFR-M5-02, NFR-M5-05, NFR-M5-06
// Canon ref: .claude/docs/canon/ui-design-bible.md
//            (binding rules §4 of the consolidated assessment)
//
// House style: mirrors find_search_bar.dart —
//   ConsumerStatefulWidget, AppLocalizations.of(context) for every string,
//   48×48 _iconBtn helper with tooltip-as-semantic-label, reduce-motion-aware
//   crossfade via MediaQuery.disableAnimations, semantic ColorScheme tokens.
//
// CANON GAPs:
//
// <!-- CANON GAP: OQ-M5-09 — list-row anatomy/typography/spacing.
//      The UI Design Bible (ui-design-bible.md) has no in-app recovery UI;
//      the upstream desktop app has no recovery list screen.
//      Decision: use Material ListTile defaults (48dp+ targets, 12dp spacing)
//      with secondary text dimmed at 0.58 opacity, matching the 0.58 dim-metadata
//      bible precedent (style.css:32-36, assessment §4). See D-007. -->
//
// <!-- CANON GAP: OQ-M5-09 — confirmation/destructive dialog anatomy.
//      The bible is silent on dialogs. Decision: Material AlertDialog with
//      ColorScheme.error-styled confirm TextButton (bible rule: destructive =
//      ColorScheme.error; assessment §4). See D-007. -->
//
// <!-- CANON GAP: OQ-M5-09 — empty-state anatomy.
//      The bible is silent on empty states. Decision: centred Text using
//      ColorScheme.onSurface at reduced opacity, semantic tokens only, no hex.
//      See D-007. -->
//
// <!-- CANON GAP: OQ-M5-13 — secondary-screen app-bar.
//      The bible dictates "no chrome at rest" for the editor (primary surface).
//      A secondary screen (/recovery) is not the editor — a back affordance is
//      required (FR-M5-13). Decision: standard Material AppBar with
//      Icons.arrow_back back button (≥48dp) and a delete-all icon action.
//      The app bar is scoped to this screen only; it does not appear on the
//      editor surface. See D-007. -->
//
// All user-facing strings via AppLocalizations — zero literal Text('...').

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/recovery/recovery_list_provider.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

/// Recovery list screen — lists saved recovery notes, allows restore/delete.
///
/// Navigated to via [Navigator.pushNamed('/recovery')]. Pops itself on back
/// or after a successful restore. Never writes to the buffer except through
/// [BufferNotifier.populate] (FR-M5-07 / NFR-M5-02).
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // recoveryListProvider is non-auto-disposed (single-provider rule §5.3),
    // so its build() runs only once per app session. A note saved AFTER that
    // first build — e.g. the buffer being persisted on backgrounding — would
    // otherwise be absent when the screen is re-opened. Re-fetch on every mount
    // so the most recently saved note always appears (FR-M5-01).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recoveryListProvider.notifier).refresh();
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the crossfade duration honouring reduce-motion (bible Motion,
  /// NFR-M5-06).
  ///
  /// Uses 1 ms rather than Duration.zero to avoid the RenderAnimatedSize
  /// re-dirty assertion (mirrors find_search_bar.dart pattern).
  Duration _crossfadeDuration(BuildContext context) {
    return MediaQuery.of(context).disableAnimations
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 200);
  }

  /// Builds a 48×48 icon button with a tooltip as the semantic label.
  ///
  /// Mirrors the `_iconBtn` helper in find_search_bar.dart (bible §Touch,
  /// NFR-M5-06, ≥48dp).
  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 48.0,
      height: 48.0,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
      ),
    );
  }

  /// Locale-aware timestamp formatter (FR-M5-05 — intl DateFormat per locale).
  String _formatTimestamp(BuildContext context, DateTime savedAt) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMd(locale).add_jm().format(savedAt.toLocal());
  }

  // ---------------------------------------------------------------------------
  // Restore flow (FR-M5-07, FR-M5-08)
  // ---------------------------------------------------------------------------

  Future<void> _onRestore(
    BuildContext context,
    AppLocalizations l10n,
    RecoveryNote note,
  ) async {
    final bufferText = ref.read(bufferProvider).text.trim();

    if (bufferText.isNotEmpty) {
      // Non-empty buffer → show confirmation dialog first (FR-M5-08).
      final confirmed = await _showRestoreDialog(context, l10n);
      if (!confirmed || !context.mounted) return;
    }

    // Restore: read text via notifier (SRP), then populate buffer.
    final text = await ref.read(recoveryListProvider.notifier).restore(note);
    if (!context.mounted) return;
    ref.read(bufferProvider.notifier).populate(text);
    Navigator.of(context).pop();
  }

  /// Shows the restore confirmation dialog.
  ///
  /// Returns true when the user confirms, false on cancel.
  ///
  /// <!-- CANON GAP: OQ-M5-09 — dialog anatomy/styling uses Material
  ///      AlertDialog; bible is silent on dialogs. ColorScheme.error for
  ///      destructive confirm action per assessment §4 binding rule. -->
  Future<bool> _showRestoreDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final errorColor = Theme.of(ctx).colorScheme.error;
            return AlertDialog(
              title: Text(l10n.recoveryRestoreDialogTitle),
              content: Text(l10n.recoveryRestoreDialogBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.recoveryDialogCancel),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: errorColor),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.recoveryRestoreDialogConfirm),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // ---------------------------------------------------------------------------
  // Delete single note (FR-M5-10)
  // ---------------------------------------------------------------------------

  Future<void> _onDelete(
    BuildContext context,
    AppLocalizations l10n,
    RecoveryNote note,
  ) async {
    final confirmed = await _showDeleteDialog(context, l10n);
    if (!confirmed || !context.mounted) return;
    await ref.read(recoveryListProvider.notifier).delete(note);
  }

  /// <!-- CANON GAP: OQ-M5-09 — dialog anatomy. See class-level comment. -->
  Future<bool> _showDeleteDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final errorColor = Theme.of(ctx).colorScheme.error;
            return AlertDialog(
              title: Text(l10n.recoveryDeleteDialogTitle),
              content: Text(l10n.recoveryDeleteDialogBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.recoveryDialogCancel),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: errorColor),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.recoveryDeleteDialogConfirm),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // ---------------------------------------------------------------------------
  // Delete-all (FR-M5-11)
  // ---------------------------------------------------------------------------

  Future<void> _onDeleteAll(BuildContext context, AppLocalizations l10n) async {
    final confirmed = await _showDeleteAllDialog(context, l10n);
    if (!confirmed || !context.mounted) return;
    await ref.read(recoveryListProvider.notifier).deleteAll();
  }

  /// <!-- CANON GAP: OQ-M5-09 — dialog anatomy. See class-level comment. -->
  Future<bool> _showDeleteAllDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final errorColor = Theme.of(ctx).colorScheme.error;
            return AlertDialog(
              title: Text(l10n.recoveryDeleteAllDialogTitle),
              content: Text(l10n.recoveryDeleteAllDialogBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.recoveryDialogCancel),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: errorColor),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.recoveryDeleteAllDialogConfirm),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // ---------------------------------------------------------------------------
  // Toggle (FR-M5-14)
  // ---------------------------------------------------------------------------

  Future<void> _onToggle(bool value) async {
    await ref
        .read(settingsProvider.notifier)
        .setEmergencyRecoveryEnabled(value);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final recoveryAsync = ref.watch(recoveryListProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final toggleEnabled = settingsAsync.value?.emergencyRecoveryEnabled ?? true;

    // <!-- CANON GAP: OQ-M5-13 — secondary-screen app-bar.
    //      See class-level comment. -->
    return Scaffold(
      appBar: AppBar(
        // Back affordance (FR-M5-13): Icons.arrow_back, ≥48dp, ARB tooltip.
        leading: _iconBtn(
          icon: Icons.arrow_back,
          tooltip: l10n.recoveryBackTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.recoveryTitle),
        actions: [
          // Delete-all action (FR-M5-11).
          _iconBtn(
            icon: Icons.delete_sweep,
            tooltip: l10n.recoveryDeleteAllTooltip,
            onPressed: () => _onDeleteAll(context, l10n),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Co-located toggle (FR-M5-14).
          // <!-- CANON GAP: OQ-M5-13 — secondary app-bar / toggle placement.
          //      See class-level comment. -->
          Tooltip(
            message: l10n.recoveryToggleTooltip,
            child: SwitchListTile(
              title: Text(l10n.recoveryToggleLabel),
              value: toggleEnabled,
              onChanged: _onToggle,
            ),
          ),
          const Divider(height: 1),

          // List / empty / error body.
          Expanded(
            child: AnimatedCrossFade(
              duration: _crossfadeDuration(context),
              crossFadeState:
                  recoveryAsync.hasValue && recoveryAsync.value!.isNotEmpty
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: _buildEmptyOrErrorState(
                context,
                l10n,
                theme,
                recoveryAsync,
              ),
              secondChild:
                  recoveryAsync.hasValue && recoveryAsync.value!.isNotEmpty
                  ? _buildNoteList(context, l10n, theme, recoveryAsync.value!)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty / error state
  // ---------------------------------------------------------------------------

  /// <!-- CANON GAP: OQ-M5-09 — empty-state anatomy.
  ///      See class-level comment. -->
  Widget _buildEmptyOrErrorState(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    AsyncValue<List<RecoveryNote>> recoveryAsync,
  ) {
    return Center(
      child: Opacity(
        opacity: 0.58,
        child: Text(
          l10n.recoveryEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Note list
  // ---------------------------------------------------------------------------

  /// <!-- CANON GAP: OQ-M5-09 — list-row anatomy/typography/spacing.
  ///      See class-level comment. -->
  Widget _buildNoteList(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    List<RecoveryNote> notes,
  ) {
    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (ctx, index) =>
          _buildNoteRow(ctx, l10n, theme, notes[index]),
    );
  }

  Widget _buildNoteRow(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    RecoveryNote note,
  ) {
    final timestamp = _formatTimestamp(context, note.savedAt);

    // <!-- CANON GAP: OQ-M5-09 — list-row anatomy. See class-level comment. -->
    return ListTile(
      // Timestamp as primary text.
      title: Text(timestamp),
      // Preview as secondary text, dimmed at 0.58 opacity (bible §style.css:32-36
      // dim-metadata precedent, assessment §4).
      subtitle: Opacity(
        opacity: 0.58,
        child: Text(note.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Restore button.
          _iconBtn(
            icon: Icons.restore,
            tooltip: l10n.recoveryRestoreTooltip,
            onPressed: () => _onRestore(context, l10n, note),
          ),
          // Per-note delete button.
          _iconBtn(
            icon: Icons.delete_outline,
            tooltip: l10n.recoveryDeleteTooltip,
            onPressed: () => _onDelete(context, l10n, note),
          ),
        ],
      ),
    );
  }
}
