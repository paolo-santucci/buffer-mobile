// BufferEditor.swift
// iosApp
//
// UIViewRepresentable wrapping a UITextView — the editor content surface. The SwiftUI
// built-in editor and text-field wrappers stay unused (AR-02 / FR-01).
//
// Presentation contract (FR-09, FR-12, FR-13): plain theme background, monospaced font
// at the shared absolute slot sizes, line height 1.4, and a first-line inset derived from
// the shared chrome-pill geometry tokens. Text handling, delegate behaviour, and the
// shared font-size table are frozen.
//
// Spec refs: FR-01, FR-09, FR-10, FR-12, FR-13, FR-15, FR-20, FR-21; §5.1.d, §5.2;
//            §6.1 EC-03, EC-12, EC-13, EC-24, EC-25; NFR-03, NFR-06.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import UIKit
import SwiftUI
import shared

// MARK: - Editor inset seam

/// Top inset that positions the first line of text just below the floating chrome pill.
///
/// Derived by compile-time reference from the shared chrome geometry tokens, so the pill's
/// rendered height and the editor's first-line placement cannot drift apart (FR-10 lockstep).
/// Pure and total over `safeAreaTop`. The chrome auto-hide state is never consulted, so text
/// does not move when chrome hides or reveals (C-06).
///
/// - Parameter safeAreaTop: The device safe-area top inset in points.
/// - Returns: The total inset to apply to `textContainerInset.top` (NFR-03).
func kEditorTopInset(safeAreaTop: CGFloat) -> CGFloat {
    safeAreaTop + ChromeMetrics.pillTopGap + ChromeMetrics.pillHeight + ChromeMetrics.pillBottomGap
}

// MARK: - Font-size slot helper

/// Resolve the point size for a given font-size slot index.
///
/// Reads `AppSettings(fontSizeIndex:).fontSizePt`, the shared computed accessor over the
/// canonical 21-slot table (FR-14), avoiding the KotlinList subscript bridge. The size is
/// absolute: no Dynamic-Type pre-multiplication (FR-15).
///
/// - Parameter index: Font-size slot index in `[0, 20]`; the shared constructor clamps it.
/// - Returns: The corresponding font size in points.
private func fontPt(for index: Int) -> CGFloat {
    CGFloat(AppSettings(colorScheme: AppColorScheme.follow, fontSizeIndex: Int32(index)).fontSizePt)
}

// MARK: - BufferEditor

/// `UIViewRepresentable` wrapping a `BufferTextView` — the editor content surface.
///
/// The wrapped view keeps `textContainerInset` aligned with the attached window's live safe
/// area. That reconciliation writes nothing but the inset, so text, selection, typing
/// attributes, and scroll offset survive every tick (EC-12).
///
/// `makeUIView` publishes the coordinator into `coordinatorBox.coordinator` (weak) so the
/// toolbar closures can dispatch actions to it without UIKit coupling. `updateUIView` wires
/// the chrome-visibility callbacks onto the coordinator (FR-19). Both are additive and
/// idempotent; font and text are reconciled on divergence only, so an update tick never
/// clobbers in-session content when only `fontSizeIndex` changes (EC-12).
///
/// CANON GAP: `UIColor.systemBackground` is the iOS semantic stand-in for the
/// `--view-bg-color` token; swap it for a named asset color once the catalog holds one.
struct BufferEditor: UIViewRepresentable {

    // MARK: Properties

    /// The presentation-state model, bound at the call site by the composition root.
    let viewModel: BufferViewModel

    /// The chrome auto-hide/reveal state machine. `updateUIView` wires its inject* methods
    /// onto the coordinator's optional callbacks. Optional so the editor can be built
    /// without a live state machine.
    let chromeVisibility: ChromeVisibility?

    /// Reference-type bridge that receives the live coordinator once it is created, so the
    /// toolbar closures can reach it without UIKit coupling.
    let coordinatorBox: CoordinatorBox?

    // MARK: Init

    init(
        viewModel: BufferViewModel,
        chromeVisibility: ChromeVisibility? = nil,
        coordinatorBox: CoordinatorBox? = nil
    ) {
        self.viewModel = viewModel
        self.chromeVisibility = chromeVisibility
        self.coordinatorBox = coordinatorBox
    }

    // MARK: Editor text view

    /// `UITextView` that keeps `textContainerInset` aligned with the attached window's
    /// live safe area.
    ///
    /// Reconciliation is window-guarded and divergence-only: only `textContainerInset` is
    /// ever written, so in-session text, selection, and typing attributes survive every tick
    /// (EC-12). A detached view keeps the last applied inset rather than falling back to a
    /// constant (EC-24).
    final class BufferTextView: UITextView {

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reconcileTopInset()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            reconcileTopInset()
        }

        /// Converge `textContainerInset` on the attached window's live safe area.
        ///
        /// No-op while detached, and no-op while the top inset already matches the window's
        /// safe area, so repeated ticks never invalidate layout for nothing.
        func reconcileTopInset() {
            guard let window = window else { return }
            let desired = kEditorTopInset(safeAreaTop: window.safeAreaInsets.top)
            guard textContainerInset.top != desired else { return }
            textContainerInset = UIEdgeInsets(
                top: desired,
                left: ChromeMetrics.chromeHorizontalInset,
                bottom: 0,
                right: ChromeMetrics.chromeHorizontalInset
            )
        }
    }

    // MARK: UIViewRepresentable

    /// Build the editor surface: plain theme background, token-derived inset (provisional
    /// until the window attaches), zero line-fragment padding, monospaced font, coordinator
    /// wiring.
    func makeUIView(context: Context) -> UITextView {
        let textView = BufferTextView()

        textView.backgroundColor = .systemBackground
        textView.textColor = .label

        textView.textContainerInset = UIEdgeInsets(
            top: kEditorTopInset(safeAreaTop: 0),
            left: ChromeMetrics.chromeHorizontalInset,
            bottom: 0,
            right: ChromeMetrics.chromeHorizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0

        applyFont(to: textView, index: viewModel.fontSizeIndex)

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        coordinatorBox?.coordinator = context.coordinator

        return textView
    }

    /// Reconcile font size, text, and the inset — each on divergence only.
    func updateUIView(_ uiView: UITextView, context: Context) {
        let desiredPt = fontPt(for: viewModel.fontSizeIndex)
        if uiView.font?.pointSize != desiredPt {
            applyFont(to: uiView, index: viewModel.fontSizeIndex)
        }

        if uiView.text != viewModel.text {
            uiView.text = viewModel.text
        }

        BufferEditor.reconcileInset(of: uiView)

        if let cv = chromeVisibility {
            context.coordinator.onTyping = { [weak cv] in cv?.injectTyping() }
            context.coordinator.onScroll = { [weak cv] dir in cv?.injectScroll(dir) }
            context.coordinator.onKeyboardDismiss = { [weak cv] in cv?.injectKeyboardDismiss() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Update-leg seam

    /// The additive `updateUIView` reconciliation leg: window-guarded and divergence-only, so
    /// an update tick writes nothing but the inset when the safe area has moved
    /// (EC-12 / EC-24). A view that is not a `BufferTextView` is left untouched.
    ///
    /// Factored out as a context-free seam because `UIViewRepresentableContext` has no public
    /// initializer, so the update leg cannot be driven directly from the test target.
    static func reconcileInset(of uiView: UITextView) {
        (uiView as? BufferTextView)?.reconcileTopInset()
    }

    // MARK: - Private helpers

    /// Apply the monospaced font at the given slot index, paired with line height 1.4.
    ///
    /// Font: `UIFont.monospacedSystemFont(ofSize:weight:)` (FR-14). Size: the absolute point
    /// value from the shared 21-slot table, with no Dynamic-Type scaling (FR-15). Line height:
    /// 1.4 via `NSMutableParagraphStyle.lineHeightMultiple` on `typingAttributes`, so newly
    /// typed characters inherit the style.
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

    /// `UITextViewDelegate` implementing the single pre-edit hook and the toolbar action
    /// hooks, plus the callbacks that feed the chrome auto-hide state machine.
    ///
    /// Decision table (top-down; first matching row wins):
    ///
    /// | Condition | Action | Return |
    /// |-----------|--------|--------|
    /// | text=="\n" AND range.length==0 AND process!=nil | write result text+caret, mirror VM | false |
    /// | text=="\n" AND range.length==0 AND process==nil | passthrough | true |
    /// | any other edit (non-newline, paste, "\n" with selection) | passthrough | true |
    ///
    /// Hard rules (FR-02 / EC-03): no post-edit diff predicate, and no boolean latch or
    /// re-entrancy flag — a direct `.text =` assignment in UIKit does not re-enter
    /// `shouldChangeTextIn`. `process` is computed from the pre-edit text and `range.location`.
    ///
    /// Action hooks dispatched by the bottom toolbar: `copyToPasteboard()`, `pasteAtCaret()`,
    /// `closeKeyboard()`, `applyIndentResult(text:range:)`. Optional callbacks:
    /// `onTyping`, `onScroll(_:)`, `onKeyboardDismiss`. All are nil-safe when `textView` is nil.
    final class Coordinator: NSObject, UITextViewDelegate {

        // MARK: Properties

        private let viewModel: BufferViewModel

        /// Weak handle to the live text view, set by `makeUIView` right after construction.
        /// `nil`-safe after the view deallocates — no retain cycle (EC-13).
        weak var textView: UITextView?

        /// Called on every keystroke; wired to the chrome-visibility typing seam.
        var onTyping: (() -> Void)?

        /// Called on every scroll tick with the derived direction; nil-safe when unset.
        var onScroll: ((ScrollDirection) -> Void)?

        /// Called when the text view ends editing; nil-safe when unset.
        var onKeyboardDismiss: (() -> Void)?

        /// Content-offset Y recorded at the end of the previous `scrollViewDidScroll` tick,
        /// used to derive the scroll direction (FR-19).
        private var lastContentOffsetY: CGFloat = 0

        // MARK: Init

        init(viewModel: BufferViewModel) {
            self.viewModel = viewModel
        }

        // MARK: Action hooks (dispatched by BottomToolbar)

        /// Copy the buffer text to the system pasteboard (FR-16).
        ///
        /// Copies even when the buffer is empty — the share surface, not copy, is gated on
        /// non-empty (FR-08 vs FR-16).
        func copyToPasteboard() {
            UIPasteboard.general.string = viewModel.text
        }

        /// Insert the current pasteboard string at the caret position (FR-16 / EC-03).
        ///
        /// No-op when the pasteboard string is `nil` or empty (EC-03), and no-op after
        /// teardown (EC-13).
        func pasteAtCaret() {
            guard let tv = textView else { return }
            guard let paste = UIPasteboard.general.string, !paste.isEmpty else { return }
            let range = tv.selectedRange
            if let textRange = tv.selectedTextRange {
                tv.replace(textRange, withText: paste)
            } else {
                let mutable = NSMutableString(string: tv.text ?? "")
                mutable.replaceCharacters(in: range, with: paste)
                tv.text = mutable as String
                let newLocation = range.location + (paste as NSString).length
                tv.selectedRange = NSRange(location: newLocation, length: 0)
            }
            viewModel.updateText(tv.text ?? "")
        }

        /// Resign first responder on the live text view, dismissing the keyboard (FR-16).
        ///
        /// No-op after teardown (EC-13).
        func closeKeyboard() {
            textView?.resignFirstResponder()
        }

        /// Assign the indent/outdent result back to the live text view (FR-17).
        ///
        /// Sets `textView.text` and `textView.selectedRange`. No-op after teardown (EC-13).
        ///
        /// - Parameters:
        ///   - text:  The new full buffer text returned by `viewModel.indent`/`outdent`.
        ///   - range: The new selection returned by the same call (UTF-16 NSRange).
        func applyIndentResult(text: String, range: NSRange) {
            guard let tv = textView else { return }
            tv.text = text
            tv.selectedRange = range
        }

        // MARK: UITextViewDelegate — the single pre-edit hook (FR-02)

        /// The only `UITextViewDelegate` text-gating method (FR-02), implementing the
        /// decision table above.
        ///
        /// `onTyping` is emitted on the continuation branch, because the suppressing return
        /// value means `textViewDidChange` will not run for that edit (FR-19).
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {

            if text == "\n", range.length == 0 {
                let caret = TextOffsetBridge.caretOffset(
                    from: range,
                    in: textView.text as NSString
                )

                if let result = ListContinuation.shared.process(
                    fullText: textView.text,
                    caretOffset: Int32(caret)
                ) {
                    textView.text = result.text

                    textView.selectedRange = TextOffsetBridge.collapsedRange(
                        at: Int(result.caret),
                        in: textView.text as NSString
                    )

                    viewModel.updateText(result.text)

                    onTyping?()

                    return false
                }

                return true
            }

            return true
        }

        // MARK: UITextViewDelegate — committed-text mirror

        /// Mirror committed text into the `BufferViewModel` after every UIKit-applied edit
        /// (FR-13), and emit the typing event for the chrome auto-hide state machine (FR-19).
        ///
        /// The continuation branch (which returns `false`) mirrors inside
        /// `shouldChangeTextIn` instead, because `textViewDidChange` never runs for it.
        func textViewDidChange(_ textView: UITextView) {
            viewModel.updateText(textView.text)
            onTyping?()
        }

        // MARK: UIScrollViewDelegate — scroll-direction tracking (FR-19)

        /// Derive the scroll direction against the last recorded content offset and emit
        /// `onScroll(_:)`.
        ///
        /// `UITextViewDelegate` inherits from `UIScrollViewDelegate`, so this runs whenever
        /// the text view's embedded scroll view moves. A decreased content-offset Y is a
        /// forward scroll (chrome reveals); an increased one is reverse (chrome hides).
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let currentY = scrollView.contentOffset.y
            let direction: ScrollDirection = currentY < lastContentOffsetY ? .forward : .reverse
            lastContentOffsetY = currentY
            onScroll?(direction)
        }

        // MARK: UITextViewDelegate — keyboard-dismiss event (FR-19)

        /// Emit `onKeyboardDismiss` when the text view loses first-responder status.
        ///
        /// Nil-safe: `onKeyboardDismiss` is optional, so calling it through `?.()` is a no-op
        /// when unset.
        func textViewDidEndEditing(_ textView: UITextView) {
            onKeyboardDismiss?()
        }
    }
}
