// Chrome/TopPill.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph)
//
// Top-right glass pill: Share control (disabled on empty buffer) + overflow
// menu button. Renders with native iOS 26 Liquid Glass; no hand-rolled
// blur/fill/shadow; no #available fallback (min target iOS 26.0).
//
// ┌─ TAP-ROUTING FIX (supersedes the prior "single capsule" design) ─────────┐
// │ EARLIER BUG: the pill was ONE glass surface — `.glassEffect(.regular,    │
// │ in: .capsule)` on the HStack — with the Share + overflow buttons nested  │
// │ inside as `.buttonStyle(.plain)`. On iOS 26 this is broken: the system   │
// │ MERGES adjacent/contained glass into a single interactive group and      │
// │ routes the group's taps to the FIRST child in the hierarchy. Share was   │
// │ first, so Share worked and the overflow `…` tap was silently swallowed   │
// │ (no feedback, nothing fired). Confirmed on-device: Share OK, overflow    │
// │ dead; a bare glass-free Button in the overflow slot opened the menu.     │
// │                                                                          │
// │ FIX: each control is now its OWN glass element via `.buttonStyle(.glass)`│
// │ so each keeps its own gesture handler and is independently hit-testable. │
// │ They are visually fused back into one capsule with `.glassEffectUnion`   │
// │ (same id + namespace on BOTH) — union merges the LOOK, not the gestures. │
// │ The morph identity `.glassEffectID(glassID, ...)` moves onto the OVERFLOW│
// │ button only: it is the element that morphs into MenuBubble. Share does   │
// │ not morph (it cross-fades with the chrome layer).                        │
// └──────────────────────────────────────────────────────────────────────────┘
//
// Morph seam (§3.1): receives `glassNamespace` and `glassID` from ChromeOverlay.
// The overflow button attaches `.glassEffectID(glassID, in: glassNamespace)` so
// the glass system can morph the overflow capsule into the MenuBubble panel and
// back inside the shared GlassEffectContainer owned by ChromeOverlay (C-03).
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
// (.medium); inter-icon spacing -> ChromeMetrics.capsuleControlSpacing.
// Rendered pill HEIGHT target stays ~44pt (C-01 — BufferEditor hard-codes
// kEditorTopInset = safeAreaTop + 16 + 44 + 8). NOTE: `.buttonStyle(.glass)`
// supplies its own intrinsic padding; verify the rendered height still reads
// as 44pt on-device and pin `.frame(height: 44)` on the buttons if it drifts.
//
// Spec refs: FR-01, FR-02, FR-08, FR-23, NFR-01, NFR-02, NFR-04;
//            EC-01, EC-14; CG-1.
// Contract: §3.1 (morph identity seam — glassNamespace, glassID, menuToggleAnimation additive params).

import SwiftUI

// MARK: - TopPill

/// Top-right glass pill hosting the Share control and the overflow `…` menu button.
///
/// **Input surface:**
/// - `text`: current buffer text — drives the Share disabled state (EC-01/FR-08).
/// - `isMenuPresented`: binding toggled by the overflow button tap (EC-14 write-source #1).
/// - `glassNamespace`: the `@Namespace.ID` passed from `ChromeOverlay` (§3.1 morph seam).
/// - `glassID`: the shared glass effect ID passed from `ChromeOverlay` (§3.1 morph seam).
/// - `menuToggleAnimation`: the resolved `Animation?` passed from `ChromeOverlay` (§3.1
///   animation seam). `nil` under Reduce Motion, an under-damped spring otherwise —
///   reduce-motion authority stays in ChromeOverlay (C-06).
///
/// **Glass architecture (tap-routing fix):**
/// Each control is its OWN glass element (`.buttonStyle(.glass)`), so each keeps a
/// distinct gesture handler and is independently hit-testable. The two are visually
/// fused into a single capsule with `.glassEffectUnion(id:namespace:)` applied to
/// BOTH — union merges the rendered shape, not the gesture handling. The overflow
/// button additionally carries `.glassEffectID(glassID, in: glassNamespace)` so it
/// (and only it) morphs into the `MenuBubble` panel inside the `GlassEffectContainer`
/// owned by `ChromeOverlay` (C-03 / NFR-01/02).
///
/// Do NOT wrap the HStack in a single `.glassEffect(...)` capsule: that merges the
/// two controls into one interactive glass surface and iOS 26 routes the merged
/// group's taps to the first child, silently swallowing the overflow tap.
///
/// **Disabled-share gate (EC-01/FR-08):**
/// The Share control is `.disabled(text.trimmed.isEmpty)` — a declarative gate,
/// not a try/catch, not a runtime guard on the `ShareLink` action.
///
/// **Accessibility:**
/// Every control has an `.accessibilityLabel` and `.accessibilityAddTraits(.isButton)`.
/// Touch targets are enforced to ≥ 44×44 pt via `.frame(minWidth: 44, minHeight: 44)`,
/// and `Label(...).labelStyle(.iconOnly)` keeps the full frame hittable on iOS 26.
///
/// **Dynamic Type:**
/// SF Symbols scale with the system font; each glass button auto-sizes around its content.
struct TopPill: View {

    // MARK: - Inputs

    /// The current buffer text. Drives `isShareDisabled` (EC-01/FR-08).
    let text: String

    /// Controls the menu bubble's presented state.
    /// EC-14 write-source #1: the overflow button toggles this binding via
    /// `withAnimation(menuToggleAnimation)`. Write-source #2 is the tap-catcher in ChromeOverlay.
    @Binding var isMenuPresented: Bool

    /// The morph namespace from `ChromeOverlay` (§3.1 morph identity seam).
    /// Used by `.glassEffectUnion` (visual fusion of the two controls) and by
    /// `.glassEffectID` on the overflow button (capsule↔panel morph).
    let glassNamespace: Namespace.ID

    /// The shared glass effect ID from `ChromeOverlay` (§3.1 morph identity seam).
    /// Matches the ID used by `MenuBubble` so the overflow control and the panel
    /// share one morph identity.
    let glassID: String

    /// The resolved animation for the overflow toggle (§3.1 animation seam).
    /// Passed from ChromeOverlay — `nil` under Reduce Motion, an under-damped spring
    /// otherwise. TopPill does NOT read `accessibilityReduceMotion` directly (C-06).
    let menuToggleAnimation: Animation?

    // MARK: - Private constants

    /// Shared union id that fuses the Share + overflow glass shapes into one
    /// rendered capsule while keeping their gesture handlers independent.
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
        // NO `.glassEffect(...)` and NO `.glassEffectID(...)` on this HStack — both
        // were the tap-routing bug. Each child is its own glass element below; the
        // `.glassEffectUnion` on each child fuses them into one rendered capsule.
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            shareButton
            overflowButton
        }
    }

    // MARK: - Share control (FR-08, EC-01)

    /// `ShareLink` exporting the current buffer text, as its own glass element.
    ///
    /// Disabled (gated, not try/catch) when `text.trimmed.isEmpty` (EC-01).
    /// SF Symbol `square.and.arrow.up` via a Label (iOS 26 hit-target — see header).
    /// Does NOT carry `.glassEffectID` — Share does not morph; it cross-fades with
    /// the chrome layer. It DOES carry `.glassEffectUnion` so it visually fuses with
    /// the overflow button into a single capsule.
    private var shareButton: some View {
        ShareLink(item: text) {
            // Apple-Notes-26: icon weight via ChromeMetrics token (non-gated, C-02).
            Label(
                String(localized: "Share", comment: "Share button label in the top pill"),
                systemImage: "square.and.arrow.up"
            )
            .labelStyle(.iconOnly)
            .fontWeight(ChromeMetrics.iconScaleWeight)
            .imageScale(.large)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG). Literal kept inline — m6_gate check 11 (C-02).
        .frame(minWidth: 44, minHeight: 44)
        // Gated disable — NOT try/catch (EC-01/FR-08).
        .disabled(isShareDisabled)
        // Own glass element ⇒ own gesture handler (tap-routing fix).
        .buttonStyle(.glass)
        // Visual fusion with the overflow button into one capsule (look only).
        .glassEffectUnion(id: Self.pillUnionID, namespace: glassNamespace)
        // Accessibility (NFR-04).
        .accessibilityLabel(
            String(localized: "Share", comment: "Share button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip shown on long-press / pointer hover (FR-23).
        .help(
            String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
        )
    }

    // MARK: - Overflow button (FR-08, EC-14)

    /// Always-enabled `…` overflow button that toggles the menu bubble, as its own
    /// glass element.
    ///
    /// EC-14 write-source #1: toggles `isMenuPresented` (the binding from ChromeOverlay).
    /// Carries `.glassEffectID(glassID, ...)` — it is the element that morphs into the
    /// MenuBubble panel — AND `.glassEffectUnion(...)` so at rest it reads as one capsule
    /// with the Share button.
    private var overflowButton: some View {
        Button {
            // EC-14 write-source #1: overflow toggle.
            // Animation seam (§3.1 C-05/C-06): uses the pre-resolved Animation? from
            // ChromeOverlay (nil under Reduce Motion; spring otherwise) — identical to
            // the tap-catcher write in ChromeOverlay. No second reduce-motion reader here.
            withAnimation(menuToggleAnimation) {
                isMenuPresented.toggle()
            }
        } label: {
            // Apple-Notes-26: icon weight via ChromeMetrics token (non-gated, C-02).
            Label(
                String(localized: "Menu", comment: "Overflow menu button label in the top pill"),
                systemImage: "ellipsis"
            )
            .labelStyle(.iconOnly)
            .fontWeight(ChromeMetrics.iconScaleWeight)
            .imageScale(.large)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG). Literal kept inline — m6_gate check 11 (C-02).
        .frame(minWidth: 44, minHeight: 44)
        // Own glass element ⇒ own gesture handler (tap-routing fix — this is the
        // control that was previously dead because the shared capsule swallowed its tap).
        .buttonStyle(.glass)
        // Visual fusion with the Share button into one capsule (look only).
        .glassEffectUnion(id: Self.pillUnionID, namespace: glassNamespace)
        // Morph identity: shared with MenuBubble inside ChromeOverlay's GlassEffectContainer
        // so the glass system morphs THIS control into the menu panel and back (§3.1).
        .glassEffectID(glassID, in: glassNamespace)
        // Accessibility (NFR-04).
        .accessibilityLabel(
            String(localized: "Menu", comment: "Overflow menu button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23).
        .help(
            String(localized: "Open menu", comment: "Overflow menu button tooltip in the top pill (FR-23)")
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("TopPill — non-empty buffer") {
    // Previews use a dummy namespace; morph behaviour requires a live GlassEffectContainer.
    // menuToggleAnimation: pass the full spring as previews run without Reduce Motion gating.
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
