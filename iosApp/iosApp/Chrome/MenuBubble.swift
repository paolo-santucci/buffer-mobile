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
                makeChildren: recoveryActions
            )
            .frame(minHeight: 44)
            Divider().padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            NativeSubmenuButton(
                title: String(localized: "About"), symbol: "info.circle",
                makeChildren: aboutActions
            )
            .frame(minHeight: 44)
        }
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
    }

    private func recoveryActions() -> [UIMenuElement] {
        let model = menuVM.makeRecoveryListViewModel()
        model.refresh()
        guard !model.rows.isEmpty else {
            return [UIAction(title: String(localized: "No recent notes."), attributes: .disabled) { _ in }]
        }
        return model.rows.map { row in
            let action = UIAction(title: row.previewTitle, image: UIImage(systemName: "doc.text")) { _ in
                model.select(path: row.path)
                onDismiss()
            }
            action.subtitle = row.dateSubtitle
            action.accessibilityLabel = String(
                format: String(localized: "Restore note: %@, saved %@"), row.previewTitle, row.dateSubtitle
            )
            action.accessibilityHint = String(localized: "Restore this note")
            return action
        }
    }

    private func aboutActions() -> [UIMenuElement] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let identity = UIAction(title: "Foglietto", image: UIImage(systemName: "app"), attributes: .disabled) { _ in }
        identity.subtitle = [version, "Paolo Santucci", "GPL-3.0"].filter { !$0.isEmpty }.joined(separator: " · ")
        return [
            identity,
            linkAction(title: String(localized: "Report an issue"), symbol: "exclamationmark.bubble",
                       address: "https://buffer.paolosantucci.com/bug/"),
            linkAction(title: String(localized: "Website"), symbol: "globe",
                       address: "https://buffer.paolosantucci.com/")
        ]
    }

    private func linkAction(title: String, symbol: String, address: String) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol)) { _ in
            guard let url = URL(string: address) else { return }
            onDismiss()
            UIApplication.shared.open(url)
        }
    }
}

struct NativeSubmenuButton: UIViewRepresentable {
    let title: String
    let symbol: String
    let makeChildren: () -> [UIMenuElement]

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.contentHorizontalAlignment = .leading
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = .secondaryLabel
        chevron.isAccessibilityElement = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -ChromeMetrics.menuRowHorizontalPadding),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
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
        button.menu = Self.menu(title: title, makeChildren: makeChildren)
    }

    static func menu(title: String, makeChildren: @escaping () -> [UIMenuElement]) -> UIMenu {
        UIMenu(title: title, children: [UIDeferredMenuElement.uncached { completion in
            completion(makeChildren())
        }])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let width = proposal.width ?? ChromeMetrics.menuPanelWidth
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, size.height))
    }
}
