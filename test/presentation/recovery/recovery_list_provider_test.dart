// Tests for RecoveryListNotifier / recoveryListProvider (TASK-07).
//
// Spec refs: FR-M5-01, FR-M5-07, FR-M5-10, FR-M5-11, FR-M5-12, NFR-M5-02
//
// TDD: tests written first. The implementation file
// lib/presentation/recovery/recovery_list_provider.dart does not yet exist at
// time of writing — all tests below are expected to fail (red) until it is
// created.
//
// Test strategy: a FakeRecoveryRepository backed by an in-memory map is
// preferred over a temp-dir-backed one because it is hermetic, deterministic,
// and avoids dart:io in the test-double layer. The SRP assertion
// (restore does NOT call bufferProvider.notifier.populate) is verified by NOT
// overriding bufferProvider in the container for the restore tests — if
// restore internally called populate, the unimplemented bufferProvider would
// throw.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/recovery/recovery_list_provider.dart';

// ---------------------------------------------------------------------------
// Test double
// ---------------------------------------------------------------------------

/// In-memory fake that satisfies [RecoveryRepository] without dart:io.
///
/// [_notes] is the ordered list of notes (newest-first); the fake preserves
/// that ordering so callers can trust it during tests.
class _FakeRecoveryRepository implements RecoveryRepository {
  _FakeRecoveryRepository(List<RecoveryNote> notes, Map<String, String> texts)
    : _notes = List<RecoveryNote>.from(notes),
      _texts = Map<String, String>.from(texts);

  final List<RecoveryNote> _notes;
  final Map<String, String> _texts; // path → full text
  bool shouldThrow = false;

  @override
  Future<File> save(String text) => throw UnimplementedError('save not needed');

  @override
  Future<List<RecoveryNote>> list() async {
    if (shouldThrow) throw const FileSystemException('fake list failure');
    return List<RecoveryNote>.from(_notes);
  }

  @override
  Future<String> read(RecoveryNote note) async {
    final text = _texts[note.path];
    if (text == null) throw FileSystemException('not found', note.path);
    return text;
  }

  @override
  Future<void> delete(RecoveryNote note) async {
    _notes.removeWhere((n) => n.path == note.path);
    _texts.remove(note.path);
  }

  @override
  Future<void> deleteAll() async {
    _notes.clear();
    _texts.clear();
  }

  @override
  Future<void> trim(int keep) async {
    // not exercised in this test file
  }

  // Defect-B sync stub — not exercised by list-provider tests.
  @override
  File saveSync(String text, {int keep = 10}) =>
      throw UnimplementedError('saveSync not needed in list tests');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds three [RecoveryNote]s newest-first (descending savedAt).
List<RecoveryNote> _threeNotes() {
  final now = DateTime.now().toUtc();
  return [
    RecoveryNote(
      path: '/recovery/2026-06-14T12-00-00-000Z.txt',
      savedAt: now.subtract(const Duration(minutes: 1)),
      preview: 'newest note',
    ),
    RecoveryNote(
      path: '/recovery/2026-06-14T11-00-00-000Z.txt',
      savedAt: now.subtract(const Duration(hours: 1)),
      preview: 'middle note',
    ),
    RecoveryNote(
      path: '/recovery/2026-06-14T10-00-00-000Z.txt',
      savedAt: now.subtract(const Duration(hours: 2)),
      preview: 'oldest note',
    ),
  ];
}

Map<String, String> _threeTexts(List<RecoveryNote> notes) => {
  notes[0].path: 'newest note full text',
  notes[1].path: 'middle note full text',
  notes[2].path: 'oldest note full text',
};

/// Creates a [ProviderContainer] with the given fake wired into
/// [recoveryRepositoryProvider]. [bufferProvider] is intentionally NOT
/// overridden — any accidental call to populate would throw
/// UnimplementedError, asserting SRP for restore().
ProviderContainer _container(_FakeRecoveryRepository fake) {
  return ProviderContainer(
    overrides: [recoveryRepositoryProvider.overrideWithValue(fake)],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RecoveryListNotifier', () {
    // -----------------------------------------------------------------------
    // build() — list state
    // -----------------------------------------------------------------------

    test(
      '3-note repo → build() resolves AsyncData of 3 notes newest-first',
      () async {
        final notes = _threeNotes();
        final fake = _FakeRecoveryRepository(notes, _threeTexts(notes));
        final container = _container(fake);
        addTearDown(container.dispose);

        // Wait for the AsyncNotifier to settle.
        await container.read(recoveryListProvider.future);
        final state = container.read(recoveryListProvider);

        expect(state, isA<AsyncData<List<RecoveryNote>>>());
        final list = state.value!;
        expect(list.length, 3);
        // Each preview ≤80, no \n
        for (final note in list) {
          expect(note.preview.length, lessThanOrEqualTo(80));
          expect(note.preview.contains('\n'), isFalse);
        }
        // Newest-first order preserved from the fake.
        expect(list[0].path, notes[0].path);
        expect(list[1].path, notes[1].path);
        expect(list[2].path, notes[2].path);
      },
    );

    test('empty repo → build() resolves AsyncData([])', () async {
      final fake = _FakeRecoveryRepository([], {});
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(recoveryListProvider.future);
      final state = container.read(recoveryListProvider);

      expect(state, isA<AsyncData<List<RecoveryNote>>>());
      expect(state.value, isEmpty);
    });

    test(
      'repo.list() throws FileSystemException → state is AsyncError',
      () async {
        final fake = _FakeRecoveryRepository([], {})..shouldThrow = true;
        final container = _container(fake);
        addTearDown(container.dispose);

        // Wait for the future to settle (will throw internally).
        try {
          await container.read(recoveryListProvider.future);
        } catch (_) {
          // Expected — the future rejects.
        }

        final state = container.read(recoveryListProvider);
        expect(state, isA<AsyncError<List<RecoveryNote>>>());
      },
    );

    // -----------------------------------------------------------------------
    // delete
    // -----------------------------------------------------------------------

    test(
      'delete(middleNote) → repo removes it + refresh → state has 2 notes',
      () async {
        final notes = _threeNotes();
        final fake = _FakeRecoveryRepository(notes, _threeTexts(notes));
        final container = _container(fake);
        addTearDown(container.dispose);

        await container.read(recoveryListProvider.future);

        final middleNote = notes[1];
        await container.read(recoveryListProvider.notifier).delete(middleNote);

        final state = container.read(recoveryListProvider);
        expect(state, isA<AsyncData<List<RecoveryNote>>>());
        final list = state.value!;
        expect(list.length, 2);
        expect(list.any((n) => n.path == middleNote.path), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // deleteAll
    // -----------------------------------------------------------------------

    test('deleteAll() → state transitions to AsyncData([])', () async {
      final notes = _threeNotes();
      final fake = _FakeRecoveryRepository(notes, _threeTexts(notes));
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(recoveryListProvider.future);
      await container.read(recoveryListProvider.notifier).deleteAll();

      final state = container.read(recoveryListProvider);
      expect(state, isA<AsyncData<List<RecoveryNote>>>());
      expect(state.value, isEmpty);
    });

    // -----------------------------------------------------------------------
    // restore — SRP check: does NOT touch bufferProvider
    // -----------------------------------------------------------------------

    test('restore(note) returns full text and does NOT call '
        'bufferProvider.notifier.populate (SRP)', () async {
      final notes = _threeNotes();
      final fake = _FakeRecoveryRepository(notes, _threeTexts(notes));
      final container = _container(fake);
      addTearDown(container.dispose);

      await container.read(recoveryListProvider.future);

      // If restore() internally calls bufferProvider.notifier.populate,
      // the unimplemented provider would throw UnimplementedError and the
      // test would fail — that is the SRP enforcement mechanism.
      final text = await container
          .read(recoveryListProvider.notifier)
          .restore(notes[0]);

      expect(text, 'newest note full text');
    });

    // -----------------------------------------------------------------------
    // NFR-M5-02 — no persist|write|store|share in provider/method names
    // -----------------------------------------------------------------------

    test('NFR-M5-02: recoveryListProvider source contains no method names '
        'matching persist|write|store|share', () {
      // Source-level scan mirrors the m5_gate test pattern.
      // We read the source file and assert the regex doesn't match any method
      // declaration line.
      final source = File(
        'lib/presentation/recovery/recovery_list_provider.dart',
      ).readAsStringSync();

      // Look for method/function declarations (lines with `Future` or `void`
      // or the method name directly) that include the banned words.
      final banned = RegExp(r'\b(persist|write|store|share)\b');
      // Filter to lines that look like method declarations.
      final methodLines = source
          .split('\n')
          .where(
            (line) =>
                line.trimLeft().startsWith('Future') ||
                line.trimLeft().startsWith('void') ||
                line.trimLeft().startsWith('String'),
          )
          .toList();

      for (final line in methodLines) {
        expect(
          banned.hasMatch(line),
          isFalse,
          reason: 'Method declaration contains banned word: $line',
        );
      }
    });

    // -----------------------------------------------------------------------
    // Non-auto-disposed — provider is not auto-disposed (single-provider rule)
    // -----------------------------------------------------------------------

    test(
      'recoveryListProvider is non-auto-disposed (AsyncNotifierProvider)',
      () {
        // The provider being AsyncNotifierProvider (not .autoDispose) means
        // state survives zero-listener windows. We verify this structural fact
        // by checking that the provider's runtimeType is NOT an autoDispose
        // variant. The Riverpod API makes this observable via toString().
        final description = recoveryListProvider.toString();
        expect(
          description.contains('autoDispose'),
          isFalse,
          reason: 'recoveryListProvider must not be auto-disposed',
        );
      },
    );
  });
}
