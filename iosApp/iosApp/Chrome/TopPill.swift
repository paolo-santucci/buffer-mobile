// Chrome/TopPill.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome
//
// Top-right glass pill: Share control (disabled on empty buffer) + overflow
// menu button. Renders with native iOS 26 Liquid Glass via .glassEffect /
// glass button style; no hand-rolled blur/fill/shadow; no #available fallback.
//
// CANON GAP CG-1: native Liquid Glass system material supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color @90%
// color-mix fill + hairline ring. 0.68 / 90% survive as legibility intent
// only (NFR-03). Decision logged per spec §8 OQ-01.
//
// Visibility wiring (crossfade with ChromeVisibility.isVisible) is TASK-11.
// This file exposes the control surface and its required inputs.
//
// Spec refs: FR-01, FR-02, FR-08, FR-23, NFR-01, NFR-02, NFR-04;
//            EC-01; CG-1.
// Contract: §4.1, §5.1.c.

import SwiftUI

// MARK: - TopPill

/// Top-right glass pill hosting the Share control and the overflow `…` menu button.
///
/// **Input surface (for TASK-11 wiring):**
/// - `text`: current buffer text — drives the Share disabled state (EC-01/FR-08).
/// - `isMenuPresented`: binding toggled by the overflow button tap; the bubble view
///   (TASK-10) is anchored to this binding by TASK-11.
///
/// **Disabled-share gate (EC-01/FR-08):**
/// The Share control is `.disabled(text.trimmed.isEmpty)` — a declarative gate,
/// not a try/catch, not a runtime guard on the `ShareLink` action.
///
/// **Native glass:**
/// `.glassEffect(in: .capsule)` is applied to the pill container.
/// Both buttons use `.buttonStyle(.glass)` (iOS 26 native glass button style).
/// Unconditional — min deployment target iOS 26.0, no availability guard needed (NFR-02).
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
    /// TASK-11 wires a `@State var isMenuPresented: Bool` from `ChromeOverlay`
    /// and passes it here as a binding so the overflow button can toggle it.
    @Binding var isMenuPresented: Bool

    // MARK: - Derived state

    /// `true` when the Share control must be disabled (EC-01/FR-08):
    /// the buffer is blank (trimmed empty) so there is nothing to share.
    private var isShareDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            shareButton
            overflowButton
        }
        // Native iOS 26 Liquid Glass — no hand-rolled blur/fill/shadow (NFR-01/02).
        .glassEffect(in: .capsule)
    }

    // MARK: - Share control (FR-08, EC-01)

    /// `ShareLink` exporting the current buffer text.
    ///
    /// Disabled (gated, not try/catch) when `text.trimmed.isEmpty` (EC-01).
    /// SF Symbol `square.and.arrow.up` (FR-08).
    private var shareButton: some View {
        ShareLink(item: text) {
            Image(systemName: "square.and.arrow.up")
                .imageScale(.medium)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        // Gated disable — NOT try/catch (EC-01/FR-08).
        .disabled(isShareDisabled)
        // Native glass button style (iOS 26).
        .buttonStyle(.glass)
        // Accessibility (NFR-04).
        .accessibilityLabel(
            String(localized: "Share", comment: "Share button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip shown on long-press / pointer hover (FR-23, EN literal — localized in M6).
        .help(
            String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
        )
    }

    // MARK: - Overflow button (FR-08)

    /// Always-enabled `…` overflow button that toggles the menu bubble.
    ///
    /// The bubble view itself is TASK-10. TASK-11 wires `isMenuPresented` to
    /// a `popover` / `.sheet` modifier on the bubble anchor.
    private var overflowButton: some View {
        Button {
            isMenuPresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .imageScale(.medium)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        // Always enabled (FR-08 — overflow is never gated).
        // Native glass button style (iOS 26).
        .buttonStyle(.glass)
        // Accessibility (NFR-04).
        .accessibilityLabel(
            String(localized: "Menu", comment: "Overflow menu button accessibility label in the top pill")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23, EN literal — localized in M6).
        .help(
            String(localized: "Open menu", comment: "Overflow menu button tooltip in the top pill (FR-23)")
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("TopPill — non-empty buffer") {
    TopPill(text: "Hello, Foglietto!", isMenuPresented: .constant(false))
        .padding()
}

#Preview("TopPill — empty buffer (Share disabled)") {
    TopPill(text: "", isMenuPresented: .constant(false))
        .padding()
}
#endif
