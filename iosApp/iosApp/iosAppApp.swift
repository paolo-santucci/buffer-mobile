// iosAppApp.swift
// iosApp
//
// Application entry point and composition root.
//
// Spec refs: FR-03, FR-19, FR-13 (wiring), FR-09; §4.1; §4.3 Cold start
//
// Composition invariant (§4.1 / FR-03 / CM-1):
//   EXACTLY ONE SettingsRepository instance is constructed here via the Kotlin
//   top-level factory IosSettingsFactoryKt.createIosSettingsRepository().
//   EXACTLY ONE RecoveryRepository instance is constructed here via the Kotlin
//   top-level factory IosRecoveryFactoryKt.createIosRecoveryRepository() (TASK-02).
//   Both handles are wired in init() so they can be shared across:
//     - @State settings  → ContentView → EditorPinchModifier (pinch-end save)
//     - BufferViewModel(settings:)  → fontSizeIndex cold-start read
//     - @State recovery  → chrome injection: MenuViewModel / RecoveryListViewModel
//                          (consumed in TASK-10 / TASK-11)
//     - @State chromeVisibility → chrome state machine (consumed in TASK-11)
//   This eliminates the CM-1 split-handle bug (two NSUserDefaults handles for
//   settings → fontSizeIndex desync when the M4 menu writes theme/font through a
//   different handle than the one the VM loaded from).
//
// No ScenePhase / .onChange(of: scenePhase) save wiring — that is M5 (FR-14).

import SwiftUI
import shared

@main
struct iosAppApp: App {

    // MARK: - Composition root (§4.1 / §4.3 cold-start path)

    /// The single SettingsRepository for the session (FR-03 / CM-1).
    ///
    /// Constructed once in init() via the Kotlin top-level factory.  Injected into
    /// both BufferViewModel(settings:) and ContentView(settings:) so all settings
    /// reads and writes share the same NSUserDefaults handle.
    @State private var settings: SettingsRepository

    /// The single RecoveryRepository for the session (FR-05 / CM-3).
    ///
    /// Constructed once in init() via IosRecoveryFactoryKt.createIosRecoveryRepository()
    /// (TASK-02 iosMain factory).  Held here for injection into the chrome layer:
    /// MenuViewModel and RecoveryListViewModel consume it in TASK-10 / TASK-11.
    @State private var recovery: RecoveryRepository

    /// The single `BufferViewModel` for the session.
    ///
    /// `@State` is the correct ownership wrapper for an `@Observable` object on iOS 17+/26:
    /// `@StateObject` is for `ObservableObject`; `@Observable` classes should be stored in
    /// `@State` (or as `let` constants injected from outside).  Using `@State` here ensures
    /// SwiftUI owns the lifetime and the reference is stable across scene restarts.
    ///
    /// Initialised in init() with the single `settings` instance so that fontSizeIndex on
    /// cold start and the pinch-end save both reference the same store (FR-03 / CM-1).
    @State private var viewModel: BufferViewModel

    /// The chrome auto-hide/reveal state machine (FR-19 / FR-20 / FR-21).
    ///
    /// Owned here at the composition root so the ZStack overlay in TASK-11 can bind to
    /// it directly.  ChromeVisibility lands in TASK-07 (same Wave 2); this reference
    /// is CI-authoritative and will compile on the macos-26 runner once TASK-07 lands.
    @State private var chromeVisibility: ChromeVisibility

    // MARK: - Composition-root init (CM-1 single-instance DI)

    /// Constructs exactly one SettingsRepository and exactly one RecoveryRepository,
    /// then threads them through to the view model and state properties (§4.1 / FR-03).
    ///
    /// Swift default-value property initialisers cannot reference sibling stored
    /// properties, so a custom `init()` is the canonical SwiftUI pattern for seeding
    /// multiple `@State` properties from shared instances constructed at the root.
    init() {
        let settingsRepo = IosSettingsFactoryKt.createIosSettingsRepository()
        let recoveryRepo = IosRecoveryFactoryKt.createIosRecoveryRepository()

        // Wire the single settings handle into both @State settings and BufferViewModel.
        // Using _settings = State(wrappedValue:) is the correct SwiftUI initializer
        // pattern for @State properties — do not assign to settings directly in init().
        _settings = State(wrappedValue: settingsRepo)
        _recovery = State(wrappedValue: recoveryRepo)
        _viewModel = State(wrappedValue: BufferViewModel(settings: settingsRepo))
        _chromeVisibility = State(wrappedValue: ChromeVisibility())
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            // Pass all session-scoped instances into ContentView (§4.1 / §4.3 DI).
            //
            // viewModel + settings: as in M3; EditorPinchModifier reads settings.
            // recovery: forwarded to ContentView → MenuViewModel → RecoveryListViewModel.
            // chromeVisibility: the SM owned here, forwarded for ZStack overlay wiring
            //   and Coordinator callback injection (FR-19).
            //
            // ContentView builds MenuViewModel from these injected instances (DIP).
            // No new factory calls here — gate check 4 invariant (single settings
            // factory call in iosAppApp.init() only) is preserved.
            ContentView(
                viewModel: viewModel,
                settings: settings,
                recovery: recovery,
                chromeVisibility: chromeVisibility
            )
        }
    }
}
