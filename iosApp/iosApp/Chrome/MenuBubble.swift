import SwiftUI
import UIKit

struct MenuBubble: View {
    let menuVM: MenuViewModel
    var maximumHeight: CGFloat = 480
    let onDismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
                .frame(height: maximumHeight)
        }
        .frame(width: ChromeMetrics.menuPanelWidth)
        .frame(maxHeight: maximumHeight)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            NativeSubmenuButton(
                title: String(localized: "Recent notes"),
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                makeItems: recoveryItems
            )
            .frame(minHeight: 44)
            Divider().padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            NativeSubmenuButton(
                title: String(localized: "About"), symbol: "info.circle",
                makeItems: aboutItems
            )
            .frame(minHeight: 44)
        }
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
    }

    private func recoveryItems() -> [PopupMenuItem] {
        let model = menuVM.makeRecoveryListViewModel()
        model.refresh()
        guard !model.rows.isEmpty else {
            return [PopupMenuItem(title: String(localized: "No recent notes."), isEnabled: false)]
        }
        return model.rows.map { row in
            PopupMenuItem(
                title: row.previewTitle,
                subtitle: row.dateSubtitle,
                symbol: "doc.text",
                accessibilityLabel: String(
                    format: String(localized: "Restore note: %@, saved %@"), row.previewTitle, row.dateSubtitle
                ),
                accessibilityHint: String(localized: "Restore this note")
            ) {
                model.select(path: row.path)
                onDismiss()
            }
        }
    }

    private func aboutItems() -> [PopupMenuItem] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let details = [version, "Paolo Santucci", "GPL-3.0"].filter { !$0.isEmpty }.joined(separator: " · ")
        return [
            PopupMenuItem(title: "Foglietto", subtitle: details, symbol: "app", isEnabled: false),
            linkItem(title: String(localized: "Report an issue"), symbol: "exclamationmark.bubble",
                     address: "https://buffer.paolosantucci.com/bug/"),
            linkItem(title: String(localized: "Website"), symbol: "globe",
                     address: "https://buffer.paolosantucci.com/")
        ]
    }

    private func linkItem(title: String, symbol: String, address: String) -> PopupMenuItem {
        PopupMenuItem(title: title, symbol: symbol) {
            guard let url = URL(string: address) else { return }
            onDismiss()
            UIApplication.shared.open(url)
        }
    }
}

struct PopupMenuItem: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String?
    var symbol: String?
    var isEnabled = true
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var action: () -> Void = {}
}

struct NativeSubmenuButton: UIViewRepresentable {
    let title: String
    let symbol: String
    let makeItems: () -> [PopupMenuItem]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = .secondaryLabel
        chevron.isAccessibilityElement = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        button.addAction(UIAction { [weak coordinator = context.coordinator, weak button] _ in
            guard let button else { return }
            coordinator?.presentPopup(from: button)
        }, for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -ChromeMetrics.menuRowHorizontalPadding),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = ChromeMetrics.menuRowHorizontalPadding
        configuration.baseForegroundColor = .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = UIFont.preferredFont(forTextStyle: .body)
            return attributes
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: ChromeMetrics.menuRowVerticalPadding, leading: ChromeMetrics.menuRowHorizontalPadding,
            bottom: ChromeMetrics.menuRowVerticalPadding, trailing: ChromeMetrics.pillHeight
        )
        button.configuration = configuration
        button.accessibilityLabel = title
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let width = proposal.width ?? ChromeMetrics.menuPanelWidth
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, size.height))
    }

    @MainActor
    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var parent: NativeSubmenuButton

        init(parent: NativeSubmenuButton) {
            self.parent = parent
        }

        func presentPopup(from button: UIButton) {
            guard let presenter = button.nearestViewController, presenter.presentedViewController == nil else { return }
            let controller = SubmenuPopoverController(
                title: parent.title, symbol: parent.symbol, items: parent.makeItems(), source: presenter
            )
            controller.modalPresentationStyle = .popover
            guard let popover = controller.popoverPresentationController else { return }
            popover.sourceView = button
            popover.sourceRect = button.bounds
            popover.canOverlapSourceViewRect = true
            popover.delegate = self
            presenter.present(controller, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
            alignTrailingEdge(popoverPresentationController)
        }

        func popoverPresentationController(
            _ popoverPresentationController: UIPopoverPresentationController,
            willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>,
            in view: AutoreleasingUnsafeMutablePointer<UIView>
        ) {
            alignTrailingEdge(popoverPresentationController)
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            .none
        }

        private func alignTrailingEdge(_ popover: UIPopoverPresentationController) {
            guard let container = popover.containerView,
                  let mainPanel = popover.presentingViewController.view else { return }
            mainPanel.layoutIfNeeded()
            let frame = mainPanel.convert(mainPanel.bounds, to: container)
            let inset = ChromeMetrics.chromeHorizontalInset
            let right = max(inset, container.bounds.maxX - frame.maxX)
            let left = max(inset, container.bounds.width - right - ChromeMetrics.submenuPanelWidth)
            popover.popoverLayoutMargins = UIEdgeInsets(
                top: inset, left: left, bottom: inset, right: right
            )
        }
    }
}

private struct SubmenuBubble: View {
    let title: String
    let symbol: String
    let items: [PopupMenuItem]
    var maximumHeight: CGFloat

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .frame(height: maximumHeight)
        }
        .frame(width: ChromeMetrics.submenuPanelWidth)
        .frame(maxHeight: maximumHeight)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ChromeMetrics.menuRowHorizontalPadding) {
                Image(systemName: symbol)
                Text(title).fontWeight(.bold)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            .frame(minHeight: 44)
            Divider().padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: ChromeMetrics.menuRowHorizontalPadding) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol).frame(width: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if let subtitle = item.subtitle {
                                Text(subtitle).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.body)
                    .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                    .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .accessibilityLabel(Text(item.accessibilityLabel ?? item.title))
                .accessibilityHint(Text(item.accessibilityHint ?? ""))
            }
        }
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
    }
}

private final class SubmenuPopoverController: UIHostingController<SubmenuBubble> {
    private weak var source: UIViewController?

    init(title: String, symbol: String, items: [PopupMenuItem], source: UIViewController) {
        self.source = source
        super.init(rootView: SubmenuBubble(title: title, symbol: symbol, items: items, maximumHeight: 480))
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
        guard let window = source?.view.window else { return }
        let height = max(44, window.safeAreaLayoutGuide.layoutFrame.height - 2 * ChromeMetrics.chromeHorizontalInset)
        if rootView.maximumHeight != height {
            rootView.maximumHeight = height
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var candidate: UIResponder? = self
        while let responder = candidate?.next {
            if let controller = responder as? UIViewController { return controller }
            candidate = responder
        }
        return nil
    }
}
