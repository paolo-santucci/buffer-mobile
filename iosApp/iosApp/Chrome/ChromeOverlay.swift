// Chrome/ChromeOverlay.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome
//
// Container view composing TopPill + MenuBubble over the editor.
// Reads ChromeVisibility.isVisible and crossfades the chrome layer.
// Hosts NO glass directly — delegates to TopPill and MenuBubble (children
// own their own .glassEffect; this container is non-visual composition only).
//
// EC-14: SM events (typing, scroll, keyboard) do NOT force the bubble closed.
//        Only an outside-tap on the popover dismisses it.
//
// ChromeOverlay also owns the CoordinatorBox — a lightweight reference-type
// bridge that lets ContentView publish the live BufferEditor.Coordinator to
// the BottomToolbar closure wiring. BufferEditor sets coordinatorBox.coordinator
// in makeUIView (once, at creation time). ChromeOverlay's closures then capture
// [weak coordinatorBox] to read the coordinator safely at toolbar-tap time.
//
// CANON GAP CG-1: native Liquid Glass material on the chrome layer supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color@90% fill (OQ-01).
// This container is non-visual (no glass here); the CG-1 note is on TopPill +
// MenuBubble which carry their own glass surfaces.
//
// Spec refs: FR-02, FR-18, FR-19, FR-20, NFR-01, NFR-07;
//            EC-13, EC-14, EC-17; CG-1.
// Contract: §4.1, §4.3.

import SwiftUI
import shared

// MARK: - CoordinatorBox

/// Lightweight reference-type bridge that publishes the live `BufferEditor.Coordinator`
/// once it is available (set by `BufferEditor.makeUIView`).
///
/// This avoids a hard dependency between `ContentView`/`ChromeOverlay` and the
/// internal `UIViewRepresentable` coordinator lifecycle. The box is owned as `@State`
/// in `ContentView` and passed to both `BufferEditor` (which writes) and
/// `ChromeOverlay` (which reads for toolbar-closure wiring).
///
/// `coordinator` is declared `weak` so the box does not extend the coordinator's
/// lifetime beyond the UIViewRepresentable's natural teardown.
final class CoordinatorBox {
    /// The live `BufferEditor.Coordinator`. Set once in `BufferEditor.makeUIView`;
    /// cleared automatically when the coordinator deallocates (weak ref). All
    /// toolbar closures guard against `nil` before use (EC-13).
    weak var coordinator: BufferEditor.Coordinator?
}

// MARK: - ChromeOverlay

/// Non-visual composition container for the Liquid Glass chrome controls.
///
/// Lays out:
///   - `TopPill` (top-trailing, within safe area) — Share + overflow `…` toggle.
///   - `MenuBubble` (popover anchored to the pill) — presented when `isMenuPresented == true`.
///
/// Reads `chromeVisibility.isVisible` to crossfade the entire chrome layer in/out.
/// Applies `.opacity` + `.animation` so that SM transitions animate smoothly (FR-20).
///
/// **Bubble dismiss contract (EC-14):**
/// The `isMenuPresented` state is local to `ChromeOverlay`. SM events
/// (`injectTyping`, `injectScroll`, `injectKeyboardDismiss`) NEVER write to
/// `isMenuPresented`. Only the popover's own outside-tap mechanism closes it.
///
/// **No glass here:**
/// This view applies no `.glassEffect`/`GlassEffectContainer`/`.glass*` modifier.
/// Glass is owned exclusively by `TopPill` and `MenuBubble` (NFR-01/02; gate check 2).
struct ChromeOverlay: View {

    // MARK: - Inputs (from ContentView / composition root)

    /// Current buffer text — forwarded to `TopPill` for the Share disabled gate (EC-01/FR-08).
    let text: String

    /// The menu view model — forwarded to `MenuBubble` (ctor-injected DIP).
    let menuVM: MenuViewModel

    /// Chrome auto-hide/reveal state machine — drives the crossfade (FR-19/FR-20).
    let chromeVisibility: ChromeVisibility

    /// Coordinator box — read by toolbar closures to dispatch actions (EC-13).
    let coordinatorBox: CoordinatorBox

    /// The `BufferViewModel` — passed through for indent/outdent closures (FR-17).
    let viewModel: BufferViewModel

    // MARK: - Local state

    /// Controls the `MenuBubble` popover presentation.
    ///
    /// EC-14: set only by the overflow button (toggle) and by the standard popover
    /// dismiss gesture (set to false by SwiftUI) — NEVER by SM events.
    @State private var isMenuPresented: Bool = false

    // MARK: - Body

    var body: some View {
        // Full-overlay container respecting the safe area (FR-02).
        // TopPill is positioned top-trailing within the safe area.
        VStack {
            HStack {
                Spacer()
                pillAndBubble
            }
            Spacer()
        }
        .padding()
        // Crossfade the chrome layer with ChromeVisibility.isVisible (FR-20).
        // EC-14: crossfade is purely visual — it does NOT mutate isMenuPresented.
        .opacity(chromeVisibility.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: chromeVisibility.isVisible)
    }

    // MARK: - Pill + bubble anchor

    /// The `TopPill` with the `MenuBubble` popover anchored to it.
    ///
    /// The popover is presented via `.popover(isPresented:)` on the pill so it
    /// grows from the pill's top-trailing corner (FR-09 / §4.1 anchor spec).
    @ViewBuilder
    private var pillAndBubble: some View {
        TopPill(text: text, isMenuPresented: $isMenuPresented)
            .popover(isPresented: $isMenuPresented, arrowEdge: .top) {
                // MenuBubble is the popover content — wired with the shared menuVM
                // and the local isMenuPresented binding (FR-09).
                MenuBubble(menuVM: menuVM, isPresented: $isMenuPresented)
            }
    }
}
