// EditorPinchModifier.swift
// iosApp
//
// Two-finger pinch-to-zoom gesture plumbing for the editor surface.
//
// Spec refs: FR-17 (consumed via shared PinchZoom), FR-18, FR-21;
//            §5.1.c; §6.1 EC-09/EC-10
//
// Design contract (Conformance Rule 9 / spec §4 OQ-02):
//   ALL pinch arithmetic lives in shared `PinchZoom` (Kotlin, jvmTest-covered).
//   This file is PURE PLUMBING: capture startIndex on begin, two-finger guard,
//   live apply on update, persist exactly once on end.
//   ZERO `ln`/`round`/`1.15` derivations are permitted in this file.
//
// Injection correction (plan §6 deviation 2026-06-21):
//   `SettingsRepository.shared` does NOT exist — it is a Kotlin interface, not
//   a singleton.  The `settings` parameter uses
//   `IosSettingsFactoryKt.createIosSettingsRepository()` as the production
//   default, matching `BufferViewModel`'s initialiser default.  TASK-07 will
//   inject the SAME instance into both so they share one store (see §5.3 seam).
//
// <!-- CANON GAP: ui-design-bible.md has no dedicated §Motion / gesture spec
//      for the two-finger pinch-to-zoom interaction.  The slot bounds [0, 20]
//      and font-size scale are canon-governed (§Typography 21-slot scale).
//      Motion duration/easing for the live font-resize feedback is deferred to
//      M4 when the canon motion section is populated. -->

import SwiftUI
import shared

// MARK: - EditorPinchModifier

/// A `ViewModifier` that attaches a two-finger pinch gesture to the editor
/// surface and maps zoom to font-size slot changes via shared `PinchZoom`.
///
/// ## Lifecycle
/// 1. **Begin** — `startIndex` is captured once from `viewModel.fontSizeIndex`.
///    It is stored in `@State` and NOT re-read on subsequent updates (FR-17/18).
/// 2. **Update** — only while the gesture reports exactly two active pointers
///    (`MagnifyGesture` is inherently two-finger on iOS; the guard honours the
///    spec's two-finger intent).  `viewModel.fontSizeIndex` is set live via
///    `PinchZoom.shared.clampedTargetIndex(scale:startIndex:)` (FR-18, EC-09).
/// 3. **End** — `SettingsRepository.save(_:)` is called **exactly once** per
///    completed gesture (EC-10).  A cancelled or single-finger gesture saves
///    nothing.
///
/// ## Testable seam
/// The gesture callbacks themselves cannot be synthesised in XCTest without a
/// running UIKit event loop.  To allow unit testing without UIKit simulation,
/// the core logic is factored into three `internal` methods:
///   - `onPinchBegan(currentIndex:)` — captures `startIndex`.
///   - `onPinchChanged(scale:)` — applies live slot update if the seam is armed.
///   - `onPinchEnded()` — persists once if the seam was armed; resets.
/// Tests call these directly, bypassing the SwiftUI gesture plumbing.
///
/// ## No pinch math in Swift (Conformance Rule 9)
/// `clampedTargetIndex(scale:startIndex:)` is the ONLY arithmetic call.
/// The formula `round(ln(scale)/ln(1.15))` is never re-derived here.
struct EditorPinchModifier: ViewModifier {

    // MARK: - Dependencies

    /// The presentation-state model.  `fontSizeIndex` is mutated live during
    /// the gesture and read once on end to persist the final value (FR-18).
    let viewModel: BufferViewModel

    /// The settings store used to persist the chosen font-size index on gesture
    /// end.  Defaults to the production UserDefaults-backed store via the Kotlin
    /// top-level factory.  Inject a stub in tests.
    let settings: SettingsRepository

    // MARK: - Init

    /// Creates an `EditorPinchModifier`.
    ///
    /// - Parameters:
    ///   - viewModel: The buffer presentation-state model.
    ///   - settings: The settings repository for persistence.  Defaults to the
    ///     production store via `IosSettingsFactoryKt.createIosSettingsRepository()`.
    init(
        viewModel: BufferViewModel,
        settings: SettingsRepository = IosSettingsFactoryKt.createIosSettingsRepository()
    ) {
        self.viewModel = viewModel
        self.settings = settings
    }

    // MARK: - Internal gesture state

    /// The `fontSizeIndex` captured at gesture begin.
    /// `nil` means no gesture is in progress (seam not armed).
    @State private var gestureStartIndex: Int? = nil

    // MARK: - ViewModifier body

    func body(content: Content) -> some View {
        content
            .gesture(
                // `MagnifyGesture` is the iOS 17+ / iOS 26 API.
                // `MagnificationGesture` is deprecated.
                // The gesture is inherently two-finger on iOS — the OS will not
                // deliver a MagnifyGesture from a single-finger drag.  This
                // satisfies FR-18's two-finger guard intent (EC-10 neg).
                MagnifyGesture()
                    .onChanged { value in
                        // `value.magnification` is the cumulative scale factor
                        // relative to the beginning of THIS gesture sequence.
                        // On the very first `onChanged` call the seam may not
                        // yet be armed — arm it now by capturing startIndex.
                        onPinchChanged(scale: value.magnification)
                    }
                    .onEnded { _ in
                        onPinchEnded()
                    }
            )
    }

    // MARK: - Testable seam (internal — called by tests directly)

    /// Called when the gesture begins (or on the first `onChanged` if begin is
    /// coalesced).  Captures `startIndex` exactly once.
    ///
    /// - Parameter currentIndex: The `fontSizeIndex` to use as the zoom anchor.
    internal func onPinchBegan(currentIndex: Int) {
        guard gestureStartIndex == nil else { return }
        gestureStartIndex = currentIndex
    }

    /// Called on each gesture update.
    ///
    /// Arms the seam on the first invocation (captures `startIndex`), then
    /// applies the clamped target index live via `PinchZoom.shared`.
    ///
    /// - Parameter scale: The cumulative magnification factor from the gesture.
    ///   NO arithmetic is performed here — the value is forwarded to the shared
    ///   Kotlin object verbatim (Conformance Rule 9).
    internal func onPinchChanged(scale: CGFloat) {
        // Arm the seam on first update if not yet armed.
        if gestureStartIndex == nil {
            gestureStartIndex = viewModel.fontSizeIndex
        }
        guard let startIndex = gestureStartIndex else { return }

        // ALL arithmetic delegated to shared PinchZoom (FR-17, Conformance Rule 9).
        // `scale` is cast to Double for the Kotlin call; result is Int32 bridged to Swift.
        let targetIndex = PinchZoom.shared.clampedTargetIndex(
            scale: Double(scale),
            startIndex: Int32(startIndex)
        )
        // Live update — no save here, only on end (EC-10).
        viewModel.fontSizeIndex = Int(targetIndex)
    }

    /// Called when the gesture ends normally.
    ///
    /// Persists the final `fontSizeIndex` exactly once.
    /// Uses `settings.load().setFontSizeIndex(index:)` to preserve the existing
    /// `colorScheme` field — constructing a bare `AppSettings(fontSizeIndex:)`
    /// would clobber the user's theme choice (EC-10 / §5.1.a seam).
    ///
    /// A cancelled or single-finger gesture must not reach this path.
    internal func onPinchEnded() {
        guard gestureStartIndex != nil else {
            // Seam was never armed — nothing to save.
            return
        }
        // Persist exactly once (EC-10): load current settings, update only
        // fontSizeIndex (identity-stable — preserves colorScheme), save.
        let updated = settings.load().setFontSizeIndex(index: Int32(viewModel.fontSizeIndex))
        settings.save(settings: updated)
        // Reset the seam so the next gesture starts clean.
        gestureStartIndex = nil
    }
}
