// ContentView.swift
// iosApp
//
// Composition seam: ZStack of editor (content) + ChromeOverlay (chrome) +
// .safeAreaInset BottomToolbar. The editor fills the window (content-is-everything
// axiom); chrome respects the safe area; the toolbar is anti-additively inset
// by SwiftUI's .safeAreaInset so keyboardHeight and bottomSafeAreaInset are
// combined as max(...), not summed (FR-18/NFR-07/EC-17 — no manual arithmetic).
//
// Coordinator-access seam (§4.3 / FR-19 seam decision):
//   ContentView owns a CoordinatorBox (@State private var coordinatorBox).
//   BufferEditor writes its Coordinator to coordinatorBox.coordinator in makeUIView.
//   ChromeOverlay and the toolbar closures read coordinatorBox.coordinator at
//   call-time (weak ref, nil-safe per EC-13). SM callbacks are wired by passing
//   chromeVisibility into BufferEditor, which sets them in updateUIView.
//   This keeps ContentView free of UIKit imports and avoids two-phase binding.
//
// Spec refs: FR-02, FR-18, FR-19, FR-20, NFR-01, NFR-07; EC-13, EC-14, EC-17.
// §4.1 composition root / §4.3 data flow.
//
// CANON GAP: retained launch identity #2D73BA/#330A3C != bible Colour-&-branding
// launch tokens; binding per parent spec §5.3 identity-retention; OQ-02 deferred.
//
// No ScenePhase save wiring in this file (M5, FR-14).

import SwiftUI
import shared

/// The editor + chrome composition root view.
///
/// Composes a `ZStack` with:
///   1. `BufferEditor` — full-bleed, `.ignoresSafeArea()`, content layer (no glass).
///   2. `ChromeOverlay` — safe-area-respecting sibling; hosts `TopPill` + `MenuBubble`.
///   `.safeAreaInset(edge: .bottom)` — `BottomToolbar` hosted as a bottom inset so
///   SwiftUI anti-additively computes `max(keyboardHeight, bottomSafeAreaInset)`.
///
/// No manual keyboard-height arithmetic anywhere (FR-18/NFR-07/EC-17).
struct ContentView: View {

    // MARK: - Dependencies (injected from iosAppApp, §4.1)

    /// The single buffer presentation-state model for the session.
    let viewModel: BufferViewModel

    /// The settings repository shared with BufferViewModel (CM-1/FR-03).
    /// Forwarded to EditorPinchModifier and MenuViewModel.
    let settings: SettingsRepository

    /// The single recovery repository for the session (CM-3/FR-05).
    /// Forwarded to MenuViewModel.
    let recovery: RecoveryRepository

    /// The chrome auto-hide/reveal state machine (FR-19/FR-20/FR-21).
    /// Owned as @State in iosAppApp; passed here for ZStack wiring.
    let chromeVisibility: ChromeVisibility

    // MARK: - Coordinator bridge

    /// Reference-type box bridging the live `BufferEditor.Coordinator` to the
    /// toolbar closures without UIKit coupling in this SwiftUI file.
    ///
    /// Owned as `@State` here so SwiftUI keeps the same reference across renders.
    /// `BufferEditor` receives this box and sets `box.coordinator` in `makeUIView`.
    @State private var coordinatorBox: CoordinatorBox = CoordinatorBox()

    // MARK: - Menu view model

    /// The `MenuViewModel` is constructed once here (not in iosAppApp) because it
    /// is a chrome-layer concern and does NOT call any settings/recovery factory —
    /// it receives the already-constructed repository instances (DIP / gate check 4).
    ///
    /// Stored as `@State` so SwiftUI owns the lifetime and the @Observable instance
    /// is not recreated on every body re-evaluation.
    @State private var menuVM: MenuViewModel

    // MARK: - Init

    /// Accepts all injected dependencies and constructs the chrome view model.
    ///
    /// `MenuViewModel` is built here rather than in `iosAppApp` to keep the chrome
    /// concern within `ContentView`'s layer. It does NOT call any repository factory
    /// (no `createIosSettingsRepository()` / `createIosRecoveryRepository()` here —
    /// gate check 4 invariant preserved).
    init(
        viewModel: BufferViewModel,
        settings: SettingsRepository,
        recovery: RecoveryRepository,
        chromeVisibility: ChromeVisibility
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.recovery = recovery
        self.chromeVisibility = chromeVisibility
        // Build the menu VM from the already-constructed repositories (DIP).
        _menuVM = State(wrappedValue: MenuViewModel(
            settings: settings,
            recovery: recovery,
            viewModel: viewModel
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Layer 1: Editor (content, no glass) ──────────────────────────
            // Full-bleed UITextView-backed editor. .ignoresSafeArea() lets it
            // extend under the home indicator, notch, and rounded corners
            // (content-is-everything axiom / FR-02).
            // chromeVisibility and coordinatorBox are passed so BufferEditor can
            // wire SM callbacks and publish its Coordinator (§4.3 seam).
            BufferEditor(
                viewModel: viewModel,
                chromeVisibility: chromeVisibility,
                coordinatorBox: coordinatorBox
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .modifier(EditorPinchModifier(viewModel: viewModel, settings: settings))

            // ── Layer 2: ChromeOverlay (control/navigation, respects safe area) ─
            // TopPill (top-trailing) + MenuBubble popover. No glass here —
            // glass lives inside TopPill/MenuBubble (NFR-01/02; gate checks 1+2).
            // EC-14: SM events never close the bubble — only outside-tap does.
            ChromeOverlay(
                text: viewModel.text,
                menuVM: menuVM,
                chromeVisibility: chromeVisibility,
                coordinatorBox: coordinatorBox,
                viewModel: viewModel
            )
        }
        // ── .safeAreaInset: BottomToolbar (anti-additive keyboard avoidance) ──
        // SwiftUI's .safeAreaInset provides max(keyboardHeight, bottomSafeAreaInset)
        // automatically — NO manual sum arithmetic anywhere (FR-18/NFR-07/EC-17).
        // NOTE OQ-14: CI simulator may report keyboardHeight==0; .safeAreaInset
        // remains the correct idiom — it is trivially correct when keyboard==0.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomToolbar(
                onCopy: { [coordinatorBox] in
                    coordinatorBox.coordinator?.copyToPasteboard()
                },
                onPaste: { [coordinatorBox] in
                    coordinatorBox.coordinator?.pasteAtCaret()
                },
                onCloseKeyboard: { [coordinatorBox] in
                    coordinatorBox.coordinator?.closeKeyboard()
                },
                onIndent: { [coordinatorBox, viewModel] in
                    // FR-17 / §4.3: read selectedRange from live textView,
                    // route through viewModel.indent, apply result back.
                    guard let tv = coordinatorBox.coordinator?.textView else { return }
                    let result = viewModel.indent(in: tv.selectedRange, of: tv.text ?? "")
                    coordinatorBox.coordinator?.applyIndentResult(
                        text: result.text,
                        range: result.selection
                    )
                },
                onOutdent: { [coordinatorBox, viewModel] in
                    guard let tv = coordinatorBox.coordinator?.textView else { return }
                    let result = viewModel.outdent(in: tv.selectedRange, of: tv.text ?? "")
                    coordinatorBox.coordinator?.applyIndentResult(
                        text: result.text,
                        range: result.selection
                    )
                }
            )
        }
    }
}
