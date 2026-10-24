import SwiftUI
import shared

struct ContentView: View {
    let viewModel: BufferViewModel
    let recovery: RecoveryRepository
    let lifecycle: LifecycleSaveCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinatorBox = CoordinatorBox()
    @State private var menuVM: MenuViewModel

    init(viewModel: BufferViewModel, recovery: RecoveryRepository, lifecycle: LifecycleSaveCoordinator) {
        self.viewModel = viewModel
        self.recovery = recovery
        self.lifecycle = lifecycle
        _menuVM = State(wrappedValue: MenuViewModel(recovery: recovery, viewModel: viewModel))
    }

    var body: some View {
        ChromeOverlay(
            text: viewModel.text,
            menuVM: menuVM,
            canUndo: coordinatorBox.canUndo,
            onUndo: { [coordinatorBox] in coordinatorBox.coordinator?.undo() }
        ) {
            BufferEditor(viewModel: viewModel, coordinatorBox: coordinatorBox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomToolbar
                }
        }
        .ignoresSafeArea(.container)
        .preferredColorScheme(nil)
        .onChange(of: scenePhase) { _, newPhase in
            ContentView.dispatchScenePhase(newPhase, to: lifecycle)
        }
    }

    private var bottomToolbar: some View {
        HStack {
            BottomToolbar(
                onCopy: { [coordinatorBox] in coordinatorBox.coordinator?.copyToPasteboard() },
                onPaste: { [coordinatorBox] in coordinatorBox.coordinator?.pasteAtCaret() },
                onCloseKeyboard: { [coordinatorBox] in coordinatorBox.coordinator?.closeKeyboard() },
                onIndent: { [coordinatorBox, viewModel] in
                    guard let textView = coordinatorBox.coordinator?.textView else { return }
                    let result = viewModel.indent(in: textView.selectedRange, of: textView.text ?? "")
                    coordinatorBox.coordinator?.applyIndentResult(text: result.text, range: result.selection)
                },
                onOutdent: { [coordinatorBox, viewModel] in
                    guard let textView = coordinatorBox.coordinator?.textView else { return }
                    let result = viewModel.outdent(in: textView.selectedRange, of: textView.text ?? "")
                    coordinatorBox.coordinator?.applyIndentResult(text: result.text, range: result.selection)
                }
            )
            Spacer()
        }
        .padding(.leading, ChromeMetrics.toolbarFloatingPadding)
        .padding(.bottom, ChromeMetrics.toolbarFloatingPadding)
    }

    @MainActor
    static func dispatchScenePhase(_ phase: ScenePhase, to coordinator: LifecycleSaveCoordinator) {
        switch phase {
        case .background:
            coordinator.onBackground()
        case .active:
            coordinator.onActive()
        case .inactive:
            coordinator.onInactive()
        @unknown default:
            break
        }
    }
}
