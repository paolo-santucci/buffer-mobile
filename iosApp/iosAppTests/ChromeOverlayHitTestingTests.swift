// ChromeOverlayHitTestingTests.swift
// iosAppTests
//
// XCTest coverage for the chrome layer's visibility seam:
//   - the pure predicate that decides whether a chrome-hide transition dismisses an
//     open menu panel (write-source 5, §5.1.f / FR-07).
//
// Strategy:
//   `ChromeOverlay.shouldDismissMenuOnVisibilityChange(visible:menuPresented:)` is a
//   pure, side-effect-free function — it is the guard in front of the chrome-hide
//   dismissal writer. It needs no view, no window, and no asynchronous work, so every
//   row of its truth table is asserted directly, plus the exhaustive enumeration that
//   pins the dismissal set to exactly one input combination. Any wrong cell fails.
//
// M3 CI conventions (MANDATORY):
//   @MainActor at class level; no async/await, no Task, no wall-clock sleeps;
//   @testable import iosApp.
//
// Spec refs: §5.1.a, §5.1.f, §4.2; FR-06, FR-07, FR-07n, FR-08; EC-16, EC-22; NFR-06.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import XCTest
@testable import iosApp

// ---------------------------------------------------------------------------
// MARK: - ChromeOverlayHitTestingTests
// ---------------------------------------------------------------------------

/// The chrome layer's visibility-to-dismissal contract: when the chrome is hidden the
/// open menu panel is dismissed, when it is revealed the panel state is left alone, and
/// a hide with the panel already closed is a no-op (FR-07/FR-07n).
@MainActor
final class ChromeOverlayHitTestingTests: XCTestCase {

    // -----------------------------------------------------------------------
    // MARK: - Truth table (§5.1.f)
    // -----------------------------------------------------------------------

    /// FR-07 / EC-16: hiding the chrome while the menu panel is open is the one
    /// combination that dismisses — write-source 5 fires from the crossfade wrapper.
    func testChromeHideDismissesOpenMenu() {
        XCTAssertTrue(
            ChromeOverlay.shouldDismissMenuOnVisibilityChange(visible: false, menuPresented: true)
        )
    }

    /// FR-07n: a reveal never dismisses — neither an open panel nor a closed one.
    func testRevealNeverDismisses() {
        XCTAssertFalse(
            ChromeOverlay.shouldDismissMenuOnVisibilityChange(visible: true, menuPresented: true)
        )
        XCTAssertFalse(
            ChromeOverlay.shouldDismissMenuOnVisibilityChange(visible: true, menuPresented: false)
        )
    }

    /// EC-16 idempotency: hiding the chrome with the panel already closed writes nothing.
    func testHideWithClosedMenuIsIdempotent() {
        XCTAssertFalse(
            ChromeOverlay.shouldDismissMenuOnVisibilityChange(visible: false, menuPresented: false)
        )
    }

    /// Exhaustive over both inputs: the predicate is total, and its dismissing set is
    /// exactly `{(visible: false, menuPresented: true)}` — nothing else dismisses.
    func testDismissingCombinationIsExhaustivelyUnique() {
        let combinations: [(visible: Bool, menuPresented: Bool)] = [
            (visible: true, menuPresented: true),
            (visible: true, menuPresented: false),
            (visible: false, menuPresented: true),
            (visible: false, menuPresented: false)
        ]

        let dismissing = combinations.filter {
            ChromeOverlay.shouldDismissMenuOnVisibilityChange(
                visible: $0.visible,
                menuPresented: $0.menuPresented
            )
        }

        XCTAssertEqual(dismissing.count, 1, "exactly one combination may dismiss the panel")
        XCTAssertEqual(dismissing.map { $0.visible }, [false])
        XCTAssertEqual(dismissing.map { $0.menuPresented }, [true])
    }
}
