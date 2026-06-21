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
// IMPORTANT: with no SKIE bridge, the Kotlin `AppColorScheme` enum is exported
// through standard Kotlin/Native Obj-C interop as a Swift *class* (not a Swift
// enum). `case .follow:` etc. are therefore expression patterns matched via `==`
// on the bridged singletons, so this is a non-enum switch: it needs a plain
// `default:` (an `@unknown default:` is only valid on enum switches and fails to
// compile here). The `default` maps to `nil` (System) — the safest fallback if
// the shared enum ever gains a case the Swift side has not learned.
extension AppColorScheme {
    /// SwiftUI color scheme to drive `.preferredColorScheme(_:)`.
    /// `.follow` → `nil` (inherit device); `.light` → `.light`; `.dark` → `.dark`.
    var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .follow: return nil       // System — inherit the device trait.
        case .light:  return .light
        case .dark:   return .dark
        default:      return nil       // Bridged Obj-C class → plain default required.
        }
    }
}
