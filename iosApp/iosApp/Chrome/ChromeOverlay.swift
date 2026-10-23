// Chrome/ChromeOverlay.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Container view composing the top-right chrome: a standalone Undo glass circle
// beside ONE glass capsule (rc24 anatomy: Share + `…` behind a single pinned
// `.regular` capsule) that deforms as a liquid unit into the menu panel
// (MenuBubble) and back, over the editor. Reads ChromeVisibility.isVisible and
// crossfades the chrome layer. Owns the ONE shared morph container, the morph
// namespace, and the private `isMenuPresented` state.
//
// ┌─ MORPH TOPOLOGY (read before changing) ────────────────────────────────────┐
// │ ONE positioned top-trailing container holding EXACTLY ONE child per state:  │
// │                                                                            │
// │   ZStack(alignment: .topTrailing) {                                         │
// │       if open { tapCatcher }          // sibling, NOT in the morph container│
// │       undoButton                     // PINNED trailing inset — never moved │
// │       shareAnchor                    // invisible zoom source, every state  │
// │       morphContainer(spacing: 35) {  // LAST z-child — expands OVER Undo     │
// │           if sharing { melt }         // pill glass shrinks to nothing      │
// │           else if open { MenuBubble } else { closedPill }  // XOR          │
// │               .glassEffectID(chromeGlassID)  — NO .transition on children   │
// │       }                                                                     │
// │   }                                                                         │
// │                                                                            │
// │ WHY one child per state: the glass system fuses glass shapes inside one     │
// │  container. Two live children would metaball-merge into one blob ("Share    │
// │  glues to the panel", rc15/rc18-initial). One child = one glass shape, so    │
// │  the merge is never observable and the whole-pill→panel deformation reads   │
// │  as a single liquid unit (FR-01…FR-03).                                     │
// │ WHY NO .transition on the XOR children (device-verified, LiquidMenuDemo):   │
// │  `.identity` removes the animated insertion/removal window the glass        │
// │  container needs to interpolate — it KILLS the morph (rc21). The default    │
// │  branch crossfade is demo parity; INNER row fades compound (rc22 D1)        │
// │ WHY the capsule carries the morph ID as a WHOLE (rc24 restoration, DD-6     │
// │  direction superseded): rc25's split topology (small `…` capsule as the     │
// │  source, Share a standalone circle) made the at-rest pill read as two       │
// │  lenses and the open animation "just expands". The pill is back to the     │
// │  rc24 anatomy — ONE capsule over two plain Share + `…` buttons, pinned      │
// │  `.regular` — and the WHOLE capsule carries `glassEffectID`, so the `…`    │
// │  tap deforms the entire pill (droplet down, then settle into the panel).   │
// │  Share unmounts on open (consumed into the panel's first row, Apple-Notes  │
// │  pattern, FR-04), so nothing live can glue to the flying glass (rc18-cut1).│
// │  Undo is the one chrome artifact OUTSIDE the container (its own glass).     │
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
// │ • `if #available` fallbacks, and share presentation without a zoom source  │
// │   (`SystemSharePresenter.present` without `from:`) — the whole-pill melt    │
// │   and the zoom anchor are one seam, on every share path.                    │
// └────────────────────────────────────────────────────────────────────────────┘
//
// WHOLE-PILL SHARE MORPH (user directive, "Apple Notes the pill morphs into the
// system share sheet"): the Share half of the closed pill is a plain Button, not
// a ShareLink — ShareLink exposes no hook into the system share presentation, so
// no transition source can ride it. On tap: (1) the morph container flips to its
// MELT state — an empty zero-size glass child carrying the same morph identity,
// so the capsule's glass shrinks to nothing while (2) SystemSharePresenter
// presents the system activity sheet with `preferredTransition = .zoom` sourced
// at `ShareSourceAnchor` — an inert UIView mirroring the pill's exact slot,
// mounted in every state (the melt unmounts the pill, never the anchor). On
// completion/dismissal the zoom closes the sheet back into the pill's frame and
// the melt reverses — the pill glass grows back. The still-open MenuBubble is
// NOT reachable during a share (the Share control is only mounted while closed),
// so share and menu morphs can never overlap.
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
//   (1) overflow toggle       — the `…` capsule's button — withAnimation(menuOpenAnimation)
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
///   - A pinned standalone Undo glass circle (own trailing inset — never moves;
///     hit-testing off while glass renders over it).
///   - The shared morph container — the positioned top-trailing child, holding EXACTLY one
///     child per state: `closedPill` (closed) XOR `MenuBubble` (open), sharing the morph ID.
///     As the LAST z-child it expands OVER the Undo circle instead of pushing it.
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

    /// `true` while the system share sheet is presented by the pill's Share tap.
    /// Written by exactly two sources: `presentShareSheet()` (open, with the
    /// melt) and the `SystemSharePresenter` completion (close, when the zoomed
    /// sheet completes/dismisses — the pill glass grows back from the same
    /// frame). The container hosts an empty zero-size glass child in this
    /// state so the pill's morph identity shrinks to nothing as the zoom starts.
    @State private var isShareSurfacePresented: Bool = false

    /// Reference box receiving the inert share-source anchor UIView (the zoom
    /// transition's geometric source — the closed pill's exact slot).
    @State private var shareAnchorBox = ShareAnchorBox()

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

            // The top chrome: the Undo circle is its own glass artifact OUTSIDE the
            // morph container, PINNED at its own trailing inset so its position is
            // independent of what the morph container hosts. The morph container is
            // the LAST z-child, so whatever it expands into (the panel now, the
            // share sheet later) grows OVER the Undo circle instead of pushing it
            // — the Apple-Notes layering the user requires.
            undoButton
                .padding(.top, ChromeMetrics.pillTopGap)
                .padding(.trailing, ChromeMetrics.undoCircleTrailingInset)
                // The pinned Undo circle must not intercept taps that belong to
                // the open panel or the outside-tap dismiss (both state that
                // render glass OVER it).
                .allowsHitTesting(!isMenuPresented)

            // Inert coordinate anchor mirroring the closed pill's exact slot — the
            // zoom transition's geometric source for the system share sheet.
            // Invisible, never interactive, and mounted in EVERY state so its
            // window frame is always resolvable (the share melt unmounts the
            // pill, never this anchor).
            ShareSourceAnchor(box: shareAnchorBox)
                .frame(width: ChromeMetrics.closedPillWidth, height: ChromeMetrics.pillHeight)
                .padding(.top, ChromeMetrics.pillTopGap)
                .padding(.trailing, ChromeMetrics.chromeHorizontalInset)

            GlassEffectContainer(spacing: ChromeMetrics.metaballSpacing) {
                if isShareSurfacePresented {
                    // The share melt: the pill's morph identity shrinks to a
                    // zero-size glass shape while the system share sheet zooms
                    // out of the anchor's frame (the pill "melts into" the
                    // sheet). The identity continuity lets the glass system
                    // deform the capsule down instead of hard-swapping it.
                    Color.clear
                        .frame(width: 0, height: 0)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectTransition(.matchedGeometry)
                        .glassEffectID(Self.chromeGlassID, in: glassNamespace)
                } else if isMenuPresented {
                    MenuBubble(
                        menuVM: menuVM,
                        isPresented: $isMenuPresented,
                        glassNamespace: glassNamespace,
                        glassID: Self.chromeGlassID,
                        dismissAnimation: menuCloseAnimation,
                        text: text,
                        isShareDisabled: isShareDisabled
                    )
                    // No transition modifier on either XOR child — .identity kills
                    // the morph (rc21). The branch crossfade stays (demo parity);
                    // rows inside the panel add none (rc22 D1).
                } else {
                    closedPill
                }
            }
            .padding(.top, ChromeMetrics.pillTopGap)
            .padding(.trailing, ChromeMetrics.chromeHorizontalInset)
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

    /// The top-leading control: a standalone glass circle in the same
    /// manual-glass anatomy as the pill capsule, sized to equal its height
    /// (44pt circle vs 44pt capsule — user-approved DD-3a).
    ///
    /// Deliberately OUTSIDE the morph container and PINNED at
    /// `ChromeMetrics.undoCircleTrailingInset`, so its position is independent
    /// of the morph container's content: when the panel (or later the share
    /// sheet) expands, it grows OVER this circle instead of pushing it aside.
    /// While the panel is open the circle stops hit-testing so taps fall
    /// through to the outside-tap dismiss (see the body allowsHitTesting gate).
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

    // MARK: - Closed pill: Share + `…` fused (rc24 restoration)

    /// The closed state's ONLY glass shape, restored from rc24: ONE capsule over
    /// two plain buttons (Share + `…`) — the `BottomToolbar` anatomy. The capsule
    /// glass is PINNED `.regular` (the interactive variant is prohibited on
    /// multi-button glass — rc8 tap-swallow) and the WHOLE capsule carries the
    /// morph identity, so both the `…` tap and (later) the Share tap deform the
    /// entire pill as a single liquid unit.
    private var closedPill: some View {
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            shareControl
            ellipsisControl
        }
        .padding(.horizontal, ChromeMetrics.capsuleHorizontalPadding)
        .glassEffect(.regular, in: .capsule)
        .glassEffectTransition(.matchedGeometry)
        .glassEffectID(Self.chromeGlassID, in: glassNamespace)
    }

    // MARK: - Share control, one half of the fused closed pill (rc24)

    /// Share as ONE HALF of the rc24 fused capsule: a plain Button whose glass
    /// is the pill capsule itself. Tapping it deforms the WHOLE pill (its morph
    /// identity melts to a zero-size glass shape, presentShareSheet below)
    /// while the system share sheet zooms out of the pill's exact frame — the
    /// same button→overlay morph Apple Notes performs of its share panel.
    /// (`ShareLink` had to go: it exposes no hook into the system share
    /// presentation, so the zoom source cannot be attached to it.)
    ///
    /// The tap target is armed by the inline 44pt frame + contentShape (DD-2).
    private var shareControl: some View {
        Button {
            presentShareSheet()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .fontWeight(ChromeMetrics.iconScaleWeight)
                .imageScale(.large)
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
    }

    // MARK: - Share presentation seam (whole-pill melt + system zoom morph)

    /// Opens the system share sheet as a zoom-morph out of the pill.
    ///
    /// Two concurrent halves of one animation:
    ///   1. The SwiftUI half — `isShareSurfacePresented` flips the morph
    ///      container to its empty glass child, so the capsule's glass identity
    ///      shrinks to nothing (the melt) under the open spring.
    ///   2. The system half — `SystemSharePresenter` presents the share sheet
    ///      zooming out of the anchor that mirrors the pill's exact frame.
    /// The presenter owns the close seam: its `onFinish` (sheet completed or
    /// dismissed — or presentation failed outright) melts the pill back under
    /// the close spring, from the same frame the sheet zoomed into.
    private func presentShareSheet() {
        withAnimation(menuOpenAnimation) {
            isShareSurfacePresented = true
        }
        SystemSharePresenter.present(text: text, from: shareAnchorBox) {
            withAnimation(menuCloseAnimation) {
                isShareSurfacePresented = false
            }
        }
    }

    // MARK: - `…` control, one half of the fused closed pill (rc24)

    /// The `…` as ONE HALF of the rc24 fused capsule: a plain button whose glass
    /// is the pill capsule itself (rc24 restoration) — the rc8 tap-swallow
    /// prohibition (`.interactive()` on multi-button glass) cannot trigger
    /// because the capsule is pinned `.regular` and every button inside it is
    /// `.plain`. The frame + contentShape arm the full 44pt tap target (DD-2).
    private var ellipsisControl: some View {
        Button {
            // EC-14 write-source 1 — the control is mounted only while closed.
            withAnimation(menuOpenAnimation) {
                isMenuPresented = true
            }
        } label: {
            Image(systemName: "ellipsis")
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
}
