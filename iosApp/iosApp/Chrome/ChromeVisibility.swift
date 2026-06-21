// Chrome/ChromeVisibility.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome
//
// Auto-hide/reveal chrome state machine (FR-19, FR-20, FR-21).
// Pure logic: no view dependency, no real scroll/keyboard reference.
// Every state transition is driven exclusively via the inject* seam
// (§5.1.d), making the SM synchronously testable without wall-clock
// waits or real UIKit events.
//
// CANON GAP CG-3: 1300ms idle-reveal debounce + scroll-direction
// reveal/hide (touch model) supersedes ui-design-bible §Motion
// 4s-steady / 2s-first-run + top-60px pointer-reveal zone
// (desktop pointer-motion, no touch analogue for mobile).
// Decision logged per spec §8 OQ-03.
//
// Spec refs: FR-19, FR-20, FR-21; EC-11, EC-12, EC-14; CG-3.
// Contract: §5.1.d / §4.2.

import Foundation

// MARK: - ScrollDirection

/// The scroll direction as seen by the chrome state machine.
///
/// `forward` = scrolling toward the top of the document (reveals chrome).
/// `reverse` = scrolling toward the bottom (hides chrome).
///
/// Defined here because ChromeVisibility is the SM's primary consumer.
/// TASK-05 (BufferEditor.swift) uses this type for its `onScroll` callback;
/// TASK-11 (ChromeOverlay/ContentView) wires them together.
/// ScrollDirection's canonical home is ChromeVisibility.swift.
public enum ScrollDirection: Sendable {
    case forward  // scroll-up → reveal chrome
    case reverse  // scroll-down → hide chrome
}

// MARK: - ChromeVisibility

/// `@Observable` auto-hide/reveal state machine for the Liquid Glass chrome.
///
/// State diagram (§4.2):
///
///     [*] → visible      (initial — FR-19)
///     visible → hidden   on injectTyping()
///     visible → hidden   on injectScroll(.reverse)
///     hidden  → visible  on injectScroll(.forward)
///     hidden  → visible  on injectKeyboardDismiss()
///     hidden  → visible  on injectExplicitReveal()
///     hidden  → visible  on injectIdleRevealFired()
///     visible → visible  on injectExplicitReveal() / injectKeyboardDismiss()   (no-op stay)
///     visible → visible  on injectScroll(.forward)                              (no-op stay)
///
/// The 1300ms idle-reveal debounce (CG-3) is owned and managed by this SM.
/// `injectTyping()` cancels any pending debounce item and schedules a new one;
/// `injectIdleRevealFired()` is the synchronous seam the debounce calls (and
/// tests call directly — no wall-clock dependency in tests; OQ-10).
@Observable
public final class ChromeVisibility {

    // MARK: - State

    public enum State: Sendable {
        case visible
        case hidden
    }

    /// Current visibility state. Initial = `.visible` (FR-19).
    private(set) public var state: State = .visible

    /// Computed convenience accessor consumed by `ChromeOverlay` (§4.1).
    public var isVisible: Bool { state == .visible }

    // MARK: - Debounce

    /// The 1300ms idle-reveal debounce timer.
    ///
    /// Cancel-and-restart on every `injectTyping()` call (EC-11).
    /// The pending item calls `injectIdleRevealFired()` on the main queue
    /// so the SM mutation is always on the @Observable isolation.
    private var debounceItem: DispatchWorkItem?

    /// Idle-reveal delay (CG-3: touch model, 1300ms).
    /// Defined as a constant so tests could, if needed, reference it;
    /// the seam (`injectIdleRevealFired`) makes wall-clock bypass unnecessary.
    private let idleRevealDelay: TimeInterval = 1.3

    // MARK: - Initialiser

    public init() {}

    // MARK: - Event-injection seam (§5.1.d)

    /// User typed a character → chrome hides; the 1300ms idle-reveal
    /// debounce is cancelled and restarted (FR-19, FR-20, EC-11).
    public func injectTyping() {
        state = .hidden
        restartDebounce()
    }

    /// Scroll event received.
    ///
    /// `.forward` (scroll-up) → visible (FR-19).
    /// `.reverse` (scroll-down) → hidden (FR-19).
    /// `.forward` while already visible is a self-no-op (EC-12).
    public func injectScroll(_ direction: ScrollDirection) {
        switch direction {
        case .forward:
            state = .visible
        case .reverse:
            state = .hidden
        }
    }

    /// Keyboard dismissed → chrome reveals (FR-19).
    /// Already visible: no-op stay (EC-14).
    public func injectKeyboardDismiss() {
        state = .visible
    }

    /// Explicit reveal (e.g. tap on content) → chrome reveals (FR-19).
    /// Already visible: no-op stay.
    public func injectExplicitReveal() {
        state = .visible
    }

    /// Called by the 1300ms debounce timer OR directly by tests as a
    /// synchronous seam — bypasses wall-clock entirely (FR-21, OQ-10).
    ///
    /// Hidden → visible; already visible → self-no-op stay (EC-12: stale
    /// debounce firing after a scroll-forward reveal stays visible).
    public func injectIdleRevealFired() {
        state = .visible
    }

    // MARK: - Debounce internals

    /// Cancels any pending debounce item and schedules a new one that will
    /// call `injectIdleRevealFired()` after `idleRevealDelay` seconds.
    private func restartDebounce() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.injectIdleRevealFired()
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + idleRevealDelay, execute: item)
    }
}
