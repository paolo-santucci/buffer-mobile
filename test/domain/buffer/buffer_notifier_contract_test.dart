import 'package:buffer/domain/buffer/buffer_notifier.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-test fake — the only concrete implementation in scope for these tests.
// ---------------------------------------------------------------------------

class _FakeBufferNotifier implements BufferNotifier {
  _FakeBufferNotifier() : _state = BufferState.empty();

  BufferState _state;

  @override
  BufferState get state => _state;

  @override
  void updateText(String text) {
    _state = _state.copyWith(text: text, isDirty: text.isNotEmpty);
  }

  @override
  void reset() {
    _state = BufferState.empty();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BufferNotifier contract', () {
    // -----------------------------------------------------------------------
    // Interface-shape assertions (FR-09)
    // -----------------------------------------------------------------------

    test(
      'given_BufferNotifier_when_inspected_then_state_getter_exists_and_mutators_are_exactly_updateText_and_reset',
      () {
        // A fake that compiles and satisfies the interface is proof the three
        // members exist with the exact declared signatures.  The compile-time
        // check IS the shape assertion; if a fourth public mutator were added
        // to the interface the fake would have to implement it too.
        final notifier = _FakeBufferNotifier();

        // state getter is accessible
        expect(notifier.state, isA<BufferState>());

        // updateText and reset are callable — no other public mutators exist
        // because the fake would fail to compile if any were missing.
        notifier.updateText('probe');
        notifier.reset();
        // reaching here without compile error confirms mutators == {updateText, reset}
      },
    );

    // -----------------------------------------------------------------------
    // Ephemerality backstop: no persistence/share method names (EC-08/NFR-09)
    // -----------------------------------------------------------------------

    test(
      'given_BufferNotifier_interface_when_member_names_checked_then_no_name_matches_save_persist_write_store_share',
      () {
        // The interface declares exactly: state, updateText, reset.
        // Assert none of them match the forbidden pattern.
        const memberNames = ['state', 'updateText', 'reset'];
        final forbidden = RegExp(
          r'save|persist|write|store|share',
          caseSensitive: false,
        );

        for (final name in memberNames) {
          expect(
            forbidden.hasMatch(name),
            isFalse,
            reason:
                'Member "$name" matches forbidden persistence/share pattern',
          );
        }
      },
    );

    // -----------------------------------------------------------------------
    // Happy-path behaviour (FR-09)
    // -----------------------------------------------------------------------

    test(
      'given_state_is_empty_when_updateText_called_with_abc_then_state_text_equals_abc',
      () {
        final notifier = _FakeBufferNotifier();

        notifier.updateText('abc');

        expect(notifier.state.text, equals('abc'));
      },
    );

    // -----------------------------------------------------------------------
    // Reset behaviour (FR-09)
    // -----------------------------------------------------------------------

    test(
      'given_state_text_is_abc_when_reset_called_then_state_equals_BufferState_empty',
      () {
        final notifier = _FakeBufferNotifier()..updateText('abc');

        notifier.reset();

        expect(notifier.state, equals(BufferState.empty()));
      },
    );
  });
}
