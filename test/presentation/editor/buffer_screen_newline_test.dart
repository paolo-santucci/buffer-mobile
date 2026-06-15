// T-01 — Real key-event regression tests for Enter / newline handling.
//
// These tests close the "green tests, broken on device" gap that let the
// Enter-is-swallowed defect ship (see assessment: editor-newline-bugs.md).
//
// Root cause recap: the Shortcuts map binds LogicalKeyboardKey.enter to
// ContinueListIntent. EditorContinueListAction.invoke() returns void, which
// means the Framework marks the key event *handled* unconditionally — even on
// non-list lines where continueListOnNewline returns null. As a result,
// EditableText never receives the Enter key and no '\n' is inserted.
//
// Fix (T-01): override consumesKey() on EditorContinueListAction to return
// false when no list continuation applies, so EditableText's default '\n'
// insertion fires and routes through the existing _onControllerChanged literal-
// \n change-path (:510-555 of buffer_screen.dart).
//
// C-06 compliance: tests drive REAL key events via tester.sendKeyEvent so that
// the Shortcuts layer is exercised exactly as it is on a real device.
//
// Spec refs: EC-07, R-03, FR-08, C-01, C-02, C-03, C-06

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async => File('/tmp/sentinel.txt');

  @override
  Future<List<RecoveryNote>> list() async => const [];

  @override
  Future<String> read(RecoveryNote note) async => '';

  @override
  Future<void> delete(RecoveryNote note) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<void> trim(int keep) async {}

  // Defect-B sync stub — not exercised by T-01 tests.
  @override
  File saveSync(String text, {int keep = 10}) => File('/tmp/sentinel-sync.txt');
}

class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(spellingEnabled: false);
}

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

Future<void> _pumpBufferScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSharedTextProvider.overrideWithValue(null),
        shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
        recoveryRepositoryProvider.overrideWithValue(_FakeRecoveryRepository()),
        settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BufferScreen(),
      ),
    ),
  );
  // Allow initState + first frame.
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests — Group 1: Enter key on non-list and list lines
// ---------------------------------------------------------------------------

void main() {
  group('Group 1 — Enter key event (T-01, C-06)', () {
    testWidgets('pressing_enter_on_non_list_line_inserts_literal_newline', (
      tester,
    ) async {
      await _pumpBufferScreen(tester);

      // Focus the editor and type "hello".
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // Read the controller via bufferProvider text.
      final bufferText = ProviderScope.containerOf(
        tester.element(find.byType(BufferScreen)),
      ).read(bufferProvider).text;
      expect(bufferText, 'hello');

      // Place caret at end of "hello" (offset 5).
      final textField = tester.widget<TextField>(find.byType(TextField));
      final editingController = textField.controller!;
      editingController.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      // Act: send a REAL hardware Enter key event through the Shortcuts layer.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Assert: controller.text == "hello\n" and caret == 6.
      expect(
        editingController.text,
        'hello\n',
        reason:
            'Non-list Enter must insert literal \\n via EditableText default; '
            'consumesKey=false on non-list branch must allow the key through.',
      );
      expect(
        editingController.selection.baseOffset,
        6,
        reason: 'Caret must land immediately after the inserted \\n.',
      );
    });

    testWidgets('pressing_enter_on_list_line_continues_list_via_single_path', (
      tester,
    ) async {
      await _pumpBufferScreen(tester);

      // Focus and type "- item" (a markdown bullet list line).
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '- item');
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      final editingController = textField.controller!;

      // Place caret at end of "- item" (offset 6).
      editingController.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      // Act: send a REAL hardware Enter key event.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Assert: text continues the list via continueListOnNewline (EC-07, R-03).
      // Expected: "- item\n- " (7 + 2 = 9 chars, caret at 9).
      expect(
        editingController.text,
        '- item\n- ',
        reason:
            'List Enter must fire continueListOnNewline (the SINGLE list path) '
            'and produce the continuation marker; consumesKey=true on list branch '
            'must prevent double insertion.',
      );
      expect(
        editingController.selection.baseOffset,
        9,
        reason: 'Caret must land after the inserted continuation prefix "- ".',
      );
    });
  });
}
