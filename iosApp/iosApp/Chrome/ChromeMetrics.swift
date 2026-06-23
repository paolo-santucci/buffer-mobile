// Chrome/ChromeMetrics.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Non-gated Apple-Notes restyle style tokens. Centralizes ONLY values the
// gate scripts do NOT grep (C-02). The gated literals (minWidth: 44 /
// minHeight: 44 in TopPill, lineFragmentPadding = 0 in BufferEditor) stay
// INLINE at their call sites and are NOT referenced here.
//
// CANON GAP CG-1: native Liquid Glass system material on the chrome layer
// supersedes ui-design-bible §"Auto-hiding overlay chrome" fill. These tokens
// target the Apple Notes (iOS 26) visual language for the non-glass geometry
// (panel width, row padding, icon weight, toolbar spacing).
//
// Spec refs: qp-20260622 §3.1; C-02, C-03; CG-1.
import SwiftUI

enum ChromeMetrics {
    // Overflow menu panel (MenuBubble)
    static let menuPanelWidth: CGFloat = 280          // existing ~280pt, now named
    static let menuRowVerticalPadding: CGFloat = 11
    static let menuRowHorizontalPadding: CGFloat = 16
    static let menuRowSpacing: CGFloat = 2
    static let menuPanelCornerRadius: CGFloat = 20

    // Pill + toolbar glass capsules (visual only — NOT the 44pt tap target)
    static let capsuleControlSpacing: CGFloat = 2      // inter-icon spacing inside a capsule
    static let iconScaleWeight: Font.Weight = .regular  // SF Symbol weight (Apple-Notes look — regular, not bold)

    // Bottom toolbar
    static let toolbarItemSpacing: CGFloat = 4
    static let toolbarHorizontalPadding: CGFloat = 8
}
