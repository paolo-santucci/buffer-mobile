// Chrome/ChromeOverlay.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Container view composing the top-right chrome: a standalone Undo glass circle
// beside ONE glass capsule (rc24 anatomy: Share + `…` behind a single pinned
// `.regular` capsule) that melts into a travelling drop and blooms into the menu
// panel (MenuBubble) and back, over the editor. The chrome is permanently visible:
// the auto-hide state machine (ChromeVisibility) is retired — no fade while
// writing, no scroll-direction hide. Owns the ONE shared morph container, the
// morph namespace, the drop-journey stage machine, and the private
// `isMenuPresented` state.
//
// ┌─ MORPH TOPOLOGY (read before changing) ────────────────────────────────────┐
// │ ONE positioned top-trailing container holding EXACTLY ONE child per state:  │
// │                                                                            │
// │   ZStack(alignment: .topTrailing) {                                         │
// │       if open { tapCatcher }          // sibling, NOT in the morph container│
// │       undoButton                     // PINNED trailing inset — never moved │
// │       shareAnchor                    // invisible popover anchor, every state│
// │       morphContainer(spacing: 35) {  // LAST z-child — expands OVER Undo     │
// │         GeometryReader {             // the drop's whole-overlay travel field│
// │           if sharing { blob }        // pill stretches into the share panel │
// │           else if stage == .dropping { dropCarrier } // the traveling egg  │
// │           else if stage == .open { MenuBubble } else { closedPill } // XOR │
// │               .glassEffectID(...)    — NO .transition on children           │
// │         }                                                                   │
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
// │ WHY the three-act drop journey (user direction — the pill must TRAVEL): the │
// │  old in-place deflate/inflate read wrong against Notes. `stage`             │
// │  (closed → dropping → open) drives ONE `dropCarrier` glass:                 │
// │   ACT 1 — the pill's capsule MELTS into an egg (44×56) WHILE it travels to  │
// │           the centre-bottom of the screen; melt and travel are ONE bouncy   │
// │           spring, so the drop elongates as it falls.                        │
// │   ACT 2 — it rests: a beat of stillness with residual spring wobble.        │
// │   ACT 3 — it BLOOMS: the egg's glass morphs up into the panel's frame at    │
// │           the top-right, the panel's rows arriving refracted inside it.     │
// │  Close runs the film backward: the panel shrinks into the egg at the resting│
// │  point (same-identity swap), pause, the egg rises and regrows to the pill's │
// │  frame, then the pill (icons) takes over frame-identically. A close that    │
// │  interrupts a fall skips the shrink and simply reverses the drop.           │
// │  Every handoff is an exclusive same-transaction swap: the drop inherits     │
// │  `chrome.morph` while falling and flips to `chrome.panel` only while it is  │
// │  the SOLE holder of both ids (the panel mounts in that same transaction).   │
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
// │   RETRIED since rc29 per user direction (the drop squish needs it on      │
// │   iOS 26.5): the capsule is `.regular.interactive()`, buttons `.plain`.    │
// │   REVERT the interactive variant if the inner buttons stop firing.         │
// │ • `.glassEffectID` on a persistent multi-element HStack.               rc17 │
// │   The ID rides only the two transient XOR children.                        │
// │ • Nested glass inside panel rows.                                 rc18-cut1 │
// │   Every panel row is `.plain`; MenuBubble owns the panel's single glass.    │
// │ • `.popover(` as the dismiss mechanism, an availability-guarded fallback     │
// │   branch under Chrome/, a find affordance, a separate keyboard accessory    │
// │   bar — all gate-checked (sp_chrome_morph c1, m4-3/7/8).                    │
// │ • `if #available` fallbacks, and share presentation without the pill anchor │
// │   (`SystemSharePresenter.present` without `from:`) — the whole-pill blob    │
// │   and the anchored popover are one seam, on every share path.               │
// └────────────────────────────────────────────────────────────────────────────┘
//
// WHOLE-PILL SHARE MORPH (user directive, frames img15–19: "the pill becomes
// the share panel"): the Share half of the closed pill is a plain Button, not
// a ShareLink — ShareLink exposes no hook into the system share presentation, so
// no transition source can ride it. On tap: (1) the morph container flips to its
// BLOB state — an empty panel-sized glass child carrying the same morph identity,
// so the capsule stretches INTO the blob (the pill becomes the panel) while (2)
// SystemSharePresenter presents the system activity panel POPOVER-ANCHORED at
// `ShareSourceAnchor` — an inert UIView mirroring the pill's exact slot, mounted
// in every state (the blob unmounts the pill, never the anchor); the adaptive
// `.none` override keeps the panel floating at the pill's top-right corner instead
// of adapting into a bottom sheet. On completion/dismissal the blob morphs back —
// the pill grows from the panel's frame. The still-open MenuBubble is
// NOT reachable during a share (the Share control is only mounted while closed),
// so share and menu morphs can never overlap.
//
// SUPERSESSION of the rc18-r2 header contract ("Share OUTSIDE the container — do NOT
// reintroduce"). That guard protected against Share fusing with the OPEN panel while
// coexisting as a SECOND live glass element. This design has no such counterpart:
// exactly one glass shape exists per state INSIDE the morph container — the closed
// fused capsule XOR the travelling drop XOR the open panel (XOR the share blob) —
// so two shapes never coalesce there, and while
// the panel is open Share is a plain row inside it. The Undo circle is a second
// top-chrome glass artifact by design; it lives OUTSIDE the container, giving it its
// own non-merging glass surface in both states. Every other entry of that history
// box is retained above.
//
// EC-14 / §5.3 — the `isMenuPresented` writer set is EXHAUSTIVE (three sources):
//   (1) overflow toggle       — the pill's `…` button — withAnimation(menuOpenAnimation)
//   (2) tap-catcher           — the full-screen catcher below — withAnimation(menuCloseAnimation)
//   (3) recovery-row dismiss  — MenuBubble's RecoverySection, through the `isPresented` binding
// Every close write uses menuCloseAnimation; the open write uses menuOpenAnimation. Both
// resolve to nil under Reduce Motion (FR-21). No other writer exists: the state is the
// PRIVATE @State declared here, MenuBubble's only reach is the `isPresented` binding
// (source 3), and MenuViewModel, RecoveryListViewModel, BufferViewModel and shared/
// never touch it (FR-08/FR-08n). (The former Share-row writer is retired with the
// panel's Share row — removed per user direction; Share lives only on the pill. The
// former chrome-hide writer is retired with ChromeVisibility.)
// The overlay's own morph stage machine (closed → dropping → open) is driven by
// `.onChange(of: isMenuPresented)`: it OBSERVES that state, never writes it, so the
// three-writer set above is untouched.
//
// `isShareSurfacePresented` writer set is EXHAUSTIVE (two sources):
//   (1) presentShareSheet()      — the pill's Share button — withAnimation(menuOpenAnimation)
//   (2) presenter completion     — SystemSharePresenter's onFinish — withAnimation(menuCloseAnimation)
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
//            NFR-01, NFR-02, NFR-04, NFR-06, NFR-08; EC-01, EC-13, EC-14, EC-16, EC-23;
//            CG-1.
// Contract: §4.2 (topology diagrams), §4.4 (supersession + prohibited set), §5.1.a,
//           §5.1.c, §5.3 (four-writer table + two-writer share seam).

import SwiftUI
import shared
import Observation

// MARK: - CoordinatorBox

/// Lightweight reference-type bridge that publishes the live `BufferEditor.Coordinator`
/// once it is available (set by `BufferEditor.makeUIView`).
///
/// `coordinator` is declared `weak` so the box does not extend the coordinator's
/// lifetime beyond the UIViewRepresentable's natural teardown.
///
/// `@Observable`: `canUndo` is mirrored here by `BufferEditor.Coordinator`
/// (via `onUndoStateChange`), so SwiftUI re-renders whichever view reads the
/// box — the always-visible-only-when-undoable gating of the Undo circle.
/// Undo with an empty stack is a no-op (FR-15 analog), so hiding the circle
/// reflects reachability, not correctness.
@Observable
final class CoordinatorBox {
    /// The live `BufferEditor.Coordinator`. Set once in `BufferEditor.makeUIView`;
    /// cleared automatically when the coordinator deallocates (weak ref). All
    /// toolbar closures guard against `nil` before use (EC-13).
    weak var coordinator: BufferEditor.Coordinator?

    /// `true` while the live text view's undo manager holds an undoable state
    /// (`UITextView.undoManager.canUndo`), mirrored from the Coordinator on
    /// every text-affecting path. `false` → the Undo circle is not rendered.
    var canUndo: Bool = false
}

// MARK: - ChromeOverlay

/// Non-visual composition container for the Liquid Glass chrome controls.
///
/// Layout (top-trailing, within safe area):
///   - A pinned standalone Undo glass circle (own trailing inset — never moves;
///     hit-testing off while glass renders over it).
///   - The shared morph container — the positioned top-trailing child, holding EXACTLY one
///     child per state: `closedPill` (closed) XOR the `dropCarrier` (mid-journey) XOR
///     `MenuBubble` (open), sharing the morph identity per stage. As the LAST z-child it
///     expands OVER the Undo circle instead of pushing it.
///   - Transparent full-screen tap-catcher (only while open) — outside-tap dismiss (EC-14).
///
/// **Glass morph (FR-02/FR-03):** see the header topology diagram. The pill's glass
/// detaches as a drop, travels to the centre-bottom of the screen, rests, and blooms into
/// the panel; closing runs the film backward. The iOS 26 glass system owns every
/// deformation (one identity holder at a time) — no stranded Share, no notch.
///
/// **Hit-testing:** the chrome is permanently visible (no ChromeVisibility
/// crossfade/gate anymore). The pinned Undo circle alone is hit-gated while
/// open glass renders over it (see the body).
///
/// **Reduce Motion (FR-21):** both animation seams resolve to `nil`, so every state
/// change applies instantaneously instead of springing — and both drop journeys
/// short-circuit, so the traveling carrier never even mounts.
///
/// **Bubble dismiss contract (EC-14):** write-sources 1, 2 are declared here;
/// source 3 lives in `MenuBubble` behind the `isPresented` binding. The
/// three-writer set is enumerated in the file header.
struct ChromeOverlay: View {

    // MARK: - Inputs (from ContentView / composition root)

    /// Current buffer text — forwarded to BOTH Share surfaces (the closed pill's link and
    /// the panel's Share row) and to the single empty-buffer gate (EC-01/FR-04).
    let text: String

    /// The menu view model — forwarded to `MenuBubble` (ctor-injected DIP).
    let menuVM: MenuViewModel

    /// `true` while the live editor's undo manager has something to undo
    /// (mirrored by `BufferEditor.Coordinator` into `CoordinatorBox.canUndo`).
    /// `false` → the Undo circle is not rendered: the control is visible only
    /// when there is something to undo.
    let canUndo: Bool

    /// Chrome-dispatched undo of the last editor edit — invoked by the standalone
    /// Undo circle and routed by the composition root to the live editor coordinator.
    let onUndo: () -> Void

    // MARK: - Local state

    /// Controls the `MenuBubble` presented state.
    /// EC-14: written by EXACTLY three enumerated sources — the fused pill's `…` toggle
    /// (#1), the tap-catcher (#2), and, through `MenuBubble`'s binding, the recovery-row
    /// (#3) dismissal.
    /// Private by design: nothing outside this view can reach it directly.
    @State private var isMenuPresented: Bool = false

    /// `true` while the system share panel is presented by the pill's Share tap.
    /// Written by exactly two sources: `presentShareSheet()` (open, pill→blob)
    /// and the `SystemSharePresenter` completion (close, when the anchored
    /// panel completes/dismisses — the blob morphs back into the pill). The
    /// container hosts an empty panel-sized glass child in this state so the
    /// pill's morph identity stretches into the share panel's shape.
    @State private var isShareSurfacePresented: Bool = false

    /// Reference box receiving the inert share-source anchor UIView (the
    /// anchored popover's geometric source — the closed pill's exact slot).
    @State private var shareAnchorBox = ShareAnchorBox()

    // MARK: - Drop-journey stage machine (three-act morph)

    /// The three acts of the pill↔panel journey: the pill at rest, the traveling drop,
    /// the fully bloomed panel. Driven exclusively by `onChange(of: isMenuPresented)`.
    private enum MorphStage {
        case closed
        case dropping
        case open
    }

    /// Which act is live right now.
    @State private var stage: MorphStage = .closed

    /// The drop carrier's frame — animates between the pill's frame and the egg frame.
    @State private var dropSize: CGSize = .zero

    /// The drop carrier's centre in the morph container's coordinate space — animates
    /// between the pill's slot centre and the landing point.
    @State private var dropCenter: CGPoint = .zero

    /// The glass identity the drop carries at this instant: `chromeGlassID` while it
    /// falls (inherited from the pill, so the handoff is frame-identical) and
    /// `panelGlassID` while it blooms into the panel or shrinks back out of it.
    @State private var currentDropGlassID: String = ChromeOverlay.chromeGlassID

    /// The morph container's measured size — the space `pillCenter` and `landingCenter`
    /// are derived from. A measurement that cannot contain the pill (e.g. an unresolved
    /// first layout) makes the journeys take the instantaneous path (see the guards in
    /// `presentMenuJourney` / `dismissMenuJourney`) instead of deriving bogus coordinates.
    @State private var overlaySize: CGSize = .zero

    /// The running act sequence. Every journey start cancels it first, so a close that
    /// interrupts a fall (or an open that interrupts a close) reverses cleanly.
    @State private var journeyTask: Task<Void, Never>? = nil

    // MARK: - Morph identity (§5.1.a morph identity seam)

    /// Namespace binding the closed capsule and the menu panel into one shared glass
    /// identity for the capsule↔panel morph inside the shared morph container (C-03).
    @Namespace private var glassNamespace

    /// Shared glass effect ID — carried by the closed pill, by the share blob (the
    /// pill↔blob stretch) and by the DROP while it falls (it inherits the pill's
    /// identity so the pill→drop mount is an invisible frame-identical swap). The menu
    /// PANEL deliberately carries a DIFFERENT id (`panelGlassID`): with one shared id
    /// the system merges the two shapes into ONE identity and morphs their captured
    /// CONTENTS into each other — the horizontal content smear the user showed against
    /// the Notes reference. With separate ids the travelling egg and the panel animate
    /// as two shapes in one container: the drop's glass morphs into the panel's frame
    /// while the panel's rows arrive refracted. AT MOST ONE live view holds an id at any
    /// instant, and every handoff is an exclusive same-transaction swap.
    private static let chromeGlassID = "chrome.morph"

    /// The menu panel's own glass identity (see chromeGlassID rationale). Also carried
    /// by the DROP while it blooms into the panel and while it shrinks back out of it —
    /// the drop is the sole holder of `chrome.panel` for the duration of those swaps.
    private static let panelGlassID = "chrome.panel"

    // MARK: - Accessibility

    /// When `true`, every morph/collapse animation resolves to `nil` (FR-21).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation seam (§5.1.a / §4.2 — directional, RM-gated)

    /// Opening spring — used by write-source 1 (and resolved to `nil` under Reduce Motion).
    /// Slower + slightly less bouncy than the demo's 0.45/0.15: the drop lingers
    /// elongated before settling, matching the Notes blob's reading.
    /// The journey's bloom step reuses `ChromeMetrics.menuOpenSpring` directly: both
    /// journeys short-circuit under Reduce Motion, so the raw spring is unreachable there.
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

    // MARK: - Journey geometry (derived from the measured morph container)

    /// The closed pill's frame — the journey's start and end size.
    private var pillSize: CGSize {
        CGSize(width: ChromeMetrics.closedPillWidth, height: ChromeMetrics.pillHeight)
    }

    /// The closed pill's centre in the morph container's measured space: its slot is the
    /// top-trailing corner of the padded region, so the drop mounts exactly under it.
    private var pillCenter: CGPoint {
        CGPoint(
            x: overlaySize.width - ChromeMetrics.closedPillWidth / 2,
            y: ChromeMetrics.pillHeight / 2
        )
    }

    /// Where the drop comes to rest: the centre-bottom anchor of the overlay.
    private var landingCenter: CGPoint {
        CGPoint(
            x: overlaySize.width * ChromeMetrics.dropLandingHorizontalAnchor,
            y: overlaySize.height * ChromeMetrics.dropLandingVerticalAnchor
        )
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
            if canUndo {
                undoButton
                    .padding(.top, ChromeMetrics.pillTopGap)
                    .padding(.trailing, ChromeMetrics.undoCircleTrailingInset)
                    // The pinned Undo circle must not intercept taps that belong to
                    // the open panel or the outside-tap dismiss (both state that
                    // render glass OVER it).
                    .allowsHitTesting(!isMenuPresented)
            }

            // Inert coordinate anchor mirroring the closed pill's exact slot — the
            // anchored share popover's geometric source. Invisible, never
            // interactive, and mounted in EVERY state so its window frame is
            // always resolvable (the share blob unmounts the pill, never this
            // anchor).
            ShareSourceAnchor(box: shareAnchorBox)
                .frame(width: ChromeMetrics.closedPillWidth, height: ChromeMetrics.pillHeight)
                .padding(.top, ChromeMetrics.pillTopGap)
                .padding(.trailing, ChromeMetrics.chromeHorizontalInset)

            morphContainer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onChange(of: isMenuPresented) { _, presented in
            if presented {
                presentMenuJourney()
            } else {
                dismissMenuJourney()
            }
        }
        // The chrome is PERMANENTLY visible (user direction: the pill never fades
        // while writing — the auto-hide state machine is retired). No crossfade,
        // no hit-testing gate, no chrome-hide dismissal writer.
    }

    // MARK: - Morph container (the ONE glass shape per state)

    /// The overlay-spanning glass morph container.
    ///
    /// The top-trailing paddings stay OUTSIDE the measured region, so the pill, the panel
    /// and the share blob keep EXACTLY their previous slots (the padded region's
    /// top-trailing corner); the inner `GeometryReader` gives the drop the whole-overlay
    /// travel field the journey needs.
    private var morphContainer: some View {
        GlassEffectContainer(spacing: ChromeMetrics.metaballSpacing) {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    morphChild
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
                .onAppear { overlaySize = geo.size }
                .onChange(of: geo.size) { _, size in overlaySize = size }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, ChromeMetrics.pillTopGap)
        .padding(.trailing, ChromeMetrics.chromeHorizontalInset)
    }

    /// The morph container's XOR state branch: EXACTLY ONE glass child is live per state —
    /// share blob XOR the traveling drop XOR the open panel XOR the closed pill.
    ///
    /// No `.transition` on any branch — `.identity` removes the animated
    /// insertion/removal window the glass container needs to interpolate and KILLS the
    /// morph (rc21). The default branch crossfade is demo parity; the panel's rows add
    /// none (rc22 D1). Geometry is owned entirely by `.glassEffectID`.
    @ViewBuilder
    private var morphChild: some View {
        if isShareSurfacePresented {
            shareBlob
        } else if stage == .dropping {
            dropCarrier
        } else if stage == .open {
            MenuBubble(
                menuVM: menuVM,
                isPresented: $isMenuPresented,
                glassNamespace: glassNamespace,
                glassID: Self.panelGlassID,
                dismissAnimation: menuCloseAnimation
            )
        } else {
            closedPill
        }
    }

    /// The share blob: the pill's morph identity stretches into a panel-sized glass
    /// surface while the system share popover presents over it — the pill "becomes" the
    /// share panel, and its content arrives refracted on top. The identity continuity is
    /// what deforms the capsule into the blob instead of hard-swapping it.
    private var shareBlob: some View {
        Color.clear
            .frame(
                width: ChromeMetrics.sharePanelBlobWidth,
                height: ChromeMetrics.sharePanelBlobHeight
            )
            .glassEffect(.regular, in: .rect(cornerRadius: ChromeMetrics.menuPanelCornerRadius))
            .glassEffectTransition(.matchedGeometry)
            .glassEffectID(Self.chromeGlassID, in: glassNamespace)
    }

    // MARK: - Drop carrier (the traveling glass identity)

    /// The ONLY glass shape while `stage == .dropping`: a small egg-shaped capsule that
    /// melts out of the pill's frame, travels to the landing point, and rests there before
    /// blooming into the panel. One `.glassEffect` on a clear fill — never content, never
    /// nested glass, never hit-testable, hidden from VoiceOver.
    private var dropCarrier: some View {
        Color.clear
            .frame(width: dropSize.width, height: dropSize.height)
            .glassEffect(.regular, in: .capsule)
            .glassEffectTransition(.matchedGeometry)
            .glassEffectID(currentDropGlassID, in: glassNamespace)
            .position(x: dropCenter.x, y: dropCenter.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Drop journey (three-act choreography)

    /// The open journey, driven by `.onChange(of: isMenuPresented)`.
    ///
    /// The `…` writer has already flipped `isMenuPresented` under `menuOpenAnimation`;
    /// every subsequent frame belongs to this journey, so it applies its own explicit
    /// springs. The drop first mounts at the pill's exact frame and identity (an invisible
    /// swap), then ACT 1 melts + travels under one bouncy spring, ACT 2 rests for the
    /// settle beat, ACT 3 flips to the panel identity in the SAME transaction that mounts
    /// `MenuBubble` — the glass morph from egg to panel.
    ///
    /// Reduce Motion (FR-21): short-circuits to `.open`, so the drop never mounts — the
    /// writers' animation seam is already `nil`. An unmeasured container takes the same
    /// path, so the chrome can never get stuck mid-journey.
    private func presentMenuJourney() {
        journeyTask?.cancel()
        journeyTask = nil
        guard !reduceMotion,
              overlaySize.width > ChromeMetrics.closedPillWidth,
              overlaySize.height > ChromeMetrics.pillHeight else {
            stage = .open
            return
        }
        var mount = Transaction()
        mount.disablesAnimations = true
        withTransaction(mount) {
            stage = .dropping
            currentDropGlassID = Self.chromeGlassID
            dropCenter = pillCenter
            dropSize = pillSize
        }
        journeyTask = Task { @MainActor in
            await self.runPresentJourney()
        }
    }

    /// The reverse film, driven by `.onChange(of: isMenuPresented)`.
    ///
    /// From `.open` the panel first shrinks into the egg at the resting point (an
    /// exclusive same-identity swap), then — after the settle beat — the egg rises and
    /// regrows to the pill's frame. A close that interrupts a fall skips the shrink: the
    /// drop simply reverses course from wherever it is.
    ///
    /// Reduce Motion (FR-21): short-circuits to `.closed`, so the drop never mounts.
    private func dismissMenuJourney() {
        journeyTask?.cancel()
        journeyTask = nil
        guard !reduceMotion,
              overlaySize.width > ChromeMetrics.closedPillWidth,
              overlaySize.height > ChromeMetrics.pillHeight else {
            stage = .closed
            return
        }
        let shrinksFromPanel = stage == .open
        if shrinksFromPanel {
            withAnimation(ChromeMetrics.dropShrinkSpring) {
                currentDropGlassID = Self.panelGlassID
                stage = .dropping
                dropCenter = landingCenter
                dropSize = ChromeMetrics.dropEggSize
            }
        }
        journeyTask = Task { @MainActor in
            await self.runDismissJourney(shrinksFromPanel: shrinksFromPanel)
        }
    }

    /// ACT 1–3: melt + travel, rest, bloom.
    @MainActor
    private func runPresentJourney() async {
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        withAnimation(ChromeMetrics.dropFallSpring) {
            dropSize = ChromeMetrics.dropEggSize
            dropCenter = landingCenter
        }
        try? await Task.sleep(for: .seconds(ChromeMetrics.dropTravelSettle))
        guard !Task.isCancelled else { return }
        withAnimation(ChromeMetrics.menuOpenSpring) {
            currentDropGlassID = Self.panelGlassID
            stage = .open
        }
    }

    /// The reverse film: shrink into the egg (when coming from the panel), rise + regrow,
    /// then hand the frame over to the pill.
    @MainActor
    private func runDismissJourney(shrinksFromPanel: Bool) async {
        if shrinksFromPanel {
            try? await Task.sleep(for: .seconds(ChromeMetrics.dropShrinkSettle))
            guard !Task.isCancelled else { return }
        }
        withAnimation(ChromeMetrics.dropRiseSpring) {
            currentDropGlassID = Self.chromeGlassID
            dropCenter = pillCenter
            dropSize = pillSize
        }
        try? await Task.sleep(for: .seconds(ChromeMetrics.dropRiseSettle))
        guard !Task.isCancelled else { return }
        stage = .closed
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
    /// carries the WHOLE morph identity and, since rc29, `.interactive()` — the
    /// touch-squish the LiquidMenuDemo drop feel requires (user-directed rc29
    /// experiment). rc8 RISK NOTE: this is the exact shape that swallowed
    /// inner-button taps on iOS 26.0 (rc8→rc9); the user accepted re-trying it
    /// on 26.5 — if the Share/`…` buttons stop firing, REVERT to the pinned
    /// `.regular` variant.
    private var closedPill: some View {
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            shareControl
            ellipsisControl
        }
        .padding(.horizontal, ChromeMetrics.capsuleHorizontalPadding)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectTransition(.matchedGeometry)
        .glassEffectID(Self.chromeGlassID, in: glassNamespace)
    }

    // MARK: - Share control, one half of the fused closed pill (rc24)

    /// Share as ONE HALF of the rc24 fused capsule: a plain Button whose glass
    /// is the pill capsule itself. Tapping it deforms the WHOLE pill (its morph
    /// identity stretches into the blob, presentShareSheet below)
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

    // MARK: - Share presentation seam (pill→blob + anchored popover)

    /// Opens the system share panel anchored at the pill.
    ///
    /// Two concurrent halves of one animation:
    ///   1. The SwiftUI half — `isShareSurfacePresented` flips the morph
    ///      container to its empty glass child, so the capsule's glass identity
    ///      stretches into the blob (the pill→panel morph) under the open spring.
    ///   2. The system half — `SystemSharePresenter` presents the share panel
    ///      popover-anchored at the mirror of the pill's exact frame (top edge
    ///      where the pill's top edge is — the user-required landing).
    /// The presenter owns the close seam: its `onFinish` (panel completed or
    /// dismissed — or presentation failed outright) morphs the blob back under
    /// the close spring, from the same frame the panel grew out of.
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
    /// is the pill capsule itself (rc24 restoration). The frame + contentShape
    /// arm the full 44pt tap target (DD-2).
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
