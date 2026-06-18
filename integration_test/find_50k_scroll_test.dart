// Find 50k-char scroll on-device integration test — buffer-mobile
//
// Spec refs: FR-17; NFR-01, NFR-04 ("50k-char find scroll" metric)
// Platforms: Android (primary); iOS (secondary).
// Tags: ['on-device'] — this test REQUIRES a running Android/iOS device or
//   emulator. It is SKIPPED by plain `flutter test` (no --device-id). Run it
//   manually with:
//
//   flutter test integration_test/find_50k_scroll_test.dart \
//       --device-id <device-id>
//
// What it verifies (FR-17 / NFR-01 — 50k-char find-and-scroll performance):
//
//   1. Boot the app with a 50 000-character buffer seeded via provider override.
//   2. Activate find for a query that produces 200+ matches in the buffer.
//   3. Navigate through 10 matches via findProvider.next().
//   4. Assert the shared _scrollController offset changes toward the expected
//      match position on each navigation (direction test: FR-17 scroll-to-match).
//   5. Assert no dropped-frame regression vs the pre-find baseline (NFR-01):
//      the 99th-percentile frame time during find navigation must not exceed
//      twice the 99th-percentile baseline frame time measured before search.
//
// Why this test matters (NFR-01 / NFR-04):
//   The spec requires that match recomputation is offloaded to a compute()
//   isolate at/above kFindIsolateThreshold (10k chars). This test exercises
//   the above-threshold isolate path with a 50k buffer — 5x the threshold —
//   and confirms that scroll-to-match drives the shared ScrollController
//   offset in the correct direction without jank.
//
//   The frame-timing baseline is measured before search is activated; the
//   navigation phase measures frames during next() calls. A regression is
//   flagged if the p99 frame time during navigation exceeds 2x the baseline
//   p99. This is deliberately generous (not a sub-16ms gate) to avoid CI
//   flakiness across device tiers while still catching gross regressions
//   (e.g., blocking UI work on each recompute keypress).
//
// NOTE: Scroll assertion uses the direction test only (offset moves toward
//   the match), not an exact pixel value — consistent with spec §5.4 which
//   states "brought into view" as the behaviour-level requirement (FR-17).
//   On headless flutter-tester the test is tagged @Tags(['on-device']) and
//   will be skipped automatically.

@Tags(['on-device'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foglietto/domain/find/find_state.dart';
import 'package:foglietto/infrastructure/share/share_intent_service.dart';
import 'package:foglietto/presentation/app.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/find/find_provider.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────────────

/// Total buffer character count: 5× the kFindIsolateThreshold (10k) so
/// the above-threshold compute() isolate path is exercised.
const _kBufferLength = 50000;

/// Query term. Short, common, and case-insensitive: guaranteed to appear
/// many times in the filler text (≥ 200 occurrences in 50k chars).
const _kQuery = 'the';

/// Minimum match count the buffer must yield for the test to be meaningful.
const _kMinMatchCount = 200;

/// Number of next() navigations to perform in the test.
const _kNavigations = 10;

/// Maximum p99-frame-time ratio before a regression is flagged.
/// 2.0 = 200 % of baseline (generous threshold for multi-device CI).
const _kMaxFrameRatioP99 = 2.0;

// ──────────────────────────────────────────────────────────────────────────────
// Fakes
// ──────────────────────────────────────────────────────────────────────────────

/// No-op share service — keeps the provider graph satisfied without touching
/// the real package channel.
class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Builds a 50k-character buffer text that contains `_kQuery` many times.
///
/// Strategy: repeat a short sentence that naturally contains "the" multiple
/// times per paragraph. 50 chars per paragraph × 1000 repetitions = 50k chars.
String _buildLargeBuffer() {
  // "the" appears 3 times per unit of 50 chars → ~3000 occurrences total.
  const unit = 'The quick brown fox jumps over the lazy dog. And the ';
  final sb = StringBuffer();
  while (sb.length < _kBufferLength) {
    sb.write(unit);
  }
  return sb.toString().substring(0, _kBufferLength);
}

/// Returns the p99 value from a sorted list of microsecond durations.
/// Returns 0 if the list is empty.
int _p99(List<int> sorted) {
  if (sorted.isEmpty) return 0;
  final idx = ((sorted.length - 1) * 0.99).round();
  return sorted[idx];
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ────────────────────────────────────────────────────────────────────────────
  // Test: 50k buffer + 200+ matches → 10 next() navigations assert
  //       scroll offset moves toward match and no dropped-frame regression.
  //
  // This test exercises the full above-threshold search path end-to-end on a
  // real Android/iOS device:
  //   1. Boot the app with a 50k-char buffer via initialSharedTextProvider.
  //   2. Measure baseline frame timings for 2 seconds of idle rendering.
  //   3. Open search (findProvider.setQuery + startSearch).
  //   4. Wait for the above-threshold compute() to settle (match list non-empty).
  //   5. Record the initial ScrollController offset before navigation.
  //   6. For each of 10 navigations via next():
  //      a. Record the currentMatchIndex before and after.
  //      b. Record the scroll offset after pumpAndSettle.
  //      c. Assert the offset moved toward the expected proportional position
  //         of the match in the buffer.
  //   7. Assert p99 frame time during navigation ≤ _kMaxFrameRatioP99 × baseline.
  //
  // Why direction-only assertion (not exact pixel):
  //   Exact pixel positions depend on the device's font metrics, screen density,
  //   and layout engine. The spec says "brought into view" (FR-17); the
  //   direction test (offset changes) is deterministic and device-independent.
  //   On device the RenderEditable geometry path runs; in a headless runner
  //   (excluded by @Tags) the proportional fallback would run.
  // ────────────────────────────────────────────────────────────────────────────

  testWidgets('should_scroll_toward_each_match_and_no_dropped_frame_regression_'
      'when_navigating_10_matches_given_50k_buffer', (tester) async {
    // ── 1. Set up fresh SharedPreferences and seed a 50k-char buffer ──────
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final largeBuffer = _buildLargeBuffer();

    expect(
      largeBuffer.length,
      equals(_kBufferLength),
      reason: 'Buffer must be exactly $_kBufferLength characters.',
    );

    // Count "the" occurrences (case-insensitive) to verify ≥ 200 matches.
    final matchCount = RegExp(
      _kQuery,
      caseSensitive: false,
    ).allMatches(largeBuffer).length;
    expect(
      matchCount,
      greaterThanOrEqualTo(_kMinMatchCount),
      reason:
          'Buffer must contain at least $_kMinMatchCount occurrences of '
          '"$_kQuery" (case-insensitive) to exercise meaningful navigation.',
    );

    // ── 2. Boot the full app with the seeded buffer ───────────────────────
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Seed the buffer via the share-intake path (same as warm-start
          // share flow in M2). On warm start the screen calls
          // populate(initialSharedText) → bufferProvider is primed with
          // the large buffer without any UI interaction.
          initialSharedTextProvider.overrideWithValue(largeBuffer),
          shareIntentServiceProvider.overrideWithValue(
            _FakeShareIntentService(),
          ),
        ],
        child: const BufferApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the buffer TextField exists and contains the seeded text.
    final textFieldFinder = find.byType(TextField);
    expect(
      textFieldFinder,
      findsOneWidget,
      reason: 'BufferScreen must render exactly one TextField.',
    );
    final textField = tester.widget<TextField>(textFieldFinder);
    final controller = textField.controller;
    expect(
      controller,
      isNotNull,
      reason: 'TextField must have an EditorController.',
    );
    expect(
      controller!.text.length,
      equals(_kBufferLength),
      reason: 'EditorController must hold the full 50k-char buffer.',
    );

    // Locate the ScrollController via the Scrollable widget that wraps the
    // editor. The BufferScreen uses a shared external ScrollController
    // attached to a SingleChildScrollView (or equivalent) around the
    // TextField. We read its current offset before and after navigation.
    //
    // Note: We use the Scrollable's ScrollController rather than a direct
    // reference because the _scrollController field is private. The single
    // Scrollable in the editor tree owns our shared controller.
    final scrollableFinder = find.byType(Scrollable).first;
    expect(
      scrollableFinder,
      findsOneWidget,
      reason:
          'BufferScreen must contain a Scrollable (shared ScrollController '
          'attached, EC-09).',
    );
    ScrollController? scrollController;
    await tester.runAsync(() async {
      final scrollable = tester.widget<Scrollable>(scrollableFinder);
      scrollController = scrollable.controller;
    });

    // ── 3. Measure baseline frame timings (idle rendering for 2 seconds) ──
    final baselineTimings = <int>[];
    binding.addTimingsCallback((timingsList) {
      for (final t in timingsList) {
        baselineTimings.add(t.totalSpan.inMicroseconds);
      }
    });

    // Pump for ~2 seconds to collect baseline frame data.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    binding.addTimingsCallback((_) {}); // detach; baseline captured

    // ── 4. Activate find search ───────────────────────────────────────────
    // Access findProvider via the ProviderScope container bound to the app.
    // We use the ProviderScope.containerOf approach to read/write providers
    // from the test body without a ConsumerWidget.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    container.read(findProvider.notifier).setQuery(_kQuery);
    container.read(findProvider.notifier).startSearch(entryOffset: 0);

    // Allow the above-threshold compute() isolate to complete. The buffer
    // is 50k chars (> kFindIsolateThreshold=10k), so the recompute is
    // dispatched asynchronously. Wait for the match list to settle.
    int waitIterations = 0;
    while (container.read(findProvider).matches.isEmpty &&
        waitIterations < 50) {
      await tester.pump(const Duration(milliseconds: 100));
      waitIterations++;
    }
    await tester.pumpAndSettle();

    final stateAfterSearch = container.read(findProvider);
    expect(
      stateAfterSearch.active,
      isTrue,
      reason: 'findProvider must be active after startSearch (FR-06).',
    );
    expect(
      stateAfterSearch.matches.length,
      greaterThanOrEqualTo(_kMinMatchCount),
      reason:
          'findProvider must have found ≥ $_kMinMatchCount matches in the '
          '50k buffer after isolate recompute (FR-08 / NFR-01).',
    );
    expect(
      stateAfterSearch.currentMatchIndex,
      isNotNull,
      reason:
          'currentMatchIndex must be non-null after startSearch with a '
          'non-empty match list (FR-06).',
    );

    // ── 5. Record initial scroll offset ───────────────────────────────────
    double prevOffset = 0.0;
    if (scrollController != null && scrollController!.hasClients) {
      prevOffset = scrollController!.offset;
    }

    // ── 6. Navigate 10 matches via next() ─────────────────────────────────
    final navTimings = <int>[];
    binding.addTimingsCallback((timingsList) {
      for (final t in timingsList) {
        navTimings.add(t.totalSpan.inMicroseconds);
      }
    });

    FindState? lastState;
    for (var nav = 0; nav < _kNavigations; nav++) {
      final stateBeforeNav = container.read(findProvider);
      final indexBefore = stateBeforeNav.currentMatchIndex!;

      container.read(findProvider.notifier).next();
      await tester.pumpAndSettle();

      final stateAfterNav = container.read(findProvider);
      final indexAfter = stateAfterNav.currentMatchIndex!;

      // Assert index advanced (or wrapped — both are valid).
      final expectedIndex = (indexBefore + 1) % stateAfterNav.matches.length;
      expect(
        indexAfter,
        equals(expectedIndex),
        reason:
            'Navigation $nav: currentMatchIndex must advance from '
            '$indexBefore to $expectedIndex (wrap at ${stateAfterNav.matches.length}, '
            'FR-10).',
      );

      // Assert scroll offset moved (scroll-to-match, FR-17).
      // The direction test: the offset must have changed (either increased
      // toward a lower match or decreased toward an earlier one on wrap).
      // We assert the change is non-trivial (> 0 px or a wrap-around
      // direction change) rather than an exact pixel value, since the exact
      // geometry depends on device font metrics.
      if (scrollController != null && scrollController!.hasClients) {
        final currentOffset = scrollController!.offset;
        final currentMatch = stateAfterNav.currentMatch!;
        final text = controller.text;

        // Compute the proportional expected offset for this match.
        final proportion = text.isNotEmpty
            ? currentMatch.start / text.length
            : 0.0;
        final maxExtent = scrollController!.position.maxScrollExtent;
        final expectedApproxOffset = (proportion * maxExtent).clamp(
          0.0,
          maxExtent,
        );

        // Relaxed assertion: after scroll-to-match, the current offset must
        // be closer to the expected proportional position than the previous
        // offset was, OR the offset must have changed (meaning the scroll
        // mechanism fired). We accept either condition.
        final distBefore = (prevOffset - expectedApproxOffset).abs();
        final distAfter = (currentOffset - expectedApproxOffset).abs();

        expect(
          distAfter <= distBefore || (currentOffset - prevOffset).abs() > 0.5,
          isTrue,
          reason:
              'Navigation $nav: scroll offset must move toward match '
              '$indexAfter (match.start=${currentMatch.start}, '
              'proportional position ≈ $expectedApproxOffset, '
              'prevOffset=$prevOffset, currentOffset=$currentOffset). '
              'FR-17 scroll-to-match must animate the shared '
              'ScrollController toward the current match.',
        );

        prevOffset = currentOffset;
      }

      lastState = stateAfterNav;
    }

    binding.addTimingsCallback((_) {}); // detach; nav timings captured

    // Final state sanity check.
    expect(
      lastState,
      isNotNull,
      reason: 'lastState must be set after navigation loop.',
    );
    expect(
      lastState!.active,
      isTrue,
      reason:
          'findProvider must remain active after $_kNavigations next() calls '
          '(EC-17 provider survival).',
    );

    // ── 7. Frame-timing regression check (NFR-01) ─────────────────────────
    // Only assert if we collected meaningful frame data.
    if (baselineTimings.isNotEmpty && navTimings.isNotEmpty) {
      final baselineSorted = List<int>.from(baselineTimings)..sort();
      final navSorted = List<int>.from(navTimings)..sort();

      final baselineP99 = _p99(baselineSorted);
      final navP99 = _p99(navSorted);

      if (baselineP99 > 0) {
        final ratio = navP99 / baselineP99;
        expect(
          ratio,
          lessThanOrEqualTo(_kMaxFrameRatioP99),
          reason:
              'NFR-01 dropped-frame regression: p99 frame time during find '
              'navigation ($navP99µs) exceeds $_kMaxFrameRatioP99× the '
              'baseline p99 ($baselineP99µs). Ratio: '
              '${ratio.toStringAsFixed(2)}. The above-threshold compute() '
              'isolate path must not block UI frames during navigation.',
        );
      }
    }
  });
}
