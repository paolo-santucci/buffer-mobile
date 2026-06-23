// Chrome/ChromeOverlay.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph + top-pad)
//
// Container view composing the top toolbar (TopPill) + the morphing menu panel
// (MenuBubble) over the editor. Reads ChromeVisibility.isVisible and crossfades
// the chrome layer. Owns the single GlassEffectContainer + morph namespace.
//
// ┌─ MORPH LAYOUT (read before changing) ─────────────────────────────────────┐
// │ ONE GlassEffectContainer holds a VStack:                                    │
// │     ┌ TopPill ──────────────┐   ← toolbar row: [Share] [overflow]           │
// │     └ MenuBubble (if open) ─┘   ← panel, BELOW the toolbar                   │
// │                                                                            │
// │  • The container's `spacing` fuses adjacent glass: it merges Share +        │
// │    overflow into one capsule, and it lets the overflow morph DOWN into the  │
// │    panel (the liquid teardrop). This is the single knob for both effects.   │
// │  • Only the overflow (in TopPill) and the panel (MenuBubble) carry the       │
// │    shared `chromeGlassID`, and they are MUTUALLY EXCLUSIVE: the overflow is  │
// │    shown only while closed (TopPill hides it when `isMenuPresented`), the    │
// │    panel only while open. So the glass system does a clean matched-geometry  │
// │    morph from the overflow's frame to the panel's frame and back.            │
// │  • Share is PERSISTENT (always in TopPill) and never morphs — keeping it     │
// │    out of the swap is what fixed the "panel lands mid-screen on close" bug   │
// │    (previously the WHOLE pill was swapped, relaying the morph source frame). │
// │                                                                            │
// │ DO NOT swap TopPill↔MenuBubble (old design — relays the morph source).       │
// │ DO NOT wrap the toolbar in a single `.glassEffect(.capsule)` or add          │
// │ `.glassEffectUnion` (tap swallow / broken morph respectively).               │
// └──────────────────────────────────────────────────────────────────────────┘
//
// EC-14: isMenuPresented is written by EXACTLY two sources —
//   (1) the overflow toggle inside TopPill (via the $isMenuPresented binding)
//   (2) the full-screen transparent tap-catcher rendered when the menu is open
// SM events (injectTyping/injectScroll/injectKeyboardDismiss) and MenuViewModel
// NEVER reference or mutate isMenuPresented. The tap-catcher (not a .popover)
// is the outside-tap dismiss mechanism.
//
// EC-16: the tap-catcher sits INSIDE the chromeVisibility.isVisible crossfaded
// layer, so the menu is dismissed together with the chrome when chrome hides.
//
// ChromeOverlay also owns the CoordinatorBox — a lightweight reference-type
// bridge that lets ContentView publish the live BufferEditor.Coordinator to
// the BottomToolbar closure wiring. BufferEditor sets coordinatorBox.coordinator
// in makeUIView (once, at creation time). ChromeOverlay's closures then capture
// [weak coordinatorBox] to read the coordinator safely at toolbar-tap time.
//
// CANON GAP CG-1: native Liquid Glass material on the chrome layer supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color@90% fill (OQ-01).
//
// Spec refs: FR-02, FR-18, FR-19, FR-20, NFR-01, NFR-07;
//            EC-13, EC-14, EC-16, EC-17; CG-1.
// Contract: §3.1 (morph identity seam), §4.1, §4.3.

import SwiftUI
import shared

// MARK: - CoordinatorBox

/// Lightweight reference-type bridge that publishes the live `BufferEditor.Coordinator`
/// once it is available (set by `BufferEditor.makeUIView`).
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
/// Lays out (top-trailing, within safe area), inside ONE `GlassEffectContainer`:
///   - `TopPill` — toolbar row: persistent Share + overflow `…` (the latter only when closed).
///   - `MenuBubble` — the menu panel, BELOW the toolbar, shown when `isMenuPresented`.
///     Morphs up/down out of the overflow via the shared `chromeGlassID`.
///   - Transparent full-screen tap-catcher — outside-tap dismiss (EC-14).
///
/// **Glass morph (§3.1):** see the header box. Container spacing fuses the toolbar
/// capsule and drives the overflow↔panel teardrop. Only the overflow + panel carry
/// the shared id; Share is persistent.
///
/// **Reduce Motion (C-07):** when `accessibilityReduceMotion` is true the toggle
/// animation is `nil` (instantaneous) instead of the spring morph.
///
/// **Bubble dismiss contract (EC-14):** `isMenuPresented` is written by EXACTLY two
/// sources — the overflow toggle in `TopPill` and the tap-catcher below.
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

    /// Controls the `MenuBubble` presented state.
    /// EC-14: written by EXACTLY two sources — the overflow toggle in `TopPill`
    /// and the tap-catcher. SM events and `MenuViewModel` NEVER mutate this.
    @State private var isMenuPresented: Bool = false

    // MARK: - Morph identity (§3.1 morph identity seam)

    /// Namespace binding the overflow capsule and the menu panel into one shared
    /// glass identity for the capsule↔panel morph inside `GlassEffectContainer` (C-03).
    @Namespace private var glassNamespace

    /// Shared glass effect ID — on TopPill's overflow control and on MenuBubble's panel.
    private static let chromeGlassID = "chrome.morph"

    /// Container merge threshold. This ONE value does two jobs (header box):
    /// (1) fuses Share + overflow into a single capsule, and (2) drives the
    /// overflow↔panel liquid teardrop. Larger = stronger stretch / stickier fuse.
    /// If Share visually bleeds into the panel when open, lower this.
    private static let glassSpacing: CGFloat = 40

    /// Vertical gap between the toolbar row and the panel. Keep it small so the
    /// overflow and the panel stay within `glassSpacing` and the teardrop connects.
    private static let toolbarToPanelGap: CGFloat = 8

    // MARK: - Accessibility

    /// When `true`, the morph animation is replaced by an instantaneous transition (C-07).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation seam (§3.1 / C-05 / C-06)

    /// Resolved morph animation — computed once so BOTH `isMenuPresented` write-sites
    /// (C-05) use an identical spring, and `TopPill` receives the same value without
    /// its own reduce-motion reader (C-06). `nil` under Reduce Motion; a bouncy spring
    /// otherwise (the elastic settle that sells the liquid-glass "drop").
    private var menuToggleAnimation: Animation? {
        reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.15)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-screen tap-catcher: only when the menu is open, behind the bubble
            // (EC-14 outside-tap dismiss). Inside the crossfaded layer so EC-16 holds.
            if isMenuPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // EC-14 writer #2 — same bouncy curve as the overflow toggle (C-05).
                        withAnimation(menuToggleAnimation) {
                            isMenuPresented = false
                        }
                    }
            }

            // Chrome controls: toolbar + morphing panel, top-trailing.
            VStack {
                HStack {
                    Spacer()
                    pillAndBubble
                }
                Spacer()
            }
            .padding(.top, 6)
            .padding(.horizontal, 16)
        }
        // Crossfade the chrome layer (incl. tap-catcher) with ChromeVisibility (FR-20 / EC-16).
        .opacity(chromeVisibility.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: chromeVisibility.isVisible)
    }

    // MARK: - Toolbar + morphing panel (§3.1 morph identity seam)

    /// The single `GlassEffectContainer`. A trailing-aligned VStack stacks the
    /// persistent toolbar (`TopPill`) on top and the menu panel (`MenuBubble`)
    /// directly below it. The overflow (inside TopPill, shown only while closed)
    /// and the panel share `chromeGlassID` and are mutually exclusive, so the glass
    /// system morphs the overflow DOWN into the panel and back — Share stays put.
    ///
    /// See the file header box for what NOT to do (whole-pill swap / capsule wrap /
    /// union). The `withAnimation` wrapping `isMenuPresented` is reduce-motion gated.
    @ViewBuilder
    private var pillAndBubble: some View {
        GlassEffectContainer(spacing: Self.glassSpacing) {
            VStack(alignment: .trailing, spacing: Self.toolbarToPanelGap) {
                // Persistent toolbar row. Share is always here; the overflow is
                // shown only while closed (it morphs into the panel below).
                TopPill(
                    text: text,
                    isMenuPresented: $isMenuPresented,
                    glassNamespace: glassNamespace,
                    glassID: Self.chromeGlassID,
                    menuToggleAnimation: menuToggleAnimation
                )

                // Menu panel — only while open. Same id as the overflow ⇒ the glass
                // system morphs the overflow capsule into this panel (C-04). Inner
                // rows carry .transition(.opacity) in MenuBubble.swift (T-04). No
                // explicit transition on the panel container — glassEffectID owns geometry.
                if isMenuPresented {
                    MenuBubble(
                        menuVM: menuVM,
                        isPresented: $isMenuPresented,
                        glassNamespace: glassNamespace,
                        glassID: Self.chromeGlassID
                    )
                }
            }
        }
    }
}
