// Chrome/ChromeOverlay.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph + top-pad)
//
// Container view composing the top toolbar (TopPill) + the morphing menu panel
// (MenuBubble) over the editor. Reads ChromeVisibility.isVisible and crossfades
// the chrome layer. Owns the single GlassEffectContainer + morph namespace.
//
// ┌─ MORPH LAYOUT (read before changing) ─────────────────────────────────────┐
// │ ONE GlassEffectContainer holds a whole-view SWAP:                           │
// │     if isMenuPresented  →  MenuBubble  (sole bearer of chromeGlassID)       │
// │     else                →  TopPill     (overflow bears chromeGlassID)        │
// │                                                                            │
// │  • WHOLE-SWAP is required. In the persistent-toolbar model (eeeb7a0) the    │
// │    overflow button was inserted into an existing HStack on close, so its    │
// │    layout frame was unresolved when the morph started → morph landed        │
// │    mid-screen, then snapped. With the whole-swap, TopPill is freshly        │
// │    inserted at a deterministic top-trailing position; its frame is stable   │
// │    before the glass system starts animating to it.                          │
// │  • .transition(.identity) on BOTH branches suppresses SwiftUI's default     │
// │    opacity crossfade so only the glass morph drives the transition. Without │
// │    it, the fade competes with the morph and produces "almost but not quite" │
// │    artifacts.                                                               │
// │  • .glassEffectUnion on Share + overflow in TopPill fuses them into one     │
// │    even capsule (visual only — gestures stay independent). Union does NOT   │
// │    affect morph geometry; .glassEffectID on the overflow governs the        │
// │    morph source/destination frame independently.                            │
// │  • GlassEffectContainer spacing fuses the capsule and drives the teardrop   │
// │    stretch during morph. 30–45 matches Apple Notes feel.                    │
// │                                                                            │
// │ HISTORY — do NOT reintroduce:                                                │
// │  • VStack with TopPill+MenuBubble both present (eeeb7a0) — frame race.      │
// │  • .glassEffect(.capsule) on the TopPill HStack — swallows overflow tap.    │
// │  • .interactive() on container-level glass — swallows overflow tap.         │
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
///   - Either `TopPill` (closed) OR `MenuBubble` (open) — whole-view swap, never both.
///   - Transparent full-screen tap-catcher — outside-tap dismiss (EC-14).
///
/// **Glass morph (§3.1):** see the header box. Whole-swap ensures the morph
/// destination frame (overflow button in TopPill) is fully resolved before the glass
/// system animates to it. `.transition(.identity)` suppresses competing SwiftUI
/// transitions so the glass morph is the only animation. `.glassEffectUnion` in
/// TopPill fuses Share+overflow visually; `.glassEffectID` on the overflow governs
/// the morph frame independently.
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

    /// Metaball merge threshold for `GlassEffectContainer`.
    /// Fuses Share+overflow into one even capsule and drives the liquid teardrop
    /// stretch during the overflow↔panel morph. 30–45 matches Apple Notes feel.
    /// Larger = stronger fuse / more stretch; lower this if Share bleeds into the panel.
    private static let glassSpacing: CGFloat = 35

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

    // MARK: - Pill + morph container (§3.1 morph identity seam)

    /// `GlassEffectContainer` wrapping EITHER `TopPill` (closed) OR `MenuBubble`
    /// (open) — never both simultaneously.
    ///
    /// **Why whole-swap (not persistent-toolbar + appended-panel):**
    /// `glassEffectID` morph needs the destination frame resolved before animation
    /// starts. In the whole-swap model TopPill is freshly inserted at a known
    /// top-trailing position, so its layout is settled before the glass system
    /// animates to the overflow button's frame. In the persistent-toolbar model
    /// (eeeb7a0), inserting the overflow button into an existing HStack left its
    /// frame unresolved at morph time → mid-screen landing then snap.
    ///
    /// **Why `.transition(.identity)` on both branches:**
    /// Suppresses SwiftUI's default opacity/scale transition so the glass morph
    /// is the ONLY animation. Without it, a competing fade produces "almost but
    /// not quite" residual artifacts on top of the glass morph.
    ///
    /// **Why `.glassEffectUnion` in TopPill (see TopPill.swift header):**
    /// Share and overflow have different intrinsic symbol widths; without union
    /// they render as two unequal blobs. Union fuses their outlines into one even
    /// capsule. It does NOT affect morph geometry — `.glassEffectID` on the overflow
    /// button uses that button's layout frame as the morph source/destination.
    @ViewBuilder
    private var pillAndBubble: some View {
        GlassEffectContainer(spacing: Self.glassSpacing) {
            if isMenuPresented {
                // OPEN — panel is the sole bearer of chromeGlassID.
                // .transition(.identity) suppresses SwiftUI's default opacity crossfade
                // so only the glass morph animates. Inner rows fade via .transition(.opacity)
                // in MenuBubble.swift (T-04); the panel container itself has no transition —
                // glassEffectID owns the geometry morph (C-04).
                MenuBubble(
                    menuVM: menuVM,
                    isPresented: $isMenuPresented,
                    glassNamespace: glassNamespace,
                    glassID: Self.chromeGlassID
                )
                .transition(.identity)
            } else {
                // CLOSED — TopPill's overflow button is the sole bearer of chromeGlassID.
                // Both buttons always present in TopPill → deterministic frame on morph close.
                // .transition(.identity) for the same reason as the panel above.
                TopPill(
                    text: text,
                    isMenuPresented: $isMenuPresented,
                    glassNamespace: glassNamespace,
                    glassID: Self.chromeGlassID,
                    menuToggleAnimation: menuToggleAnimation
                )
                .transition(.identity)
            }
        }
    }
}
