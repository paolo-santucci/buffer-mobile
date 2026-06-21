// ContentView.swift
// iosApp
//
// Composition surface: hosts BufferEditor filling the window with the pinch modifier applied.
//
// Spec refs: FR-19, FR-13 (wiring), FR-09; §6.1 EC-01/EC-14; §4.1
// UI canon: ui-design-bible.md §Editor text view — content fills window, no chrome at rest.
//           Background: --view-bg-color (UIColor.systemBackground).
//
// CANON GAP: retained launch identity #2D73BA/#330A3C != bible Colour-&-branding launch tokens;
// binding per parent spec §5.3 identity-retention; OQ-02 reconciliation deferred.
//
// FR-19 acceptance: no deleted-symbol call remains in this file.
// No ScenePhase save wiring in this file (M5, FR-12).

import SwiftUI
import shared

/// The editor composition root view.
///
/// Hosts `BufferEditor` filling the window (content-is-everything axiom, EC-01):
///   - No chrome at rest — only the `UITextView`-backed editor surface is visible on launch.
///   - Background: `--view-bg-color` (mapped to `UIColor.systemBackground` in `BufferEditor`).
///   - Pinch-to-zoom gesture is applied via `EditorPinchModifier`, which receives the SAME
///     `SettingsRepository` instance the `BufferViewModel` was initialized with, so the
///     pinch save and the VM load share one backing store (§4.1 composition invariant).
///
/// No `ScenePhase` / `.onChange(of: scenePhase)` save wiring — that is M5 (FR-12).
struct ContentView: View {

    // MARK: - Dependencies (injected from iosAppApp, §4.1)

    /// The single buffer presentation-state model for the session.
    /// Owned as `@State` in `iosAppApp` and passed here; SwiftUI tracks the `@Observable`
    /// object automatically without a separate `@StateObject` wrapper (iOS 17+/iOS 26).
    let viewModel: BufferViewModel

    /// The settings repository shared with `BufferViewModel`'s initializer.
    /// Passed through to `EditorPinchModifier` so pinch-end saves reach the same
    /// store the VM loaded `fontSizeIndex` from at init time (§4.1 seam).
    let settings: SettingsRepository

    // MARK: - Body

    var body: some View {
        // BufferEditor fills the window — no frame/chrome/glass (EC-01).
        // .ignoresSafeArea ensures the UITextView extends under the home indicator and
        // any rounded corners, matching the content-is-everything axiom (ui-design-bible §1).
        BufferEditor(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .modifier(EditorPinchModifier(viewModel: viewModel, settings: settings))
    }
}
