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
