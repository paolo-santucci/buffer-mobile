// Chrome/ChromeOverlay.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph + top-pad)
//
// Container view composing TopPill + MenuBubble over the editor.
// Reads ChromeVisibility.isVisible and crossfades the chrome layer.
// Owns the GlassEffectContainer and morph namespace so the overflow control
// and the menu panel share one glass identity and morph capsule↔panel.
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
// GlassEffectContainer is the single glass grouping for the pill + menu morph.
//
// NOTE (tap-routing fix): the pill is NOT a single glass capsule. TopPill renders
// the Share + overflow controls as independent glass elements fused via
// glassEffectUnion, with the morph glassEffectID on the overflow control only.
// ChromeOverlay's job is unchanged: own the GlassEffectContainer + namespace and
// swap TopPill (closed) ↔ MenuBubble (open). See TopPill.swift header for why.
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
///   - `MenuBubble` (inline, morphing from the overflow control) — shown when `isMenuPresented`.
///   - Transparent full-screen tap-catcher — rendered behind the bubble when open
///     to handle outside-tap dismiss (EC-14).
///
/// Reads `chromeVisibility.isVisible` to crossfade the entire chrome layer in/out.
/// Applies `.opacity` + `.animation` so SM transitions animate smoothly (FR-20).
///
/// **Glass morph (§3.1 morph identity seam):**
/// Owns `glassNamespace` (`@Namespace`) and the `chromeGlassID` string constant.
/// Both `TopPill` (on its overflow control) and `MenuBubble` receive these values
/// and attach `.glassEffectID(chromeGlassID, in: glassNamespace)` so the overflow
/// capsule morphs into the panel and back inside the single `GlassEffectContainer`.
///
/// **Reduce Motion (C-07):**
/// Reads `@Environment(\.accessibilityReduceMotion)`. When true, the morph
/// toggle uses an instantaneous `.identity` / `.opacity` transition instead of
/// the capsule↔panel shape morph.
///
/// **Bubble dismiss contract (EC-14):**
/// `isMenuPresented` is written by EXACTLY two sources — the overflow toggle in
/// `TopPill` and the tap-catcher below. SM events (`injectTyping`, `injectScroll`,
/// `injectKeyboardDismiss`) and `MenuViewModel` NEVER write to `isMenuPresented`.
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
    ///
    /// EC-14: written by EXACTLY two sources —
    ///   (1) the overflow button toggle inside `TopPill` (via `$isMenuPresented`)
    ///   (2) the full-screen transparent tap-catcher (sets to `false`)
    /// SM events and `MenuViewModel` NEVER mutate this state.
    @State private var isMenuPresented: Bool = false

    // MARK: - Morph identity (§3.1 morph identity seam)

    /// Namespace that binds the overflow capsule and the menu panel into one
    /// shared glass identity, enabling the capsule↔panel morph inside
    /// `GlassEffectContainer` (iOS 26 native glass morph — C-03).
    @Namespace private var glassNamespace

    /// The shared glass effect ID passed to both `TopPill` and `MenuBubble`.
    /// TopPill attaches it to its overflow control and `MenuBubble` to its panel,
    /// so the material morphs between the overflow capsule and the menu panel shape.
    private static let chromeGlassID = "chrome.morph"

    // MARK: - Accessibility

    /// When `true`, the morph animation is replaced by an instantaneous/opacity
    /// transition (C-07 / `prefers-reduce-motion`).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation seam (§3.1 / C-05 / C-06)

    /// Resolved morph animation — computed once so BOTH `isMenuPresented` write-sites
    /// (C-05) use an identical spring, and `TopPill` receives the same value without
    /// needing its own `@Environment(\.accessibilityReduceMotion)` reader (C-06).
    ///
    /// `nil` when Reduce Motion is enabled (instantaneous toggle); a bouncy spring
    /// otherwise to drive the glass capsule↔panel morph.
    ///
    /// The `.bouncy` curve is the elastic settle that sells the liquid-glass
    /// "drop" feel (per the Liquid Glass morph reference); a linear/critically-
    /// damped curve kills the metaball stretch.
    private var menuToggleAnimation: Animation? {
        reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.15)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-screen tap-catcher: rendered only when the menu is open,
            // above the editor and behind the bubble (EC-14 outside-tap dismiss).
            // Lives inside this crossfaded layer so EC-16 holds — when chrome
            // crossfades out the tap-catcher disappears with it.
            if isMenuPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // EC-14 writer #2: the tap-catcher closes the menu.
                        // Identical bouncy curve to the TopPill overflow toggle (C-05).
                        withAnimation(menuToggleAnimation) {
                            isMenuPresented = false
                        }
                    }
            }

            // Chrome controls: pill + morph container, top-trailing.
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
        // Crossfade the chrome layer (including the tap-catcher) with
        // ChromeVisibility.isVisible (FR-20 / EC-16).
        // EC-14: crossfade is purely visual — it does NOT mutate isMenuPresented.
        .opacity(chromeVisibility.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: chromeVisibility.isVisible)
    }

    // MARK: - Pill + morph container (§3.1 morph identity seam)

    /// `GlassEffectContainer` wrapping either `TopPill` (closed) or `MenuBubble`
    /// (open) — never both simultaneously.
    ///
    /// iOS 26 `glassEffectID` morph requires the source and destination glass
    /// surfaces to be **mutually exclusive**: exactly one view bears the shared ID
    /// at any point in time. When `isMenuPresented` flips, SwiftUI removes the
    /// old view and inserts the new one inside the same transaction; the glass
    /// system interpolates the overflow capsule geometry into the panel geometry
    /// and back.
    ///
    /// If both children were mounted together (e.g. in a VStack) the system
    /// would find two views with the same ID and skip the morph entirely,
    /// producing the "panel pops in below the pill" symptom observed on-device.
    ///
    /// The shared `.glassEffectID(chromeGlassID, in: glassNamespace)` lives on
    /// TopPill's overflow control and on MenuBubble's panel — no change needed in
    /// their bodies.
    ///
    /// The `withAnimation` wrapping `isMenuPresented` changes is Reduce-Motion
    /// gated: when `reduceMotion` is true `menuToggleAnimation` is `nil` and
    /// the swap is instantaneous (C-07).
    @ViewBuilder
    private var pillAndBubble: some View {
        // CANON GAP CG-1: GlassEffectContainer is the iOS 26 native grouping
        // API — no hand-rolled blur/fill/shadow (C-03 / NFR-01/02).
        //
        // `spacing:` is the metaball merge threshold: the larger it is, the more
        // the capsule and panel stay "stuck together" and the liquid stretch
        // reads during the capsule↔panel morph. Without it (default) the shapes
        // hand off too far apart and the morph degrades to a plain swap — the
        // "menu pops under the pill" symptom. 30–45 matches the Apple Notes feel.
        GlassEffectContainer(spacing: 35) {
            if isMenuPresented {
                // Menu open — panel is the sole bearer of chromeGlassID.
                // No explicit .transition on the panel container: .glassEffectID
                // owns the capsule↔panel geometry morph (C-04). Inner menu rows
                // carry .transition(.opacity) in MenuBubble.swift (T-04).
                MenuBubble(
                    menuVM: menuVM,
                    isPresented: $isMenuPresented,
                    glassNamespace: glassNamespace,
                    glassID: Self.chromeGlassID
                )
            } else {
                // Menu closed — TopPill's overflow control is the sole bearer of
                // chromeGlassID. withAnimation at the overflow toggle site is applied
                // inside TopPill using the resolved menuToggleAnimation from here (C-06).
                // The tap-catcher above uses the same spring value (C-05).
                TopPill(
                    text: text,
                    isMenuPresented: $isMenuPresented,
                    glassNamespace: glassNamespace,
                    glassID: Self.chromeGlassID,
                    menuToggleAnimation: menuToggleAnimation
                )
            }
        }
    }
}
