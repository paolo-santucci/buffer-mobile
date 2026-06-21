// EditorPinchModifierTests.swift
// iosAppTests
//
// XCTest suite for EditorPinchModifier — exercises the testable gesture seam.
//
// Spec refs: FR-17, FR-18, FR-21; §6.1 EC-09/EC-10; TASK-06 TDD block
//
// These tests call `onPinchBegan(currentIndex:)`, `onPinchChanged(scale:)`, and
// `onPinchEnded()` directly on the modifier's internal seam.  This avoids
// synthesising UIKit touch events and lets the gesture-callback logic run
// synchronously in a simulator unit-test context.
//
// Registration: this file is authored on disk by TASK-06 and registered in
// the `iosAppTests` XCTest target's Sources phase by TASK-08 (the single
// pbxproj writer for all test sources).

import XCTest
@testable import iosApp
import shared

// MARK: - Mocks / Stubs

/// A minimal in-memory stub conforming to `AppSettings` mutations.
///
/// Records the number of `save(_:)` calls and the last-saved `fontSizeIndex`
/// so tests can assert save-once and no-save-on-cancel invariants (EC-10).
final class MockSettingsRepository: SettingsRepository {

    // Backing store — starts at default index 8 (14pt), follow-system theme.
    private var storedIndex: Int32 = 8
    private var storedScheme: AppColorScheme = AppColorScheme.follow

    /// Number of times `save(_:)` has been called.
    var saveCallCount: Int = 0

    /// The `fontSizeIndex` from the most recent `save(_:)` call.  `nil` if never saved.
    var lastSavedIndex: Int32? = nil

    func load() -> AppSettings {
        return AppSettings(colorScheme: storedScheme, fontSizeIndex: storedIndex)
    }

    func save(_ settings: AppSettings) {
        saveCallCount += 1
        storedIndex = settings.fontSizeIndex
        storedScheme = settings.colorScheme
        lastSavedIndex = settings.fontSizeIndex
    }
}

// MARK: - EditorPinchModifierTests

final class EditorPinchModifierTests: XCTestCase {

    // MARK: - Helpers

    /// Constructs a modifier with a stub settings repository and a fresh VM at
    /// the given initial font-size index.
    private func makeModifier(
        startFontIndex: Int = 8,
        settings: MockSettingsRepository = MockSettingsRepository()
    ) -> (modifier: EditorPinchModifier, vm: BufferViewModel, settings: MockSettingsRepository) {
        let mockSettings = settings
        // Seed the mock so VM init reads the desired index.
        // (MockSettingsRepository.load() returns whatever was saved last;
        //  we prime it by initialising the vm with a stub that returns startFontIndex.)
        let vm = BufferViewModel(settings: mockSettings)
        // Override to startFontIndex since MockSettingsRepository starts at 8.
        // If startFontIndex differs, manually set it on the VM.
        vm.fontSizeIndex = startFontIndex
        let modifier = EditorPinchModifier(viewModel: vm, settings: mockSettings)
        return (modifier, vm, mockSettings)
    }

    // MARK: - Test: startIndex captured on begin, not re-read each update

    /// FR-17/18: `startIndex` is the anchor at gesture-begin.  Mutating
    /// `viewModel.fontSizeIndex` between updates must NOT change the clamp
    /// anchor — only the FIRST captured value is used.
    func test_startIndex_capturedOnceNotReRead() {
        let (modifier, vm, _) = makeModifier(startFontIndex: 8)

        // First update arms the seam and captures startIndex = 8.
        modifier.onPinchChanged(scale: 1.0)   // identity scale → index stays 8
        XCTAssertEqual(vm.fontSizeIndex, 8, "identity scale should leave index at 8")

        // Externally change fontSizeIndex to something else after begin.
        vm.fontSizeIndex = 15

        // A scale of 1.15 from startIndex=8 → PinchZoom.clampedTargetIndex(1.15, 8) = 9.
        // If startIndex were re-read (15), result would be 16 — not 9.
        modifier.onPinchChanged(scale: 1.15)
        // The shared Kotlin PinchZoom.clampedTargetIndex(1.15, 8) returns 9.
        XCTAssertEqual(vm.fontSizeIndex, 9,
            "startIndex must be the value captured on begin (8), not the externally-mutated value (15)")
    }

    // MARK: - Test: two-finger guard — non-2-finger leaves fontSizeIndex unchanged

    /// EC-10 neg / FR-18: `MagnifyGesture` is inherently two-finger.  A
    /// single-finger pan never delivers a MagnifyGesture event, so the modifier
    /// never fires.  We model this by verifying that a modifier whose seam was
    /// never armed (no `onPinchChanged` call) leaves the VM untouched.
    ///
    /// This also confirms `clampedTargetIndex` is NOT called on a cancelled path
    /// because `gestureStartIndex` remains nil.
    func test_twoFingerGuard_noCallsLeavesIndexUnchanged() {
        let (modifier, vm, settings) = makeModifier(startFontIndex: 8)

        // Simulate: gesture fires onEnded without any onChanged (e.g. immediate lift).
        modifier.onPinchEnded()

        // fontSizeIndex must be unchanged.
        XCTAssertEqual(vm.fontSizeIndex, 8, "fontSizeIndex must be unchanged when seam was never armed")
        // No save should have occurred.
        XCTAssertEqual(settings.saveCallCount, 0,
            "no save must occur when gesture seam was never armed (EC-10 neg)")
        XCTAssertNil(settings.lastSavedIndex, "lastSavedIndex must be nil if no save was issued")
    }

    // MARK: - Test: live update — scale 1.15 from index 8 → clampedTargetIndex result

    /// FR-18 / EC-09: on an update with scale=1.15, `clampedTargetIndex(1.15, 8)`
    /// returns 9 (round(ln(1.15)/ln(1.15)) = round(1.0) = 1; 8+1=9, clamped to [0,20]).
    func test_liveUpdate_scale1_15_fromIndex8_yields9() {
        let (modifier, vm, _) = makeModifier(startFontIndex: 8)

        modifier.onPinchChanged(scale: 1.15)

        // PinchZoom.shared.clampedTargetIndex(1.15, 8) == 9 (spec FR-17 worked example).
        XCTAssertEqual(vm.fontSizeIndex, 9,
            "scale=1.15 from startIndex=8 must yield fontSizeIndex=9 (FR-17 worked example)")
    }

    // MARK: - Test: save-once — begin + 10 updates + end → saveCallCount == 1

    /// EC-10: exactly one `settings.save(_:)` per completed gesture regardless
    /// of how many `onChanged` ticks fired.
    func test_saveOnce_multipleUpdates() {
        let (modifier, vm, settings) = makeModifier(startFontIndex: 8)

        // Simulate gesture: 10 update ticks then end.
        for _ in 0..<10 {
            modifier.onPinchChanged(scale: 1.15)
        }
        modifier.onPinchEnded()

        XCTAssertEqual(settings.saveCallCount, 1,
            "save must fire exactly once on gesture end regardless of update count (EC-10)")
        XCTAssertEqual(settings.lastSavedIndex, Int32(vm.fontSizeIndex),
            "saved index must match the final fontSizeIndex on the VM")
    }

    // MARK: - Test: no-save-on-cancel — seam not armed → saveCallCount == 0

    /// EC-10 neg: if the gesture ends without ever having fired `onPinchChanged`
    /// (the seam was never armed), no save must be issued.
    func test_noSaveOnCancel_seamNeverArmed() {
        let (modifier, _, settings) = makeModifier(startFontIndex: 8)

        // End without any update — seam never armed.
        modifier.onPinchEnded()

        XCTAssertEqual(settings.saveCallCount, 0,
            "no save must occur when gesture ended without being armed (EC-10 neg)")
    }

    // MARK: - Test: save preserves colorScheme (load+setFontSizeIndex pattern)

    /// The save path uses `settings.load().setFontSizeIndex(index:)` to preserve
    /// the existing `colorScheme` field.  Verify that after a pinch the saved
    /// `colorScheme` is unchanged from the pre-gesture value.
    func test_savePreservesColorScheme() {
        let mockSettings = MockSettingsRepository()
        // Pre-seed a non-default colorScheme in the mock.
        // We do this by saving an AppSettings with a custom scheme first.
        mockSettings.save(AppSettings(colorScheme: AppColorScheme.dark, fontSizeIndex: 8))
        // Reset the call count after the seed.
        mockSettings.saveCallCount = 0

        let vm = BufferViewModel(settings: mockSettings)
        vm.fontSizeIndex = 8
        let modifier = EditorPinchModifier(viewModel: vm, settings: mockSettings)

        modifier.onPinchChanged(scale: 1.15)
        modifier.onPinchEnded()

        XCTAssertEqual(settings: mockSettings,
            savedScheme: AppColorScheme.dark,
            "colorScheme must be preserved through the setFontSizeIndex path")
    }

    // MARK: - Test: clamping at upper bound (startIndex at 20, scale > 1)

    /// EC-09: clamp prevents index from exceeding 20.
    func test_clamp_upperBound() {
        let (modifier, vm, _) = makeModifier(startFontIndex: 20)

        modifier.onPinchChanged(scale: 2.0)  // large scale → delta positive but clamped to 20

        XCTAssertEqual(vm.fontSizeIndex, 20,
            "fontSizeIndex must be clamped to 20 at the upper bound (EC-09)")
    }

    // MARK: - Test: clamping at lower bound (startIndex at 0, scale < 1)

    /// EC-09: clamp prevents index from going below 0.
    func test_clamp_lowerBound() {
        let (modifier, vm, _) = makeModifier(startFontIndex: 0)

        modifier.onPinchChanged(scale: 0.5)  // shrink scale → delta negative but clamped to 0

        XCTAssertEqual(vm.fontSizeIndex, 0,
            "fontSizeIndex must be clamped to 0 at the lower bound (EC-09)")
    }

    // MARK: - Test: identity scale (scale == 1.0) → no change

    /// EC-09: scale == 1.0 produces delta 0 → fontSizeIndex unchanged.
    func test_identityScale_noChange() {
        let (modifier, vm, _) = makeModifier(startFontIndex: 10)

        modifier.onPinchChanged(scale: 1.0)

        XCTAssertEqual(vm.fontSizeIndex, 10,
            "scale == 1.0 must leave fontSizeIndex unchanged (EC-09)")
    }
}

// MARK: - Custom assertion helper

private func XCTAssertEqual(
    settings: MockSettingsRepository,
    savedScheme: AppColorScheme,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    // Load the final persisted state to read its colorScheme.
    let persisted = settings.load()
    XCTAssertTrue(persisted.colorScheme == savedScheme, message, file: file, line: line)
}
