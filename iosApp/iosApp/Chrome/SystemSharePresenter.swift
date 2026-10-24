import UIKit

@MainActor
enum SystemSharePresenter {
    static func present(text: String, from source: UIBarButtonItem, in presenting: UIViewController) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              presenting.view.window != nil,
              presenting.presentedViewController == nil else { return }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.modalPresentationStyle = .popover
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceItem = source
        popover.delegate = SharePopoverAdaptivity.shared
        presenting.present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

private final class SharePopoverAdaptivity: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = SharePopoverAdaptivity()

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}
