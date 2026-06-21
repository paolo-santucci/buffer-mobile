// iosAppApp.swift
// iosApp
//
// Application entry point and composition root.
//
// Spec refs: FR-03, FR-14, FR-19, FR-13 (wiring), FR-09; §4.1; §4.3 Cold start
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
//     - @State lifecycle → LifecycleSaveCoordinator (M5 FR-14)
//     - @State chromeVisibility → chrome state machine (consumed in TASK-11)
//   This eliminates the CM-1 split-handle bug (two NSUserDefaults handles for
//   settings → fontSizeIndex desync when the M4 menu writes theme/font through a
//   different handle than the one the VM loaded from).
//
// ScenePhase save wiring (M5 / FR-14):
//   LifecycleSaveCoordinator is constructed here from the single `recoveryRepo`
//   and the already-constructed `viewModel`.  The scene-phase `.onChange` lives
//   in ContentView; `applicationWillTerminate` is forwarded via AppDelegate (R-11,
//   best-effort).  No new factory call is introduced (m4_gate check 4).

import SwiftUI
import shared

// MARK: - AppDelegate (applicationWillTerminate — best-effort R-11)

/// Minimal UIApplicationDelegate that forwards `applicationWillTerminate` to
/// the lifecycle coordinator.
///
/// `onTerminate` is a var closure set once at construction (in `iosAppApp.body`)
/// and called by the OS when the app is about to terminate.  R-11: this callback
/// is unreliable (the OS does not guarantee it fires before the process dies), so
/// it is a best-effort supplement to the `.background` save — not the primary path.
///
/// Why set in `body` with `if appDelegate.onTerminate == nil`:
///   `body` is the earliest point where `@UIApplicationDelegateAdaptor` is
///   guaranteed to be initialised AND where the `@State lifecycle` wrapper value
///   is accessible (SwiftUI resolves @State before evaluating `body`, but the
///   wrapped value is NOT available in `init()` — only the `_lifecycle` backing
///   store is seeded there).  Guarding with `== nil` ensures the closure is
///   assigned exactly once regardless of how many times SwiftUI re-evaluates body.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Called by `iosAppApp.body` once, immediately after the coordinator is known.
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ application: UIApplication) {
        onTerminate?()
    }
}

@main
struct iosAppApp: App {

    // MARK: - AppDelegate adaptor (applicationWillTerminate — R-11 best-effort)

    /// Bridges `UIApplicationDelegate.applicationWillTerminate` into the SwiftUI
    /// lifecycle.  The `onTerminate` closure is set once in `body` and calls
    /// `lifecycle.onTerminate()` (R-11: best-effort, unreliable — documented).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

    /// The lifecycle save coordinator (FR-14 / M5).
    ///
    /// Constructed once in init() from the already-constructed `recoveryRepo` and
    /// `viewModel` — NO new `createIosRecoveryRepository()` call here (m4_gate check 4).
    /// Capturing `viewModel` in the closures is safe: SwiftUI owns the same reference
    /// via `@State private var viewModel`, so both the coordinator closure and SwiftUI
    /// read and write the identical object.
    @State private var lifecycle: LifecycleSaveCoordinator

    // MARK: - Composition-root init (CM-1 single-instance DI)

    /// Constructs exactly one SettingsRepository and exactly one RecoveryRepository,
    /// then threads them through to the view model, lifecycle coordinator, and state
    /// properties (§4.1 / FR-03).
    ///
    /// Swift default-value property initialisers cannot reference sibling stored
    /// properties, so a custom `init()` is the canonical SwiftUI pattern for seeding
    /// multiple `@State` properties from shared instances constructed at the root.
    init() {
        let settingsRepo = IosSettingsFactoryKt.createIosSettingsRepository()
        let recoveryRepo = IosRecoveryFactoryKt.createIosRecoveryRepository()
        let vm = BufferViewModel(settings: settingsRepo)

        // Wire the single settings handle into both @State settings and BufferViewModel.
        // Using _settings = State(wrappedValue:) is the correct SwiftUI initializer
        // pattern for @State properties — do not assign to settings directly in init().
        _settings = State(wrappedValue: settingsRepo)
        _recovery = State(wrappedValue: recoveryRepo)
        _viewModel = State(wrappedValue: vm)
        _chromeVisibility = State(wrappedValue: ChromeVisibility())

        // Build the lifecycle coordinator from the single recovery handle and the
        // already-constructed vm reference.  The coordinator pulls text via the
        // textProvider closure and resets via resetBuffer — NO save logic in the VM
        // (FR-12 / m4_gate check 5).  No new factory call (m4_gate check 4).
        _lifecycle = State(wrappedValue: LifecycleSaveCoordinator(
            recovery: recoveryRepo,
            textProvider: { vm.text },
            resetBuffer: { vm.populate($0) }
        ))
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
            // lifecycle: the FR-14 coordinator; ContentView drives it via scenePhase.
            //
            // ContentView builds MenuViewModel from these injected instances (DIP).
            // No new factory calls here — gate check 4 invariant (single settings
            // factory call in iosAppApp.init() only) is preserved.
            ContentView(
                viewModel: viewModel,
                settings: settings,
                recovery: recovery,
                chromeVisibility: chromeVisibility,
                lifecycle: lifecycle
            )
            // Wire appDelegate.onTerminate exactly once (guard == nil).
            // This is the earliest reliable site: @State is resolved before body
            // evaluates, but the wrapped value is NOT accessible in init() — only
            // the _lifecycle backing store is seeded there.  body runs on the main
            // actor; the closure is set on first evaluation and ignored on subsequent
            // re-evaluations (SwiftUI may call body multiple times).
            // R-11: applicationWillTerminate is best-effort and unreliable; the
            // .background save via ContentView.dispatchScenePhase is the primary path.
            .onAppear {
                if appDelegate.onTerminate == nil {
                    appDelegate.onTerminate = { [lifecycle] in
                        lifecycle.onTerminate()
                    }
                }
            }
        }
    }
}
