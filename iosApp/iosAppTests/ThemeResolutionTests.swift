// ThemeResolutionTests.swift
// iosAppTests
//
// Unit tests for `AppColorScheme.swiftUIColorScheme` — the M6 (FR-23) mapping
// from the shared KMP enum to a SwiftUI `ColorScheme?` value.
//
// Strategy:
//   `swiftUIColorScheme` is a pure value mapping with no side-effects or async
//   operations; these tests drive it directly as plain XCTest assertions.
//   No spy or stub needed — the extension operates on the KMP enum alone.
//
// Stub naming:
//   No helpers or spies in this file (pure enum extension test).
//   If additional spy infrastructure is added in future, name it
//   `ThemeResolutionSpy*` to avoid any collision with other test files
//   (M3 dup-stub CI-red lesson / C-08).
//
// M3 CI conventions (MANDATORY):
//   @MainActor at class level — consistent with tests that touch @MainActor types;
//   also required if this class is ever extended to test the ContentView modifier.
//   import shared + @testable import iosApp.
//
// Spec refs: FR-23; QP §3.1 contract; C-04 (@unknown default), C-05, C-08.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import XCTest
import SwiftUI
@testable import iosApp
import shared

// ---------------------------------------------------------------------------
// MARK: - ThemeResolutionTests
// ---------------------------------------------------------------------------

/// Tests for `AppColorScheme.swiftUIColorScheme` — the QP §3.1 contract extension.
///
/// Verifies that all three cases of the shared KMP `AppColorScheme` enum map
/// to the expected `ColorScheme?` value:
///   - `.follow` → `nil`   (inherit device — System)
///   - `.light`  → `.light`
///   - `.dark`   → `.dark`
///
/// `@MainActor`: applied at class level per M3 CI-red lesson (C-08).
/// `AppColorScheme` is a KMP-bridged enum; the `@unknown default` branch in
/// `swiftUIColorScheme` is required for Swift 6 compilation (C-04) and is
/// implicitly exercised if the shared framework ever adds a new case.
@MainActor
final class ThemeResolutionTests: XCTestCase {

    // -----------------------------------------------------------------------
    // MARK: - swiftUIColorScheme — three-case mapping (FR-23 / §3.1)
    // -----------------------------------------------------------------------

    /// All three `AppColorScheme` cases must map to the specified `ColorScheme?`.
    ///
    /// This is the authoritative CI gate for the §3.1 contract:
    ///   `.follow` → `nil`, `.light` → `.light`, `.dark` → `.dark`.
    ///
    /// If the KMP `AppColorScheme` enum gains a new case, the `@unknown default`
    /// branch in `swiftUIColorScheme` returns `nil` (System fallback), which is
    /// the safe and deliberate behaviour per C-04.
    func test_swiftUIColorScheme_mapsAllThreeCases() {
        XCTAssertNil(
            AppColorScheme.follow.swiftUIColorScheme,
            ".follow must map to nil (inherit device / System)"
        )
        XCTAssertEqual(
            AppColorScheme.light.swiftUIColorScheme,
            .light,
            ".light must map to ColorScheme.light"
        )
        XCTAssertEqual(
            AppColorScheme.dark.swiftUIColorScheme,
            .dark,
            ".dark must map to ColorScheme.dark"
        )
    }
}
