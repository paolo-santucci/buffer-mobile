import SwiftUI
import shared

// ThemeColorScheme.swift — M6 (FR-23) theme-application contract.
//
// QP §3.1 contract. The single mapping from the shared, platform-neutral
// `AppColorScheme` setting (System / Light / Dark) to a SwiftUI `ColorScheme?`
// that can be fed to `.preferredColorScheme(_:)`.
//
// `nil` means "inherit the device trait" — used for `.follow` (System).
//
// IMPORTANT: `AppColorScheme` is a Kotlin-bridged enum (non-frozen across the
// KMP boundary), so the `@unknown default` case is REQUIRED for the switch to
// compile under Swift 6 strict mode. It maps to `nil` (System) — the safest
// fallback if the shared enum ever gains a case the Swift side has not learned.
extension AppColorScheme {
    /// SwiftUI color scheme to drive `.preferredColorScheme(_:)`.
    /// `.follow` → `nil` (inherit device); `.light` → `.light`; `.dark` → `.dark`.
    var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .follow: return nil       // System — inherit the device trait.
        case .light:  return .light
        case .dark:   return .dark
        @unknown default: return nil   // Non-frozen KMP enum — default REQUIRED to compile.
        }
    }
}
