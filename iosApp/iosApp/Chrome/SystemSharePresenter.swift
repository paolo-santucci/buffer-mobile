// Chrome/SystemSharePresenter.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Presents the SYSTEM share sheet as a floating, pill-anchored Liquid Glass
// panel: popover-style presentation pinned to the pill anchor view (adaptive
// `.none` so it does NOT adapt into a bottom sheet on iPhone) — the panel's
// top-right corner lands where the pill's top-right corner is, exactly like
// the Apple Notes share panel the user requires.
//
// ShareLink cannot host this: it exposes no hook into the system share
// presentation, so the pill's Share tap routes through this presenter instead.
// The pill's own glass is deformed by ChromeOverlay (its morph identity
// shrinks to nothing) while the system presents the anchored panel — the
// closed loop the user requires:
//   open:  pill melts ⇢ anchored panel hangs from the pill's top edge
//   close: panel dismisses ⇢ pill glass grows back from the same frame
//
// ShareAnchorBox / ShareSourceAnchor: a reference box bridging a
// UIViewRepresentable's UIView to the presenter. The anchor mirrors the
// closed pill's slot geometry (ChromeMetrics.closedPillWidth × pillHeight at
// the pill's top/trailing paddings) and is mounted in EVERY chrome state so
// its window frame is always resolvable — the melt unmounts the pill, never
// the anchor.
//
// No glass symbols here: the presenter is presentation plumbing, not chrome
// glass (the glass stays owned by ChromeOverlay/MenuBubble — m4 check 2).
// All UIKit work happens on the main actor (annotation below; callers are
// SwiftUI body/MainActor code).
//
// Spec refs (FR-20 share morph, user-directed rc28+): anchored popover panel.
// Contract: SystemSharePresenter.present(text:from:onFinish:) is the ONLY
// entry; onFinish fires exactly once, on presentation failure (box detached,
// presenting chain busy, no presenting controller) or when the share panel
// completes/dismisses.

import UIKit
import SwiftUI
import Observation

// MARK: - ShareAnchorBox

/// Reference box bridging the `ShareSourceAnchor` UIView to the presenter
/// (weak — the UIViewRepresentable owns the view's lifetime).
final class ShareAnchorBox {
    weak var view: UIView?
}

// MARK: - ShareSourceAnchor

/// Inert, never-interactive UIView that mirrors the closed pill's exact slot,
/// giving the zoom transition the pill's geometry. Invisible: no content, no
/// layout, no gesture (isUserInteractionEnabled off — this file hosts NO
/// chrome glass and NO chrome controls).
struct ShareSourceAnchor: UIViewRepresentable {
    let box: ShareAnchorBox

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        box.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - SystemSharePresenter

/// Delegate pinning the share activity view to its floating popover on iPhone
/// (adaptive `.none`): the panel stays anchored at the pill instead of adapting
/// into a bottom sheet. A singleton because presentation controllers retain
/// their delegates weakly.
private final class SharePopoverAdaptivity: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = SharePopoverAdaptivity()

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}

/// Presents the system share sheet zoom-morphing out of the chrome pill.
///
/// - Parameters:
///   - text: The buffer text to share (EC-01: callers gate Presentation on
///     non-empty text — the pill's Share control is `.disabled` on empty).
///   - anchor: The `ShareAnchorBox` whose view carries the pill's frame.
///   - onFinish: Fired exactly once — immediately when presentation cannot
///     start (detached anchor/no presenting controller), otherwise when the
///     activity sheet completes or is dismissed. Closing the melt state must
///     ride this so the pill glass grows back from the zoomed-out frame.
@MainActor
enum SystemSharePresenter {

    /// Presents the system share sheet anchored AT the pill (popover style,
    /// floating Liquid Glass panel whose top edge lands where the pill's top
    /// edge is) and reports completion through `onFinish`.
    ///
    /// The adaptive `.none` override is what keeps the panel floating on
    /// iPhone: without it the system adapts the popover into an edge sheet —
    /// the bottom landing the user rejected.
    static func present(
        text: String,
        from anchor: ShareAnchorBox,
        onFinish: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let source = anchor.view,
              let presenting = topPresentingController(for: source),
              // Fast-fail while a presentation is already in progress on that
              // chain (UIKit would silently skip the second present() and the
              // melt would never learn the sheet failed to appear).
              presenting.presentedViewController == nil else {
            onFinish()
            return
        }

        let controller = UIActivityViewController(
            activityItems: [text],
            applicationActivities: []
        )
        controller.modalPresentationStyle = .popover
        guard let popover = controller.popoverPresentationController else {
            onFinish()
            return
        }
        // The arrow rides the pill anchor's TOP edge, so the panel hangs from
        // where the pill's top was: the panel's top-right corner sits at the
        // pill's top-right corner (user-required landing).
        popover.sourceView = source
        popover.sourceRect = CGRect(
            x: source.bounds.midX,
            y: 0,
            width: 1,
            height: 1
        )
        popover.permittedArrowDirections = .up
        popover.delegate = SharePopoverAdaptivity.shared
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Documented main-thread completion; the Task hop keeps the
            // MainActor call statically legal under Swift 6 concurrency rules.
            Task { @MainActor in
                onFinish()
            }
        }
        presenting.present(controller, animated: true)
    }

    /// The view controller to present from: the key window scene's root,
    /// climbed to the topmost presented child (nil-tolerant — no scene/no
    /// window/no root reports failure and `present` closes the melt state).
    private static func topPresentingController(for view: UIView) -> UIViewController? {
        guard let scene = view.window?.windowScene else { return nil }
        let keyRoot = scene.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene.windows.compactMap(\.rootViewController).first
        var top = keyRoot
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
