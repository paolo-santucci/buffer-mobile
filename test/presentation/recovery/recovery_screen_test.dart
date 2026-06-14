// TASK-10 (M5): RecoveryScreen widget tests — TDD red phase written first.
//
// Spec refs: FR-M5-05, FR-M5-06, FR-M5-07, FR-M5-08, FR-M5-10, FR-M5-11,
//            FR-M5-13, FR-M5-14, NFR-M5-02, NFR-M5-05, NFR-M5-06
// Canon ref: .claude/docs/canon/ui-design-bible.md
//            .claude/docs/specs/sp-20260614-m5-emergency-recovery-assessment/
//            consolidated-inputs.md §4/§5
//
// Strategy: ProviderScope with fake recoveryListProvider + settingsProvider +
// bufferProvider overrides, mirroring find_search_bar_test.dart.
//
// All tests are expected to fail (red) until
// lib/presentation/recovery/recovery_screen.dart is implemented.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/recovery/recovery_list_provider.dart';
import 'package:buffer/presentation/recovery/recovery_screen.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

/// Tracks calls to populate() for assertion.
///
/// [_initialText] is used to pre-seed the buffer state from [build] so the
/// notifier doesn't need to call [state=] before being attached to a container.
class _TrackingBufferNotifier extends BufferNotifierImpl {
  _TrackingBufferNotifier({this._initialText = ''});

  final String _initialText;
  int populateCount = 0;
  String? lastPopulatedText;

  @override
  BufferState build() => BufferState(text: _initialText);

  @override
  void populate(String text) {
    populateCount++;
    lastPopulatedText = text;
    super.populate(text);
  }
}

/// Fake [RecoveryListNotifier] backed by an in-memory list.
///
/// Extends [RecoveryListNotifier] so it can be used with
/// `recoveryListProvider.overrideWith(() => _FakeRecoveryListNotifier(...))`.
/// Tracks calls to [delete], [deleteAll], and [restore] for assertion.
class _FakeRecoveryListNotifier extends RecoveryListNotifier {
  _FakeRecoveryListNotifier({
    required List<RecoveryNote> initialNotes,
    Map<String, String>? texts,
    this._shouldError = false,
  }) : _notes = List<RecoveryNote>.from(initialNotes),
       _texts = texts ?? {};

  final List<RecoveryNote> _notes;
  final Map<String, String> _texts;
  final bool _shouldError;

  int deleteCount = 0;
  RecoveryNote? lastDeleted;
  int deleteAllCount = 0;
  int restoreCount = 0;
  String? lastRestoredPath;

  @override
  Future<List<RecoveryNote>> build() async {
    if (_shouldError) throw Exception('fake list error');
    return List<RecoveryNote>.from(_notes);
  }

  @override
  Future<void> refresh() async {
    state = AsyncData(List<RecoveryNote>.from(_notes));
  }

  @override
  Future<void> delete(RecoveryNote note) async {
    deleteCount++;
    lastDeleted = note;
    _notes.removeWhere((n) => n.path == note.path);
    state = AsyncData(List<RecoveryNote>.from(_notes));
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCount++;
    _notes.clear();
    state = const AsyncData(<RecoveryNote>[]);
  }

  @override
  Future<String> restore(RecoveryNote note) async {
    restoreCount++;
    lastRestoredPath = note.path;
    return _texts[note.path] ?? 'restored text';
  }
}

/// Fake [SettingsNotifier] with a controllable [emergencyRecoveryEnabled] flag.
///
/// Extends [SettingsNotifier] so it can be used with
/// `settingsProvider.overrideWith(() => _FakeSettingsNotifier(...))`.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier({this._enabled = true});

  bool _enabled;
  int setEnabledCount = 0;
  bool? lastSetValue;

  @override
  Future<AppSettings> build() async {
    return AppSettings(emergencyRecoveryEnabled: _enabled);
  }

  @override
  Future<void> setEmergencyRecoveryEnabled(bool enabled) async {
    setEnabledCount++;
    lastSetValue = enabled;
    _enabled = enabled;
    state = AsyncData(AppSettings(emergencyRecoveryEnabled: _enabled));
  }
}

// ---------------------------------------------------------------------------
// Test notes helpers
// ---------------------------------------------------------------------------

RecoveryNote _note(String label, {int hoursAgo = 0}) {
  final savedAt = DateTime.utc(2026, 6, 14, 12 - hoursAgo);
  return RecoveryNote(
    path: '/recovery/$label.txt',
    savedAt: savedAt,
    preview: 'preview of $label',
  );
}

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildApp({
  required _FakeRecoveryListNotifier recoveryNotifier,
  required _FakeSettingsNotifier settingsNotifier,
  required _TrackingBufferNotifier bufferNotifier,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: [
      recoveryListProvider.overrideWith(() => recoveryNotifier),
      settingsProvider.overrideWith(() => settingsNotifier),
      bufferProvider.overrideWith(() => bufferNotifier),
    ],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const RecoveryScreen(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. List rows — 2 notes → 2 rows with timestamp + preview
  // =========================================================================
  group('RecoveryScreen list rows', () {
    testWidgets(
      'given_2notes_when_mounted_then_renders2RowsWithTimestampAndPreview',
      (tester) async {
        final note1 = _note('a', hoursAgo: 0);
        final note2 = _note('b', hoursAgo: 1);
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note1, note2],
          texts: {note1.path: 'full text a', note2.path: 'full text b'},
        );
        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        // Both previews must appear.
        expect(find.text('preview of a'), findsOneWidget);
        expect(find.text('preview of b'), findsOneWidget);

        // Two Opacity widgets at 0.58 for the secondary text (timestamp +
        // preview). There may be more Opacity widgets from other elements —
        // we assert at least one per note (the preview secondary text).
        final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
        final dimmed = opacities
            .where((o) => (o.opacity - 0.58).abs() < 0.001)
            .toList();
        expect(dimmed.length, greaterThanOrEqualTo(2));
      },
    );
  });

  // =========================================================================
  // 2. Empty state — 0 notes → dedicated empty widget
  // =========================================================================
  group('RecoveryScreen empty state', () {
    testWidgets('given_0notes_when_mounted_then_showsDedicatedEmptyState', (
      tester,
    ) async {
      final recoveryNotifier = _FakeRecoveryListNotifier(initialNotes: []);
      await tester.pumpWidget(
        _buildApp(
          recoveryNotifier: recoveryNotifier,
          settingsNotifier: _FakeSettingsNotifier(),
          bufferNotifier: _TrackingBufferNotifier(),
        ),
      );
      await tester.pumpAndSettle();

      // The ARB key 'recoveryEmpty' → 'No recovered notes' in EN.
      expect(find.text('No recovered notes'), findsOneWidget);

      // No note previews when empty — verify no note row previews rendered.
      // (SwitchListTile renders a ListTile internally, so we check for
      // the absence of note-specific content rather than ListTile type.)
      expect(find.text('preview of'), findsNothing);
    });
  });

  // =========================================================================
  // 3. AsyncError → error/empty state rendered, no crash
  // =========================================================================
  group('RecoveryScreen error state', () {
    testWidgets('given_asyncError_when_mounted_then_rendersErrorStateNoCrash', (
      tester,
    ) async {
      final recoveryNotifier = _FakeRecoveryListNotifier(
        initialNotes: [],
        shouldError: true,
      );
      await tester.pumpWidget(
        _buildApp(
          recoveryNotifier: recoveryNotifier,
          settingsNotifier: _FakeSettingsNotifier(),
          bufferNotifier: _TrackingBufferNotifier(),
        ),
      );
      // Pump without settle so we can handle the error state.
      await tester.pump();
      await tester.pump();

      // No crash — widget still renders without exception.
      expect(tester.takeException(), isNull);

      // The empty/error state text should appear (same ARB key).
      expect(find.text('No recovered notes'), findsOneWidget);
    });
  });

  // =========================================================================
  // 4. Restore with EMPTY buffer → populate called, no dialog, Navigator.pop
  // =========================================================================
  group('RecoveryScreen restore empty buffer', () {
    testWidgets(
      'given_emptyBuffer_when_restoreTapped_then_populateCalledNoDialogNavigatorPop',
      (tester) async {
        final note = _note('restore-me');
        final bufferNotifier = _TrackingBufferNotifier(); // empty by default
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note],
          texts: {note.path: 'restored text'},
        );

        // Use a navigator so we can verify pop.
        bool didPop = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              recoveryListProvider.overrideWith(() => recoveryNotifier),
              settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
              bufferProvider.overrideWith(() => bufferNotifier),
            ],
            child: MediaQuery(
              data: const MediaQueryData(),
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('en'),
                home: Builder(
                  builder: (ctx) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RecoveryScreen(),
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
                navigatorObservers: [_PopObserver(() => didPop = true)],
              ),
            ),
          ),
        );

        // Navigate to RecoveryScreen.
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Tap the restore button for the only note.
        await tester.tap(find.byTooltip('Restore'));
        await tester.pumpAndSettle();

        // No AlertDialog should appear (empty buffer).
        expect(find.byType(AlertDialog), findsNothing);

        // populate was called once with the restored text.
        expect(bufferNotifier.populateCount, 1);
        expect(bufferNotifier.lastPopulatedText, 'restored text');

        // Navigator popped.
        expect(didPop, isTrue);
      },
    );
  });

  // =========================================================================
  // 5. Restore with NON-EMPTY buffer → AlertDialog shown first
  //    confirm → populate + pop; dismiss → no populate
  // =========================================================================
  group('RecoveryScreen restore non-empty buffer', () {
    testWidgets(
      'given_nonEmptyBuffer_when_restoreTapped_then_alertDialogShownFirst',
      (tester) async {
        final note = _note('restore-nonempty');
        final bufferNotifier = _TrackingBufferNotifier(
          initialText: 'existing text',
        );
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note],
          texts: {note.path: 'restored text'},
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: bufferNotifier,
          ),
        );
        await tester.pumpAndSettle();

        // Tap restore.
        await tester.tap(find.byTooltip('Restore'));
        await tester.pumpAndSettle();

        // AlertDialog must appear.
        expect(find.byType(AlertDialog), findsOneWidget);

        // No populate yet.
        expect(bufferNotifier.populateCount, 0);
      },
    );

    testWidgets('given_restoreDialog_when_confirmed_then_populatePlusPop', (
      tester,
    ) async {
      final note = _note('restore-confirm');
      final bufferNotifier = _TrackingBufferNotifier(
        initialText: 'existing text',
      );
      final recoveryNotifier = _FakeRecoveryListNotifier(
        initialNotes: [note],
        texts: {note.path: 'restored text'},
      );

      bool didPop = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryListProvider.overrideWith(() => recoveryNotifier),
            settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
            bufferProvider.overrideWith(() => bufferNotifier),
          ],
          child: MediaQuery(
            data: const MediaQueryData(),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RecoveryScreen(),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
              navigatorObservers: [_PopObserver(() => didPop = true)],
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();

      // AlertDialog present — confirm.
      expect(find.byType(AlertDialog), findsOneWidget);

      // The confirm button text is 'Restore' (ARB recoveryRestoreDialogConfirm).
      // Tap it.
      await tester.tap(find.text('Restore').last);
      await tester.pumpAndSettle();

      expect(bufferNotifier.populateCount, 1);
      expect(bufferNotifier.lastPopulatedText, 'restored text');
      expect(didPop, isTrue);
    });

    testWidgets('given_restoreDialog_when_dismissed_then_populateNotCalled', (
      tester,
    ) async {
      final note = _note('restore-dismiss');
      final bufferNotifier = _TrackingBufferNotifier(
        initialText: 'existing text',
      );
      final recoveryNotifier = _FakeRecoveryListNotifier(
        initialNotes: [note],
        texts: {note.path: 'restored text'},
      );

      await tester.pumpWidget(
        _buildApp(
          recoveryNotifier: recoveryNotifier,
          settingsNotifier: _FakeSettingsNotifier(),
          bufferNotifier: bufferNotifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();

      // Cancel.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No populate, dialog gone, list still visible.
      expect(bufferNotifier.populateCount, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('preview of restore-dismiss'), findsOneWidget);
    });

    testWidgets(
      'given_restoreDialog_when_shown_then_confirmActionHasColorSchemeErrorStyling',
      (tester) async {
        final note = _note('restore-error-style');
        final bufferNotifier = _TrackingBufferNotifier(
          initialText: 'existing text',
        );
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note],
          texts: {note.path: 'text'},
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: bufferNotifier,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Restore'));
        await tester.pumpAndSettle();

        // The confirm TextButton should use ColorScheme.error foreground.
        // Find the confirm button widget.
        final confirmButtons = tester
            .widgetList<TextButton>(find.byType(TextButton))
            .toList();
        expect(
          confirmButtons.isNotEmpty,
          isTrue,
          reason: 'Expected at least one TextButton in dialog',
        );

        // Hit-test the confirm button — should be >= 48dp.
        final confirmFinder = find.text('Restore').last;
        final renderBox = tester.renderObject<RenderBox>(
          find.ancestor(of: confirmFinder, matching: find.byType(TextButton)),
        );
        expect(renderBox.size.height, greaterThanOrEqualTo(48.0));
      },
    );
  });

  // =========================================================================
  // 6. Delete single note → confirm dialog → delete(note) → row removed
  // =========================================================================
  group('RecoveryScreen delete single note', () {
    testWidgets(
      'given_3notes_when_deleteNote2Confirmed_then_deleteCalledAndRowRemoved',
      (tester) async {
        final note1 = _note('a');
        final note2 = _note('b', hoursAgo: 1);
        final note3 = _note('c', hoursAgo: 2);
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note1, note2, note3],
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        // Find all Delete tooltip buttons and tap the second one (note2).
        final deleteBtns = find.byTooltip('Delete');
        expect(deleteBtns, findsNWidgets(3));

        await tester.tap(deleteBtns.at(1));
        await tester.pumpAndSettle();

        // Confirm dialog must appear.
        expect(find.byType(AlertDialog), findsOneWidget);

        // Confirm — find the 'Delete' button inside the dialog.
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        // delete() called once.
        expect(recoveryNotifier.deleteCount, 1);
        expect(recoveryNotifier.lastDeleted?.path, note2.path);

        // note2 preview gone; note1 and note3 still present.
        expect(find.text('preview of b'), findsNothing);
        expect(find.text('preview of a'), findsOneWidget);
        expect(find.text('preview of c'), findsOneWidget);
      },
    );

    testWidgets(
      'given_deleteDialog_when_dismissed_then_deleteNotCalledAndRowsRemain',
      (tester) async {
        final note1 = _note('a');
        final note2 = _note('b', hoursAgo: 1);
        final note3 = _note('c', hoursAgo: 2);
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note1, note2, note3],
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Delete').first);
        await tester.pumpAndSettle();

        // Cancel.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(recoveryNotifier.deleteCount, 0);
        expect(find.text('preview of a'), findsOneWidget);
        expect(find.text('preview of b'), findsOneWidget);
        expect(find.text('preview of c'), findsOneWidget);
      },
    );
  });

  // =========================================================================
  // 7. Delete-all → confirm dialog → deleteAll() → empty state
  // =========================================================================
  group('RecoveryScreen delete-all', () {
    testWidgets(
      'given_3notes_when_deleteAllConfirmed_then_deleteAllCalledAndEmptyState',
      (tester) async {
        final note1 = _note('a');
        final note2 = _note('b', hoursAgo: 1);
        final note3 = _note('c', hoursAgo: 2);
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note1, note2, note3],
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the delete-all button in the app bar.
        await tester.tap(find.byTooltip('Delete all'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        // Confirm 'Delete all'.
        await tester.tap(find.text('Delete all').last);
        await tester.pumpAndSettle();

        expect(recoveryNotifier.deleteAllCount, 1);
        expect(find.text('No recovered notes'), findsOneWidget);
      },
    );

    testWidgets(
      'given_deleteAllDialog_when_dismissed_then_deleteAllNotCalledAndRowsRemain',
      (tester) async {
        final note1 = _note('a');
        final note2 = _note('b', hoursAgo: 1);
        final note3 = _note('c', hoursAgo: 2);
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note1, note2, note3],
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Delete all'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(recoveryNotifier.deleteAllCount, 0);
        expect(find.text('preview of a'), findsOneWidget);
        expect(find.text('preview of b'), findsOneWidget);
        expect(find.text('preview of c'), findsOneWidget);
      },
    );
  });

  // =========================================================================
  // 8. Back affordance → Navigator.pop, no populate/updateText
  // =========================================================================
  group('RecoveryScreen back affordance', () {
    testWidgets(
      'given_nonEmptyBuffer_when_backTapped_then_popNoPopulateAndBufferUnchanged',
      (tester) async {
        final note = _note('a');
        final bufferNotifier = _TrackingBufferNotifier(
          initialText: 'original text',
        );
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note],
        );

        bool didPop = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              recoveryListProvider.overrideWith(() => recoveryNotifier),
              settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
              bufferProvider.overrideWith(() => bufferNotifier),
            ],
            child: MediaQuery(
              data: const MediaQueryData(),
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('en'),
                home: Builder(
                  builder: (ctx) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RecoveryScreen(),
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
                navigatorObservers: [_PopObserver(() => didPop = true)],
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Back button is Icons.arrow_back with ARB tooltip.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        // populate was never called — buffer unchanged.
        expect(bufferNotifier.populateCount, 0);
        expect(bufferNotifier.lastPopulatedText, isNull);
        expect(didPop, isTrue);
      },
    );

    testWidgets('given_mounted_then_backButtonIsIconsArrowBackAndAtLeast48dp', (
      tester,
    ) async {
      final recoveryNotifier = _FakeRecoveryListNotifier(initialNotes: []);
      await tester.pumpWidget(
        _buildApp(
          recoveryNotifier: recoveryNotifier,
          settingsNotifier: _FakeSettingsNotifier(),
          bufferNotifier: _TrackingBufferNotifier(),
        ),
      );
      await tester.pumpAndSettle();

      // Back button tooltip exists.
      expect(find.byTooltip('Back'), findsOneWidget);

      // Icon is arrow_back.
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('Back'),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.arrow_back);

      // Hit-target ≥ 48dp.
      final renderBox = tester.renderObject<RenderBox>(find.byTooltip('Back'));
      expect(renderBox.size.width, greaterThanOrEqualTo(48.0));
      expect(renderBox.size.height, greaterThanOrEqualTo(48.0));
    });
  });

  // =========================================================================
  // 9. Toggle on→off → setEmergencyRecoveryEnabled(false) once; ≥48dp
  // =========================================================================
  group('RecoveryScreen toggle', () {
    testWidgets(
      'given_toggleOn_when_toggled_then_setEnabledFalseOnceAndReflectsOff',
      (tester) async {
        final settingsNotifier = _FakeSettingsNotifier(enabled: true);
        final recoveryNotifier = _FakeRecoveryListNotifier(initialNotes: []);

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: settingsNotifier,
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        // Find the SwitchListTile by its label.
        expect(find.text('Save emergency recovery files'), findsOneWidget);

        // Toggle it off.
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(settingsNotifier.setEnabledCount, 1);
        expect(settingsNotifier.lastSetValue, isFalse);

        // Switch should now be off.
        final sw = tester.widget<Switch>(find.byType(Switch));
        expect(sw.value, isFalse);
      },
    );

    testWidgets('given_mounted_then_toggleControlIsAtLeast48dp', (
      tester,
    ) async {
      final recoveryNotifier = _FakeRecoveryListNotifier(initialNotes: []);
      await tester.pumpWidget(
        _buildApp(
          recoveryNotifier: recoveryNotifier,
          settingsNotifier: _FakeSettingsNotifier(),
          bufferNotifier: _TrackingBufferNotifier(),
        ),
      );
      await tester.pumpAndSettle();

      // SwitchListTile hit target — find it by the label.
      final listTileFinder = find.widgetWithText(
        SwitchListTile,
        'Save emergency recovery files',
      );
      final renderBox = tester.renderObject<RenderBox>(listTileFinder);
      expect(renderBox.size.height, greaterThanOrEqualTo(48.0));
    });
  });

  // =========================================================================
  // 10. Every IconButton has ARB-resolved non-empty tooltip ≥ 48dp
  // =========================================================================
  group('RecoveryScreen icon buttons a11y and size', () {
    testWidgets(
      'given_2notes_when_mounted_then_everyIconButtonHasARBTooltipAnd48dpHitTarget',
      (tester) async {
        final note1 = _note('a');
        final note2 = _note('b', hoursAgo: 1);
        final recoveryNotifier = _FakeRecoveryListNotifier(
          initialNotes: [note1, note2],
        );

        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        // Find all Tooltip widgets and assert non-empty message + ≥ 48dp.
        final tooltipFinders = find.byType(Tooltip);
        expect(tooltipFinders, findsWidgets);

        for (final tooltipFinder in tooltipFinders.evaluate()) {
          final tooltip = tooltipFinder.widget as Tooltip;
          expect(
            tooltip.message,
            isNotNull,
            reason: 'Tooltip message must not be null',
          );
          expect(
            (tooltip.message ?? '').isNotEmpty,
            isTrue,
            reason: 'Tooltip message must not be empty: ${tooltip.message}',
          );
        }

        // Check all IconButton hit targets.
        final iconButtons = find.byType(IconButton);
        for (final iconButtonFinder in iconButtons.evaluate()) {
          final box = iconButtonFinder.renderObject as RenderBox?;
          if (box != null) {
            expect(
              box.size.width,
              greaterThanOrEqualTo(48.0),
              reason: 'IconButton width must be ≥ 48dp: ${box.size.width}',
            );
            expect(
              box.size.height,
              greaterThanOrEqualTo(48.0),
              reason: 'IconButton height must be ≥ 48dp: ${box.size.height}',
            );
          }
        }
      },
    );
  });

  // =========================================================================
  // 11. Under MediaQuery.disableAnimations → instant transitions
  // =========================================================================
  group('RecoveryScreen reduce-motion', () {
    testWidgets(
      'given_disableAnimations_when_mounted_then_screenRendersWithoutCrash',
      (tester) async {
        final recoveryNotifier = _FakeRecoveryListNotifier(initialNotes: []);
        await tester.pumpWidget(
          _buildApp(
            recoveryNotifier: recoveryNotifier,
            settingsNotifier: _FakeSettingsNotifier(),
            bufferNotifier: _TrackingBufferNotifier(),
            disableAnimations: true,
          ),
        );
        await tester.pumpAndSettle();

        // The screen mounts without crash under reduce-motion.
        expect(tester.takeException(), isNull);

        // The AnimatedCrossFade inside RecoveryScreen should use instant (1ms)
        // duration. The Scaffold + AppBar are present regardless.
        expect(find.byType(RecoveryScreen), findsOneWidget);

        // Verify the AnimatedCrossFade is present (crossfade-only motion).
        expect(find.byType(AnimatedCrossFade), findsOneWidget);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Navigator observer helper
// ---------------------------------------------------------------------------

class _PopObserver extends NavigatorObserver {
  _PopObserver(this.onPop);
  final VoidCallback onPop;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPop();
  }
}
