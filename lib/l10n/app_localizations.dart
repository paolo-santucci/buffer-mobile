import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// The title of the application displayed in the window title bar and as the app name.
  ///
  /// In en, this message translates to:
  /// **'Buffer Mobile'**
  String get appTitle;

  /// Placeholder text shown in the search field.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get findHintText;

  /// Label showing the current match position and total match count. Empty when no matches.
  ///
  /// In en, this message translates to:
  /// **'{position} of {count}'**
  String findCountLabel(int position, int count);

  /// Tooltip for the previous match button in the search bar.
  ///
  /// In en, this message translates to:
  /// **'Previous Match'**
  String get findPreviousTooltip;

  /// Tooltip for the next match button in the search bar.
  ///
  /// In en, this message translates to:
  /// **'Next Match'**
  String get findNextTooltip;

  /// Placeholder text shown in the replace field.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get findReplaceHintText;

  /// Label for the replace button in the search bar.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get findReplaceButton;

  /// Tooltip for the toggle replace button in the search bar.
  ///
  /// In en, this message translates to:
  /// **'Toggle Replace'**
  String get findReplaceToggleTooltip;

  /// Tooltip for the close/back button in the search bar.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get findCloseTooltip;

  /// Title displayed in the recovery screen app bar.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get recoveryTitle;

  /// Empty-state message shown on the recovery screen when there are no saved recovery notes.
  ///
  /// In en, this message translates to:
  /// **'No recovered notes'**
  String get recoveryEmpty;

  /// Tooltip for the restore icon button on each recovery note row.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get recoveryRestoreTooltip;

  /// Tooltip for the delete icon button on each recovery note row.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get recoveryDeleteTooltip;

  /// Tooltip for the delete-all icon button in the recovery screen app bar.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get recoveryDeleteAllTooltip;

  /// Title of the confirmation dialog shown before restoring a recovery note when the buffer is non-empty.
  ///
  /// In en, this message translates to:
  /// **'Restore note?'**
  String get recoveryRestoreDialogTitle;

  /// Body text of the confirmation dialog shown before restoring a recovery note.
  ///
  /// In en, this message translates to:
  /// **'Restoring will replace the text currently in the buffer.'**
  String get recoveryRestoreDialogBody;

  /// Confirm action label in the restore confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get recoveryRestoreDialogConfirm;

  /// Title of the confirmation dialog shown before permanently deleting a single recovery note.
  ///
  /// In en, this message translates to:
  /// **'Delete note?'**
  String get recoveryDeleteDialogTitle;

  /// Body text of the confirmation dialog shown before deleting a single recovery note.
  ///
  /// In en, this message translates to:
  /// **'This note will be permanently deleted.'**
  String get recoveryDeleteDialogBody;

  /// Confirm action label in the single-note delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get recoveryDeleteDialogConfirm;

  /// Title of the confirmation dialog shown before permanently deleting all recovery notes.
  ///
  /// In en, this message translates to:
  /// **'Delete all notes?'**
  String get recoveryDeleteAllDialogTitle;

  /// Body text of the confirmation dialog shown before deleting all recovery notes.
  ///
  /// In en, this message translates to:
  /// **'All recovered notes will be permanently deleted.'**
  String get recoveryDeleteAllDialogBody;

  /// Confirm action label in the delete-all confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get recoveryDeleteAllDialogConfirm;

  /// Cancel action label used in all recovery confirmation dialogs.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get recoveryDialogCancel;

  /// Tooltip for the back icon button in the recovery screen app bar.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get recoveryBackTooltip;

  /// Label for the toggle switch that enables or disables emergency recovery file saving.
  ///
  /// In en, this message translates to:
  /// **'Save emergency recovery files'**
  String get recoveryToggleLabel;

  /// Tooltip describing the behaviour of the emergency recovery toggle switch.
  ///
  /// In en, this message translates to:
  /// **'When on, the buffer is saved when the app is backgrounded; the last ten are kept.'**
  String get recoveryToggleTooltip;

  /// Label for the Follow System theme swatch in the theme selector. Used verbatim as upstream semantics label.
  ///
  /// In en, this message translates to:
  /// **'Follow System Style'**
  String get themeFollowSystem;

  /// Label for the Light theme swatch in the theme selector. Used verbatim as upstream semantics label.
  ///
  /// In en, this message translates to:
  /// **'Light Style'**
  String get themeLight;

  /// Label for the Dark theme swatch in the theme selector. Used verbatim as upstream semantics label.
  ///
  /// In en, this message translates to:
  /// **'Dark Style'**
  String get themeDark;

  /// Accessibility label for the theme selector widget.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSelectorLabel;

  /// Tooltip and accessibility label for the chrome menu affordance button that opens the main menu sheet.
  ///
  /// In en, this message translates to:
  /// **'Open menu'**
  String get menuTooltip;

  /// Tooltip/Semantics label for the outgoing-share button in the editor chrome.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTooltip;

  /// Label for the Preferences entry in the main menu sheet, navigating to the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get menuPreferences;

  /// Label for the About entry in the main menu sheet, navigating to the About screen.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// Label for the Recovery entry in the main menu sheet, navigating to the Recovery screen.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get menuRecovery;

  /// Label for the Find / Replace entry in the main menu sheet, opening the find-and-replace bar. SP-20260615 FR-17.
  ///
  /// In en, this message translates to:
  /// **'Find / Replace'**
  String get menuFind;

  /// Title displayed in the Settings screen app bar.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsTitle;

  /// Section header for the Appearance group in the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Section header for the Behavior group in the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get settingsBehavior;

  /// Label for the theme mode row in the Settings screen Appearance section.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeMode;

  /// Label for the recovery-enabled toggle in the Settings screen Behavior section.
  ///
  /// In en, this message translates to:
  /// **'Save emergency recovery files'**
  String get settingsRecoveryEnabled;

  /// Label for the spell-check toggle in the Settings screen Behavior section.
  ///
  /// In en, this message translates to:
  /// **'Check spelling'**
  String get settingsSpellCheck;

  /// Title displayed in the About screen app bar.
  ///
  /// In en, this message translates to:
  /// **'About Buffer'**
  String get aboutTitle;

  /// Developer name displayed in the About screen.
  ///
  /// In en, this message translates to:
  /// **'Paolo Santucci'**
  String get aboutDeveloper;

  /// Label prefix for the app version row in the About screen. The actual version number is appended at runtime.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// License identifier displayed in the About screen. Must reference GPL-3.0 to match upstream licensing (NFR-M6-06).
  ///
  /// In en, this message translates to:
  /// **'GPL-3.0'**
  String get aboutLicense;

  /// Label for the issue-tracker link in the About screen. The URL itself is not localized.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get aboutIssues;

  /// Label for the project website link in the About screen. The URL itself is not localized.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// Toast message shown when the font size changes. The {n} placeholder is replaced with the new font size in points. Defined for M7 use — not emitted by M6 (FR-M6-16 / D2).
  ///
  /// In en, this message translates to:
  /// **'Font size now {n}pt'**
  String fontSizeToast(int n);

  /// Accessibility label for the indent toolbar button in the editor.
  ///
  /// In en, this message translates to:
  /// **'Indent'**
  String get editorIndentLabel;

  /// Accessibility label for the outdent toolbar button in the editor.
  ///
  /// In en, this message translates to:
  /// **'Outdent'**
  String get editorOutdentLabel;

  /// Label for the font size row in the Settings screen Appearance section and in the menu sheet.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get settingsFontSize;

  /// Label for the monospace font toggle in the Settings screen Appearance section.
  ///
  /// In en, this message translates to:
  /// **'Monospace font'**
  String get settingsMonospaceFont;

  /// Accessibility label for the increase font size (zoom in) button in the FontSizeStepper.
  ///
  /// In en, this message translates to:
  /// **'Increase font size'**
  String get a11yZoomIn;

  /// Accessibility label for the decrease font size (zoom out) button in the FontSizeStepper.
  ///
  /// In en, this message translates to:
  /// **'Decrease font size'**
  String get a11yZoomOut;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
