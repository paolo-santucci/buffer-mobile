// Chrome/ChromeMetrics.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Non-gated Apple-Notes restyle style tokens. Centralizes ONLY values the
// gate scripts do NOT grep (C-02). The gated literals (the 44pt tap-target
// frames on the chrome controls, the textContainerInset assignment and
// lineFragmentPadding = 0 in BufferEditor) stay INLINE at their call sites and
// are NOT referenced here.
//
// Lockstep contract (FR-10): the chrome layer and the editor's first-line inset
// consume this geometry by compile-time reference — the rendered capsule height
// must equal pillHeight, and the first text line sits at
// pillTopGap + pillHeight + pillBottomGap below the safe area.
//
// CANON GAP CG-1: native Liquid Glass system material on the chrome layer
// supersedes ui-design-bible §"Auto-hiding overlay chrome" fill. These tokens
// target the Apple Notes (iOS 26) visual language for the non-glass geometry
// (pill geometry, panel width/radius, row padding, icon weight, toolbar spacing)
// and for chrome motion.
//
// Spec refs: §5.2; FR-10, FR-12, FR-14n, FR-21; NFR-01, NFR-03, NFR-04; C-02, C-03; CG-1.
import SwiftUI

enum ChromeMetrics {
    // Pill geometry (the editor inset math and the chrome placement share these)
    static let pillHeight: CGFloat = 44
    static let pillTopGap: CGFloat = 16
    static let pillBottomGap: CGFloat = 8
    static let chromeHorizontalInset: CGFloat = 16
    static let metaballSpacing: CGFloat = 35

    // Overflow menu panel (MenuBubble)
    static let menuPanelWidth: CGFloat = 280          // existing ~280pt, now named
    static let recoveryScrollHeight: CGFloat = 320
    static let menuRowVerticalPadding: CGFloat = 11
    static let menuRowHorizontalPadding: CGFloat = 16
    static let menuRowSpacing: CGFloat = 2
    static let menuPanelCornerRadius: CGFloat = 30

    // Chrome motion (gated to nil at the consuming seam under Reduce Motion)
    static let menuOpenSpring: Animation = .bouncy(duration: 0.45, extraBounce: 0.15)
    static let menuCloseSpring: Animation = .bouncy(duration: 0.40, extraBounce: 0.10)
    static let submenuExpandAnimation: Animation = .bouncy(duration: 0.35, extraBounce: 0.10)

    // Pill + toolbar glass capsules (visual only — NOT the 44pt tap target)
    static let capsuleControlSpacing: CGFloat = 2      // inter-icon spacing inside a capsule
    static let iconScaleWeight: Font.Weight = .regular  // SF Symbol weight (Apple-Notes look — regular, not bold)

    // Bottom toolbar
    static let toolbarItemSpacing: CGFloat = 4
    static let capsuleHorizontalPadding: CGFloat = 8
    static let toolbarFloatingPadding: CGFloat = 12    // toolbar hosting paddings (ContentView)
}
