// TASK-08: LifecycleBufferHost — paused-save / resumed-reset / R-07 guard /
// detached secondary.
//
// Spec refs: FR-M2-05, FR-M2-06, FR-M2-07, FR-M2-08, EC-M2-02, EC-M2-06,
//            EC-M2-08, EC-M2-13, EC-M2-14, §4.1, §4.2
//
// T-03 fix: _onPaused and _onDetached now call the SYNCHRONOUS use-case path
// (SaveBufferToRecovery.callSync) so bytes hit disk before
// didChangeAppLifecycleState returns. On Android (and iOS), the OS may freeze
// the isolate immediately after the callback returns; async I/O scheduled via
// Futures/microtasks is silently dropped in that window. The sync path
// eliminates the race entirely.
//
// UI Design Canon: This widget renders ONLY its [child] — it adds zero chrome
// (no colour, spacing, decoration, or layout of its own). The ui-design-bible
// §Design ethos "chrome-free at rest" rule is trivially satisfied because the
// host is invisible. No CANON GAP is introduced here.
//
// No literal user-facing strings. No print(). No package:flutter/material.dart
// colour or theme tokens referenced — the host is layout-transparent.

import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

/// A non-visual host widget that:
///
/// 1. Registers itself as a [WidgetsBindingObserver] in [initState] and
///    removes itself in [dispose] — lifecycle callbacks never leak.
/// 2. Renders only its [child] (no chrome, no layout container of its own).
/// 3. Owns the [_savedSinceLastResume] burst-save guard (R-07).
///
/// ## Lifecycle contract (LP §5.3 — inviolable ephemerality):
///
/// - **paused**: primary save trigger. Calls [SaveBufferToRecovery.callSync]
///   so the write completes before the OS has a chance to freeze the isolate.
///   Any [FileSystemException] (or other error) is caught and logged
///   (EC-M2-08) — a backgrounding app must never crash.
/// - **resumed**: calls [bufferProvider.notifier.reset()] and clears
///   `_savedSinceLastResume`.
/// - **detached**: secondary / best-effort path. Saves only if the guard is
///   false. `paused` is inviolable; `detached` must never be the sole save
///   path.
///
/// ## BUG-102 — resumed ordering is safe
///
/// With the sync write path, the durable write is guaranteed to complete
/// BEFORE [didChangeAppLifecycleState] returns for the [paused] event. By
/// the time [resumed] fires and calls [reset()], the file is already
/// on disk. There is no unflushed retry source that [reset()] could destroy.
/// The ordering is explicit: write-on-pause (sync, durable) → reset-on-resume
/// (safe because the write already happened).
///
/// ## Mounting
///
/// This widget is wired above the [Navigator] via [MaterialApp.builder] in
/// TASK-11 so it NEVER unmounts on route changes (EC-M2-14). The underlying
/// [bufferProvider] is non-auto-disposed, so its state survives zero-listener
/// windows during route transitions.
class LifecycleBufferHost extends ConsumerStatefulWidget {
  const LifecycleBufferHost({required this.child, super.key});

  /// The subtree rendered by this host. This widget adds no chrome around it.
  final Widget child;

  @override
  LifecycleBufferHostState createState() => LifecycleBufferHostState();
}

/// Public to allow [WidgetTester.state<LifecycleBufferHostState>] access in
/// tests.  The guard field is exposed via [savedSinceLastResumeForTest] for
/// assertion purposes only — do not read it in production code.
class LifecycleBufferHostState extends ConsumerState<LifecycleBufferHost>
    with WidgetsBindingObserver {
  bool _savedSinceLastResume = false;

  // ---------------------------------------------------------------------------
  // Lifecycle registration
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // App lifecycle callbacks
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _onPaused();
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.detached:
        _onDetached();
      default:
        break;
    }
  }

  /// Primary recovery-save trigger (FR-M2-06, FR-M2-07, FR-M2-08, LP §5.3).
  ///
  /// Uses the SYNCHRONOUS use-case path ([SaveBufferToRecovery.callSync])
  /// so the write completes before this method returns. The OS may freeze the
  /// Dart isolate immediately after [didChangeAppLifecycleState] returns;
  /// any async I/O queued after this point is silently dropped on a real
  /// device. The sync path eliminates the race (T-03 / BUG-105).
  void _onPaused() {
    if (_savedSinceLastResume) return; // R-07 burst guard.

    final text = ref.read(bufferProvider).text;
    if (text.trim().isEmpty) return; // EC-M2-02 trim gate.

    // FR-M5-16 / NFR-M5-03 / EC-08: read settings defensively — no requireValue.
    // const AppSettings() defaults emergencyRecoveryEnabled=true, so the
    // no-crash fallback during AsyncLoading still permits the save (default-ON).
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    if (!settings.emergencyRecoveryEnabled) return;

    _saveSync(text);
  }

  /// Resets buffer to empty and clears the burst guard (FR-M2-05).
  ///
  /// BUG-102: reset is safe here because the durable write is guaranteed to
  /// have completed synchronously on the preceding [paused] event (see class
  /// doc). There is no unflushed retry source that reset() could destroy.
  void _onResumed() {
    // The durable write is already on disk (sync write on paused completed
    // before didChangeAppLifecycleState returned). Reset is therefore safe.
    ref.read(bufferProvider.notifier).reset();
    _savedSinceLastResume = false;
  }

  /// Secondary / best-effort save. Fires ONLY if the guard is clear.
  ///
  /// Per LP §5.3: [_onPaused] is the inviolable primary trigger;
  /// [_onDetached] must never be the only save path.
  ///
  /// Also uses the SYNCHRONOUS save path for the same reason as [_onPaused]:
  /// the isolate may be frozen immediately after this callback returns.
  void _onDetached() {
    if (_savedSinceLastResume) return;

    final text = ref.read(bufferProvider).text;
    if (text.trim().isEmpty) return;

    // FR-M5-16 / NFR-M5-03 / EC-08: same defensive settings read as _onPaused.
    // No requireValue — const AppSettings() defaults emergencyRecoveryEnabled=true.
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    if (!settings.emergencyRecoveryEnabled) return;

    _saveSync(text);
  }

  /// Invokes [SaveBufferToRecovery.callSync] synchronously.
  ///
  /// Sets [_savedSinceLastResume] to `true` on a confirmed non-null write
  /// (BUG-104 success log). Any [FileSystemException] or unexpected error is
  /// caught and logged via [dart:developer log()] — a backgrounding app must
  /// NEVER crash (EC-M2-08). Errors are NEVER rethrown.
  void _saveSync(String text) {
    final useCase = ref.read(saveBufferToRecoveryProvider);
    try {
      final file = useCase.callSync(text);
      if (file != null) {
        // BUG-104: one success log line per confirmed write.
        dev.log(
          'LifecycleBufferHost: recovery saved synchronously to ${file.path}',
          name: 'buffer.lifecycle',
          level: 800, // Level.INFO
        );
        _savedSinceLastResume = true;
      }
    } on FileSystemException catch (error, stack) {
      // EC-M2-08: log but never rethrow — the backgrounding path is silent.
      dev.log(
        'LifecycleBufferHost: sync recovery save failed on background transition.',
        name: 'buffer.lifecycle',
        error: error,
        stackTrace: stack,
        level: 900, // Level.SEVERE
      );
    } catch (error, stack) {
      // Unexpected error: log and do not swallow silently.
      dev.log(
        'LifecycleBufferHost: unexpected error during sync recovery save.',
        name: 'buffer.lifecycle',
        error: error,
        stackTrace: stack,
        level: 1000, // Level.SHOUT
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Test-only access — exposes internal guard for assertion in widget tests.
  // ---------------------------------------------------------------------------

  /// Exposes [_savedSinceLastResume] for widget-test assertions.
  ///
  /// Do NOT read this in production code.
  @visibleForTesting
  bool get savedSinceLastResumeForTest => _savedSinceLastResume;

  // ---------------------------------------------------------------------------
  // Build — renders ONLY the child; no chrome added.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => widget.child;
}
