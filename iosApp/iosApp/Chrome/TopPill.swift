// Chrome/TopPill.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph)
//
// NOTE (rc18): ChromeOverlay now inlines the Share button and overflow button
// directly within its GlassEffectContainer. TopPill is no longer instantiated
// by ChromeOverlay. This file is retained in the Xcode project and can serve
// as a standalone preview of the share button. It is NOT part of the live morph
// architecture — see ChromeOverlay.swift for the authoritative rc18 design.
//
// ┌─ rc18 MORPH ARCHITECTURE SUMMARY (for context — live code is ChromeOverlay) ┐
// │ Share button: always mounted in ChromeOverlay, no glassEffectID.              │
// │ Overflow button: single glass capsule with .glassEffect(.regular.interactive) │
// │   + .glassEffectID → morphs into MenuBubble (panel grows DOWN).               │
// │ MenuBubble: mounted below the toolbar row when open, .glassEffectID shared.   │
// │ All three live in ONE GlassEffectContainer(spacing: 35) in ChromeOverlay.     │
// └──────────────────────────────────────────────────────────────────────────────┘
//
// Spec refs: FR-01, FR-02, FR-08, FR-23, NFR-01, NFR-02, NFR-04; EC-01, EC-14; CG-1.

import SwiftUI

// MARK: - TopPill (reference only — not instantiated in production as of rc18)

/// Standalone share-button view. As of rc18 this struct is NOT used in the
/// live app — `ChromeOverlay` inlines the share button directly. Retained for
/// preview tooling and as a reference for the share button's glass treatment.
struct TopPill: View {

    // MARK: - Inputs

    let text: String
    @Binding var isMenuPresented: Bool
    let glassNamespace: Namespace.ID
    let glassID: String
    let menuToggleAnimation: Animation?

    // MARK: - Derived state

    private var isShareDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body (reference implementation — not in live chrome)

    var body: some View {
        ShareLink(item: text) {
            Label(
                String(localized: "Share", comment: "Share button label (reference)"),
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
            String(localized: "Share", comment: "Share button accessibility label (reference)")
        )
        .accessibilityAddTraits(.isButton)
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
