// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Buffer';

  @override
  String get findHintText => 'Search';

  @override
  String findCountLabel(int position, int count) {
    return '$position of $count';
  }

  @override
  String get findPreviousTooltip => 'Previous Match';

  @override
  String get findNextTooltip => 'Next Match';

  @override
  String get findReplaceHintText => 'Replace';

  @override
  String get findReplaceButton => 'Replace';

  @override
  String get findReplaceToggleTooltip => 'Toggle Replace';

  @override
  String get findCloseTooltip => 'Back';

  @override
  String get recoveryTitle => 'Recovery';

  @override
  String get recoveryEmpty => 'No recovered notes';

  @override
  String get recoveryRestoreTooltip => 'Restore';

  @override
  String get recoveryDeleteTooltip => 'Delete';

  @override
  String get recoveryDeleteAllTooltip => 'Delete all';

  @override
  String get recoveryRestoreDialogTitle => 'Restore note?';

  @override
  String get recoveryRestoreDialogBody =>
      'Restoring will replace the text currently in the buffer.';

  @override
  String get recoveryRestoreDialogConfirm => 'Restore';

  @override
  String get recoveryDeleteDialogTitle => 'Delete note?';

  @override
  String get recoveryDeleteDialogBody =>
      'This note will be permanently deleted.';

  @override
  String get recoveryDeleteDialogConfirm => 'Delete';

  @override
  String get recoveryDeleteAllDialogTitle => 'Delete all notes?';

  @override
  String get recoveryDeleteAllDialogBody =>
      'All recovered notes will be permanently deleted.';

  @override
  String get recoveryDeleteAllDialogConfirm => 'Delete all';

  @override
  String get recoveryDialogCancel => 'Cancel';

  @override
  String get recoveryBackTooltip => 'Back';

  @override
  String get recoveryToggleLabel => 'Save emergency recovery files';

  @override
  String get recoveryToggleTooltip =>
      'When on, the buffer is saved when the app is backgrounded; the last ten are kept.';

  @override
  String get themeFollowSystem => 'Follow System Style';

  @override
  String get themeLight => 'Light Style';

  @override
  String get themeDark => 'Dark Style';

  @override
  String get themeSelectorLabel => 'Theme';

  @override
  String get menuTooltip => 'Open menu';

  @override
  String get menuPreferences => 'Preferences';

  @override
  String get menuAbout => 'About';

  @override
  String get menuRecovery => 'Recovery';

  @override
  String get menuFind => 'Find / Replace';

  @override
  String get settingsTitle => 'Preferences';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsBehavior => 'Behavior';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get settingsRecoveryEnabled => 'Save emergency recovery files';

  @override
  String get settingsSpellCheck => 'Check spelling';

  @override
  String get aboutTitle => 'About Buffer';

  @override
  String get aboutDeveloper => 'Paolo Santucci';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutLicense => 'GPL-3.0';

  @override
  String get aboutIssues => 'Report an issue';

  @override
  String get aboutWebsite => 'Website';

  @override
  String fontSizeToast(int n) {
    return 'Font size now ${n}pt';
  }

  @override
  String get editorIndentLabel => 'Indent';

  @override
  String get editorOutdentLabel => 'Outdent';

  @override
  String get settingsFontSize => 'Font size';

  @override
  String get settingsMonospaceFont => 'Monospace font';

  @override
  String get settingsLineNumbers => 'Show line numbers';

  @override
  String get a11yZoomIn => 'Increase font size';

  @override
  String get a11yZoomOut => 'Decrease font size';
}
