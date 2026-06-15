// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Buffer';

  @override
  String get findHintText => 'Cerca';

  @override
  String findCountLabel(int position, int count) {
    return '$position di $count';
  }

  @override
  String get findPreviousTooltip => 'Risultato precedente';

  @override
  String get findNextTooltip => 'Risultato successivo';

  @override
  String get findReplaceHintText => 'Sostituisci';

  @override
  String get findReplaceButton => 'Sostituisci';

  @override
  String get findReplaceToggleTooltip => 'Mostra sostituzione';

  @override
  String get findCloseTooltip => 'Indietro';

  @override
  String get recoveryTitle => 'Recupero';

  @override
  String get recoveryEmpty => 'Nessuna nota recuperata';

  @override
  String get recoveryRestoreTooltip => 'Ripristina';

  @override
  String get recoveryDeleteTooltip => 'Elimina';

  @override
  String get recoveryDeleteAllTooltip => 'Elimina tutto';

  @override
  String get recoveryRestoreDialogTitle => 'Ripristinare la nota?';

  @override
  String get recoveryRestoreDialogBody =>
      'Il ripristino sostituirà il testo attualmente nel buffer.';

  @override
  String get recoveryRestoreDialogConfirm => 'Ripristina';

  @override
  String get recoveryDeleteDialogTitle => 'Eliminare la nota?';

  @override
  String get recoveryDeleteDialogBody =>
      'La nota verrà eliminata definitivamente.';

  @override
  String get recoveryDeleteDialogConfirm => 'Elimina';

  @override
  String get recoveryDeleteAllDialogTitle => 'Eliminare tutte le note?';

  @override
  String get recoveryDeleteAllDialogBody =>
      'Tutte le note recuperate verranno eliminate definitivamente.';

  @override
  String get recoveryDeleteAllDialogConfirm => 'Elimina tutto';

  @override
  String get recoveryDialogCancel => 'Annulla';

  @override
  String get recoveryBackTooltip => 'Indietro';

  @override
  String get recoveryToggleLabel => 'Salva i file di recupero di emergenza';

  @override
  String get recoveryToggleTooltip =>
      'Se attivo, il buffer viene salvato quando l\'app va in background; vengono conservati gli ultimi dieci.';

  @override
  String get themeFollowSystem => 'Segui stile di sistema';

  @override
  String get themeLight => 'Stile chiaro';

  @override
  String get themeDark => 'Stile scuro';

  @override
  String get themeSelectorLabel => 'Tema';

  @override
  String get menuTooltip => 'Apri menu';

  @override
  String get menuPreferences => 'Preferenze';

  @override
  String get menuAbout => 'Informazioni';

  @override
  String get menuRecovery => 'Recupero';

  @override
  String get menuFind => 'Trova / Sostituisci';

  @override
  String get settingsTitle => 'Preferenze';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsBehavior => 'Comportamento';

  @override
  String get settingsThemeMode => 'Tema';

  @override
  String get settingsRecoveryEnabled => 'Salva i file di recupero di emergenza';

  @override
  String get settingsSpellCheck => 'Controllo ortografico';

  @override
  String get aboutTitle => 'Informazioni su Buffer';

  @override
  String get aboutOriginalDeveloper => 'Chris Heywood';

  @override
  String get aboutDeveloper => 'Paolo Santucci';

  @override
  String get aboutVersion => 'Versione';

  @override
  String get aboutLicense => 'GPL-3.0';

  @override
  String get aboutIssues => 'Segnala un problema';

  @override
  String get aboutWebsite => 'Sito web';

  @override
  String fontSizeToast(int n) {
    return 'Dimensione carattere: $n pt';
  }

  @override
  String get editorIndentLabel => 'Rientra';

  @override
  String get editorOutdentLabel => 'Riduci rientro';

  @override
  String get settingsFontSize => 'Dimensione carattere';

  @override
  String get settingsMonospaceFont => 'Carattere monospazio';

  @override
  String get settingsLineNumbers => 'Mostra i numeri di riga';

  @override
  String get a11yZoomIn => 'Aumenta dimensione carattere';

  @override
  String get a11yZoomOut => 'Riduci dimensione carattere';
}
