// Chrome/MenuBubble.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph)
//
// Native iOS 26 Liquid Glass overflow menu panel.
// Morphs from the pill capsule (grows inline, ~280pt wide).
// Outside-tap dismiss via a full-screen transparent tap-catcher in
// ChromeOverlay (EC-14 write-source #2) — NOT a .popover.
//
// Morph seam (§3.1): receives `glassNamespace` and `glassID` from ChromeOverlay
// and attaches `.glassEffectID(glassID, in: glassNamespace)` to the menu panel
// so the glass system can morph the TopPill capsule into this panel and back
// inside the shared GlassEffectContainer (iOS 26 native glass morph — C-03).
//
// Layout top→bottom:
//   1. Theme picker — description-only single-select rows System/Light/Dark (CG-2)
//   2. Font-size control — [−] {n}pt [+] ; − disabled at index 0, + at index 20
//   3. Divider
//   4. About — Foglietto / Paolo Santucci / version / GPL-3.0 / issue + website links
//   5. Recovery — "Recent notes" inline expandable submenu (list + restore-on-tap)
//
// Preferences row: OMITTED by design decision. The spec states "Keep a
// 'Preferences' label row only if it has a purpose; otherwise it's acceptable
// to omit it." Since ALL settings (font + theme) live inline in this bubble,
// a separate 'Preferences' row has no target and would be a no-op affordance.
// A no-op row is worse UX than omitting it — consistent with FR-21 ("all settings
// inside the menu bubble") and the scope boundary ("no separate settings screen").
//
// CANON GAP CG-1: native Liquid Glass system material supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color @90%
// color-mix fill + hairline ring. Decision logged per spec §8 OQ-01.
//
// CANON GAP CG-2: description-only single-select theme rows supersede the
// bible §6 GNOME 3-swatch circular selector (#fff/#202020 fills + accent ring).
// Parent FR-21 mandates description-only rows for the MVP.
// Decision logged per spec §8 OQ-02.
//
// No Find entry present anywhere in this file (FR-09/FR-15).
// No #available fallback branch (min iOS 26.0 — NFR-02).
// URL literals in About are NOT localized (FR-22 / gate check 12).
//
// Input surface:
//   - menuVM: MenuViewModel    — ctor-injected, passed from ChromeOverlay
//   - isPresented: Binding<Bool> — controls presented state from ChromeOverlay
//   - glassNamespace: Namespace.ID — morph namespace from ChromeOverlay (§3.1)
//   - glassID: String           — shared glass effect ID from ChromeOverlay (§3.1)
//
// Spec refs: FR-01, FR-02, FR-09, FR-10, FR-11, FR-12, FR-13, FR-14,
//            FR-22, FR-23, NFR-01, NFR-02, NFR-04, NFR-06;
//            EC-02, EC-04, EC-05, EC-07, EC-08, EC-14, EC-16, EC-19;
//            CG-1, CG-2.
// Contract: §3.1 (morph identity seam — glassNamespace, glassID additive params).

import SwiftUI
import shared

// MARK: - MenuBubble

/// Native iOS 26 Liquid Glass overflow menu panel.
///
/// **Input surface:**
/// - `menuVM: MenuViewModel` — injected from `ChromeOverlay`; owns theme/font/recovery state.
/// - `isPresented: Binding<Bool>` — the `@State` from `ChromeOverlay`; closing the panel
///   sets this to `false`.
/// - `glassNamespace: Namespace.ID` — morph namespace from `ChromeOverlay` (§3.1 morph seam).
/// - `glassID: String` — shared glass effect ID from `ChromeOverlay` (§3.1 morph seam).
///
/// The menu panel attaches `.glassEffectID(glassID, in: glassNamespace)` so the iOS 26
/// glass system can morph the `TopPill` capsule into this panel and back inside the
/// `GlassEffectContainer` owned by `ChromeOverlay` (C-03 / NFR-01/02).
///
/// **EC-14 dismiss contract:**
/// `isPresented` is set to `false` here only by recovery-row tap (EC-15 analogue).
/// The outside-tap dismiss is handled by the full-screen tap-catcher in `ChromeOverlay`
/// (EC-14 write-source #2). No `.popover` dismiss mechanism is used.
///
/// **Glass (NFR-01/02):**
/// `.glassEffect` on the container + `.glassEffectID` for the morph + `.buttonStyle(.glass)`
/// on interactive controls. Unconditional — min iOS 26.0. No `if #available` fallback.
///
/// **Accessibility (NFR-04):**
/// Every interactive control has `.accessibilityLabel` and `.accessibilityAddTraits(.isButton)`
/// where appropriate. Touch targets ≥ 44×44 pt on button controls.
struct MenuBubble: View {

    // MARK: - Inputs

    /// The view model backing the bubble. Ctor-injected by `ChromeOverlay` (DIP).
    @Bindable var menuVM: MenuViewModel

    /// Controls the presented state of this panel. Bound from `ChromeOverlay`.
    /// Set to `false` here only by recovery-row tap; outside-tap dismiss is handled
    /// by ChromeOverlay's tap-catcher (EC-14 write-source #2).
    @Binding var isPresented: Bool

    /// The morph namespace from `ChromeOverlay` (§3.1 morph identity seam).
    /// Passed to `.glassEffectID(_:in:)` so the glass system morphs the TopPill
    /// capsule into this panel and back inside the shared GlassEffectContainer.
    let glassNamespace: Namespace.ID

    /// The shared glass effect ID from `ChromeOverlay` (§3.1 morph identity seam).
    /// Matches the ID used by `TopPill` so the two surfaces share one glass identity.
    let glassID: String

    // MARK: - Local state

    /// Whether the "Recent notes" recovery submenu section is expanded.
    @State private var isRecoveryExpanded: Bool = false

    /// The fresh `RecoveryListViewModel` for the current expansion.
    /// Created via `menuVM.makeRecoveryListViewModel()` on each expand (FR-12).
    @State private var recoveryVM: RecoveryListViewModel? = nil

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Theme picker
                themePicker

                Divider()
                    .padding(.vertical, 4)

                // 2. Font-size control
                fontSizeControl

                Divider()
                    .padding(.vertical, 4)

                // 3. About
                aboutSection

                Divider()
                    .padding(.vertical, 4)

                // 4. Recovery submenu (inline expandable — FR-12)
                recoverySection
            }
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        // Native iOS 26 Liquid Glass panel — no hand-rolled blur/fill/shadow (NFR-01/02).
        .glassEffect(in: .rect(cornerRadius: 16))
        // Morph identity: shared with TopPill inside ChromeOverlay's GlassEffectContainer
        // so the glass system morphs the capsule into this panel and back (§3.1).
        .glassEffectID(glassID, in: glassNamespace)
    }

    // MARK: - Theme picker (FR-10 / EC-08 / CG-2)

    /// Description-only single-select theme picker.
    ///
    /// Three rows: System (`.follow`), Light (`.light`), Dark (`.dark`).
    /// Each row shows the label + a one-line description + a checkmark when selected.
    /// Tap → `menuVM.selectTheme(_:)`; equal-value tap is a no-op in the VM (EC-08).
    ///
    /// CANON GAP CG-2: description-only rows supersede the bible §6 GNOME 3-swatch
    /// circular selector; the 3-swatch anatomy is discarded (CG-2 / OQ-02).
    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            themeRow(
                scheme: .follow,
                label: String(localized: "System", comment: "Theme picker row label — follow system setting (FR-23)"),
                description: String(localized: "Follows your device appearance setting.", comment: "Theme picker row description for System (FR-23)")
            )
            themeRow(
                scheme: .light,
                label: String(localized: "Light", comment: "Theme picker row label — light theme (FR-23)"),
                description: String(localized: "Always uses a light background.", comment: "Theme picker row description for Light (FR-23)")
            )
            themeRow(
                scheme: .dark,
                label: String(localized: "Dark", comment: "Theme picker row label — dark theme (FR-23)"),
                description: String(localized: "Always uses a dark background.", comment: "Theme picker row description for Dark (FR-23)")
            )
        }
    }

    /// A single description-only theme selection row.
    ///
    /// - Parameters:
    ///   - scheme: The `AppColorScheme` this row represents.
    ///   - label: The display label (e.g. "System").
    ///   - description: One-line description shown beneath the label.
    private func themeRow(
        scheme: AppColorScheme,
        label: String,
        description: String
    ) -> some View {
        Button {
            // EC-08: equal-value guard is inside MenuViewModel.selectTheme(_:) —
            // no write occurs when the user taps the already-active scheme.
            menuVM.selectTheme(scheme)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Checkmark on the currently-selected scheme (FR-10 selection state).
                if menuVM.colorScheme == scheme {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // ≥ 44pt minimum touch target height (NFR-04).
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Accessibility: full row is a button; state communicated via isSelected (NFR-04).
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(
            menuVM.colorScheme == scheme
                ? String(localized: "Selected", comment: "Accessibility selected state for theme row")
                : String(localized: "Not selected", comment: "Accessibility deselected state for theme row")
        )
    }

    // MARK: - Font-size control (FR-11 / EC-07)

    /// Inline font-size stepper: [−] {n}pt [+]
    ///
    /// `−` is disabled when `fontSizeIndex == 0`; `+` is disabled when `fontSizeIndex == 20`
    /// (EC-07 / FR-11). One slot per press through the 21-slot scale (6pt…38pt).
    private var fontSizeControl: some View {
        HStack(spacing: 0) {
            // Decrease font size button
            Button {
                menuVM.stepFontSize(by: -1)
            } label: {
                Image(systemName: "minus")
                    .imageScale(.medium)
            }
            .frame(minWidth: 44, minHeight: 44)
            // EC-07: disabled at index 0.
            .disabled(menuVM.fontSizeIndex <= 0)
            .buttonStyle(.glass)
            .accessibilityLabel(
                String(localized: "Decrease font size", comment: "Font size decrease button accessibility label (FR-23)")
            )
            .accessibilityAddTraits(.isButton)
            .help(String(localized: "Decrease font size", comment: "Font size decrease button tooltip (FR-23)"))

            Spacer()

            // {n}pt label — shows the actual point size for the current index.
            Text(
                String(
                    format: String(localized: "%d pt", comment: "Font size point label, e.g. '14 pt' (FR-23)"),
                    menuVM.fontSizePt
                )
            )
            .font(.body.monospacedDigit())
            .frame(minWidth: 60)
            .multilineTextAlignment(.center)
            .accessibilityLabel(
                String(
                    format: String(localized: "%d points", comment: "Font size label accessibility text (FR-23)"),
                    menuVM.fontSizePt
                )
            )

            Spacer()

            // Increase font size button
            Button {
                menuVM.stepFontSize(by: 1)
            } label: {
                Image(systemName: "plus")
                    .imageScale(.medium)
            }
            .frame(minWidth: 44, minHeight: 44)
            // EC-07: disabled at index 20.
            .disabled(menuVM.fontSizeIndex >= 20)
            .buttonStyle(.glass)
            .accessibilityLabel(
                String(localized: "Increase font size", comment: "Font size increase button accessibility label (FR-23)")
            )
            .accessibilityAddTraits(.isButton)
            .help(String(localized: "Increase font size", comment: "Font size increase button tooltip (FR-23)"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - About section (FR-22 / EC-19)

    /// About entry: Foglietto / Paolo Santucci / version / GPL-3.0 /
    /// issue link / website link.
    ///
    /// URL literals are NOT localized (FR-22 / gate check 12).
    /// Links open externally via `Link`/`openURL` — no `canOpenURL` pre-guard (EC-19).
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "About", comment: "About section header in the menu bubble (FR-23)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                // App name
                Text("Foglietto")
                    .font(.headline)
                    .padding(.horizontal, 16)

                // Author
                Text("Paolo Santucci")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                // Bundle short version (CFBundleShortVersionString)
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                // License
                Text("GPL-3.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                // External links — URL literals not localized (FR-22 / EC-19).
                // Opened via Link/openURL; no canOpenURL pre-guard (EC-19).
                VStack(alignment: .leading, spacing: 4) {
                    // Issue / bug report link
                    Link(
                        String(localized: "Report an issue", comment: "About section issue link label (FR-23)"),
                        destination: URL(string: "https://buffer.paolosantucci.com/bug/")!
                    )
                    .font(.subheadline)
                    .padding(.horizontal, 16)

                    // Website link
                    Link(
                        String(localized: "Website", comment: "About section website link label (FR-23)"),
                        destination: URL(string: "https://buffer.paolosantucci.com/")!
                    )
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: - Recovery submenu (FR-12 / FR-13 / FR-14 / EC-02 / EC-04 / EC-16)

    /// Inline expandable "Recent notes" recovery submenu.
    ///
    /// On expand:
    ///   1. A fresh `RecoveryListViewModel` is created via `menuVM.makeRecoveryListViewModel()`.
    ///   2. `recoveryVM.refresh()` is called immediately to re-fetch `recovery.list()` (FR-12).
    ///
    /// Rows render icon + previewTitle + dateSubtitle.
    /// Tap → `recoveryVM.select(path:)` then dismiss the panel (FR-13).
    /// Empty state renders a text message when no notes exist (EC-02 / FR-12).
    ///
    /// No delete / delete-all / confirm dialog present (FR-14).
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Expand/collapse header button
            Button {
                isRecoveryExpanded.toggle()
                if isRecoveryExpanded {
                    // FR-12: fresh instance + re-fetch on every expand.
                    let vm = menuVM.makeRecoveryListViewModel()
                    vm.refresh()
                    recoveryVM = vm
                } else {
                    recoveryVM = nil
                }
            } label: {
                HStack {
                    Text(String(localized: "Recent notes", comment: "Recovery submenu header label in the menu bubble (FR-23)"))
                        .font(.body)
                    Spacer()
                    Image(systemName: isRecoveryExpanded ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: "Recent notes", comment: "Recovery submenu accessibility label (FR-23)")
            )
            .accessibilityAddTraits(.isButton)
            .help(String(localized: "Recent notes", comment: "Recovery submenu header tooltip (FR-23)"))

            // Expanded content
            if isRecoveryExpanded, let rvm = recoveryVM {
                recoveryContent(rvm: rvm)
            }
        }
    }

    /// The expanded recovery row list or empty state.
    ///
    /// - Parameter rvm: The fresh `RecoveryListViewModel` for this expansion.
    @ViewBuilder
    private func recoveryContent(rvm: RecoveryListViewModel) -> some View {
        if rvm.rows.isEmpty {
            // EC-02: empty-recovery empty-state text (FR-12).
            Text(
                String(
                    localized: "No recent notes.",
                    comment: "Empty state text in the recovery submenu (EC-02 / FR-12 / FR-23)"
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Recovery note rows — list + restore-on-tap only (FR-14: no delete).
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rvm.rows) { row in
                    recoveryRow(row: row, rvm: rvm)
                }
            }
        }
    }

    /// A single recovery note row.
    ///
    /// Tap → `rvm.select(path:)` (nil-tolerant — EC-04) then dismiss the panel.
    ///
    /// - Parameters:
    ///   - row: The `RecoveryRow` to display.
    ///   - rvm: The `RecoveryListViewModel` to call `select(path:)` on.
    private func recoveryRow(row: RecoveryRow, rvm: RecoveryListViewModel) -> some View {
        Button {
            // FR-13: restore; nil-tolerant inside RecoveryListViewModel.select(path:) (EC-04).
            rvm.select(path: row.path)
            // Dismiss the panel after restore (EC-14 / EC-16: tap closes the menu).
            isPresented = false
        } label: {
            HStack(spacing: 12) {
                // Icon for a note (FR-12 row anatomy).
                Image(systemName: "doc.text")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.previewTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(row.dateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(
                    localized: "Restore note: %@, saved %@",
                    comment: "Recovery row accessibility label: restore note title and date (FR-23)"
                ),
                row.previewTitle,
                row.dateSubtitle
            )
        )
        .accessibilityAddTraits(.isButton)
        .help(
            String(
                localized: "Restore this note",
                comment: "Recovery row tooltip (FR-23)"
            )
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MenuBubble") {
    // Preview requires stub dependencies — not wired to real DI in preview.
    // ChromeOverlay wires the real instances from iosAppApp.init().
    Color.clear
        .overlay(
            Text("Preview requires live DI wiring — see ChromeOverlay.")
                .font(.caption)
                .foregroundStyle(.secondary)
        )
        .frame(width: 280, height: 400)
}
#endif
