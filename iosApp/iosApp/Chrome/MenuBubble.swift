// Chrome/MenuBubble.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle (T-04)
//
// Native iOS 26 Liquid Glass overflow menu panel, restyled to match
// Apple Notes' iOS-26 menu visual language.
// Morphs from the pill capsule (grows inline, ChromeMetrics.menuPanelWidth pt).
// Outside-tap dismiss via a full-screen transparent tap-catcher in
// ChromeOverlay (EC-14 write-source #2) — NOT a .popover.
//
// Morph seam (§3.1 rc18): receives `glassNamespace` and `glassID` from ChromeOverlay
// and attaches `.glassEffectID(glassID, in: glassNamespace)` to the menu panel
// so the glass system can morph the overflow `…` capsule into this panel and back
// inside the shared GlassEffectContainer (iOS 26 native glass morph — C-03).
// Morph source is the overflow button in ChromeOverlay; Share persists separately.
//
// Row crossfade (T-04): inner menu rows carry `.transition(.opacity)` so they
// fade in mid-stretch during the morph. The PANEL CONTAINER does NOT carry an
// explicit transition — geometry is owned by `.glassEffectID` (C-04).
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
// Style tokens: ChromeMetrics.menuPanelWidth / menuPanelCornerRadius /
// menuRowVerticalPadding / menuRowHorizontalPadding / menuRowSpacing /
// iconScaleWeight (Apple-Notes look — qp-20260622 §3.1 / C-02).
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
// Contract: §3.1 (morph identity seam — glassNamespace, glassID additive params;
//            ChromeMetrics tokens — menuPanelWidth, menuPanelCornerRadius,
//            menuRowVerticalPadding, menuRowHorizontalPadding, menuRowSpacing,
//            iconScaleWeight).

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
/// - `dismissAnimation: Animation?` — the resolved close spring from `ChromeOverlay` (C-05/C-06).
///   Used by recovery-row dismiss so closing from a row tap morphs smoothly (same spring as the
///   tap-catcher). `nil` under Reduce Motion.
///
/// The menu panel attaches `.glassEffectID(glassID, in: glassNamespace)` so the iOS 26
/// glass system can morph the overflow `…` button (in `ChromeOverlay`) into this panel
/// and back inside the `GlassEffectContainer` owned by `ChromeOverlay` (C-03 / NFR-01/02).
/// As of rc18, the morph source is the overflow button in `ChromeOverlay` — not `TopPill`.
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
    /// Matches the ID used by the overflow button so the two surfaces share one glass identity.
    let glassID: String

    /// The resolved close animation from `ChromeOverlay` (§3.1 animation seam — C-05/C-06).
    /// Used by recovery-row dismiss so closing from a row tap morphs smoothly (same spring
    /// as the tap-catcher dismiss). `nil` under Reduce Motion (instantaneous close).
    let dismissAnimation: Animation?

    // MARK: - Local state

    /// Whether the "Recent notes" recovery submenu section is expanded.
    @State private var isRecoveryExpanded: Bool = false

    /// The fresh `RecoveryListViewModel` for the current expansion.
    /// Created via `menuVM.makeRecoveryListViewModel()` on each expand (FR-12).
    @State private var recoveryVM: RecoveryListViewModel? = nil

    // MARK: - Body

    var body: some View {
        ScrollView {
            // Inner rows carry .transition(.opacity) so they fade in mid-stretch
            // during the capsule→panel morph. The panel container itself does NOT
            // carry a transition — geometry is owned by .glassEffectID (C-04 / T-04).
            VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                // 1. Theme picker
                themePicker
                    .transition(.opacity)

                menuDivider

                // 2. Font-size control
                fontSizeControl
                    .transition(.opacity)

                menuDivider

                // 3. About
                aboutSection
                    .transition(.opacity)

                menuDivider

                // 4. Recovery submenu (inline expandable — FR-12)
                recoverySection
                    .transition(.opacity)
            }
            .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
        }
        .frame(width: ChromeMetrics.menuPanelWidth)
        // Native iOS 26 Liquid Glass panel — no hand-rolled blur/fill/shadow (NFR-01/02).
        // Corner radius from ChromeMetrics.menuPanelCornerRadius (Apple-Notes look).
        .glassEffect(in: .rect(cornerRadius: ChromeMetrics.menuPanelCornerRadius))
        // Morph identity: shared with the overflow button (rc18: in ChromeOverlay, not TopPill)
        // inside ChromeOverlay's GlassEffectContainer. The glass system morphs the overflow
        // capsule into this panel and back (§3.1). ChromeOverlay adds .transition(.identity)
        // on the MenuBubble insertion — geometry morph is driven by glassEffectID (C-04).
        .glassEffectID(glassID, in: glassNamespace)
    }

    /// A styled divider row between menu sections.
    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            .transition(.opacity)
    }

    // MARK: - Theme picker (FR-10 / EC-08 / CG-2)

    /// Description-only single-select theme picker.
    ///
    /// Three rows: System (`.follow`), Light (`.light`), Dark (`.dark`).
    /// Each row shows a leading icon + label + description + checkmark when selected.
    /// Apple Notes style: leading SF Symbol icon, label+description stacked left,
    /// checkmark trailing. Tap → `menuVM.selectTheme(_:)`; equal-value tap is a
    /// no-op in the VM (EC-08).
    ///
    /// CANON GAP CG-2: description-only rows supersede the bible §6 GNOME 3-swatch
    /// circular selector; the 3-swatch anatomy is discarded (CG-2 / OQ-02).
    private var themePicker: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            themeRow(
                scheme: .follow,
                icon: "circle.lefthalf.filled",
                label: String(localized: "System", comment: "Theme picker row label — follow system setting (FR-23)"),
                description: String(localized: "Follows your device appearance setting.", comment: "Theme picker row description for System (FR-23)")
            )
            themeRow(
                scheme: .light,
                icon: "sun.max",
                label: String(localized: "Light", comment: "Theme picker row label — light theme (FR-23)"),
                description: String(localized: "Always uses a light background.", comment: "Theme picker row description for Light (FR-23)")
            )
            themeRow(
                scheme: .dark,
                icon: "moon",
                label: String(localized: "Dark", comment: "Theme picker row label — dark theme (FR-23)"),
                description: String(localized: "Always uses a dark background.", comment: "Theme picker row description for Dark (FR-23)")
            )
        }
    }

    /// A single description-only theme selection row (Apple Notes style).
    ///
    /// - Parameters:
    ///   - scheme: The `AppColorScheme` this row represents.
    ///   - icon: SF Symbol name for the leading icon.
    ///   - label: The display label (e.g. "System").
    ///   - description: One-line description shown beneath the label.
    private func themeRow(
        scheme: AppColorScheme,
        icon: String,
        label: String,
        description: String
    ) -> some View {
        Button {
            // EC-08: equal-value guard is inside MenuViewModel.selectTheme(_:) —
            // no write occurs when the user taps the already-active scheme.
            menuVM.selectTheme(scheme)
        } label: {
            HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                // Leading SF Symbol icon (Apple Notes look — iconScaleWeight = .medium).
                Image(systemName: icon)
                    .font(.body.weight(ChromeMetrics.iconScaleWeight))
                    .imageScale(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
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
                        .font(.body.weight(ChromeMetrics.iconScaleWeight))
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
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

    /// Inline font-size stepper: leading icon + [−] {n}pt [+] (Apple Notes style).
    ///
    /// `−` is disabled when `fontSizeIndex == 0`; `+` is disabled when `fontSizeIndex == 20`
    /// (EC-07 / FR-11). One slot per press through the 21-slot scale (6pt…38pt).
    private var fontSizeControl: some View {
        HStack(spacing: ChromeMetrics.menuRowHorizontalPadding) {
            // Leading SF Symbol icon (Apple Notes look — iconScaleWeight = .medium).
            Image(systemName: "textformat.size")
                .font(.body.weight(ChromeMetrics.iconScaleWeight))
                .imageScale(.medium)
                .foregroundStyle(.primary)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            // Decrease font size button
            Button {
                menuVM.stepFontSize(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(ChromeMetrics.iconScaleWeight))
                    .imageScale(.medium)
            }
            .frame(minWidth: 44, minHeight: 44)
            // EC-07: disabled at index 0.
            .disabled(menuVM.fontSizeIndex <= 0)
            // Plain: the panel (.glassEffect on the ScrollView) is the single glass
            // surface bearing the morph ID. Nested `.glass` button shapes inside the
            // same GlassEffectContainer would metaball-merge with the panel and
            // corrupt the capsule↔panel morph.
            .buttonStyle(.plain)
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
                    .font(.body.weight(ChromeMetrics.iconScaleWeight))
                    .imageScale(.medium)
            }
            .frame(minWidth: 44, minHeight: 44)
            // EC-07: disabled at index 20.
            .disabled(menuVM.fontSizeIndex >= 20)
            // Plain: see the decrease button — keep the panel a single glass shape
            // so the morph isn't corrupted by nested glass inside the container.
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .help(String(localized: "Increase font size", comment: "Font size increase button tooltip (FR-23)"))
        }
        .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
    }

    // MARK: - About section (FR-22 / EC-19)

    /// About entry: Foglietto / Paolo Santucci / version / GPL-3.0 /
    /// issue link / website link. Apple Notes style: section header, then
    /// content rows with leading icons.
    ///
    /// URL literals are NOT localized (FR-22 / gate check 12).
    /// Links open externally via `Link`/`openURL` — no `canOpenURL` pre-guard (EC-19).
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            // Section header
            Text(String(localized: "About", comment: "About section header in the menu bubble (FR-23)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                .padding(.top, ChromeMetrics.menuRowSpacing)

            VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                // App name + author row (Apple Notes: name prominent, author secondary)
                HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                    Image(systemName: "app")
                        .font(.body.weight(ChromeMetrics.iconScaleWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.primary)
                        .frame(width: 24, alignment: .center)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                        Text("Foglietto")
                            .font(.headline)
                        Text("Paolo Santucci")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Version + license stacked trailing
                    VStack(alignment: .trailing, spacing: ChromeMetrics.menuRowSpacing) {
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text(version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("GPL-3.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
                .frame(minHeight: 44)
                .contentShape(Rectangle())

                // External links — URL literals not localized (FR-22 / EC-19).
                // Opened via Link/openURL; no canOpenURL pre-guard (EC-19).

                // Issue / bug report link row
                HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.body.weight(ChromeMetrics.iconScaleWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.primary)
                        .frame(width: 24, alignment: .center)
                        .accessibilityHidden(true)
                    Link(
                        String(localized: "Report an issue", comment: "About section issue link label (FR-23)"),
                        destination: URL(string: "https://buffer.paolosantucci.com/bug/")!
                    )
                    .font(.body)
                    Spacer()
                }
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
                .frame(minHeight: 44)

                // Website link row
                HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                    Image(systemName: "globe")
                        .font(.body.weight(ChromeMetrics.iconScaleWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.primary)
                        .frame(width: 24, alignment: .center)
                        .accessibilityHidden(true)
                    Link(
                        String(localized: "Website", comment: "About section website link label (FR-23)"),
                        destination: URL(string: "https://buffer.paolosantucci.com/")!
                    )
                    .font(.body)
                    Spacer()
                }
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: - Recovery submenu (FR-12 / FR-13 / FR-14 / EC-02 / EC-04 / EC-16)

    /// Inline expandable "Recent notes" recovery submenu (Apple Notes style).
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
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            // Expand/collapse header button (Apple Notes style: leading icon + label)
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
                HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.body.weight(ChromeMetrics.iconScaleWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.primary)
                        .frame(width: 24, alignment: .center)
                        .accessibilityHidden(true)
                    Text(String(localized: "Recent notes", comment: "Recovery submenu header label in the menu bubble (FR-23)"))
                        .font(.body)
                    Spacer()
                    Image(systemName: isRecoveryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(ChromeMetrics.iconScaleWeight))
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
                .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
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
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Recovery note rows — list + restore-on-tap only (FR-14: no delete).
            VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                ForEach(rvm.rows) { row in
                    recoveryRow(row: row, rvm: rvm)
                }
            }
        }
    }

    /// A single recovery note row (Apple Notes style: leading icon, title+date stacked).
    ///
    /// Tap → `rvm.select(path:)` (nil-tolerant — EC-04) then dismiss the panel via
    /// `withAnimation(dismissAnimation)` so the close morphs smoothly (same spring as
    /// the tap-catcher dismiss — C-05/C-06).
    ///
    /// - Parameters:
    ///   - row: The `RecoveryRow` to display.
    ///   - rvm: The `RecoveryListViewModel` to call `select(path:)` on.
    private func recoveryRow(row: RecoveryRow, rvm: RecoveryListViewModel) -> some View {
        Button {
            // FR-13: restore; nil-tolerant inside RecoveryListViewModel.select(path:) (EC-04).
            rvm.select(path: row.path)
            // Dismiss the panel with the same morph spring as the tap-catcher (C-05/C-06).
            // Without withAnimation(dismissAnimation) the close would snap instead of morphing.
            withAnimation(dismissAnimation) {
                isPresented = false
            }
        } label: {
            HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                // Icon for a note (FR-12 row anatomy — Apple Notes look).
                Image(systemName: "doc.text")
                    .font(.body.weight(ChromeMetrics.iconScaleWeight))
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                    Text(row.previewTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(row.dateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
            .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
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
