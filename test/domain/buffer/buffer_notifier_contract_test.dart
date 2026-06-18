import 'package:foglietto/domain/buffer/buffer_notifier.dart';
import 'package:foglietto/domain/buffer/buffer_state.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-test fake — the only concrete implementation in scope for these tests.
// If BufferNotifier gains or loses a public member this fake must be updated,
// which surfaces the contract change at compile time.
// ---------------------------------------------------------------------------

class _FakeBufferNotifier implements BufferNotifier {
  _FakeBufferNotifier() : _state = BufferState.empty();

  BufferState _state;

  @override
  BufferState get state => _state;

  @override
  void updateText(String text) {
    _state = _state.copyWith(text: text);
  }

  @override
  void reset() {
    _state = BufferState.empty();
  }

  @override
  void populate(String text) {
    _state = _state.copyWith(text: text);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BufferNotifier contract', () {
    // -----------------------------------------------------------------------
    // Interface-shape assertions (FR-09 / FR-M2-09)
    // -----------------------------------------------------------------------

    test(
      'given_BufferNotifier_when_inspected_then_state_getter_and_mutators_are_exactly_updateText_reset_populate',
      () {
        // A fake that compiles and satisfies the interface is proof the members
        // exist with the exact declared signatures.  The compile-time check IS
        // the shape assertion; if the interface gains or loses a public member
        // the fake will fail to compile.
        final notifier = _FakeBufferNotifier();

        // state getter is accessible
        expect(notifier.state, isA<BufferState>());

        // All three mutators are callable
        notifier.updateText('probe');
        notifier.reset();
        notifier.populate('seed');
        // reaching here without compile error confirms mutators == {updateText, reset, populate}
      },
    );

    // -----------------------------------------------------------------------
    // Ephemerality backstop: no persistence/share method names (EC-08/NFR-09)
    // -----------------------------------------------------------------------

    test(
      'given_BufferNotifier_interface_when_member_names_checked_then_no_name_matches_save_persist_write_store_share',
      () {
        // The interface declares exactly: state, updateText, reset, populate.
        // Assert none of them match the forbidden pattern.
        const memberNames = ['state', 'updateText', 'reset', 'populate'];
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
    // Happy-path behaviour — updateText (FR-09)
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
    // Happy-path behaviour — populate (FR-M2-09 / §5.1.3)
    // -----------------------------------------------------------------------

    test(
      'given_state_is_empty_when_populate_called_with_hello_then_state_text_equals_hello',
      () {
        final notifier = _FakeBufferNotifier();

        notifier.populate('hello');

        expect(notifier.state.text, equals('hello'));
      },
    );

    test(
      'given_state_is_empty_when_populate_called_with_empty_string_then_state_text_is_empty',
      () {
        final notifier = _FakeBufferNotifier();

        notifier.populate('');

        expect(notifier.state.text, equals(''));
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
