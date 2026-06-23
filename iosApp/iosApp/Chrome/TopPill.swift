// Chrome/TopPill.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph)
//
// Top toolbar row: Share control (disabled on empty buffer) + overflow `…` button.
// Renders with native iOS 26 Liquid Glass; no hand-rolled blur/fill/shadow;
// no #available fallback (min target iOS 26.0).
//
// ┌─ HOW THE CAPSULE + MORPH ACTUALLY WORK (read before changing) ────────────┐
// │ ONE CAPSULE, TWO BUTTONS — the right way:                                   │
// │  • Share and overflow are TWO independent glass buttons (`.buttonStyle(     │
// │    .glass)`), each with its own gesture handler (so each is hit-testable).  │
// │  • They read as a SINGLE capsule because the GlassEffectContainer in        │
// │    ChromeOverlay MERGES adjacent glass via its `spacing` (metaball). The    │
// │    fusion is the container's job — NOT a wrapping `.glassEffect(.capsule)`  │
// │    (that swallows the 2nd button's tap) and NOT `.glassEffectUnion` (that   │
// │    pins geometry and breaks the morph). Apple Notes / Claude iOS do exactly │
// │    this: separate glass buttons, merged by the container.                   │
// │                                                                            │
// │ ONLY THE OVERFLOW MORPHS:                                                    │
// │  • The overflow button carries `.glassEffectID(glassID, ...)` and is shown  │
// │    ONLY while the menu is closed. When the menu opens it is removed and the │
// │    MenuBubble (same id, rendered by ChromeOverlay just BELOW this row)      │
// │    appears — the glass system morphs the overflow capsule DOWN into the     │
// │    panel (the liquid teardrop). Mutually-exclusive id ⇒ clean matched-      │
// │    geometry morph.                                                          │
// │  • Share is PERSISTENT — it never morphs and never gets torn down, so its   │
// │    frame stays stable. (The earlier "capsule lands mid-screen on close" bug │
// │    was caused by swapping the WHOLE pill, which relaid the morph source's   │
// │    frame. Keeping Share persistent + swapping only overflow↔panel fixes it.)│
// │                                                                            │
// │ HISTORY of what NOT to re-introduce:                                        │
// │  • NO `.glassEffect(.regular, in: .capsule)` on the HStack — tap swallow.    │
// │  • NO `.glassEffectUnion(...)` — broke the morph (expansion-not-teardrop +  │
// │    mid-screen landing).                                                     │
// └──────────────────────────────────────────────────────────────────────────┘
//
// Morph seam (§3.1): receives `glassNamespace` and `glassID` from ChromeOverlay.
// The overflow button attaches `.glassEffectID(glassID, in: glassNamespace)`; the
// MenuBubble (in ChromeOverlay) attaches the same id. Both live in the one
// GlassEffectContainer ChromeOverlay owns, so the morph crosses the view boundary.
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
///   Also gates the overflow's visibility: the overflow is shown ONLY while closed,
///   so it can morph into the MenuBubble (same id) that ChromeOverlay renders below.
/// - `glassNamespace`: the `@Namespace.ID` passed from `ChromeOverlay` (§3.1 morph seam).
/// - `glassID`: the shared glass effect ID passed from `ChromeOverlay` (§3.1 morph seam).
/// - `menuToggleAnimation`: the resolved `Animation?` passed from `ChromeOverlay` (§3.1
///   animation seam). `nil` under Reduce Motion, an under-damped spring otherwise.
///
/// **Glass architecture:** see the header box. Two independent `.buttonStyle(.glass)`
/// controls fused into one capsule by ChromeOverlay's `GlassEffectContainer` spacing.
/// ONLY the overflow carries `.glassEffectID` and morphs; Share is persistent.
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

    /// Controls the menu bubble's presented state AND the overflow's visibility.
    /// EC-14 write-source #1: the overflow button toggles this via
    /// `withAnimation(menuToggleAnimation)`. Write-source #2 is the tap-catcher in ChromeOverlay.
    @Binding var isMenuPresented: Bool

    /// The morph namespace from `ChromeOverlay` (§3.1 morph identity seam).
    let glassNamespace: Namespace.ID

    /// The shared glass effect ID from `ChromeOverlay` (§3.1 morph identity seam).
    /// Matches the ID used by `MenuBubble` so the overflow control and the panel
    /// share one morph identity.
    let glassID: String

    /// The resolved animation for the overflow toggle (§3.1 animation seam).
    /// Passed from ChromeOverlay — `nil` under Reduce Motion, an under-damped spring
    /// otherwise. TopPill does NOT read `accessibilityReduceMotion` directly (C-06).
    let menuToggleAnimation: Animation?

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
        // NO `.glassEffect(...)`, NO `.glassEffectID(...)`, NO `.glassEffectUnion(...)`
        // on this HStack — the container fuses the two buttons; only the overflow
        // child carries the morph id. Share is persistent; the overflow is shown
        // only while the menu is closed so it can morph into the panel below.
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            shareButton
            if !isMenuPresented {
                overflowButton
            }
        }
    }

    // MARK: - Share control (FR-08, EC-01)

    /// `ShareLink` exporting the current buffer text, as its own persistent glass element.
    ///
    /// Disabled (gated, not try/catch) when `text.trimmed.isEmpty` (EC-01).
    /// Carries neither `.glassEffectID` (Share never morphs) nor `.glassEffectUnion`.
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
        .accessibilityLabel(
            String(localized: "Share", comment: "Share button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
        )
    }

    // MARK: - Overflow button (FR-08, EC-14)

    /// The `…` overflow button — the SOLE element that morphs into MenuBubble.
    /// Shown only while the menu is closed (mutually-exclusive id with the panel).
    private var overflowButton: some View {
        Button {
            // EC-14 write-source #1.
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
        .buttonStyle(.glass)                          // own glass element ⇒ own gesture handler
        // Morph identity: shared with MenuBubble inside ChromeOverlay's GlassEffectContainer.
        // The ONLY glass-grouping modifier here — no union.
        .glassEffectID(glassID, in: glassNamespace)
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
