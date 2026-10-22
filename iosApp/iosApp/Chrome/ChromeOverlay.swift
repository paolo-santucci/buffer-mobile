// Chrome/ChromeOverlay.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Container view composing the top-right chrome: a standalone Undo glass
// circle beside ONE fused glass capsule (Share + overflow `…`) that deforms as a single liquid unit into the menu panel
// (MenuBubble) and back, over the editor. Reads ChromeVisibility.isVisible and
// crossfades the chrome layer. Owns the ONE shared morph container, the morph
// namespace, and the private `isMenuPresented` state.
//
// ┌─ MORPH TOPOLOGY (read before changing) ────────────────────────────────────┐
// │ ONE positioned top-trailing container holding EXACTLY ONE child per state:  │
// │                                                                            │
// │   ZStack(alignment: .topTrailing) {                                         │
// │       if open { tapCatcher }          // sibling, NOT in the morph container│
// │       morphContainer(spacing: 35) {                                         │
// │           if open { MenuBubble } else { fusedPill }   // XOR — never both   │
// │               .transition(.identity) + .glassEffectID(chromeGlassID)         │
// │       }                                                                     │
// │   }.padding(.top, 16).padding(.horizontal, 16)                              │
// │                                                                            │
// │ WHY one child per state: the glass system fuses glass shapes inside one     │
// │  container. Two live children would metaball-merge into one blob ("Share    │
// │  glues to the panel", rc15/rc18-initial). One child = one glass shape, so    │
// │  the merge is never observable and the whole-pill→panel deformation reads    │
// │  as a single liquid unit (FR-01…FR-03).                                     │
// │ WHY .transition(.identity) on BOTH children: suppresses SwiftUI's default    │
// │  opacity crossfade so the glass morph is the only animation on insertion.    │
// │ WHY the closed capsule is ONE glass shape over PLAIN buttons: same proven    │
// │  anatomy as BottomToolbar — one capsule over an HStack of plain buttons.     │
// │  It avoids the rc8 tap-swallow class (`.interactive()` on multi-button       │
// │  glass) and rc18's per-button glass.                                         │
// │ WHY Share lives inside the closed capsule but is a PLAIN row when open:      │
// │  the closed state fuses Share + `…` into the single capsule the user sees;   │
// │  the open state consumes Share into the panel, where rows are plain so no    │
// │  nested glass can corrupt the morph (FR-04/FR-05).                           │
// └────────────────────────────────────────────────────────────────────────────┘
//
// ┌─ PROHIBITED TOPOLOGIES (device-confirmed; do NOT reintroduce) ─────────────┐
// │ • A second live glass element beside the capsule/panel — coalescence.  rc15 │
// │   Prevented structurally: exactly one container child per state.            │
// │ • Persistent toolbar row + appended panel — frame race, mid-screen.  eeeb7a0│
// │   Prevented by the XOR sole-child container.                               │
// │ • Whole-view swap that unmounts a live control — Share vanished. rc16/rc17 │
// │   Both states carry their own Share surface: pill button XOR panel row.     │
// │ • `.interactive()` on multi-button glass — swallows the tap.            rc8 │
// │   The capsule is PINNED `.regular`; every button inside it is `.plain`.     │
// │ • `.glassEffectID` on a persistent multi-element HStack.               rc17 │
// │   The ID rides only the two transient XOR children.                        │
// │ • Nested glass inside panel rows.                                 rc18-cut1 │
// │   Every panel row is `.plain`; MenuBubble owns the panel's single glass.    │
// │ • `.popover(` as the dismiss mechanism, an availability-guarded fallback     │
// │   branch under Chrome/, a find affordance, a separate keyboard accessory    │
// │   bar — all gate-checked (sp_chrome_morph c1, m4-3/7/8).                    │
// └────────────────────────────────────────────────────────────────────────────┘
//
// SUPERSESSION of the rc18-r2 header contract ("Share OUTSIDE the container — do NOT
// reintroduce"). That guard protected against Share fusing with the OPEN panel while
// coexisting as a SECOND live glass element. This design has no such counterpart:
// exactly one glass shape exists per state INSIDE the morph container — the closed
// fused capsule XOR the open panel — so two shapes never coalesce there, and while
// the panel is open Share is a plain row inside it. The Undo circle is a second
// top-chrome glass artifact by design; it lives OUTSIDE the container, giving it its
// own non-merging glass surface in both states. Every other entry of that history
// box is retained above.
//
// EC-14 / §5.3 — the `isMenuPresented` writer set is EXHAUSTIVE (five sources):
//   (1) overflow toggle       — fusedPill's `…` button — withAnimation(menuOpenAnimation)
//   (2) tap-catcher           — the full-screen catcher below — withAnimation(menuCloseAnimation)
//   (3) recovery-row dismiss  — MenuBubble's RecoverySection, through the `isPresented` binding
//   (4) Share-row dismiss     — MenuBubble's Share row, through the `isPresented` binding
//   (5) chrome-hide dismissal — the crossfade wrapper's `.onChange` below, guarded by
//                               shouldDismissMenuOnVisibilityChange(visible:menuPresented:)
// Every close write uses menuCloseAnimation; the open write uses menuOpenAnimation. Both
// resolve to nil under Reduce Motion (FR-21). No other writer exists: the state is the
// PRIVATE @State declared here, MenuBubble's only reach is the `isPresented` binding
// (sources 3–4), and ChromeVisibility's SM events, MenuViewModel, RecoveryListViewModel,
// BufferViewModel and shared/ never touch it (FR-08/FR-08n).
//
// EC-16: the tap-catcher and the container sit INSIDE the crossfaded layer, so a
// chrome hide dismisses the open panel together with the chrome layer.
//
// EC-22/FR-06 (C-1): the crossfade wrapper also applies
// `.allowsHitTesting(chromeVisibility.isVisible)`, so chrome hidden at opacity 0
// consumes zero touches — the tap falls through to the editor.
//
// ChromeOverlay also owns the CoordinatorBox — a lightweight reference-type bridge that
// lets ContentView publish the live BufferEditor.Coordinator to the BottomToolbar closure
// wiring. BufferEditor sets coordinatorBox.coordinator in makeUIView (once, at creation
// time); ContentView's toolbar closures capture [weak coordinatorBox] and read the
// coordinator safely at tap time (EC-13). The box is NOT an input of this view.
//
// CANON GAP CG-1: native Liquid Glass material on the chrome layer supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color@90% fill (OQ-01).
//
// Spec refs: FR-01, FR-02, FR-03, FR-06, FR-07, FR-08, FR-19, FR-20, FR-21, FR-24, FR-25;
//            NFR-01, NFR-02, NFR-04, NFR-06, NFR-08; EC-01, EC-13, EC-14, EC-16, EC-22, EC-23;
//            CG-1.
// Contract: §4.2 (topology diagrams), §4.4 (supersession + prohibited set), §5.1.a,
//           §5.1.c, §5.1.f, §5.3 (five-writer table).

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
/// Layout (top-trailing, within safe area):
///   - The shared morph container — the positioned top-trailing child, holding EXACTLY one
///     child per state: `fusedPill` (closed) XOR `MenuBubble` (open), sharing the morph ID.
///   - Transparent full-screen tap-catcher (only while open) — outside-tap dismiss (EC-14).
///
/// **Glass morph (FR-02/FR-03):** see the header topology diagram. The fused closed
/// capsule carries the same glass identity as the panel, so the iOS 26 glass system
/// deforms the whole capsule into the panel and back as one unit — no stranded Share,
/// no notch.
///
/// **Hit-testing (C-1/FR-06):** chrome hidden by `ChromeVisibility` takes zero touches.
///
/// **Reduce Motion (FR-21):** both animation seams resolve to `nil`, so every state
/// change applies instantaneously instead of springing.
///
/// **Bubble dismiss contract (EC-14):** write-sources 1, 2 and 5 are declared here;
/// sources 3 and 4 live in `MenuBubble` behind the `isPresented` binding. The full
/// five-writer set is enumerated in the file header.
struct ChromeOverlay: View {

    // MARK: - Inputs (from ContentView / composition root)

    /// Current buffer text — forwarded to BOTH Share surfaces (the closed pill's link and
    /// the panel's Share row) and to the single empty-buffer gate (EC-01/FR-04).
    let text: String

    /// The menu view model — forwarded to `MenuBubble` (ctor-injected DIP).
    let menuVM: MenuViewModel

    /// Chrome auto-hide/reveal state machine — drives the crossfade, the hit-testing
    /// gate (C-1) and the chrome-hide dismissal (write-source 5).
    let chromeVisibility: ChromeVisibility

    /// Chrome-dispatched undo of the last editor edit — invoked by the standalone
    /// Undo circle and routed by the composition root to the live editor coordinator.
    let onUndo: () -> Void

    // MARK: - Local state

    /// Controls the `MenuBubble` presented state.
    /// EC-14: written by EXACTLY five enumerated sources — the fused pill's `…` toggle
    /// (#1), the tap-catcher (#2), and, through `MenuBubble`'s binding, the recovery-row
    /// (#3) and Share-row (#4) dismissals, plus the chrome-hide dismissal (#5) below.
    /// Private by design: nothing outside this view can reach it directly.
    @State private var isMenuPresented: Bool = false

    // MARK: - Morph identity (§5.1.a morph identity seam)

    /// Namespace binding the closed capsule and the menu panel into one shared glass
    /// identity for the capsule↔panel morph inside the shared morph container (C-03).
    @Namespace private var glassNamespace

    /// Shared glass effect ID — carried by BOTH XOR children (the closed fused capsule and
    /// the open panel), which is what makes the whole-capsule deformation possible.
    private static let chromeGlassID = "chrome.morph"

    // MARK: - Accessibility

    /// When `true`, every morph/collapse animation resolves to `nil` (FR-21).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation seam (§5.1.a / §4.2 — directional, RM-gated)

    /// Opening spring — used by write-source 1 (and resolved to `nil` under Reduce Motion).
    private var menuOpenAnimation: Animation? {
        reduceMotion ? nil : ChromeMetrics.menuOpenSpring
    }

    /// Closing spring — used by write-sources 2, 3, 4 and 5; also forwarded to `MenuBubble`
    /// as `dismissAnimation`, so every close path shares one curve.
    private var menuCloseAnimation: Animation? {
        reduceMotion ? nil : ChromeMetrics.menuCloseSpring
    }

    // MARK: - Derived state

    /// `true` when the Share control must be disabled (EC-01/FR-04).
    /// The SINGLE empty-buffer predicate: it gates the closed pill's link and the panel's
    /// row, so the two Share surfaces can never diverge.
    private var isShareDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Dismissal seam (pure; §5.1.f)

    /// Whether a chrome visibility change must dismiss the open menu panel.
    ///
    /// Pure and total. A hide over an open panel is the one combination that dismisses
    /// (write-source 5); a reveal never dismisses, and a hide over a closed panel is a
    /// no-op (FR-07/FR-07n, EC-16).
    static func shouldDismissMenuOnVisibilityChange(visible: Bool, menuPresented: Bool) -> Bool {
        !visible && menuPresented
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isMenuPresented {
                // Demo-fidelity tap-catcher: outside-tap dismiss (EC-14 write-source 2).
                // A near-invisible fill (not `.clear`) so the whole screen is hit-testable.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(menuCloseAnimation) {
                            isMenuPresented = false
                        }
                    }
                    .transition(.opacity)
            }

            // The top chrome's glass group: the Undo circle is its own glass artifact
            // beside (never inside) the morph container, so the capsule↔panel merge
            // domain stays exactly one glass shape per state.
            HStack(alignment: .top, spacing: ChromeMetrics.chromeControlGap) {
                undoButton

                GlassEffectContainer(spacing: ChromeMetrics.metaballSpacing) {
                    if isMenuPresented {
                        MenuBubble(
                            menuVM: menuVM,
                            isPresented: $isMenuPresented,
                            glassNamespace: glassNamespace,
                            glassID: Self.chromeGlassID,
                            dismissAnimation: menuCloseAnimation,
                            text: text,
                            isShareDisabled: isShareDisabled
                        )
                        // .transition(.identity): the glass morph is the only animation on
                        // insertion/removal — no default opacity crossfade.
                        .transition(.identity)
                    } else {
                        fusedPill
                            .transition(.identity)
                    }
                }
            }
            .padding(.top, ChromeMetrics.pillTopGap)
            .padding(.horizontal, ChromeMetrics.chromeHorizontalInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        // Crossfade the chrome layer (incl. the tap-catcher) with ChromeVisibility
        // (FR-20/EC-16). Modifier order is pinned by §4.2: the two frozen modifiers
        // first, then the hit-testing gate and the dismissal observation.
        .opacity(chromeVisibility.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: chromeVisibility.isVisible)
        // C-1/FR-06: hidden chrome consumes no touches. Not animatable, so it flips with
        // the state change — instantly on hide, marginally ahead of full opacity on reveal.
        .allowsHitTesting(chromeVisibility.isVisible)
        // EC-14 write-source 5: a chrome hide dismisses the open panel through the pure
        // seam, so chrome-hidden + panel-open is unreachable by construction (FR-07/EC-16).
        .onChange(of: chromeVisibility.isVisible) { _, isVisible in
            guard Self.shouldDismissMenuOnVisibilityChange(
                visible: isVisible,
                menuPresented: isMenuPresented
            ) else { return }
            withAnimation(menuCloseAnimation) {
                isMenuPresented = false
            }
        }
    }

    // MARK: - Undo circle (DD-3/DD-10)

    /// The top-leading control beside the Share/…morph-capsule: a standalone
    /// glass circle in the same manual-glass anatomy as the capsule, sized to
    /// equal its height (44pt circle vs 44pt capsule — user-approved DD-3a).
    ///
    /// Deliberately OUTSIDE the morph container: a second live glass shape
    /// inside `GlassEffectContainer` would coalesce with the capsule or the
    /// open panel during the morph (§4.4 prohibited topologies). Separate
    /// adjacency keeps the merge domain single-shape per state.
    ///
    /// Single-button glass — `.interactive()` here is the one-control variant
    /// the rc8 prohibition does not cover (multi-button glass).
    ///
    /// Always enabled: undo with an empty stack is a no-op (FR-15 analog).
    private var undoButton: some View {
        Button {
            onUndo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .fontWeight(ChromeMetrics.iconScaleWeight)
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Same manual-glass anatomy as the capsule — `.circle` with no added
        // system padding, so the circle's diameter equals the capsule's height
        // (both 44pt, ChromeMetrics.pillHeight). `.interactive()` is the single-
        // control variant (the rc8 prohibition targets multi-button glass).
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(
            String(localized: "Undo", comment: "Undo button accessibility label in the top chrome")
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(localized: "Undo", comment: "Undo button tooltip in the top chrome (FR-23)")
        )
    }

    // MARK: - Fused closed-state capsule (§5.1.c)

    /// The closed state's ONLY glass shape: one capsule over two plain buttons
    /// (Share + `…`) — the `BottomToolbar` anatomy, proven in-repo.
    ///
    /// - The buttons are `.plain`: the capsule is the glass shape, so no per-button glass
    ///   is nested inside the shared container (rc18 regression class).
    /// - `.glassEffect(.regular, in: .capsule)` is PINNED `.regular` — the interactive
    ///   variant is prohibited on multi-button glass (rc8 tap-swallow, §4.4).
    /// - `.glassEffectID(chromeGlassID, in: glassNamespace)`: morph identity. The glass
    ///   system deforms this capsule's geometry toward `MenuBubble`'s on the open write.
    /// - Both buttons keep the inline 44pt tap targets (NFR-04); the rendered capsule
    ///   height must equal `ChromeMetrics.pillHeight` (the editor-inset lockstep token).
    private var fusedPill: some View {
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            ShareLink(item: text) {
                Label(
                    String(localized: "Share", comment: "Share button label in the top pill"),
                    systemImage: "square.and.arrow.up"
                )
                .labelStyle(.iconOnly)
                .fontWeight(ChromeMetrics.iconScaleWeight)
                .imageScale(.large)
                // The frame + contentShape live INSIDE the label: with .plain the hit
                // shape is the label's content shape — outside frames are layout only,
                // which collapsed the touch target to the symbol ink box (DD-2).
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
            // EC-01: empty buffer → no share sheet; the panel's Share row uses the same gate.
            .disabled(isShareDisabled)
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: "Share", comment: "Share button accessibility label in the top pill")
            )
            .accessibilityAddTraits(.isButton)
            .help(
                String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
            )

            Button {
                // EC-14 write-source 1 — the pill is mounted only while closed.
                withAnimation(menuOpenAnimation) {
                    isMenuPresented = true
                }
            } label: {
                Label(
                    String(localized: "Menu", comment: "Overflow menu button label in the top pill"),
                    systemImage: "ellipsis"
                )
                .labelStyle(.iconOnly)
                .fontWeight(ChromeMetrics.iconScaleWeight)
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: "Menu", comment: "Overflow menu button accessibility label in the top pill")
            )
            .accessibilityAddTraits(.isButton)
            .help(
                String(localized: "Open menu", comment: "Overflow menu button tooltip in the top pill (FR-23)")
            )
        }
        .padding(.horizontal, ChromeMetrics.capsuleHorizontalPadding)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID(Self.chromeGlassID, in: glassNamespace)
    }
}
