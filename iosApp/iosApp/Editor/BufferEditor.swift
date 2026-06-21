// BufferEditor.swift
// iosApp
//
// UIViewRepresentable wrapping UITextView — the editor content surface.
// The SwiftUI built-in wrapper type is explicitly forbidden (AR-02 / FR-01);
// this file uses UIViewRepresentable + UITextView only.
//
// Spec refs: FR-01, FR-02, FR-03, FR-04, FR-05, FR-14, FR-15, FR-20, FR-21,
//            NFR-03, NFR-06; §5.1.c/§5.1.d; §6.1 EC-03/EC-04/EC-05/EC-12/EC-13
//
// UI canon: ui-design-bible.md §Editor text view + §Typography
//   - Background:    --view-bg-color => UIColor.systemBackground (iOS semantic)
//   - Font:          SF Mono (monospace) at slotList[fontSizeIndex] pt, ABSOLUTE (no DynamicType
//                    pre-multiplication, FR-15)
//   - Line-height:   1.4 via NSMutableParagraphStyle (§Typography, style.css:11-14)
//   - Glass:         ZERO on content — no material effect on UITextView (FR-20 / NFR-03)
//   - Touch target:  UITextView fills the window; NFR-06 tap-target >=44pt is met by the
//                    full-screen surface

import UIKit
import SwiftUI
import shared

// ---------------------------------------------------------------------------
// MARK: - Font-size slot helper
// ---------------------------------------------------------------------------

/// Resolve the point size for a given font-size slot index.
///
/// Uses `AppSettings(fontSizeIndex:).fontSizePt` (the shared computed property) to avoid
/// dealing with the KotlinList subscript bridge for `AppSettings.companion.slotList`.
/// The 21-slot table `[6,7,8,9,10,11,12,13,14,15,16,17,18,20,22,24,26,28,30,34,38]`
/// lives canonically in the shared `AppSettings.companion.slotList` (FR-14).
///
/// - Parameter index: Font-size slot index in `[0, 20]`; clamped by the shared `AppSettings`
///   constructor if out of range.
/// - Returns: The corresponding font size in points.
private func fontPt(for index: Int) -> CGFloat {
    // AppSettings.companion.slotList bridging as KotlinList<KotlinInt> is awkward in UIKit;
    // fontSizePt is the canonical computed accessor on AppSettings (shared module).
    // Int32 <-> Int at the call site (FR-09).
    // CANON GAP: --view-bg-color is satisfied by UIColor.systemBackground below;
    // once a named design-token color asset is wired into Assets.xcassets, replace
    // UIColor.systemBackground with UIColor(named: "ViewBgColor") throughout this file.
    return CGFloat(AppSettings(fontSizeIndex: Int32(index)).fontSizePt)
}

// ---------------------------------------------------------------------------
// MARK: - BufferEditor
// ---------------------------------------------------------------------------

/// `UIViewRepresentable` wrapping a `UITextView` — the editor content surface.
///
/// `makeUIView` builds a fully configured `UITextView`:
///   - No border, no background decoration.
///   - Background: `UIColor.systemBackground` (the iOS semantic mapping of `--view-bg-color`,
///     ui-design-bible.md §Colour `--view-bg-color`; CANON GAP: not yet a named asset token).
///   - Monospace font (SF Mono) at `slotList[fontSizeIndex]` pt, applied as an **absolute**
///     value — NO `UIFontMetrics`/Dynamic-Type pre-multiplication (FR-15).
///   - Line-height 1.4 via `NSMutableParagraphStyle.lineHeightMultiple` set on
///     `typingAttributes` (ui-design-bible.md §Typography, `style.css:11-14`).
///   - No material visual effect on content — the editor surface is plain theme background
///     (FR-20 / NFR-03 / EC-13). Any chrome material effects are M4 only.
///
/// `updateUIView` reconciles font size and text only on real divergence so it does **not**
/// clobber `textView.text` if the text is already equal — preserving in-session text when
/// only `fontSizeIndex` changes (EC-12).
struct BufferEditor: UIViewRepresentable {

    // MARK: Properties

    /// The presentation-state model.  Bound at the call site by the composition root (TASK-07).
    let viewModel: BufferViewModel

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        // — Appearance —
        textView.backgroundColor = .systemBackground
        // CANON GAP: UIColor.systemBackground is the iOS semantic equivalent of
        // --view-bg-color (CupertinoColors.systemBackground per ui-design-bible.md §Colour).
        // Replace with UIColor(named: "ViewBgColor") once the named asset is wired.
        textView.textColor = .label

        // Remove the default container inset to let the full-bleed surface fill the window.
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // — Monospace font at absolute slot size (FR-14 / FR-15) —
        applyFont(to: textView, index: viewModel.fontSizeIndex)

        // — No visual-effect material on content (FR-20 / NFR-03 / EC-13) —
        // The UITextView is plain; any chrome material belongs to M4 overlay chrome only.

        // — Delegate —
        textView.delegate = context.coordinator

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Reconcile font size only on real divergence (EC-12).
        let desiredPt = fontPt(for: viewModel.fontSizeIndex)
        if uiView.font?.pointSize != desiredPt {
            applyFont(to: uiView, index: viewModel.fontSizeIndex)
        }

        // Reconcile text only on real divergence — do NOT overwrite if equal.
        // This preserves in-session content when only fontSizeIndex changes (EC-12 / FR-13).
        if uiView.text != viewModel.text {
            uiView.text = viewModel.text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Private helpers

    /// Apply the monospace font at the given slot index, paired with line-height 1.4.
    ///
    /// Font: `UIFont.monospacedSystemFont(ofSize:weight:)` — SF Mono on iOS (FR-14).
    /// Size: absolute point value from the 21-slot table, NO `UIFontMetrics` scaling (FR-15).
    /// Line-height: 1.4 via `NSMutableParagraphStyle.lineHeightMultiple` on `typingAttributes`
    /// so every newly typed character inherits the style (ui-design-bible §Typography, §Editor).
    private func applyFont(to textView: UITextView, index: Int) {
        let pt = fontPt(for: index)
        let font = UIFont.monospacedSystemFont(ofSize: pt, weight: .regular)

        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.4

        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .paragraphStyle: style
        ]
    }

    // MARK: - Coordinator

    /// `UITextViewDelegate` implementing the single pre-edit hook (§5.1.d decision table).
    ///
    /// Decision table (top-down; first matching row wins):
    ///
    /// | Condition | Action | Return |
    /// |-----------|--------|--------|
    /// | text=="\n" AND range.length==0 AND process!=nil | write result text+caret, mirror VM | false |
    /// | text=="\n" AND range.length==0 AND process==nil | passthrough | true |
    /// | any other edit (non-newline, paste, "\n" with selection) | passthrough | true |
    ///
    /// Hard rules (FR-02 / EC-03):
    ///   - NO post-edit diff predicate.
    ///   - No boolean latch / re-entrancy flag is needed or present — a direct `.text =` set
    ///     in UIKit does NOT re-enter `shouldChangeTextIn`, so no such flag is required.
    ///   - `process` is computed from the **pre-edit** text and `range.location`.
    final class Coordinator: NSObject, UITextViewDelegate {

        // MARK: Properties

        private let viewModel: BufferViewModel

        // MARK: Init

        init(viewModel: BufferViewModel) {
            self.viewModel = viewModel
        }

        // MARK: UITextViewDelegate — the single pre-edit hook (FR-02)

        /// The only `UITextViewDelegate` text-gating method (FR-02).
        ///
        /// Implements the §5.1.d decision table exactly.
        /// There is NO post-edit diffing predicate and no boolean-latch re-entrancy flag
        /// (EC-03 / FR-02): a direct UIKit `.text =` assignment bypasses the delegate,
        /// so the hook does not re-enter itself on the continuation branch.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {

            // Row 1 + Row 2: newline insertion at a collapsed caret.
            if text == "\n", range.length == 0 {
                // Pre-edit caret offset (UTF-16 units via the single conversion boundary).
                let caret = TextOffsetBridge.caretOffset(
                    from: range,
                    in: textView.text as NSString
                )

                // Call shared ListContinuation (FR-03).
                // Kotlin Int <-> Swift Int32 at the call site (§5.1.a).
                if let result = ListContinuation.shared.process(
                    fullText: textView.text,
                    caretOffset: Int32(caret)
                ) {
                    // Continuation branch (FR-04 / §5.1.d row 1):
                    // Write the FULL result text (not a delta) — handles checkbox reset
                    // and empty-marker termination for free.
                    textView.text = result.text

                    // Place caret at result.caret (EC-04).
                    textView.selectedRange = TextOffsetBridge.collapsedRange(
                        at: Int(result.caret),
                        in: textView.text as NSString
                    )

                    // Mirror committed text into the VM (FR-13 / keystroke origin).
                    viewModel.updateText(result.text)

                    // Return false: suppress UIKit's own "\n" insertion (FR-04).
                    // The direct .text = assignment above does NOT re-enter this hook
                    // (EC-03); no boolean latch is needed or present.
                    return false
                }

                // Nil branch (FR-05 / §5.1.d row 2): let UIKit insert the plain newline.
                return true
            }

            // Row 3: any other edit — non-newline char, paste, or "\n" with range.length>0
            // (selection active, EC-05).  Passthrough; textViewDidChange mirrors below.
            return true
        }

        // MARK: UITextViewDelegate — committed-text mirror

        /// Mirror committed text into the `BufferViewModel` after every UIKit-applied edit
        /// (FR-13 steady-state typing path).
        ///
        /// Called by UIKit only for edits UIKit itself applied (i.e., `shouldChangeTextIn`
        /// returned `true`).  For the continuation branch (return false), the mirror is
        /// done inside `shouldChangeTextIn` immediately after the direct text assignment.
        func textViewDidChange(_ textView: UITextView) {
            viewModel.updateText(textView.text)
        }
    }
}
