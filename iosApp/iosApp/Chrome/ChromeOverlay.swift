// Chrome/ChromeOverlay.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph + top-pad)
//
// Container view composing the top toolbar (Share + overflow `…`) + the morphing
// menu panel (MenuBubble) over the editor. Reads ChromeVisibility.isVisible and
// crossfades the chrome layer. Owns the single GlassEffectContainer + morph namespace.
//
// ┌─ MORPH LAYOUT rc18-r2 (read before changing) ──────────────────────────────┐
// │ STRUCTURE: Share OUTSIDE the container; container holds ONLY the morph pair. │
// │                                                                            │
// │   HStack(spacing: capsuleControlSpacing) {                                  │
// │       shareButton             // .buttonStyle(.glass), OUTSIDE container    │
// │       Color.clear.frame(44,44)// layout spacer — keeps HStack width fixed   │
// │           .overlay(.topTrailing) {                                          │
// │               GlassEffectContainer(spacing: 35) {   // only the morph XOR  │
// │                   if open { MenuBubble  }  .glassEffectID + .transition(.identity) │
// │                   else    { overflowButton }  .glassEffect(.interactive)    │
// │                                                + .glassEffectID             │
// │                                                + .transition(.identity)     │
// │               }                                                             │
// │           }                                                                 │
// │   }                                                                         │
// │                                                                            │
// │ WHY Share is outside the GlassEffectContainer:                              │
// │  • GlassEffectContainer(spacing:35) metaball-fuses glass elements inside   │
// │    it. If Share is inside the container and 0pt from the panel (VStack      │
// │    spacing:0), Share's glass shape coalesces into the panel's corner —      │
// │    the "Share glues to panel" artifact (confirmed rc18-initial / rc15).     │
// │  • Moving Share OUTSIDE the container eliminates coalescence entirely:       │
// │    metaball merge is scoped per-container; Share has its own independent    │
// │    .buttonStyle(.glass) and never participates in the morph.                │
// │                                                                            │
// │ WHY Share's frame is invariant (never moves when panel opens):              │
// │  • The HStack's second child is ALWAYS Color.clear.frame(44,44) — a fixed  │
// │    44×44 layout spacer. Its size never changes regardless of whether the    │
// │    GlassEffectContainer (in the overlay) is showing a 44pt capsule or a    │
// │    280pt panel. The overlay does not participate in HStack layout.          │
// │  • Share's trailing edge = HStack.trailing - 44 - capsuleControlSpacing.   │
// │    This is a constant — Share never shifts left or right.                  │
// │                                                                            │
// │ WHY the GlassEffectContainer is in .overlay(alignment: .topTrailing):      │
// │  • The container grows from 44pt (capsule) to 280pt wide + ~400pt tall     │
// │    (panel). If it were a direct HStack child, that growth would push Share  │
// │    left by ~236pt. The overlay layer is outside HStack layout flow: the     │
// │    container can be any size without reflowing the HStack.                  │
// │  • .topTrailing alignment anchors the panel's top-right corner at the       │
// │    spacer's top-right corner — exactly where the overflow button lives.     │
// │    The panel grows LEFT (to 280pt) and DOWN, not right or up.              │
// │                                                                            │
// │ WHY identical topology to LiquidMenuDemo.swift:                             │
// │  • The container holds EXACTLY ONE child at a time: overflowButton OR      │
// │    MenuBubble. This is the proven demo topology. No frame-race is possible  │
// │    because the freshly-inserted view is the container's ONLY child —        │
// │    its layout frame resolves without competing siblings.                    │
// │                                                                            │
// │ .glassEffect(.regular.interactive(), in: .capsule) on the overflow button: │
// │  • .interactive() gives the "squish/deform" on tap — the refractive drop   │
// │    effect. Safe on a SINGLE button (rc8 tap-swallow was .interactive() on   │
// │    a multi-button CONTAINER).                                               │
// │                                                                            │
// │ HISTORY — do NOT reintroduce:                                               │
// │  • Share INSIDE GlassEffectContainer (rc18-initial) — metaball coalescence  │
// │    with panel. Share's glass merges into the panel's corner.                │
// │  • VStack(spacing:0) with Share + panel both inside the container (rc18) — │
// │    same coalescence; also the panel-in-VStack-row caused frame-race risk.  │
// │  • Whole-view swap TopPill↔MenuBubble (rc16/rc17) — unmounts Share.        │
// │  • Persistent-toolbar + panel appended (eeeb7a0) — HStack reflow + frame   │
// │    race (panel mid-screen snap).                                            │
// │  • .glassEffect(.capsule) on toolbar HStack — swallows overflow tap.       │
// │  • .interactive() on container-level glass — swallows overflow tap.        │
// │  • glassEffectID on the whole HStack (rc17) — whole-capsule morph;         │
// │    Share vanished instead of persisting.                                   │
// └──────────────────────────────────────────────────────────────────────────┘
//
// EC-14: isMenuPresented is written by EXACTLY two sources —
//   (1) the overflow toggle (write-source #1 — in overflowButton below)
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
/// Layout (top-trailing, within safe area):
///   - `shareButton` — outside the `GlassEffectContainer`, its own `.buttonStyle(.glass)`.
///   - A `Color.clear` 44×44 layout spacer that holds the HStack width invariant.
///   - `GlassEffectContainer` in an `.overlay(.topTrailing)` on the spacer — holds ONLY
///     the `overflowButton`↔`MenuBubble` XOR pair (LiquidMenuDemo topology).
///   - Transparent full-screen tap-catcher — outside-tap dismiss (EC-14).
///
/// **Glass morph (rc18-r2 — §3.1):** see the header box. Share is outside the container
/// so it cannot metaball-coalesce with the panel. The container holds exactly one child
/// at a time: `overflowButton` (closed) or `MenuBubble` (open). Share's layout frame is
/// invariant because the HStack's second child is always the fixed 44×44 spacer.
///
/// **Reduce Motion (C-07):** when `accessibilityReduceMotion` is true the toggle
/// animation is `nil` (instantaneous) instead of the spring morph.
///
/// **Bubble dismiss contract (EC-14):** `isMenuPresented` is written by EXACTLY two
/// sources — the overflow toggle (write-source #1) and the tap-catcher below.
struct ChromeOverlay: View {

    // MARK: - Inputs (from ContentView / composition root)

    /// Current buffer text — forwarded to the share button for the disabled gate (EC-01/FR-08).
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
    /// EC-14: written by EXACTLY two sources — the overflow toggle (#1)
    /// and the tap-catcher (#2). SM events and `MenuViewModel` NEVER mutate this.
    @State private var isMenuPresented: Bool = false

    // MARK: - Morph identity (§3.1 morph identity seam)

    /// Namespace binding the overflow capsule and the menu panel into one shared
    /// glass identity for the `…`↔panel morph inside `GlassEffectContainer` (C-03).
    @Namespace private var glassNamespace

    /// Shared glass effect ID — on the overflow button (closed) and on MenuBubble (open).
    /// Share has NO ID — it does not participate in the morph.
    private static let chromeGlassID = "chrome.morph"

    /// Metaball merge threshold for the `GlassEffectContainer`.
    /// Drives the liquid teardrop stretch during the `…`↔panel morph.
    /// 30–45 matches Apple Notes feel. The container holds only the morph pair, so
    /// this value no longer affects Share (Share is outside the container).
    private static let glassSpacing: CGFloat = 35

    /// Side length of the layout spacer that anchors the `GlassEffectContainer` overlay.
    /// Must match the overflow button's rendered width/height so Share's screen position
    /// is identical whether the overflow button or the panel is showing in the overlay.
    private static let morphAnchorSize: CGFloat = 44

    // MARK: - Accessibility

    /// When `true`, the morph animation is replaced by an instantaneous transition (C-07).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation seam (§3.1 / C-05 / C-06)

    /// Resolved morph animation — computed once so ALL three `isMenuPresented` write-sites
    /// (overflow toggle, tap-catcher, recovery-row dismiss) use an identical spring (C-05/C-06).
    /// `nil` under Reduce Motion; a bouncy spring otherwise.
    private var menuToggleAnimation: Animation? {
        reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.15)
    }

    // MARK: - Derived state

    /// `true` when the Share control must be disabled (EC-01/FR-08).
    private var isShareDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            // Chrome controls: Share + overlay-anchored morph pair, top-trailing.
            VStack {
                HStack {
                    Spacer()
                    pillAndPanel
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

    // MARK: - Pill + panel (§3.1 morph identity seam)

    /// The toolbar row holding Share and the GlassEffectContainer morph pair.
    ///
    /// **Layout:**
    /// ```
    /// HStack {
    ///     shareButton                        // .buttonStyle(.glass), outside container
    ///     Color.clear.frame(44,44)           // invariant layout spacer
    ///         .overlay(.topTrailing) {
    ///             GlassEffectContainer(35) { // ONLY one child at a time
    ///                 if open { MenuBubble } else { overflowButton }
    ///             }
    ///         }
    /// }
    /// ```
    ///
    /// **Share invariance:** HStack's second child is always 44×44. The overlay's
    /// size changes (44pt→280pt wide) do not participate in HStack layout → Share
    /// stays at its initial position regardless of whether the panel is open.
    ///
    /// **No coalescence:** Share is outside the `GlassEffectContainer`. Metaball
    /// merge is per-container; Share cannot fuse with the panel. At rest, Share and
    /// the overflow button read as a two-capsule segmented pill (consistent with
    /// Notes/Calendar/Drafts). When open, Share is a standalone glass capsule.
    ///
    /// **Frame resolution:** the container holds exactly ONE child (overflow XOR panel).
    /// This is the LiquidMenuDemo topology — no frame-race, no competing siblings.
    @ViewBuilder
    private var pillAndPanel: some View {
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            // Share: plain glass button OUTSIDE the morph container.
            // Cannot coalesce with the panel; tap routing independent of the morph.
            shareButton

            // Fixed 44×44 spacer — anchors the container overlay without reflowing Share.
            // The overlay renders outside HStack layout so Share's frame is invariant.
            Color.clear
                .frame(width: Self.morphAnchorSize, height: Self.morphAnchorSize)
                .overlay(alignment: .topTrailing) {
                    // GlassEffectContainer: XOR pair — identical to LiquidMenuDemo topology.
                    // Holds EXACTLY one child; the container's top-trailing corner aligns
                    // with the spacer's top-trailing corner (same as the overflow button's position).
                    // Panel grows LEFT (to 280pt) and DOWN without touching Share's layout slot.
                    GlassEffectContainer(spacing: Self.glassSpacing) {
                        if isMenuPresented {
                            MenuBubble(
                                menuVM: menuVM,
                                isPresented: $isMenuPresented,
                                glassNamespace: glassNamespace,
                                glassID: Self.chromeGlassID,
                                dismissAnimation: menuToggleAnimation
                            )
                            // .transition(.identity): suppress SwiftUI's default fade so
                            // the glass morph is the only animation on insertion/removal.
                            .transition(.identity)
                        } else {
                            overflowButton
                        }
                    }
                }
        }
    }

    // MARK: - Share control (FR-08, EC-01)

    /// `ShareLink` exporting the current buffer text.
    ///
    /// Always mounted; always OUTSIDE `GlassEffectContainer` — cannot coalesce with the panel.
    /// No `glassEffectID` — Share does NOT morph.
    /// Disabled when `text.trimmed.isEmpty` (EC-01/FR-08 — declarative gate, not try/catch).
    private var shareButton: some View {
        ShareLink(item: text) {
            Label(
                String(localized: "Share", comment: "Share button label in the top pill"),
                systemImage: "square.and.arrow.up"
            )
            .labelStyle(.iconOnly)
            .fontWeight(ChromeMetrics.iconScaleWeight)
            .imageScale(.large)
        }
        .frame(minWidth: 44, minHeight: 44)
        .disabled(isShareDisabled)
        .buttonStyle(.glass)
        .accessibilityLabel(
            String(localized: "Share", comment: "Share button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
        )
    }

    // MARK: - Overflow button (EC-14 write-source #1)

    /// The `…` overflow button — the sole element that morphs into `MenuBubble`.
    ///
    /// - `.glassEffect(.regular.interactive(), in: .capsule)`: single-button glass capsule
    ///   with `.interactive()` squish/deformation on tap. The interactive glass provides the
    ///   "irregular drop + refraction" deformation the user wants. Safe here — this is a
    ///   single-button shape (rc8 tap-swallow was `.interactive()` on a multi-button container).
    /// - `.glassEffectID(chromeGlassID, in: glassNamespace)`: morph identity. The glass system
    ///   morphs FROM this button's layout frame TOWARD `MenuBubble`'s layout frame.
    /// - `.transition(.identity)`: suppresses SwiftUI's default opacity crossfade on removal
    ///   so the glass morph is the only animation.
    ///
    /// EC-14 write-source #1: sets `isMenuPresented = true`. Write-source #2 is the
    /// tap-catcher; write-source #3 (close-only) is `MenuBubble.dismissAnimation`.
    private var overflowButton: some View {
        Button {
            withAnimation(menuToggleAnimation) {
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
        }
        .frame(minWidth: 44, minHeight: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(Self.chromeGlassID, in: glassNamespace)
        .transition(.identity)
        .accessibilityLabel(
            String(localized: "Menu", comment: "Overflow menu button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(localized: "Open menu", comment: "Overflow menu button tooltip in the top pill (FR-23)")
        )
    }
}
