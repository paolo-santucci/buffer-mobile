import SwiftUI
import shared

struct MenuBubble: View {
    let menuVM: MenuViewModel
    var maximumHeight: CGFloat = 480
    let onDismiss: () -> Void
    @State private var isAboutExpanded = false
    @State private var isRecoveryExpanded = false
    @State private var recoveryVM: RecoveryListViewModel?

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
            RecoverySection(
                menuVM: menuVM,
                onDismiss: onDismiss,
                isExpanded: $isRecoveryExpanded,
                recoveryVM: $recoveryVM
            )
            Divider()
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            AboutSection(isExpanded: $isAboutExpanded)
        }
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
    }
}

private struct AboutSection: View {
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            Button {
                withAnimation(reduceMotion ? nil : ChromeMetrics.submenuExpandAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                MenuRow(icon: "info.circle", label: String(localized: "About"), isExpanded: isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "About"))
            .help(String(localized: "About"))

            if isExpanded {
                AboutDetails()
            }
        }
    }
}

private struct AboutDetails: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            HStack(spacing: ChromeMetrics.menuRowHorizontalPadding) {
                Image(systemName: "app")
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                    Text("Foglietto").font(.headline)
                    Text("Paolo Santucci").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: ChromeMetrics.menuRowSpacing) {
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text(version)
                    }
                    Text("GPL-3.0")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
            .frame(minHeight: 44)

            Link(destination: URL(string: "https://buffer.paolosantucci.com/bug/")!) {
                MenuRow(icon: "exclamationmark.bubble", label: String(localized: "Report an issue"))
            }
            Link(destination: URL(string: "https://buffer.paolosantucci.com/")!) {
                MenuRow(icon: "globe", label: String(localized: "Website"))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MenuRow: View {
    let icon: String
    let label: String
    var isExpanded: Bool? = nil

    var body: some View {
        HStack(spacing: ChromeMetrics.menuRowHorizontalPadding) {
            Image(systemName: icon)
                .font(.body.weight(ChromeMetrics.iconScaleWeight))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(label).font(.body)
            Spacer()
            if let isExpanded {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(ChromeMetrics.iconScaleWeight))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

private struct RecoverySection: View {
    let menuVM: MenuViewModel
    let onDismiss: () -> Void
    @Binding var isExpanded: Bool
    @Binding var recoveryVM: RecoveryListViewModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            Button(action: toggleExpansion) {
                MenuRow(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    label: String(localized: "Recent notes"),
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Recent notes"))
            .help(String(localized: "Recent notes"))

            if isExpanded, let recoveryVM {
                recoveryContent(recoveryVM)
            }
        }
    }

    private func toggleExpansion() {
        withAnimation(reduceMotion ? nil : ChromeMetrics.submenuExpandAnimation) {
            isExpanded.toggle()
            if isExpanded {
                let model = menuVM.makeRecoveryListViewModel()
                model.refresh()
                recoveryVM = model
            } else {
                recoveryVM = nil
            }
        }
    }

    @ViewBuilder
    private func recoveryContent(_ model: RecoveryListViewModel) -> some View {
        if model.rows.isEmpty {
            Text(String(localized: "No recent notes."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
        } else {
            ForEach(model.rows) { row in
                Button {
                    model.select(path: row.path)
                    onDismiss()
                } label: {
                    recoveryLabel(row)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    format: String(localized: "Restore note: %@, saved %@"),
                    row.previewTitle, row.dateSubtitle
                ))
                .help(String(localized: "Restore this note"))
            }
        }
    }

    private func recoveryLabel(_ row: RecoveryRow) -> some View {
        HStack(spacing: ChromeMetrics.menuRowHorizontalPadding) {
            Image(systemName: "doc.text")
                .frame(width: 24)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                Text(row.previewTitle).font(.subheadline).lineLimit(1)
                Text(row.dateSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}
