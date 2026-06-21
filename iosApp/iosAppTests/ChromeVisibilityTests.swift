// ChromeVisibilityTests.swift
// iosAppTests
//
// XCTest coverage for ChromeVisibility — the auto-hide/reveal chrome state machine
// (FR-19, FR-20, FR-21; EC-11, EC-12, EC-14).
//
// All transitions are exercised via the inject* synchronous seam (§5.1.d),
// which bypasses the 1300ms wall-clock debounce entirely (OQ-10 resolution:
// the seam IS the only path to test debounce correctness; no @visibleForTesting
// timer accessor is required because injectIdleRevealFired() suffices to verify
// all debounce-outcome cases without wall-clock dependency).
//
// M3 CI conventions (MANDATORY):
//   @MainActor at class level — ChromeVisibility is @Observable (main-actor-bound).
//   No async/await, no Task, no wall-clock sleeps.
//   import shared + @testable import iosApp.
//
// Spec refs: §7.1 Layer B; §7.2 integration; EC-11, EC-12, EC-14; OQ-10.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import XCTest
import shared
@testable import iosApp

// MARK: - ChromeVisibilityTests

/// Tests for ChromeVisibility state-machine transitions via the inject* seam.
///
/// `@MainActor`: `ChromeVisibility` is an `@Observable` class; mutations and reads
/// on `state` / `isVisible` must occur on the main actor.
@MainActor
final class ChromeVisibilityTests: XCTestCase {

    // -----------------------------------------------------------------------
    // MARK: - Initial state

    /// Fresh instance starts as .visible (FR-19).
    func test_initialState_isVisible() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible, "fresh ChromeVisibility must start as .visible (FR-19)")
        XCTAssertTrue(cv.isVisible, "isVisible must be true on a fresh instance (FR-19)")
    }

    // -----------------------------------------------------------------------
    // MARK: - injectTyping — hide transitions

    /// Typing from .visible → .hidden (FR-19 typing transition).
    func test_injectTyping_fromVisible_becomesHidden() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        cv.injectTyping()

        XCTAssertEqual(cv.state, .hidden,
            "injectTyping() from .visible must transition to .hidden (FR-19)")
        XCTAssertFalse(cv.isVisible,
            "isVisible must be false when state is .hidden (FR-19)")
    }

    /// Typing twice — stays .hidden; second typing does not flip back (EC-11 debounce
    /// restarts but state does not change).
    func test_injectTyping_twice_staysHidden() {
        let cv = ChromeVisibility()
        cv.injectTyping()
        XCTAssertEqual(cv.state, .hidden)

        cv.injectTyping()

        XCTAssertEqual(cv.state, .hidden,
            "injectTyping() twice must keep state .hidden — debounce restarts, no flip (EC-11)")
    }

    // -----------------------------------------------------------------------
    // MARK: - injectScroll — forward / reverse transitions

    /// Hidden + scroll forward (.forward) → .visible (scroll-up reveals chrome, FR-19).
    func test_injectScrollForward_fromHidden_becomesVisible() {
        let cv = ChromeVisibility()
        cv.injectTyping()                              // → .hidden
        XCTAssertEqual(cv.state, .hidden)

        cv.injectScroll(.forward)

        XCTAssertEqual(cv.state, .visible,
            ".hidden + injectScroll(.forward) must transition to .visible (FR-19)")
    }

    /// Visible + scroll reverse (.reverse) → .hidden (scroll-down hides chrome, FR-19).
    func test_injectScrollReverse_fromVisible_becomesHidden() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        cv.injectScroll(.reverse)

        XCTAssertEqual(cv.state, .hidden,
            ".visible + injectScroll(.reverse) must transition to .hidden (FR-19)")
    }

    /// Visible + scroll forward → stays .visible (self-no-op; EC-12 stale-debounce analogue).
    func test_injectScrollForward_fromVisible_staysVisible() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        cv.injectScroll(.forward)

        XCTAssertEqual(cv.state, .visible,
            ".visible + injectScroll(.forward) must stay .visible (self-no-op; EC-12)")
    }

    // -----------------------------------------------------------------------
    // MARK: - injectKeyboardDismiss

    /// Hidden + keyboard dismiss → .visible (FR-19).
    func test_injectKeyboardDismiss_fromHidden_becomesVisible() {
        let cv = ChromeVisibility()
        cv.injectTyping()                              // → .hidden
        XCTAssertEqual(cv.state, .hidden)

        cv.injectKeyboardDismiss()

        XCTAssertEqual(cv.state, .visible,
            ".hidden + injectKeyboardDismiss() must transition to .visible (FR-19)")
    }

    /// Visible + keyboard dismiss → stays .visible (self-no-op; EC-14 coexistence).
    func test_injectKeyboardDismiss_fromVisible_staysVisible() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        cv.injectKeyboardDismiss()

        XCTAssertEqual(cv.state, .visible,
            ".visible + injectKeyboardDismiss() must stay .visible (no-op stay; EC-14)")
    }

    // -----------------------------------------------------------------------
    // MARK: - injectExplicitReveal

    /// Hidden + explicit reveal → .visible (FR-19 explicit-reveal path).
    func test_injectExplicitReveal_fromHidden_becomesVisible() {
        let cv = ChromeVisibility()
        cv.injectTyping()                              // → .hidden
        XCTAssertEqual(cv.state, .hidden)

        cv.injectExplicitReveal()

        XCTAssertEqual(cv.state, .visible,
            ".hidden + injectExplicitReveal() must transition to .visible (FR-19)")
    }

    /// Visible + explicit reveal → stays .visible (no-op stay per §5.3).
    func test_injectExplicitReveal_fromVisible_staysVisible() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        cv.injectExplicitReveal()

        XCTAssertEqual(cv.state, .visible,
            ".visible + injectExplicitReveal() must stay .visible (no-op stay)")
    }

    // -----------------------------------------------------------------------
    // MARK: - injectIdleRevealFired (synchronous debounce-elapsed seam)

    /// Hidden + idleRevealFired → .visible (FR-20/21 debounce-elapsed reveal, no wall-clock).
    func test_injectIdleRevealFired_fromHidden_becomesVisible() {
        let cv = ChromeVisibility()
        cv.injectTyping()                              // → .hidden
        XCTAssertEqual(cv.state, .hidden)

        cv.injectIdleRevealFired()

        XCTAssertEqual(cv.state, .visible,
            ".hidden + injectIdleRevealFired() must transition to .visible (FR-20/21; no wall-clock)")
    }

    /// Visible + idleRevealFired → stays .visible (stale timer no-op, EC-12).
    func test_injectIdleRevealFired_fromVisible_staysVisible() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        cv.injectIdleRevealFired()

        XCTAssertEqual(cv.state, .visible,
            ".visible + injectIdleRevealFired() must stay .visible (stale-timer no-op; EC-12)")
    }

    // -----------------------------------------------------------------------
    // MARK: - EC-11: debounce restart — 5× typing stays .hidden, then idleRevealFired → .visible

    /// EC-11: multiple typing events keep chrome hidden; only one idleRevealFired needed.
    ///
    /// Five injectTyping() calls in rapid succession each restart the debounce but the state
    /// never flips back to visible. A single injectIdleRevealFired() then reveals (one fire
    /// suffices regardless of how many typing events preceded it).
    func test_EC11_debounceRestart_fiveTypingsThenIdleReveal() {
        let cv = ChromeVisibility()

        for _ in 0..<5 {
            cv.injectTyping()
        }
        XCTAssertEqual(cv.state, .hidden,
            "5× injectTyping() must leave state .hidden (EC-11 debounce restart)")

        cv.injectIdleRevealFired()

        XCTAssertEqual(cv.state, .visible,
            "injectIdleRevealFired() after 5× typing must reveal chrome (EC-11; one fire suffices)")
    }

    // -----------------------------------------------------------------------
    // MARK: - EC-12: scroll-forward cancels pending hide

    /// EC-12: typing → hidden; scroll forward → visible immediately;
    /// subsequent idleRevealFired stays .visible (stale debounce is a self-no-op).
    func test_EC12_scrollForwardCancelsPendingHide_idleRevealStaysVisible() {
        let cv = ChromeVisibility()

        cv.injectTyping()                              // → .hidden (debounce starts)
        XCTAssertEqual(cv.state, .hidden)

        cv.injectScroll(.forward)                      // → .visible immediately
        XCTAssertEqual(cv.state, .visible,
            "injectScroll(.forward) after typing must reveal immediately (EC-12)")

        cv.injectIdleRevealFired()                     // stale debounce fires → self-no-op
        XCTAssertEqual(cv.state, .visible,
            "injectIdleRevealFired() after scroll-forward reveal must stay .visible (EC-12 stale-debounce no-op)")
    }

    // -----------------------------------------------------------------------
    // MARK: - isVisible computed property

    /// isVisible == (state == .visible): true when visible, false when hidden.
    func test_isVisible_tracksState() {
        let cv = ChromeVisibility()

        // .visible
        XCTAssertTrue(cv.isVisible, "isVisible must be true when state == .visible")

        cv.injectTyping()                              // → .hidden
        XCTAssertFalse(cv.isVisible, "isVisible must be false when state == .hidden")

        cv.injectIdleRevealFired()                     // → .visible
        XCTAssertTrue(cv.isVisible, "isVisible must be true again after idle reveal")
    }

    // -----------------------------------------------------------------------
    // MARK: - §7.2 Integration: full state-machine round-trip

    /// Integration: typing → idleReveal → scrollReverse → scrollForward → keyboardDismiss
    /// → explicitReveal — state at each step matches the §4.2 state diagram.
    func test_integration_fullRoundTrip() {
        let cv = ChromeVisibility()

        // Step 1: typing → hidden
        cv.injectTyping()
        XCTAssertEqual(cv.state, .hidden, "step 1: typing → hidden")

        // Step 2: idle-reveal → visible
        cv.injectIdleRevealFired()
        XCTAssertEqual(cv.state, .visible, "step 2: idle-reveal → visible")

        // Step 3: scroll-reverse → hidden
        cv.injectScroll(.reverse)
        XCTAssertEqual(cv.state, .hidden, "step 3: scroll-reverse → hidden")

        // Step 4: scroll-forward → visible
        cv.injectScroll(.forward)
        XCTAssertEqual(cv.state, .visible, "step 4: scroll-forward → visible")

        // Step 5: keyboard-dismiss (already visible → stay)
        cv.injectKeyboardDismiss()
        XCTAssertEqual(cv.state, .visible, "step 5: keyboard-dismiss while visible → no-op stay")

        // Step 6: explicit-reveal (already visible → stay)
        cv.injectExplicitReveal()
        XCTAssertEqual(cv.state, .visible, "step 6: explicit-reveal while visible → no-op stay")
    }

    // -----------------------------------------------------------------------
    // MARK: - §7.2 Integration: Coordinator callbacks feed ChromeVisibility (FR-19 / §4.3)

    /// onTyping wired to ChromeVisibility.injectTyping() flips state to .hidden.
    ///
    /// Exercises the ContentView's event-wiring contract (FR-19 / §4.3 data-flow):
    /// coordinator.onTyping = { cv.injectTyping() } → fire → cv.state == .hidden.
    func test_integration_coordinatorOnTypingWiring_flipsToHidden() {
        let cv = ChromeVisibility()
        XCTAssertEqual(cv.state, .visible)

        // Simulate the ContentView / updateUIView wiring (FR-19).
        let onTyping: () -> Void = { cv.injectTyping() }
        onTyping()

        XCTAssertEqual(cv.state, .hidden,
            "coordinator.onTyping wired to cv.injectTyping() must flip state to .hidden (FR-19 / §4.3)")
    }
}
