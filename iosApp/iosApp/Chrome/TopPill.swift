// Chrome/TopPill.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph)
//
// Top-right glass pill: Share control (disabled on empty buffer) + overflow
// menu button. Renders with native iOS 26 Liquid Glass via .glassEffect /
// glass button style; no hand-rolled blur/fill/shadow; no #available fallback.
//
// Morph seam (§3.1): receives `glassNamespace` and `glassID` from ChromeOverlay
// and attaches `.glassEffectID(glassID, in: glassNamespace)` to the pill capsule
// so the glass system can morph the capsule into the MenuBubble panel and back
// inside the shared GlassEffectContainer (iOS 26 native glass morph — C-03).
//
// Animation seam (§3.1 T-02): receives `menuToggleAnimation` from ChromeOverlay
// so the overflow toggle uses the SAME animation (and reduce-motion gate) as
// ChromeOverlay's tap-catcher dismiss. Reduce-motion authority stays in
// ChromeOverlay (C-06) — TopPill adds no @Environment(\.accessibilityReduceMotion).
//
// EC-14: the overflow button is write-source #1 for `isMenuPresented`. The
// outside-tap dismiss is handled by a full-screen tap-catcher in ChromeOverlay
// (write-source #2) — NOT by a .popover. This view owns NO dismiss logic beyond
// the toggle it exposes via $isMenuPresented.
//
// CANON GAP CG-1: native Liquid Glass system material supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color @90%
// color-mix fill + hairline ring. 0.68 / 90% survive as legibility intent
// only (NFR-03). Decision logged per spec §8 OQ-01.
//
// Apple-Notes-26 restyle (T-02): icon weight -> ChromeMetrics.iconScaleWeight
// (.medium); inter-icon spacing -> ChromeMetrics.capsuleControlSpacing.
// Rendered pill HEIGHT is invariant at 44pt (C-01 — BufferEditor hard-codes
// kEditorTopInset = safeAreaTop + 16 + 44 + 8; untouched by this restyle).
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
///   animation seam). `nil` under Reduce Motion, `.spring(response:0.5,dampingFraction:0.6)`
///   otherwise — reduce-motion authority stays in ChromeOverlay (C-06).
///
/// The pill capsule attaches `.glassEffectID(glassID, in: glassNamespace)` so the
/// iOS 26 glass system can morph it into the `MenuBubble` panel and back inside the
/// `GlassEffectContainer` owned by `ChromeOverlay` (C-03 / NFR-01/02).
///
/// **Disabled-share gate (EC-01/FR-08):**
/// The Share control is `.disabled(text.trimmed.isEmpty)` — a declarative gate,
/// not a try/catch, not a runtime guard on the `ShareLink` action.
///
/// **Native glass:**
/// `.glassEffect(.regular, in: .capsule)` is applied to the pill
/// container (the SINGLE glass shape); the morph ID is overlaid via
/// `.glassEffectID(glassID, in: glassNamespace)`. Both inner buttons use
/// `.buttonStyle(.plain)` so they do NOT add nested glass (no per-icon gray
/// background, Apple-Notes style, and a clean capsule↔panel morph).
/// Unconditional — min deployment target iOS 26.0, no availability guard needed (NFR-02).
///
/// **Apple-Notes-26 restyle (CANON GAP CG-1):**
/// Icon weight uses `ChromeMetrics.iconScaleWeight` (.medium); inter-icon spacing
/// uses `ChromeMetrics.capsuleControlSpacing`. Rendered pill height is invariant
/// at 44pt (C-01 — BufferEditor hard-codes 44 and is out of scope).
///
/// **Accessibility:**
/// Every control has an `.accessibilityLabel` and `.accessibilityAddTraits(.isButton)`.
/// Touch targets are enforced to ≥ 44×44 pt via `.frame(minWidth: 44, minHeight: 44)`.
///
/// **Dynamic Type:**
/// SF Symbols scale with the system font; the pill auto-sizes around its content.
struct TopPill: View {

    // MARK: - Inputs

    /// The current buffer text. Drives `isShareDisabled` (EC-01/FR-08).
    let text: String

    /// Controls the menu bubble's presented state.
    /// EC-14 write-source #1: the overflow button toggles this binding via
    /// `withAnimation(menuToggleAnimation)`. Write-source #2 is the tap-catcher in ChromeOverlay.
    @Binding var isMenuPresented: Bool

    /// The morph namespace from `ChromeOverlay` (§3.1 morph identity seam).
    /// Passed through to `.glassEffectID(_:in:)` on the pill capsule so the
    /// glass system can morph capsule↔panel inside the shared GlassEffectContainer.
    let glassNamespace: Namespace.ID

    /// The shared glass effect ID from `ChromeOverlay` (§3.1 morph identity seam).
    /// Matches the ID used by `MenuBubble` so the two surfaces share one glass identity.
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
        HStack(spacing: ChromeMetrics.capsuleControlSpacing) {
            shareButton
            overflowButton
        }
        // Native iOS 26 Liquid Glass capsule — no hand-rolled blur/fill/shadow (NFR-01/02).
        // The pill is a SINGLE glass shape: the inner Share/overflow controls use
        // `.buttonStyle(.plain)` (NOT `.glass`) so they do NOT create their own nested
        // glass surfaces. Nested glass inside the morphing shape makes iOS skip the
        // capsule↔panel geometry handoff (the rc7 "no morph" suspect). One bearer of
        // the glass shape ⇒ one clean morph into the MenuBubble panel.
        //
        // NOTE: `.interactive()` is deliberately NOT used here. Applied to this
        // container HStack it installs a touch-reactive gesture on the glass capsule
        // that wins gesture arbitration against the inner `.buttonStyle(.plain)`
        // controls — the pill squished on touch but the overflow button's
        // `isMenuPresented.toggle()` never fired, so the menu never opened. The
        // capsule↔panel morph spring (ChromeOverlay.menuToggleAnimation) carries the
        // liquid feel instead. Re-introducing `.interactive()` requires moving it onto
        // a single glass *button* shape, not this multi-button container.
        .glassEffect(.regular, in: .capsule)
        // Morph identity: shared with MenuBubble inside ChromeOverlay's GlassEffectContainer
        // so the glass system morphs this capsule into the menu panel and back (§3.1).
        .glassEffectID(glassID, in: glassNamespace)
    }

    // MARK: - Share control (FR-08, EC-01)

    /// `ShareLink` exporting the current buffer text.
    ///
    /// Disabled (gated, not try/catch) when `text.trimmed.isEmpty` (EC-01).
    /// SF Symbol `square.and.arrow.up` (FR-08).
    private var shareButton: some View {
        ShareLink(item: text) {
            // Apple-Notes-26: icon weight via ChromeMetrics token (non-gated, C-02).
            Image(systemName: "square.and.arrow.up")
                .fontWeight(ChromeMetrics.iconScaleWeight)
                .imageScale(.large)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG). Literal kept inline — m6_gate check 11 (C-02).
        .frame(minWidth: 44, minHeight: 44)
        // Gated disable — NOT try/catch (EC-01/FR-08).
        .disabled(isShareDisabled)
        // Plain style: the pill capsule (above) is the single glass surface. A
        // nested `.buttonStyle(.glass)` here would add a second glass shape inside
        // the morphing capsule and break the capsule↔panel morph.
        .buttonStyle(.plain)
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

    /// Always-enabled `…` overflow button that toggles the menu bubble.
    ///
    /// EC-14 write-source #1: toggles `isMenuPresented` (the binding from ChromeOverlay).
    /// Outside-tap dismiss is handled by ChromeOverlay's tap-catcher (write-source #2).
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
            Image(systemName: "ellipsis")
                .fontWeight(ChromeMetrics.iconScaleWeight)
                .imageScale(.large)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG). Literal kept inline — m6_gate check 11 (C-02).
        .frame(minWidth: 44, minHeight: 44)
        // Always enabled (FR-08 — overflow is never gated).
        // Plain style: see shareButton — the pill capsule is the single glass
        // surface, so the inner controls must NOT add their own nested glass.
        .buttonStyle(.plain)
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
