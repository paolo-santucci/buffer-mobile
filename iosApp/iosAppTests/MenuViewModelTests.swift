// MenuViewModelTests.swift
// iosAppTests
//
// XCTest coverage for MenuViewModel — fresh RecoveryListViewModel creation (FR-12).
// (The theme-selection and font-stepping suites retired with the pickers — user
// direction: the app always follows the system theme and the system default font.)
//
// Stubs are FILE-PRIVATE to this file to avoid duplicate-symbol CI failures
// (M3 lesson: StubSettingsRepository declared internal across two files → CI red).
//
// M3 CI conventions (MANDATORY):
//   @MainActor at class level — MenuViewModel is composed of @Observable deps.
//   File-private stubs — never hit real NSUserDefaults/disk.
//   No async/await, no Task, no wall-clock sleeps.
//   import shared + @testable import iosApp.
//
// Spec refs: §7.1 Layer B (MenuViewModel section); §7.2 integration
//   (MenuViewModel + SettingsRepository round-trip); EC-10;
//   OQ-11 note: select(path:) calls read synchronously (non-suspend, FR-24) so
//   no async harness is required.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import XCTest
import UIKit
import shared
@testable import iosApp

// ---------------------------------------------------------------------------
// MARK: - File-private stubs
// ---------------------------------------------------------------------------

/// Minimal settings stub: the BufferViewModel dependency only (no font slot
/// read anymore — the settings construction contract is retained for the
/// composition root; the VM never reads it).
private final class StubSettingsRepository: SettingsRepository {
    var storedSettings: AppSettings

    init(fontSizeIndex: Int32 = 8, colorScheme: AppColorScheme = AppColorScheme.follow) {
        storedSettings = AppSettings(colorScheme: colorScheme, fontSizeIndex: fontSizeIndex)
    }

    private(set) var saveCallCount: Int = 0
    private(set) var savedSettings: [AppSettings] = []

    func load() -> AppSettings { storedSettings }

    func save(settings: AppSettings) {
        saveCallCount += 1
        storedSettings = settings
        savedSettings.append(settings)
    }
}

/// Minimal recovery stub: returns an empty list and nil for all reads.
/// Used as an inert dependency for MenuViewModel (recovery paths tested separately).
private final class StubRecoveryRepository: RecoveryRepository {
    func list() -> [RecoveryNote] { [] }
    func read(path: String) -> String? { nil }
    func save(text: String) -> String { "" }
    func delete(path: String) {}
    func deleteAll() {}
    func trim(keep: Int32) {}
}

// ---------------------------------------------------------------------------
// MARK: - MenuViewModelTests
// ---------------------------------------------------------------------------

/// Tests for MenuViewModel — recovery VM factory.
///
/// `@MainActor`: composes @Observable types.
@MainActor
final class MenuViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a MenuViewModel with file-private stubs.
    private func makeVM() -> MenuViewModel {
        let recovery = StubRecoveryRepository()
        let bufferVM = BufferViewModel(settings: StubSettingsRepository())
        return MenuViewModel(recovery: recovery, viewModel: bufferVM)
    }

    // -----------------------------------------------------------------------
    // MARK: - makeRecoveryListViewModel — fresh instance per call (FR-12)

    /// makeRecoveryListViewModel() returns a distinct instance each call.
    func test_makeRecoveryListViewModel_returnsDistinctInstance() {
        let vm = makeVM()

        let first = vm.makeRecoveryListViewModel()
        let second = vm.makeRecoveryListViewModel()

        XCTAssertFalse(first === second,
            "makeRecoveryListViewModel() must return a DISTINCT instance on each call (FR-12 fresh-per-expand)")
    }
}

@MainActor
final class ChromeBarCoordinatorTests: XCTestCase {
    private func makeMenu() -> MenuViewModel {
        MenuViewModel(
            recovery: StubRecoveryRepository(),
            viewModel: BufferViewModel(settings: StubSettingsRepository())
        )
    }

    func testShareTracksWhitespaceAndEditedBuffer() throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let coordinator = ChromeBarCoordinator()
        coordinator.attach(to: navigation)
        let menu = makeMenu()
        coordinator.update(text: " \n\t", menuVM: menu, canUndo: false, onUndo: {})
        let share = try XCTUnwrap(root.navigationItem.trailingItemGroups.last?.barButtonItems.first)
        XCTAssertFalse(share.isEnabled)
        coordinator.update(text: "Note", menuVM: menu, canUndo: true, onUndo: {})
        XCTAssertTrue(share.isEnabled)
        coordinator.update(text: "", menuVM: menu, canUndo: false, onUndo: {})
        XCTAssertFalse(share.isEnabled)
    }

    func testUndoChangesPreservePresentationSourceItems() throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let coordinator = ChromeBarCoordinator()
        coordinator.attach(to: navigation)
        let menu = makeMenu()
        coordinator.update(text: "Note", menuVM: menu, canUndo: false, onUndo: {})
        let originalGroup = try XCTUnwrap(root.navigationItem.trailingItemGroups.last)
        let originalItems = originalGroup.barButtonItems
        XCTAssertEqual(originalItems.count, 2)
        coordinator.update(text: "Edited", menuVM: menu, canUndo: true, onUndo: {})
        XCTAssertEqual(root.navigationItem.trailingItemGroups.count, 2)
        XCTAssertTrue(root.navigationItem.trailingItemGroups.last === originalGroup)
        coordinator.update(text: "Note", menuVM: menu, canUndo: false, onUndo: {})
        XCTAssertEqual(root.navigationItem.trailingItemGroups.count, 1)
        XCTAssertTrue(root.navigationItem.trailingItemGroups[0].barButtonItems[0] === originalItems[0])
        XCTAssertTrue(root.navigationItem.trailingItemGroups[0].barButtonItems[1] === originalItems[1])
    }

    func testMenuRemainsPopoverInCompactWidth() {
        let coordinator = ChromeBarCoordinator()
        let presentation = UIPresentationController(
            presentedViewController: UIViewController(), presenting: UIViewController()
        )
        XCTAssertEqual(coordinator.adaptivePresentationStyle(
            for: presentation, traitCollection: UITraitCollection(horizontalSizeClass: .compact)
        ), .none)
    }

    func testIdleMenuPresentationsHaveContentAndCanReopen() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let navigation = ImmediatePresentationNavigationController(rootViewController: UIViewController())
        let coordinator = ChromeBarCoordinator()
        coordinator.attach(to: navigation)
        coordinator.update(text: "Note", menuVM: makeMenu(), canUndo: false, onUndo: {})
        window.rootViewController = navigation
        let visible = expectation(description: "Navigation is visible")
        navigation.onAppear = { visible.fulfill() }
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
        }
        wait(for: [visible], timeout: 3)

        for attempt in 1...3 {
            let presented = expectation(description: "Menu opens on tap \(attempt)")
            navigation.onPresent = { presented.fulfill() }
            coordinator.presentMenu()
            wait(for: [presented], timeout: 3)
            let menu = try XCTUnwrap(navigation.presentedViewController)
            XCTAssertGreaterThan(menu.preferredContentSize.width, 0)
            XCTAssertGreaterThan(menu.preferredContentSize.height, 0)
            XCTAssertNotNil(menu.popoverPresentationController?.sourceItem)
            let dismissed = expectation(description: "Menu dismisses \(attempt)")
            menu.dismiss(animated: false) { dismissed.fulfill() }
            wait(for: [dismissed], timeout: 3)
            XCTAssertNil(navigation.presentedViewController)
        }
    }
}

@MainActor
private final class ImmediatePresentationNavigationController: UINavigationController {
    var onAppear: (() -> Void)?
    var onPresent: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let completion = onAppear
        onAppear = nil
        completion?()
    }

    override func present(
        _ controller: UIViewController,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        super.present(controller, animated: false) {
            completion?()
            self.onPresent?()
        }
    }
}
