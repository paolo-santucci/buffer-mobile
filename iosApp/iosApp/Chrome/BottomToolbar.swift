// Chrome/BottomToolbar.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome
//
// Five-button native iOS 26 Liquid Glass bottom toolbar.
// Left→right: close-keyboard, copy, paste, de-indent (outdent), indent.
// All buttons are always-enabled (FR-15).
//
// CANON GAP CG-1: native Liquid Glass toolbar material supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color@90%
// color-mix fill + hairline ring. 0.68 / 90% survive as legibility intent
// only (NFR-03). Decision logged per spec §8 OQ-01.
//
// Anti-additive keyboard avoidance (.safeAreaInset host) is TASK-11.
// This view only renders the five buttons — it contains no keyboard-height
// or safe-area arithmetic.
//
// Spec refs: FR-01, FR-02, FR-15, FR-16, FR-17, FR-18, FR-23,
//            NFR-01, NFR-02, NFR-04, NFR-07; EC-03, EC-09, EC-17; CG-1.
// Contract: §4.1, §5.1.e Coordinator hooks, §6.1 EC-03.

import SwiftUI

// MARK: - BottomToolbar

/// Five-button native iOS 26 Liquid Glass bottom toolbar.
///
/// **Button order (left → right):**
/// 1. **Hide keyboard** — resigns first responder on the live text view (FR-16).
/// 2. **Copy** — copies the current buffer text to `UIPasteboard.general`.
/// 3. **Paste** — inserts the pasteboard string at the caret; no-op on an
///    empty or nil clipboard (EC-03).
/// 4. **Outdent** — routes through `viewModel.outdent(in:of:)` then
///    `Coordinator.applyIndentResult(text:range:)` (FR-17; no VM-surface widening).
/// 5. **Indent** — same routing path via `viewModel.indent(in:of:)` (FR-17).
///
/// **Input surface (for TASK-11 wiring):**
///
/// The view accepts five closures — one per button action — so it remains
/// fully decoupled from the concrete `Coordinator` type. TASK-11 creates
/// the closures and binds them to the live Coordinator and BufferViewModel:
///
/// ```swift
/// BottomToolbar(
///     onCopy:           { coordinator.copyToPasteboard() },
///     onPaste:          { coordinator.pasteAtCaret() },
///     onCloseKeyboard:  { coordinator.closeKeyboard() },
///     onIndent: {
///         guard let tv = coordinator.textView else { return }
///         let result = viewModel.indent(in: tv.selectedRange, of: tv.text ?? "")
///         coordinator.applyIndentResult(text: result.text, range: result.selection)
///     },
///     onOutdent: {
///         guard let tv = coordinator.textView else { return }
///         let result = viewModel.outdent(in: tv.selectedRange, of: tv.text ?? "")
///         coordinator.applyIndentResult(text: result.text, range: result.selection)
///     }
/// )
/// ```
///
/// The indent/de-indent closures read `coordinator.textView` to obtain the live
/// `selectedRange` and current text, call the appropriate `viewModel` method, then
/// hand the result to `applyIndentResult` — matching the §4.2 sequence diagram and
/// the §5.1.e Coordinator contract exactly.
///
/// **Native glass:**
/// The button row uses `.buttonStyle(.glass)` (iOS 26 native glass button style)
/// on each button and `.glassEffect(in: .capsule)` on the container `HStack`.
/// Unconditional — min deployment target iOS 26.0, no availability guard needed (NFR-02).
///
/// **Accessibility (NFR-04, FR-23):**
/// Every button has an English `.accessibilityLabel` literal:
/// - "Hide keyboard", "Copy", "Paste", "Outdent", "Indent"
/// Touch targets enforced to ≥ 44×44 pt via `.frame(minWidth: 44, minHeight: 44)`.
///
/// Hosted via `.safeAreaInset` by TASK-11 (FR-15, FR-18). No keyboard-accessory-bar pattern
/// used — the toolbar is a plain SwiftUI view, not an `inputAccessory*`.
///
/// No search / find affordance is present (FR-15).
struct BottomToolbar: View {

    // MARK: - Closure surface (for TASK-11 wiring)

    /// Called when the user taps Copy.
    /// TASK-11 binds this to `Coordinator.copyToPasteboard()`.
    let onCopy: () -> Void

    /// Called when the user taps Paste.
    /// TASK-11 binds this to `Coordinator.pasteAtCaret()`.
    /// No-op on an empty or nil clipboard (EC-03) — guard lives in the Coordinator.
    let onPaste: () -> Void

    /// Called when the user taps Close keyboard.
    /// TASK-11 binds this to `Coordinator.closeKeyboard()`.
    let onCloseKeyboard: () -> Void

    /// Called when the user taps Indent.
    /// TASK-11 binds this to: read `coordinator.textView?.selectedRange` + text,
    /// call `viewModel.indent(in:of:)`, then `coordinator.applyIndentResult(text:range:)`.
    let onIndent: () -> Void

    /// Called when the user taps De-indent.
    /// TASK-11 binds this to: read `coordinator.textView?.selectedRange` + text,
    /// call `viewModel.outdent(in:of:)`, then `coordinator.applyIndentResult(text:range:)`.
    let onOutdent: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: ChromeMetrics.toolbarItemSpacing) {
            closeKeyboardButton
            copyButton
            pasteButton
            deIndentButton
            indentButton
        }
        // Horizontal inset keeps icons off the capsule edges (Apple-Notes look).
        .padding(.horizontal, ChromeMetrics.toolbarHorizontalPadding)
        // Native iOS 26 Liquid Glass — no hand-rolled blur/fill/shadow (NFR-01/02).
        .glassEffect(in: .capsule)
    }

    // MARK: - Copy button (FR-16)

    /// Copy the current buffer text to `UIPasteboard.general` (FR-16).
    ///
    /// Always enabled — copy is not gated on non-empty text (FR-15/FR-16).
    /// SF Symbol `doc.on.doc` mirrors the GNOME `edit-copy-symbolic` icon
    /// (ui-design-bible §Icons mapping table).
    private var copyButton: some View {
        Button(action: onCopy) {
            Image(systemName: "doc.on.doc")
                .imageScale(.medium)
                .fontWeight(ChromeMetrics.iconScaleWeight)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        // Always enabled (FR-15 — all five buttons are always-enabled).
        // Native glass button style (iOS 26).
        .buttonStyle(.glass)
        // Accessibility (NFR-04, FR-23).
        .accessibilityLabel(
            String(localized: "Copy", comment: "Copy button accessibility label in the bottom toolbar")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23).
        .help(
            String(localized: "Copy text", comment: "Copy button tooltip in the bottom toolbar (FR-23)")
        )
    }

    // MARK: - Paste button (FR-16 / EC-03)

    /// Insert the current pasteboard string at the caret (FR-16).
    ///
    /// No-op on an empty or nil clipboard — guard is in `Coordinator.pasteAtCaret()`
    /// (EC-03 / §6.1).  Always enabled (FR-15): the button is never disabled based
    /// on clipboard state.
    /// SF Symbol `doc.on.clipboard` mirrors `edit-paste-symbolic`.
    private var pasteButton: some View {
        Button(action: onPaste) {
            Image(systemName: "doc.on.clipboard")
                .imageScale(.medium)
                .fontWeight(ChromeMetrics.iconScaleWeight)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        // Always enabled (FR-15); guard on empty clipboard is in Coordinator (EC-03).
        .buttonStyle(.glass)
        // Accessibility (NFR-04, FR-23).
        .accessibilityLabel(
            String(localized: "Paste", comment: "Paste button accessibility label in the bottom toolbar")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23).
        .help(
            String(localized: "Paste text", comment: "Paste button tooltip in the bottom toolbar (FR-23)")
        )
    }

    // MARK: - Close-keyboard button (FR-16)

    /// Dismiss the software keyboard by calling `resignFirstResponder` on the
    /// live text view (FR-16).  No-op when `textView` is nil (EC-13 teardown
    /// safety — guard lives in `Coordinator.closeKeyboard()`).
    /// SF Symbol `keyboard.chevron.compact.down` is the standard iOS idiom for
    /// keyboard dismissal.
    private var closeKeyboardButton: some View {
        Button(action: onCloseKeyboard) {
            Image(systemName: "keyboard.chevron.compact.down")
                .imageScale(.medium)
                .fontWeight(ChromeMetrics.iconScaleWeight)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.glass)
        // Accessibility label — FR-23 introduces "Hide keyboard" as a new EN literal.
        .accessibilityLabel(
            String(localized: "Hide keyboard", comment: "Close-keyboard button accessibility label in the bottom toolbar (FR-23 new string)")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23).
        .help(
            String(localized: "Hide keyboard", comment: "Close-keyboard button tooltip in the bottom toolbar (FR-23)")
        )
    }

    // MARK: - Indent button (FR-17)

    /// Indent the current selection by one unit (FR-17).
    ///
    /// Routing (§4.2 sequence diagram):
    ///   1. Read `coordinator.textView?.selectedRange` and current text.
    ///   2. Call `viewModel.indent(in:of:)` → `(text: String, selection: NSRange)`.
    ///   3. Call `coordinator.applyIndentResult(text:range:)` to write back.
    ///
    /// This routing is wired in the `onIndent` closure by TASK-11; the view
    /// knows nothing about the Coordinator type (no VM-surface widening — FR-25).
    /// SF Symbol `increase.indent` mirrors `format-indent-more-symbolic`.
    private var indentButton: some View {
        Button(action: onIndent) {
            Image(systemName: "increase.indent")
                .imageScale(.medium)
                .fontWeight(ChromeMetrics.iconScaleWeight)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.glass)
        // Accessibility label — FR-23 introduces "Indent" as a new EN literal.
        .accessibilityLabel(
            String(localized: "Indent", comment: "Indent button accessibility label in the bottom toolbar (FR-23 new string)")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23).
        .help(
            String(localized: "Indent", comment: "Indent button tooltip in the bottom toolbar (FR-23)")
        )
    }

    // MARK: - De-indent button (FR-17)

    /// De-indent (outdent) the current selection by one unit (FR-17).
    ///
    /// Same routing contract as indent: TASK-11 wires `onOutdent` to call
    /// `viewModel.outdent(in:of:)` then `coordinator.applyIndentResult(text:range:)`.
    /// When the line has no leading indent the shared outdent is a no-op;
    /// the selection still round-trips through the bridge (EC-07/EC-09).
    /// SF Symbol `decrease.indent` mirrors `format-indent-less-symbolic`.
    private var deIndentButton: some View {
        Button(action: onOutdent) {
            Image(systemName: "decrease.indent")
                .imageScale(.medium)
                .fontWeight(ChromeMetrics.iconScaleWeight)
        }
        // ≥ 44×44 pt touch target (NFR-04/HIG).
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.glass)
        // Accessibility label — FR-23 introduces "Outdent" / "De-indent" as a new EN literal.
        // The spec names both "Outdent" and "De-indent"; "Outdent" is the standard iOS term.
        .accessibilityLabel(
            String(localized: "Outdent", comment: "De-indent button accessibility label in the bottom toolbar (FR-23 new string)")
        )
        .accessibilityAddTraits(.isButton)
        // Tooltip (FR-23).
        .help(
            String(localized: "Outdent", comment: "De-indent button tooltip in the bottom toolbar (FR-23)")
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("BottomToolbar") {
    BottomToolbar(
        onCopy:          { },
        onPaste:         { },
        onCloseKeyboard: { },
        onIndent:        { },
        onOutdent:       { }
    )
    .padding()
}
#endif
