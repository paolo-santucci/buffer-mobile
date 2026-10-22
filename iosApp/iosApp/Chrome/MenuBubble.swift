// Chrome/MenuBubble.swift
// Foglietto — Apple-Notes (iOS 26) Chrome Restyle
//
// Native iOS 26 Liquid Glass overflow menu panel, restyled to match
// Apple Notes' iOS-26 menu visual language.
// Morphs from the chrome pill (grows inline, ChromeMetrics.menuPanelWidth pt).
// Outside-tap dismiss via a full-screen transparent tap-catcher in
// ChromeOverlay (EC-14 write-source 2) — NOT a .popover.
//
// Morph seam: receives `glassNamespace` and `glassID` from ChromeOverlay and attaches
// `.glassEffectID(glassID, in: glassNamespace)` to the menu panel so the glass system
// can morph the pill capsule into this panel and back inside the shared
// GlassEffectContainer (iOS 26 native glass morph — C-03).
//
// Single glass surface (FR-05): the panel container carries the file's ONLY
// `.glassEffect` + `.glassEffectID`. Every tappable element inside it — the Share row,
// theme rows, font +/-, About links, recovery header and rows — is `.buttonStyle(.plain)`:
// a nested glass shape inside the same GlassEffectContainer metaball-merges with the
// panel and corrupts the pill↔panel morph (§4.4 prohibited topologies).
//
// No transitions inside the panel: the container child's own insertion crossfade already
// fades the whole panel in mid-stretch, and per-row fades compound with it into a second,
// competing appear/disappear over the morph (rc22 D1). Geometry is owned by `.glassEffectID`.
//
// Layout top→bottom:
//   1. Share row — plain ShareLink over the live buffer text (FR-04)
//   2. Divider
//   3. Theme picker — description-only single-select rows System/Light/Dark (CG-2)
//   4. Divider
//   5. Font-size control — [−] {n}pt [+] ; − disabled at index 0, + at index 20
//   6. Divider
//   7. About — Foglietto / Paolo Santucci / version / GPL-3.0 / issue + website links
//   8. Divider
//   9. Recovery — "Recent notes" inline expandable submenu (list + restore-on-tap)
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
// iconScaleWeight / submenuExpandAnimation (Apple-Notes look — C-02).
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
// Input surface (§5.1.b):
//   - menuVM: MenuViewModel       — ctor-injected, passed from ChromeOverlay
//   - isPresented: Binding<Bool>  — presented state owned by ChromeOverlay
//   - glassNamespace: Namespace.ID — morph namespace from ChromeOverlay
//   - glassID: String             — shared glass effect ID from ChromeOverlay
//   - dismissAnimation: Animation? — resolved close spring from ChromeOverlay
//   - text: String                — buffer text for the Share row's ShareLink (FR-04)
//   - isShareDisabled: Bool       — the single trimmed-empty predicate, derived in ChromeOverlay
//
// EC-14 writers inside this file: write-source 3 (recovery-row dismiss) and
// write-source 4 (Share-row dismiss, guarded by !isShareDisabled). Write-sources 1
// (overflow toggle), 2 (tap-catcher) and 5 (chrome-hide dismissal) live in
// ChromeOverlay; SM events and MenuViewModel NEVER mutate isPresented.
//
// Spec refs: FR-04, FR-05, FR-08, FR-15, FR-16, FR-17, FR-18, FR-21, FR-23, FR-25;
//            NFR-02, NFR-04, NFR-07; EC-01, EC-02, EC-07, EC-08, EC-14, EC-15, EC-19, EC-21;
//            CG-1, CG-2.
// Contract: §5.1.b (additive inputs, Share row, section extraction).

import SwiftUI
import shared

// MARK: - MenuBubble

/// Native iOS 26 Liquid Glass overflow menu panel.
///
/// **Input surface (§5.1.b):**
/// - `menuVM: MenuViewModel` — injected from `ChromeOverlay`; owns theme/font/recovery state.
/// - `isPresented: Binding<Bool>` — the `@State` from `ChromeOverlay`; closing the panel
///   sets this to `false` (write-sources 3 and 4).
/// - `glassNamespace: Namespace.ID` — morph namespace from `ChromeOverlay`.
/// - `glassID: String` — shared glass effect ID from `ChromeOverlay`.
/// - `dismissAnimation: Animation?` — the resolved close spring from `ChromeOverlay`.
///   Used by row dismissals so closing from a row tap morphs smoothly (same spring as the
///   tap-catcher). `nil` under Reduce Motion.
/// - `text: String` — buffer text handed to the Share row's `ShareLink` (FR-04).
/// - `isShareDisabled: Bool` — the single empty-buffer predicate derived in `ChromeOverlay`;
///   the Share row shares and dismisses only when it is `false` (EC-01).
///
/// The panel attaches `.glassEffectID(glassID, in: glassNamespace)` so the iOS 26 glass
/// system morphs the pill capsule into this panel and back inside the
/// `GlassEffectContainer` owned by `ChromeOverlay` (C-03 / NFR-01/02).
///
/// **EC-14 dismiss contract:**
/// `isPresented` is set to `false` here only by the recovery-row tap (write-source 3) and
/// the Share-row tap (write-source 4). Outside-tap dismissal is handled by the full-screen
/// tap-catcher in `ChromeOverlay` (write-source 2). No `.popover` dismiss mechanism is used.
///
/// **Glass (NFR-01/FR-05):**
/// `.glassEffect` on the container + `.glassEffectID` for the morph; every row inside stays
/// `.buttonStyle(.plain)`. Unconditional — min iOS 26.0, no availability fallback branch.
///
/// **Accessibility (NFR-04):**
/// Every interactive control has `.accessibilityLabel` and `.accessibilityAddTraits(.isButton)`
/// where appropriate. Touch targets ≥ 44×44 pt on button controls.
struct MenuBubble: View {

    // MARK: - Inputs

    /// The view model backing the bubble. Ctor-injected by `ChromeOverlay` (DIP).
    @Bindable var menuVM: MenuViewModel

    /// Controls the presented state of this panel. Bound from `ChromeOverlay`.
    /// Set to `false` here only by the recovery-row tap (write-source 3) and the
    /// Share-row tap (write-source 4); outside-tap dismiss is handled by
    /// ChromeOverlay's tap-catcher (write-source 2).
    @Binding var isPresented: Bool

    /// The morph namespace from `ChromeOverlay` (§3.1 morph identity seam).
    /// Passed to `.glassEffectID(_:in:)` so the glass system morphs the pill
    /// capsule into this panel and back inside the shared GlassEffectContainer.
    let glassNamespace: Namespace.ID

    /// The shared glass effect ID from `ChromeOverlay` (§3.1 morph identity seam).
    /// Matches the ID used by the closed-state pill so the two surfaces share one glass identity.
    let glassID: String

    /// The resolved close animation from `ChromeOverlay` (animation seam — C-05/C-06).
    /// Used by row dismissals so closing from a row tap morphs smoothly (same spring
    /// as the tap-catcher dismiss). `nil` under Reduce Motion (instantaneous close).
    let dismissAnimation: Animation?

    /// Current buffer text — the Share row's `ShareLink` payload (FR-04).
    let text: String

    /// `true` when the buffer is empty, so the Share row must not share (EC-01/FR-08).
    /// Derived once in `ChromeOverlay`; the panel never re-derives it, so the pill's
    /// gate and the panel's gate can never diverge.
    let isShareDisabled: Bool

    // MARK: - Body

    var body: some View {
        // Content-hugging panel: the glass shape follows the rows it hosts, so
        // the morph target is the menu itself — never a screen-height surface
        // over a blank editor (where glass is white-on-white invisible). The
        // recovery row list below stays bounded by ViewThatFits + a scroll cap.
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            // Rows carry no transitions of their own — the panel is one glass entity whose
            // insertion crossfade fades its whole content in (demo parity; rc22 D1).
            // 1. Share row (FR-04) — first row, followed by a divider.
            shareRow

            menuDivider

            // 2. Theme picker
            themePicker

            menuDivider

            // 3. Font-size control
            fontSizeControl

            menuDivider

            // 4. About
            AboutSection()

            menuDivider

            // 5. Recovery submenu (inline expandable — FR-18)
            RecoverySection(
                menuVM: menuVM,
                isPresented: $isPresented,
                dismissAnimation: dismissAnimation
            )
        }
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
        .frame(width: ChromeMetrics.menuPanelWidth)
        // Native iOS 26 Liquid Glass panel — no hand-rolled blur/fill/shadow (NFR-01/02).
        // Corner radius from ChromeMetrics.menuPanelCornerRadius (Apple-Notes look).
        .glassEffect(in: .rect(cornerRadius: ChromeMetrics.menuPanelCornerRadius))
        .glassEffectTransition(.matchedGeometry)
        // Geometry morph is owned by .glassEffectID; the container's XOR children
        // carry NO .transition modifiers (an explicit .identity kills the morph —
        // rc21) and neither does any row inside this panel (rc22 D1).
        .glassEffectID(glassID, in: glassNamespace)
    }

    /// A styled divider row between menu sections.
    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
    }

    // MARK: - Share row (FR-04 / FR-05 / EC-01 / EC-21)

    /// The panel's first row: a plain `ShareLink` over the live buffer text.
    ///
    /// One frozen share action with two renderings — the closed pill's button and this
    /// row — read the same `text` behind the same `isShareDisabled` predicate (FR-04).
    ///
    /// `ShareLink` exposes no action closure, so the write-source 4 dismissal rides a
    /// `.simultaneousGesture` `TapGesture`: the system share activation and the panel close
    /// fire from the same tap, under `dismissAnimation` (the same spring as every other
    /// dismiss — C-05/C-06).
    ///
    /// EC-21: the sheet anchors to the scene's presenting controller, not to this subtree,
    /// so it survives the panel→pill morph-back.
    private var shareRow: some View {
        ShareLink(item: text) {
            MenuRow(
                icon: "square.and.arrow.up",
                label: String(localized: "Share", comment: "Share button accessibility label in the top pill")
            )
        }
        .buttonStyle(.plain)
        // EC-01: empty buffer → no sheet presented.
        .disabled(isShareDisabled)
        .simultaneousGesture(TapGesture().onEnded {
            // Write-source 4: a disabled row neither shares nor dismisses.
            guard !isShareDisabled else { return }
            withAnimation(dismissAnimation) {
                isPresented = false
            }
        })
        .accessibilityLabel(
            String(localized: "Share", comment: "Share button accessibility label in the top pill")
        )
        .help(
            String(localized: "Share text", comment: "Share button tooltip in the top pill (FR-23)")
        )
    }

    // MARK: - Theme picker (FR-15 / FR-16 / EC-08 / CG-2)

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
            MenuRow(icon: icon, label: label, description: description) {
                AnyView(
                    Group {
                        // Checkmark on the currently-selected scheme (FR-15 selection state).
                        if menuVM.colorScheme == scheme {
                            Image(systemName: "checkmark")
                                .font(.body.weight(ChromeMetrics.iconScaleWeight))
                                .imageScale(.small)
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                )
            }
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

    // MARK: - Font-size control (FR-16 / EC-07)

    /// Inline font-size stepper: leading icon + [−] {n}pt [+] (Apple Notes style).
    ///
    /// `−` is disabled when `fontSizeIndex == 0`; `+` is disabled when `fontSizeIndex == 20`
    /// (EC-07 / FR-16). One slot per press through the 21-slot scale (6pt…38pt).
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
            // surface bearing the morph ID. Nested glass button shapes inside the
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
}

// MARK: - MenuRow (FR-23)

/// The shared plain row anatomy used by every panel row that fits it: a 24pt centered
/// leading SF Symbol, a label with an optional one-line description, a flexible spacer and
/// an optional trailing accessory.
///
/// `trailing` is the panel's only view-erasure point — it carries a checkmark for the
/// selected theme row and the expand/collapse chevron for the recovery header.
fileprivate struct MenuRow: View {
    let icon: String
    let label: String
    var description: String? = nil
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
            Image(systemName: icon)
                .font(.body.weight(ChromeMetrics.iconScaleWeight))
                .imageScale(.medium)
                .foregroundStyle(.primary)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
                Text(label)
                    .font(.body)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let trailing {
                trailing()
            }
        }
        .padding(.horizontal, ChromeMetrics.menuRowHorizontalPadding)
        .padding(.vertical, ChromeMetrics.menuRowVerticalPadding)
        // ≥ 44pt minimum touch target height (NFR-04).
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - AboutSection (FR-17 / EC-19)

/// About entry: Foglietto / Paolo Santucci / version / GPL-3.0 /
/// issue link / website link. Apple Notes style: section header, then
/// content rows with leading icons.
///
/// URL literals are NOT localized (FR-22 / gate check 12).
/// Links open externally via `Link`/`openURL` — no `canOpenURL` pre-guard (EC-19).
fileprivate struct AboutSection: View {

    var body: some View {
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
}

// MARK: - RecoverySection (FR-18 / EC-02 / EC-04 / EC-15)

/// Inline expandable "Recent notes" recovery submenu (Apple Notes style).
///
/// Owns the expansion `@State` and the fresh `RecoveryListViewModel` for the current
/// expansion, so a re-render of the panel never rebuilds the recovery list state.
///
/// On expand:
///   1. A fresh `RecoveryListViewModel` is created via `menuVM.makeRecoveryListViewModel()`.
///   2. `recoveryVM.refresh()` is called immediately to re-fetch `recovery.list()` (FR-18).
///
/// Rows render icon + previewTitle + dateSubtitle.
/// Tap → `recoveryVM.select(path:)` then dismiss the panel (FR-18, write-source 3).
/// Empty state renders a text message when no notes exist (EC-02 / FR-18).
///
/// No delete / delete-all / confirm dialog present (FR-18).
fileprivate struct RecoverySection: View {

    /// The view model supplying fresh recovery list instances (FR-18).
    let menuVM: MenuViewModel

    /// The panel's presented state — set to `false` on a recovery-row tap (write-source 3).
    @Binding var isPresented: Bool

    /// The resolved close spring from `ChromeOverlay`; `nil` under Reduce Motion.
    let dismissAnimation: Animation?

    /// When `true`, the submenu expand/collapse runs without animation (FR-21).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the "Recent notes" recovery submenu section is expanded.
    @State private var isRecoveryExpanded: Bool = false

    /// The fresh `RecoveryListViewModel` for the current expansion.
    /// Created via `menuVM.makeRecoveryListViewModel()` on each expand (FR-18).
    @State private var recoveryVM: RecoveryListViewModel? = nil

    /// The expand/collapse animation — `nil` under Reduce Motion so the submenu simply
    /// appears (FR-21), otherwise `ChromeMetrics.submenuExpandAnimation` (Apple-Notes feel).
    private var submenuAnimation: Animation? {
        reduceMotion ? nil : ChromeMetrics.submenuExpandAnimation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            // Expand/collapse header button (Apple Notes style: leading icon + label)
            Button {
                withAnimation(submenuAnimation) {
                    isRecoveryExpanded.toggle()
                    if isRecoveryExpanded {
                        // FR-18: fresh instance + re-fetch on every expand.
                        let vm = menuVM.makeRecoveryListViewModel()
                        vm.refresh()
                        recoveryVM = vm
                    } else {
                        recoveryVM = nil
                    }
                }
            } label: {
                MenuRow(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    label: String(localized: "Recent notes", comment: "Recovery submenu header label in the menu bubble (FR-23)")
                ) {
                    AnyView(
                        Image(systemName: isRecoveryExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(ChromeMetrics.iconScaleWeight))
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    )
                }
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
            // EC-02: empty-recovery empty-state text (FR-18).
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
            // Recovery note rows — list + restore-on-tap only (no delete).
            // A 10-note list can outgrow the screen, so the row stack is
            // offered unscrolled first and falls back to a capped scroll view
            // when it does not fit; the panel around it keeps hugging content.
            ViewThatFits(in: .vertical) {
                recoveryRows(rvm: rvm)
                ScrollView {
                    recoveryRows(rvm: rvm)
                }
                .frame(height: ChromeMetrics.recoveryScrollHeight)
            }
        }
    }

    /// The recovery row stack itself — plain rows, newest first (FR-18).
    private func recoveryRows(rvm: RecoveryListViewModel) -> some View {
        VStack(alignment: .leading, spacing: ChromeMetrics.menuRowSpacing) {
            ForEach(rvm.rows) { row in
                recoveryRow(row: row, rvm: rvm)
            }
        }
    }

    /// A single recovery note row (Apple Notes style: leading icon, title+date stacked).
    ///
    /// Tap → `rvm.select(path:)` (nil-tolerant — EC-04) then dismiss the panel via
    /// `withAnimation(dismissAnimation)` so the close morphs smoothly (same spring as
    /// the tap-catcher dismiss — C-05/C-06). Write-source 3.
    ///
    /// - Parameters:
    ///   - row: The `RecoveryRow` to display.
    ///   - rvm: The `RecoveryListViewModel` to call `select(path:)` on.
    private func recoveryRow(row: RecoveryRow, rvm: RecoveryListViewModel) -> some View {
        Button {
            // FR-18: restore; nil-tolerant inside RecoveryListViewModel.select(path:) (EC-04).
            rvm.select(path: row.path)
            // Dismiss the panel with the same morph spring as the tap-catcher (write-source 3).
            withAnimation(dismissAnimation) {
                isPresented = false
            }
        } label: {
            HStack(alignment: .center, spacing: ChromeMetrics.menuRowHorizontalPadding) {
                // Icon for a note (FR-18 row anatomy — Apple Notes look).
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
