// Chrome/TopPill.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph)
//
// Top toolbar row: Share control (disabled on empty buffer) + overflow `…` button.
// Renders with native iOS 26 Liquid Glass; no hand-rolled blur/fill/shadow;
// no #available fallback (min target iOS 26.0).
//
// ┌─ HOW THE CAPSULE + MORPH ACTUALLY WORK (read before changing) ────────────┐
// │ ONE CAPSULE, TWO BUTTONS, WHOLE-CAPSULE MORPH:                               │
// │  • Share and overflow are TWO independent glass buttons (`.buttonStyle(     │
// │    .glass)`), each with its own gesture handler (independently hit-testable) │
// │  • `.glassEffectUnion(id: pillUnionID, namespace:)` on BOTH fuses their     │
// │    glass outlines into one even capsule shape. Union is visual only —        │
// │    it does NOT affect gesture routing or morph geometry.                    │
// │  • `.glassEffectID(glassID, ...)` is on the OUTER HStack (the whole         │
// │    TopPill body), NOT on a single button. The morph source/destination is   │
// │    the HStack's layout frame — the FULL capsule width — so the whole blob   │
// │    [Share | ...] deforms into the panel (Option C / Apple Notes feel).      │
// │  • Do NOT put `.glassEffectID` on just the overflow button: the morph        │
// │    source would be the small overflow frame only, and Share would abruptly   │
// │    disappear rather than being absorbed into the stretch.                   │
// │  • Do NOT wrap the HStack in `.glassEffect(.capsule)` — that merges the     │
// │    two controls into one interactive glass surface and iOS 26 routes the    │
// │    merged group's taps to the first child, swallowing the overflow tap.     │
// │  • The container's `spacing` (GlassEffectContainer in ChromeOverlay) drives │
// │    the metaball merge and the liquid teardrop stretch during morph.          │
// │                                                                            │
// │ HISTORY of what NOT to re-introduce:                                        │
// │  • `.glassEffectID` on overflowButton only (rc16) — small-frame morph;      │
// │    Share abruptly vanishes instead of being absorbed into the stretch.       │
// │  • NO `.glassEffect(.regular, in: .capsule)` on the HStack — tap swallow.    │
// │  • NO `if !isMenuPresented { overflowButton }` inside TopPill (eeeb7a0) —   │
// │    caused HStack reflow (Share slides) and morph-destination frame race     │
// │    (panel lands mid-screen then snaps) on close.                           │
// │  • NO `.interactive()` on container-level glass — swallows overflow tap.    │
// └──────────────────────────────────────────────────────────────────────────┘
//
// Morph seam (§3.1): receives `glassNamespace` and `glassID` from ChromeOverlay.
// The outer HStack (the whole capsule) attaches `.glassEffectID(glassID, in:
// glassNamespace)`; the MenuBubble (in ChromeOverlay) attaches the same id. Both live
// in the one GlassEffectContainer ChromeOverlay owns, so the morph crosses the view boundary.
//
// Animation seam (§3.1 T-02): receives `menuToggleAnimation` from ChromeOverlay
// so the overflow toggle uses the SAME animation (and reduce-motion gate) as
// ChromeOverlay's tap-catcher dismiss. Reduce-motion authority stays in
// ChromeOverlay (C-06) — TopPill adds no @Environment(\.accessibilityReduceMotion).
//
// EC-14: the overflow button is write-source #1 for `isMenuPresented`. The
// outside-tap dismiss is handled by a full-screen tap-catcher in ChromeOverlay
// (write-source #2). This view owns NO dismiss logic beyond the toggle it
// exposes via $isMenuPresented.
//
// Hit-target (iOS 26): button labels use `Label(...).labelStyle(.iconOnly)`
// rather than a bare `Image`. On iOS 26 an Image-only button can shrink its
// tap target to the glyph; a Label keeps the full padded frame hittable and
// adds accessibility text for free.
//
// CANON GAP CG-1: native Liquid Glass system material supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color @90%
// color-mix fill + hairline ring. 0.68 / 90% survive as legibility intent
// only (NFR-03). Decision logged per spec §8 OQ-01.
//
// Apple-Notes-26 restyle (T-02): icon weight -> ChromeMetrics.iconScaleWeight
// (.medium); inter-icon spacing -> ChromeMetrics.capsuleControlSpacing (this is
// the gap between Share and overflow; keep it well below the container's spacing
// so the two buttons fuse into one capsule).
// Rendered control HEIGHT target stays ~44pt (C-01 — BufferEditor hard-codes
// kEditorTopInset = safeAreaTop + 16 + 44 + 8). NOTE: `.buttonStyle(.glass)`
// supplies its own intrinsic padding; verify the height still reads as 44pt
// on-device and pin `.frame(height: 44)` on the buttons if it drifts.
//
// Spec refs: FR-01, FR-02, FR-08, FR-23, NFR-01, NFR-02, NFR-04;
//            EC-01, EC-14; CG-1.
// Contract: §3.1 (morph identity seam — glassNamespace, glassID, menuToggleAnimation additive params).

import SwiftUI

// MARK: - TopPill

/// Top toolbar row hosting the Share control and the overflow `…` menu button.
///
/// **Input surface:**
/// - `text`: current buffer text — drives the Share disabled state (EC-01/FR-08).
/// - `isMenuPresented`: binding toggled by the overflow button tap (EC-14 write-source #1).
/// - `glassNamespace`: the `@Namespace.ID` passed from `ChromeOverlay` (§3.1 morph seam).
/// - `glassID`: the shared glass effect ID passed from `ChromeOverlay` (§3.1 morph seam).
/// - `menuToggleAnimation`: the resolved `Animation?` passed from `ChromeOverlay` (§3.1
///   animation seam). `nil` under Reduce Motion, an under-damped spring otherwise.
///
/// **Glass architecture:** see the header box. Two independent `.buttonStyle(.glass)`
/// buttons, fused visually by `.glassEffectUnion` into one even capsule. The outer
/// HStack carries `.glassEffectID` — the morph source/destination is the FULL capsule
/// frame, so the whole `[Share | ...]` blob deforms into the panel (Option C). The
/// overflow button itself does NOT carry `.glassEffectID`. ChromeOverlay performs the
/// whole-view TopPill↔MenuBubble swap; both buttons are always present here so
/// TopPill's size is deterministic.
///
/// **Disabled-share gate (EC-01/FR-08):**
/// The Share control is `.disabled(text.trimmed.isEmpty)` — a declarative gate,
/// not a try/catch, not a runtime guard on the `ShareLink` action.
///
/// **Accessibility:**
/// Every control has an `.accessibilityLabel` and `.accessibilityAddTraits(.isButton)`.
/// Touch targets ≥ 44×44 pt via `.frame(minWidth: 44, minHeight: 44)`; `Label(...)
/// .labelStyle(.iconOnly)` keeps the full frame hittable on iOS 26.
struct TopPill: View {

    // MARK: - Inputs

    /// The current buffer text. Drives `isShareDisabled` (EC-01/FR-08).
    let text: String

    /// Controls the menu bubble's presented state.
    /// EC-14 write-source #1: the overflow button toggles this via
    /// `withAnimation(menuToggleAnimation)`. Write-source #2 is the tap-catcher in ChromeOverlay.
    @Binding var isMenuPresented: Bool

    /// The morph namespace from `ChromeOverlay` (§3.1 morph identity seam).
    /// Used by `.glassEffectUnion` (visual fusion of both controls) and by
    /// `.glassEffectID` on the outer HStack (whole-capsule↔panel morph).
    let glassNamespace: Namespace.ID

    /// The shared glass effect ID from `ChromeOverlay` (§3.1 morph identity seam).
    /// Matches the ID used by `MenuBubble` so the whole capsule (the outer HStack)
    /// and the panel share one morph identity.
    let glassID: String

    /// The resolved animation for the overflow toggle (§3.1 animation seam).
    /// Passed from ChromeOverlay — `nil` under Reduce Motion, an under-damped spring
    /// otherwise. TopPill does NOT read `accessibilityReduceMotion` directly (C-06).
    let menuToggleAnimation: Animation?

    // MARK: - Private constants

    /// Shared union id that fuses Share + overflow glass shapes into one rendered
    /// capsule while keeping their gesture handlers independent (visual only).
    /// Does NOT affect morph geometry — `.glassEffectID` on the outer HStack
    /// uses the FULL capsule layout frame as the morph source/destination.
    private static let pillUnionID = "chrome.pill.union"

    // MARK: - Derived state

    /// `true` when the Share control must be disabled (EC-01/FR-08):
    /// the buffer is blank (trimmed empty) so there is nothing to share.
    private var isShareDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        // Apple-Notes-26: inter-icon spacing via ChromeMetrics token (non-gated, C-02).
        //
        // `.glassEffectID` is on the OUTER HStack so the morph source/destination
        // is the FULL capsule frame (both Share + overflow). Without this, the morph
        // source is only the overflow button's small frame and Share abruptly vanishes
        // instead of being absorbed into the liquid stretch (rc16 symptom).
        //
        // NO `.glassEffect(...)` on the HStack itself — that would create an interactive
        // glass surface on the HStack and route all taps to the first child (tap swallow).
        // Each child independently carries `.buttonStyle(.glass)` for its own gesture
        // handling. `.glassEffectUnion` on each child fuses their outlines visually.
        //
        // BOTH buttons are always rendered here. ChromeOverlay's whole-view swap removes
        // the entire TopPill when the menu opens — TopPill never needs to know.
        // Having both buttons present at all times keeps TopPill's intrinsic size
        // deterministic, which is what makes the morph-destination frame stable on close.
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            shareButton
            overflowButton
        }
        // Morph identity on the HStack = full capsule frame as morph source/destination.
        // `.glassEffectUnion` on the children fuses their glass outlines; this ID uses
        // the HStack layout frame (whole capsule width) for the morph geometry.
        .glassEffectID(glassID, in: glassNamespace)
    }

    // MARK: - Share control (FR-08, EC-01)

    /// `ShareLink` exporting the current buffer text, as its own glass element.
    ///
    /// Disabled (gated, not try/catch) when `text.trimmed.isEmpty` (EC-01).
    /// Does NOT carry `.glassEffectID` — morph identity is on the outer HStack in
    /// `body` (full capsule frame). Share is absorbed into the morph because the HStack
    /// frame spans both buttons; it does not need its own morph ID.
    /// Carries `.glassEffectUnion` to visually fuse with the overflow into one even
    /// capsule (union is visual only; gesture routing is unaffected).
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
        .buttonStyle(.glass)          // own glass element ⇒ own gesture handler
        // Visual fusion with overflow into one even capsule. Union does NOT affect
        // morph geometry or tap routing (NFR-01/02 — tap-routing fix context).
        .glassEffectUnion(id: Self.pillUnionID, namespace: glassNamespace)
        .accessibilityLabel(
            String(localized: "Share", comment: "Share button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
        )
    }

    // MARK: - Overflow button (FR-08, EC-14)

    /// The `…` overflow button — EC-14 write-source #1 for `isMenuPresented`.
    ///
    /// Carries `.glassEffectUnion` (visual fusion with Share into one capsule).
    /// Does NOT carry `.glassEffectID` — the morph identity is on the outer HStack
    /// in `body`, so the morph source/destination is the FULL capsule frame (both
    /// buttons as one blob). Putting `.glassEffectID` here would restrict the morph
    /// to this button's small frame only (rc16 symptom: Share abruptly vanishes).
    private var overflowButton: some View {
        Button {
            // EC-14 write-source #1: overflow toggle.
            // Animation seam (§3.1 C-05/C-06): uses the pre-resolved Animation? from
            // ChromeOverlay (nil under Reduce Motion; spring otherwise).
            withAnimation(menuToggleAnimation) {
                isMenuPresented.toggle()
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
        .buttonStyle(.glass)          // own glass element ⇒ own gesture handler
        // Visual fusion with Share into one even capsule (look only — gestures independent).
        // `.glassEffectID` is on the outer HStack, not here (see body comment).
        .glassEffectUnion(id: Self.pillUnionID, namespace: glassNamespace)
        .accessibilityLabel(
            String(localized: "Menu", comment: "Overflow menu button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(localized: "Open menu", comment: "Overflow menu button tooltip in the top pill (FR-23)")
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("TopPill — non-empty buffer") {
    @Namespace var ns
    return TopPill(
        text: "Hello, Foglietto!",
        isMenuPresented: .constant(false),
        glassNamespace: ns,
        glassID: "preview.morph",
        menuToggleAnimation: .spring(response: 0.5, dampingFraction: 0.6)
    )
    .padding()
}

#Preview("TopPill — empty buffer (Share disabled)") {
    @Namespace var ns
    return TopPill(
        text: "",
        isMenuPresented: .constant(false),
        glassNamespace: ns,
        glassID: "preview.morph",
        menuToggleAnimation: .spring(response: 0.5, dampingFraction: 0.6)
    )
    .padding()
}
#endif
