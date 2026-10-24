import SwiftUI
import UIKit
import Observation

@Observable
final class CoordinatorBox {
    weak var coordinator: BufferEditor.Coordinator?
    var canUndo = false
}

struct ChromeOverlay<Content: View>: UIViewControllerRepresentable {
    let text: String
    let menuVM: MenuViewModel
    let canUndo: Bool
    let onUndo: () -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> ChromeBarCoordinator {
        ChromeBarCoordinator()
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let editor = UIHostingController(rootView: content())
        let navigation = UINavigationController(rootViewController: editor)
        navigation.navigationBar.prefersLargeTitles = false
        context.coordinator.attach(to: navigation)
        context.coordinator.update(text: text, menuVM: menuVM, canUndo: canUndo, onUndo: onUndo)
        return navigation
    }

    func updateUIViewController(_ navigation: UINavigationController, context: Context) {
        (navigation.viewControllers.first as? UIHostingController<Content>)?.rootView = content()
        context.coordinator.update(text: text, menuVM: menuVM, canUndo: canUndo, onUndo: onUndo)
    }

    static func dismantleUIViewController(_ navigation: UINavigationController, coordinator: ChromeBarCoordinator) {
        navigation.dismiss(animated: false)
    }
}

@MainActor
final class ChromeBarCoordinator: NSObject, UIPopoverPresentationControllerDelegate {
    private weak var navigation: UINavigationController?
    private weak var menuController: UIViewController?
    private var text = ""
    private var menuVM: MenuViewModel?
    private var onUndo: () -> Void = {}
    private var showsUndo = false

    private lazy var shareItem = UIBarButtonItem(
        title: String(localized: "Share"),
        image: UIImage(systemName: "square.and.arrow.up"),
        primaryAction: UIAction { [weak self] _ in self?.presentShare() }
    )

    private lazy var menuItem = UIBarButtonItem(
        title: String(localized: "Menu"),
        image: UIImage(systemName: "ellipsis"),
        primaryAction: UIAction { [weak self] _ in self?.presentMenu() }
    )

    private lazy var undoItem = UIBarButtonItem(
        title: String(localized: "Undo"),
        image: UIImage(systemName: "arrow.uturn.backward"),
        primaryAction: UIAction { [weak self] _ in self?.onUndo() }
    )

    private lazy var shareMenuGroup = UIBarButtonItemGroup(
        barButtonItems: [shareItem, menuItem], representativeItem: nil
    )
    private lazy var undoGroup = UIBarButtonItemGroup(barButtonItems: [undoItem], representativeItem: nil)

    func attach(to navigation: UINavigationController) {
        self.navigation = navigation
        shareItem.accessibilityLabel = String(localized: "Share")
        menuItem.accessibilityLabel = String(localized: "Menu")
        undoItem.accessibilityLabel = String(localized: "Undo")
        shareItem.accessibilityHint = String(localized: "Share text")
        menuItem.accessibilityHint = String(localized: "Open menu")
        updateGroups()
    }

    func update(text: String, menuVM: MenuViewModel, canUndo: Bool, onUndo: @escaping () -> Void) {
        self.text = text
        self.menuVM = menuVM
        self.onUndo = onUndo
        shareItem.isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if showsUndo != canUndo {
            showsUndo = canUndo
            updateGroups()
        }
    }

    private func updateGroups() {
        navigation?.viewControllers.first?.navigationItem.trailingItemGroups =
            showsUndo ? [undoGroup, shareMenuGroup] : [shareMenuGroup]
    }

    func presentMenu() {
        guard let navigation, let menuVM,
              navigation.view.window != nil,
              navigation.presentedViewController == nil else { return }
        let controller = MenuPopoverController(menuVM: menuVM, source: navigation) { [weak self] in
            self?.menuController?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        }
        controller.modalPresentationStyle = .popover
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceItem = menuItem
        popover.delegate = self
        menuController = controller
        navigation.present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func presentShare() {
        guard let navigation, shareItem.isEnabled else { return }
        SystemSharePresenter.present(text: text, from: shareItem, in: navigation)
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}

private final class MenuPopoverController: UIHostingController<MenuBubble> {
    private weak var source: UIViewController?

    init(menuVM: MenuViewModel, source: UIViewController, onDismiss: @escaping () -> Void) {
        self.source = source
        super.init(rootView: MenuBubble(menuVM: menuVM, onDismiss: onDismiss))
        sizingOptions = .preferredContentSize
        view.backgroundColor = .clear
        updateHeightLimit()
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        return nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateHeightLimit()
    }

    private func updateHeightLimit() {
        guard let source else { return }
        let height = max(44, source.view.safeAreaLayoutGuide.layoutFrame.height - 2 * ChromeMetrics.chromeHorizontalInset)
        if rootView.maximumHeight != height {
            rootView.maximumHeight = height
        }
    }
}
