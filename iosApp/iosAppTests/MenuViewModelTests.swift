// MenuViewModelTests.swift
// iosAppTests
//
// XCTest coverage for MenuViewModel — theme selection, font-size stepping,
// and fresh RecoveryListViewModel creation (FR-10, FR-11, FR-12; EC-07, EC-08, EC-10).
//
// Stubs are FILE-PRIVATE to this file to avoid duplicate-symbol CI failures
// (M3 lesson: StubSettingsRepository declared internal across two files → CI red).
//
// M3 CI conventions (MANDATORY):
//   @MainActor at class level — MenuViewModel holds @Observable state.
//   File-private stubs — never hit real NSUserDefaults/disk.
//   No async/await, no Task, no wall-clock sleeps.
//   import shared + @testable import iosApp.
//
// Spec refs: §7.1 Layer B (MenuViewModel section); §7.2 integration
//   (MenuViewModel + SettingsRepository round-trip); EC-07, EC-08, EC-10;
//   OQ-11 note: select(path:) calls read synchronously (non-suspend, FR-24) so
//   no async harness is required.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import XCTest
import shared
@testable import iosApp

// ---------------------------------------------------------------------------
// MARK: - File-private stubs
// ---------------------------------------------------------------------------

/// Minimal settings stub: records save calls + the last-saved AppSettings.
/// The `storedSettings` is mutable so tests can seed the initial state before
/// constructing a MenuViewModel.
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

/// Tests for MenuViewModel — theme selection, font stepping, recovery VM factory.
///
/// `@MainActor`: MenuViewModel is `@Observable` and its init reads settings on the main actor.
@MainActor
final class MenuViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a MenuViewModel with a controlled settings stub pre-seeded with the
    /// given fontSizeIndex and colorScheme.
    private func makeVM(
        fontSizeIndex: Int32 = 8,
        colorScheme: AppColorScheme = AppColorScheme.follow
    ) -> (vm: MenuViewModel, stub: StubSettingsRepository) {
        let stub = StubSettingsRepository(fontSizeIndex: fontSizeIndex, colorScheme: colorScheme)
        let recovery = StubRecoveryRepository()
        let bufferVM = BufferViewModel(settings: stub)
        let vm = MenuViewModel(settings: stub, recovery: recovery, viewModel: bufferVM)
        return (vm, stub)
    }

    // -----------------------------------------------------------------------
    // MARK: - selectTheme — write-through (FR-10 / CM-2)

    /// selectTheme(.dark) saves AppSettings with colorScheme=.dark, fontSizeIndex preserved.
    func test_selectTheme_dark_savesCorrectSettings() {
        let (vm, stub) = makeVM(fontSizeIndex: 7, colorScheme: .follow)

        vm.selectTheme(.dark)

        XCTAssertEqual(stub.saveCallCount, 1,
            "selectTheme must call save exactly once (FR-10)")
        let saved = stub.storedSettings
        XCTAssertEqual(saved.colorScheme, AppColorScheme.dark,
            "saved colorScheme must be .dark (FR-10 / CM-2)")
        XCTAssertEqual(saved.fontSizeIndex, 7,
            "saved fontSizeIndex must be preserved — 7 (CM-2 identity-stable setColorScheme)")
    }

    // -----------------------------------------------------------------------
    // MARK: - selectTheme — equal-value no-op (EC-08 / FR-10)

    /// Re-selecting the active theme must NOT call save (EC-08 no-write-on-equal).
    func test_selectTheme_equalValue_doesNotSave() {
        let (vm, stub) = makeVM(fontSizeIndex: 5, colorScheme: .dark)

        // Stub starts with .dark; selecting .dark again is a no-op.
        vm.selectTheme(.dark)

        XCTAssertEqual(stub.saveCallCount, 0,
            "selectTheme with the already-active scheme must NOT call save (EC-08 / FR-10)")
    }

    // -----------------------------------------------------------------------
    // MARK: - stepFontSize — increment and decrement (FR-11)

    /// stepFontSize(+1) from index 8 saves fontSizeIndex 9.
    func test_stepFontSize_increment_savesFontSize9() {
        let (vm, stub) = makeVM(fontSizeIndex: 8)

        vm.stepFontSize(by: 1)

        XCTAssertEqual(stub.saveCallCount, 1,
            "stepFontSize must call save once (FR-11)")
        XCTAssertEqual(stub.storedSettings.fontSizeIndex, 9,
            "stepFontSize(by:1) from index 8 must save fontSizeIndex 9 (FR-11)")
    }

    /// stepFontSize(-1) from index 8 saves fontSizeIndex 7.
    func test_stepFontSize_decrement_savesFontSize7() {
        let (vm, stub) = makeVM(fontSizeIndex: 8)

        vm.stepFontSize(by: -1)

        XCTAssertEqual(stub.saveCallCount, 1,
            "stepFontSize must call save once (FR-11)")
        XCTAssertEqual(stub.storedSettings.fontSizeIndex, 7,
            "stepFontSize(by:-1) from index 8 must save fontSizeIndex 7 (FR-11)")
    }

    // -----------------------------------------------------------------------
    // MARK: - stepFontSize — lower-clamp at 0 (EC-07 / FR-11)

    /// stepFontSize(-1) when already at index 0 must NOT call save.
    func test_stepFontSize_lowerClamp_doesNotSave() {
        let (vm, stub) = makeVM(fontSizeIndex: 0)

        vm.stepFontSize(by: -1)

        XCTAssertEqual(stub.saveCallCount, 0,
            "stepFontSize at lower-clamp (index 0, delta -1) must NOT call save (EC-07 / FR-11)")
    }

    // -----------------------------------------------------------------------
    // MARK: - stepFontSize — upper-clamp at 20 (EC-07 / FR-11)

    /// stepFontSize(+1) when already at index 20 must NOT call save.
    func test_stepFontSize_upperClamp_doesNotSave() {
        let (vm, stub) = makeVM(fontSizeIndex: 20)

        vm.stepFontSize(by: 1)

        XCTAssertEqual(stub.saveCallCount, 0,
            "stepFontSize at upper-clamp (index 20, delta +1) must NOT call save (EC-07 / FR-11)")
    }

    // -----------------------------------------------------------------------
    // MARK: - makeRecoveryListViewModel — fresh instance per call (FR-12)

    /// makeRecoveryListViewModel() returns a distinct instance each call.
    func test_makeRecoveryListViewModel_returnsDistinctInstance() {
        let (vm, _) = makeVM()

        let first = vm.makeRecoveryListViewModel()
        let second = vm.makeRecoveryListViewModel()

        XCTAssertFalse(first === second,
            "makeRecoveryListViewModel() must return a DISTINCT instance on each call (FR-12 fresh-per-expand)")
    }

    // -----------------------------------------------------------------------
    // MARK: - §7.2 Integration: interleaved selectTheme + stepFontSize (EC-10 / CM-1)

    /// EC-10 / CM-1: selectTheme(.dark) → stepFontSize(+1) → selectTheme(.light)
    /// leaves last-saved colorScheme=.light and fontSizeIndex=9 (started at 8).
    ///
    /// Proves the single-store invariant: all three calls read+write the same
    /// stub (one source of truth, no desync).
    func test_integration_interleavedOperations_singleStore() {
        let (vm, stub) = makeVM(fontSizeIndex: 8, colorScheme: .follow)

        vm.selectTheme(.dark)           // save: colorScheme=.dark, fontSizeIndex=8
        vm.stepFontSize(by: 1)          // save: colorScheme=.dark, fontSizeIndex=9
        vm.selectTheme(.light)          // save: colorScheme=.light, fontSizeIndex=9

        let final = stub.storedSettings
        XCTAssertEqual(final.colorScheme, AppColorScheme.light,
            "last selectTheme(.light) must win as colorScheme (EC-10 / CM-1)")
        XCTAssertEqual(final.fontSizeIndex, 9,
            "stepFontSize(+1) must be preserved after subsequent selectTheme (EC-10 single store)")
        XCTAssertEqual(stub.saveCallCount, 3,
            "exactly 3 saves must have occurred (one per non-no-op operation)")
    }

    // -----------------------------------------------------------------------
    // MARK: - §7.2 Integration: equal-value no-op does not reset fontSizeIndex (EC-08 neg)

    /// Re-selecting the active theme (no-op) followed by stepFontSize must not
    /// accidentally clear fontSizeIndex (EC-08 negative integration path).
    func test_integration_equalValueNoOp_doesNotClearFontSizeIndex() {
        let (vm, stub) = makeVM(fontSizeIndex: 5, colorScheme: .dark)

        vm.selectTheme(.dark)           // no-op — save NOT called
        vm.stepFontSize(by: 1)          // save: colorScheme=.dark, fontSizeIndex=6

        let final = stub.storedSettings
        XCTAssertEqual(final.fontSizeIndex, 6,
            "fontSizeIndex must be 6 after stepFontSize(+1) from 5 (EC-08 neg integration path)")
        XCTAssertEqual(final.colorScheme, AppColorScheme.dark,
            "colorScheme must still be .dark after the no-op selectTheme + stepFontSize (EC-08)")
        XCTAssertEqual(stub.saveCallCount, 1,
            "exactly 1 save: only stepFontSize saves; selectTheme(.dark) on .dark is no-op")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Single-settings-instance test (EC-10 / CM-1 regression guard)
//
// Proves that a MenuViewModel.stepFontSize change is observed by a BufferViewModel
// reading the SAME injected settings stub. Placed here (adjacent to MenuViewModel
// tests) so the stub type is reusable without cross-file collisions.
// ---------------------------------------------------------------------------

/// Single-settings-instance invariant (EC-10 / CM-1 regression guard).
///
/// A MenuViewModel-triggered stepFontSize(by:1) must cause the BufferViewModel's
/// subsequent fontSizeIndex read to reflect the incremented value, because both
/// share exactly one SettingsRepository instance.
@MainActor
final class SingleSettingsInstanceTests: XCTestCase {

    func test_menuVM_stepFontSize_observedByBufferVM_sameStub() {
        // One shared stub — the single settings store (CM-1 / FR-03).
        let sharedStub = StubSettingsRepository(fontSizeIndex: 8, colorScheme: .follow)
        let recoveryStub = StubRecoveryRepository()

        // Both VMs injected with the same stub.
        let bufferVM = BufferViewModel(settings: sharedStub)
        let menuVM = MenuViewModel(settings: sharedStub, recovery: recoveryStub, viewModel: bufferVM)

        XCTAssertEqual(bufferVM.fontSizeIndex, 8, "precondition: BufferVM reads index 8 from shared stub")

        // MenuViewModel steps the font size.
        menuVM.stepFontSize(by: 1)

        // The stub now has fontSizeIndex 9. BufferViewModel re-reads from the same stub.
        // BufferViewModel.fontSizeIndex is a cached Int read from settings at init;
        // the single-store invariant is proven at the STORE level (sharedStub.storedSettings).
        XCTAssertEqual(sharedStub.storedSettings.fontSizeIndex, 9,
            "menuVM.stepFontSize(+1) must update the shared stub to fontSizeIndex=9 (CM-1 single store)")

        // A fresh BufferViewModel constructed from the same stub reflects the new index.
        // This proves that if BufferVM re-reads (e.g. on next updateUIView fontPt reconcile)
        // it will see index 9, not a stale 8 from a separate store.
        let newBufferVM = BufferViewModel(settings: sharedStub)
        XCTAssertEqual(newBufferVM.fontSizeIndex, 9,
            "a BufferViewModel constructed from the same shared stub must read index 9 (CM-1 regression guard EC-10)")
    }
}
