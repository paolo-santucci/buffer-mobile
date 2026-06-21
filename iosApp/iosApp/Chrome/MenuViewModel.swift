// Chrome/MenuViewModel.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome
//
// @Observable view model backing the menu bubble. Ctor-injected (DIP, no
// provider indirection). Owns theme selection, font-size stepping, and
// fresh RecoveryListViewModel creation on each submenu expand.
//
// CANON GAP CG-1: native Liquid Glass system material supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color @90%
// color-mix fill + hairline ring. Decision logged per spec §8 OQ-01.
//
// CANON GAP CG-2: description-only single-select theme rows supersede the
// bible §6 GNOME 3-swatch circular selector (#fff/#202020 fills + accent
// ring). Parent FR-21 mandates description-only rows for the MVP.
// Decision logged per spec §8 OQ-02.
//
// Spec refs: FR-03, FR-10, FR-11, FR-12, FR-23, NFR-05, NFR-06;
//            EC-07, EC-08, EC-10; CG-1, CG-2.
// Contract: §5.1.d.

import Observation
import shared

// MARK: - MenuViewModel

/// `@Observable` view model backing `MenuBubble`.
///
/// Ctor-injected with the three dependencies it needs (DIP — concretes wired
/// at the composition root in `iosAppApp.init()`; no provider or singleton
/// access inside this class):
///   - `settings: SettingsRepository` — the **single** shared settings store (CM-1/FR-03).
///   - `recovery: RecoveryRepository` — for passing to fresh `RecoveryListViewModel` instances.
///   - `viewModel: BufferViewModel` — for passing to fresh `RecoveryListViewModel` instances.
///
/// **Theme selection (FR-10/EC-08):**
/// `selectTheme(_:)` calls `settings.save(settings.load().setColorScheme(scheme))`.
/// The shared `setColorScheme` is identity-stable: equal-valued input returns the
/// same (equal) `AppSettings` instance. A prior load-compare guard ensures `save`
/// is only called when the scheme actually changes (EC-08 no-write-on-equal).
///
/// **Font stepping (FR-11/EC-07):**
/// `stepFontSize(by:)` loads, clamps `fontSizeIndex + delta` to `0...20`, then
/// saves only when the result differs from the current index (EC-07 no-write-at-clamp-end).
///
/// **Fresh RecoveryListViewModel (FR-12):**
/// `makeRecoveryListViewModel()` returns a NEW `RecoveryListViewModel` on every call,
/// so each submenu expand re-fetches `recovery.list()` fresh (never launch-cached).
@Observable
final class MenuViewModel {

    // MARK: - Injected dependencies (DIP)

    private let settings: SettingsRepository
    private let recovery: RecoveryRepository
    private let bufferViewModel: BufferViewModel

    // MARK: - Observable state (mirrored from settings store)

    /// Current `AppColorScheme` — refreshed from the store on every
    /// `selectTheme` call so the theme picker row reflects the active selection.
    private(set) var colorScheme: AppColorScheme

    /// Current font-size index in `[0, 20]` — refreshed on every `stepFontSize` call
    /// so the `{n}pt` label and `−`/`+` disabled states stay in sync.
    private(set) var fontSizeIndex: Int

    // MARK: - Init

    /// Designated initialiser — DIP: all concrete dependencies wired by the caller.
    ///
    /// Initial `colorScheme` and `fontSizeIndex` are loaded from `settings` once here
    /// so the bubble's rendering state is immediately accurate without an extra
    /// call to `refresh()`. Subsequent writes propagate through `selectTheme` and
    /// `stepFontSize` which also update the mirrors.
    ///
    /// - Parameters:
    ///   - settings: The single shared `SettingsRepository` instance (CM-1/FR-03).
    ///   - recovery: The shared `RecoveryRepository` instance (CM-3/FR-05).
    ///   - viewModel: The shared `BufferViewModel` instance.
    init(settings: SettingsRepository, recovery: RecoveryRepository, viewModel: BufferViewModel) {
        self.settings = settings
        self.recovery = recovery
        self.bufferViewModel = viewModel

        let loaded = settings.load()
        self.colorScheme  = loaded.colorScheme
        // Int32 → Int at the call site (shared API is Int32; Swift mirror is Int).
        self.fontSizeIndex = Int(loaded.fontSizeIndex)
    }

    // MARK: - Theme selection (FR-10 / EC-08)

    /// Select a theme scheme.
    ///
    /// Calls `settings.save(settings.load().setColorScheme(scheme))`.
    ///
    /// **Equal-value no-op (EC-08 / FR-10):** The shared `setColorScheme` is
    /// identity-stable — it returns the same `AppSettings` instance when the
    /// scheme is already equal. A prior guard compares the loaded scheme to `scheme`
    /// before calling `save`, ensuring no write occurs when the user re-taps the
    /// active row. This is the picker's no-write guarantee.
    ///
    /// - Parameter scheme: The `AppColorScheme` the user selected.
    func selectTheme(_ scheme: AppColorScheme) {
        let current = settings.load()
        // EC-08: equal-value guard — no write when scheme is already active.
        if current.colorScheme == scheme { return }
        settings.save(settings: current.setColorScheme(scheme: scheme))
        colorScheme = scheme
    }

    // MARK: - Font-size stepping (FR-11 / EC-07)

    /// Step the font-size index by `delta` (+1 or −1).
    ///
    /// Clamps the resulting index to `0...20` (the 21-slot scale). When the
    /// current index is already at the clamp end (`0` for `delta < 0`, `20` for
    /// `delta > 0`), the button is disabled in the UI (EC-07 / FR-11), so this
    /// method would not be called. But the no-op guard here is a defence-in-depth
    /// belt-and-suspenders: if `delta == 0` or the clamped value equals the current
    /// index, no write is emitted.
    ///
    /// - Parameter delta: `+1` (increase) or `−1` (decrease).
    func stepFontSize(by delta: Int) {
        let current = settings.load()
        let currentIndex = Int(current.fontSizeIndex)
        let clamped = max(0, min(20, currentIndex + delta))
        // EC-07: no-op when already at clamp end (or delta == 0).
        guard clamped != currentIndex else { return }
        settings.save(settings: current.setFontSizeIndex(index: Int32(clamped)))
        fontSizeIndex = clamped
    }

    // MARK: - Fresh RecoveryListViewModel factory (FR-12)

    /// Returns a **fresh** `RecoveryListViewModel` on every call.
    ///
    /// TASK-11 / `MenuBubble` calls this when the "Recent notes" submenu is expanded.
    /// A fresh instance is returned (never cached from the previous expand) so that
    /// `refresh()` re-fetches `recovery.list()` from the current on-disk state.
    /// Caching would violate FR-12 ("re-fetches on every expand").
    ///
    /// - Returns: A new `RecoveryListViewModel` ready to have `refresh()` called on it.
    func makeRecoveryListViewModel() -> RecoveryListViewModel {
        RecoveryListViewModel(recovery: recovery, viewModel: bufferViewModel)
    }

    // MARK: - Font-size point value (for the {n}pt label — FR-11 / FR-23)

    /// The font-size in points corresponding to the current `fontSizeIndex`.
    ///
    /// Reads `fontSizePt` from the loaded `AppSettings` computed property.
    /// This drives the `{n}pt` label in the font-size control (FR-11 / FR-23).
    ///
    /// Computed each time from the live settings to stay in sync with
    /// both the stepper and any pinch-zoom changes that happened
    /// while the bubble was open (EC-10 single source of truth).
    var fontSizePt: Int {
        Int(settings.load().fontSizePt)
    }
}
