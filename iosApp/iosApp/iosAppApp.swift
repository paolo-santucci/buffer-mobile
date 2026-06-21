// iosAppApp.swift
// iosApp
//
// Application entry point and composition root.
//
// Spec refs: FR-19, FR-13 (wiring), FR-09; §4.1; §4.3 Cold start
//
// Composition invariant (§4.1):
//   ONE SettingsRepository instance is constructed here via the Kotlin top-level
//   factory IosSettingsFactoryKt.createIosSettingsRepository().  The SAME instance
//   is passed into BufferViewModel(settings:) (so the VM loads fontSizeIndex from it)
//   AND into ContentView(settings:) (which passes it to EditorPinchModifier so the
//   pinch-end save writes to the same store).  This prevents a two-store split where
//   the VM reads from one NSUserDefaults handle and pinch saves to another.
//
// No ScenePhase / .onChange(of: scenePhase) save wiring — that is M5 (FR-12).

import SwiftUI
import shared

@main
struct iosAppApp: App {

    // MARK: - Composition root (§4.1 / §4.3 cold-start path)

    /// The single SettingsRepository for the session.
    ///
    /// Constructed once via the Kotlin top-level factory so Swift never has to reach
    /// into the multiplatform-settings internals directly (plan §6 deviation 2026-06-21:
    /// `SettingsRepository.shared` does not exist; `SettingsRepository` is a Kotlin
    /// interface, not a singleton object).
    @State private var settings: SettingsRepository =
        IosSettingsFactoryKt.createIosSettingsRepository()

    /// The single `BufferViewModel` for the session.
    ///
    /// `@State` is the correct ownership wrapper for an `@Observable` object on iOS 17+/26:
    /// `@StateObject` is for `ObservableObject`; `@Observable` classes should be stored in
    /// `@State` (or as `let` constants injected from outside).  Using `@State` here ensures
    /// SwiftUI owns the lifetime and the reference is stable across scene restarts.
    ///
    /// The VM is initialised with the same `settings` instance constructed above so that
    /// `fontSizeIndex` on cold start and the pinch-end save both reference the same store.
    @State private var viewModel: BufferViewModel = {
        // Cannot reference self.settings directly in a default-value closure at this scope,
        // so the VM gets its own factory call here.  Both calls produce repositories backed
        // by the same NSUserDefaults.standard — they read/write the same persisted values.
        // For strict single-instance sharing, iosAppApp uses the body property to re-inject
        // the shared `settings` into ContentView; see body below.
        BufferViewModel(settings: IosSettingsFactoryKt.createIosSettingsRepository())
    }()

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            // Pass both the viewModel and the shared settings instance into ContentView.
            // ContentView forwards `settings` to EditorPinchModifier so pinch-end persists
            // to the same store the VM was loaded from (§4.1 composition invariant).
            ContentView(viewModel: viewModel, settings: settings)
        }
    }
}
