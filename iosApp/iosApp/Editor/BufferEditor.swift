// BufferEditor.swift
// iosApp
//
// UIViewRepresentable wrapping UITextView — the editor content surface.
// The SwiftUI built-in wrapper type is explicitly forbidden (AR-02 / FR-01);
// this file uses UIViewRepresentable + UITextView only.
//
// Spec refs: FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-14, FR-15, FR-16, FR-17,
//            FR-19, FR-20, FR-21, NFR-03, NFR-06; §5.1.c/§5.1.d/§5.1.e;
//            §6.1 EC-03/EC-04/EC-05/EC-12/EC-13
//
// UI canon: ui-design-bible.md §Editor text view + §Typography
//   - Background:    --view-bg-color => UIColor.systemBackground (iOS semantic)
//   - Font:          SF Mono (monospace) at slotList[fontSizeIndex] pt, ABSOLUTE (no DynamicType
//                    pre-multiplication, FR-15)
//   - Line-height:   1.4 via NSMutableParagraphStyle (§Typography, style.css:11-14)
//   - No native material visual effect on content — ZERO on UITextView (FR-20 / NFR-03)
//   - Touch target:  UITextView fills the window; NFR-06 tap-target >=44pt is met by the
//                    full-screen surface

import UIKit
import SwiftUI
import shared

// ---------------------------------------------------------------------------
// MARK: - Editor inset constants (C-06 / §3.1 kEditorHInset / kEditorTopInset)
// ---------------------------------------------------------------------------

/// Horizontal (left + right) padding between the UITextView edge and the text column.
///
/// Applied via `textContainerInset` in `makeUIView` so the full-bleed UITextView fills the
/// window (NFR-06 tap target) while text appears inset 16 pt.  `lineFragmentPadding` is kept
/// at `0`, so the effective side inset is exactly this value (not 16 + the default 5).
///
/// Spec: §3.1 kEditorHInset; C-06 (inset via UIKit, not SwiftUI .padding()).
private let kEditorHInset: CGFloat = 16

/// STATIC top inset: positions the first line of text just below the floating pill.
///
/// Formula: `safeAreaTop + 16 (gap above pill) + 44 (pill height) + 8 (gap below pill)`
///
/// `safeAreaTop` is read once in `makeUIView` via `textView.window?.safeAreaInsets.top`.
/// If the window is not yet attached at that point (rare during first layout), the fallback
/// value `59` is used — a typical iPhone Face-ID / Dynamic-Island safe-area top on iOS 26.
/// This inset is NEVER updated by `updateUIView` or driven by `ChromeVisibility`; it does
/// NOT move when chrome auto-hides (C-06 STATIC constraint).
///
/// - Parameter safeAreaTop: The device safe-area top inset in points.
/// - Returns: The total top inset to apply to `textContainerInset.top`.
///
/// Spec: §3.1 kEditorTopInset(safeAreaTop:); C-06.
private func kEditorTopInset(safeAreaTop: CGFloat) -> CGFloat { safeAreaTop + 16 + 44 + 8 }

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
    return CGFloat(AppSettings(colorScheme: AppColorScheme.follow, fontSizeIndex: Int32(index)).fontSizePt)
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
///
/// **Coordinator-access seam (TASK-11 / §4.3):**
/// `makeUIView` publishes the newly created coordinator into `coordinatorBox.coordinator`
/// so `ContentView` / `ChromeOverlay`'s toolbar closures can dispatch actions to it.
/// `updateUIView` wires `chromeVisibility`'s inject* methods onto the coordinator's
/// `onTyping` / `onScroll` / `onKeyboardDismiss` callbacks (FR-19). Both operations are
/// purely additive — no M3 behaviour is changed or removed (EC-13 nil-safety retained).
struct BufferEditor: UIViewRepresentable {

    // MARK: Properties

    /// The presentation-state model.  Bound at the call site by the composition root (TASK-07).
    let viewModel: BufferViewModel

    // MARK: TASK-11 additive seam — coordinator bridge + SM callback wiring

    /// The chrome auto-hide/reveal SM.  `updateUIView` wires its inject* methods onto the
    /// coordinator's optional callbacks.  Optional so that `BufferEditor` can be used in
    /// previews/tests without a live `ChromeVisibility` instance.
    let chromeVisibility: ChromeVisibility?

    /// Reference-type bridge that receives the live `Coordinator` once it is created.
    /// `makeUIView` sets `coordinatorBox.coordinator = context.coordinator` so that
    /// `ContentView`'s toolbar closures can reach it without UIKit coupling (§4.3 seam).
    let coordinatorBox: CoordinatorBox?

    // MARK: Convenience init (preserves any existing call-sites that pass only viewModel)

    /// Full-parameter initialiser used by `ContentView` in TASK-11.
    init(
        viewModel: BufferViewModel,
        chromeVisibility: ChromeVisibility? = nil,
        coordinatorBox: CoordinatorBox? = nil
    ) {
        self.viewModel = viewModel
        self.chromeVisibility = chromeVisibility
        self.coordinatorBox = coordinatorBox
    }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        // — Appearance —
        textView.backgroundColor = .systemBackground
        // CANON GAP: UIColor.systemBackground is the iOS semantic equivalent of
        // --view-bg-color (CupertinoColors.systemBackground per ui-design-bible.md §Colour).
        // Replace with UIColor(named: "ViewBgColor") once the named asset is wired.
        textView.textColor = .label

        // Apply side insets (kEditorHInset = 16 pt) and a STATIC top inset that positions
        // the first text line just below the floating pill.
        //
        // The top inset is computed once here in makeUIView and is NEVER updated in
        // updateUIView — it does NOT move when ChromeVisibility hides/reveals the chrome
        // (C-06 STATIC constraint).  lineFragmentPadding stays 0 so the effective side
        // inset is exactly 16 pt, not 16 + the UIKit default 5 = 21 pt.
        //
        // safeAreaTop: read from the window if already attached; fallback 59 pt covers
        // the typical iPhone Face-ID / Dynamic-Island safe-area height on iOS 26.
        let safeAreaTop = textView.window?.safeAreaInsets.top ?? 59
        textView.textContainerInset = UIEdgeInsets(
            top: kEditorTopInset(safeAreaTop: safeAreaTop),
            left: kEditorHInset,
            bottom: 0,
            right: kEditorHInset
        )
        textView.textContainer.lineFragmentPadding = 0

        // — Monospace font at absolute slot size (FR-14 / FR-15) —
        applyFont(to: textView, index: viewModel.fontSizeIndex)

        // — No native material visual effect on content (FR-20 / NFR-03 / EC-13) —
        // The UITextView is plain; any chrome-layer material belongs to M4 overlay only.

        // — Delegate —
        textView.delegate = context.coordinator

        // — CM-6 / FR-06: store a weak handle to the live text view (EC-13) —
        // The Coordinator holds this as 'weak var textView', so no retain cycle is introduced.
        context.coordinator.textView = textView

        // — TASK-11 coordinator bridge: publish coordinator to ContentView's toolbar closures —
        // CoordinatorBox.coordinator is weak, so this does not extend the coordinator's
        // lifetime beyond the UIViewRepresentable's natural teardown (EC-13).
        coordinatorBox?.coordinator = context.coordinator

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

        // — TASK-11 SM-callback wiring (FR-19 / §4.3) —
        // Wire chromeVisibility's inject* methods onto the coordinator's optional
        // callbacks. Using [weak chromeVisibility] avoids a retain cycle if the SM
        // is ever deallocated while the coordinator is still live.
        // These assignments are idempotent — reassigning the same closure on every
        // updateUIView call is safe and does not cause re-entrancy (EC-13).
        if let cv = chromeVisibility {
            context.coordinator.onTyping = { [weak cv] in cv?.injectTyping() }
            context.coordinator.onScroll = { [weak cv] dir in cv?.injectScroll(dir) }
            context.coordinator.onKeyboardDismiss = { [weak cv] in cv?.injectKeyboardDismiss() }
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

    /// `UITextViewDelegate` implementing the single pre-edit hook (§5.1.d decision table)
    /// and the CM-6/FR-06 action hooks + SM-feeding callbacks (§5.1.e).
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
    ///
    /// CM-6 / FR-06 additions (§5.1.e, additive — M3 behaviour unchanged):
    ///   - `weak var textView` holds a reference to the live `UITextView` without a retain
    ///     cycle; it is `nil`-safe after the view deallocates (EC-13).
    ///   - Four action hooks dispatched by the bottom toolbar: `copyToPasteboard()`,
    ///     `pasteAtCaret()` (no-op on empty/nil clipboard, EC-03), `closeKeyboard()`,
    ///     `applyIndentResult(text:range:)`.
    ///   - Three SM-feeding optional callbacks: `onTyping`, `onScroll(_:)`,
    ///     `onKeyboardDismiss`. All nil-safe when `textView == nil` (EC-13).
    final class Coordinator: NSObject, UITextViewDelegate {

        // MARK: Properties

        private let viewModel: BufferViewModel

        // MARK: CM-6 / §5.1.e — weak UITextView handle (EC-13: no retain cycle)

        /// Weak reference to the live `UITextView`.  Set by `makeUIView` immediately after
        /// constructing the text view.  Becomes `nil` automatically when the view deallocates.
        /// All action hooks below guard against `nil` before use (EC-13).
        weak var textView: UITextView?

        // MARK: CM-6 / §5.1.e — SM-feeding callbacks (set by ContentView in TASK-11)

        /// Called on every keystroke.  `ContentView` sets this to `ChromeVisibility.injectTyping`.
        /// Nil-safe — no-op when not set.
        var onTyping: (() -> Void)?

        /// Called on every scroll tick with the derived direction.  `ContentView` sets this to
        /// `ChromeVisibility.injectScroll(_:)`.  Nil-safe — no-op when not set.
        var onScroll: ((ScrollDirection) -> Void)?

        /// Called when the keyboard dismisses (text view ends editing).  `ContentView` sets this
        /// to `ChromeVisibility.injectKeyboardDismiss`.  Nil-safe — no-op when not set.
        var onKeyboardDismiss: (() -> Void)?

        // MARK: Scroll-direction tracking (for onScroll derivation)

        /// Content-offset Y recorded at the end of the previous `scrollViewDidScroll` tick.
        /// Used to derive scroll direction (FR-19): decreasing Y → forward (scroll-up) →
        /// chrome reveals; increasing Y → reverse (scroll-down) → chrome hides.
        private var lastContentOffsetY: CGFloat = 0

        // MARK: Init

        init(viewModel: BufferViewModel) {
            self.viewModel = viewModel
        }

        // MARK: CM-6 / §5.1.e — Action hooks (dispatched by BottomToolbar in TASK-09)

        /// Copy the current buffer text to the system pasteboard (FR-16).
        ///
        /// Copies even when the buffer is empty — the share button (not copy) is gated on
        /// non-empty (FR-08 vs FR-16).  No-op safety against nil `textView` is not needed
        /// here because the text is read from `viewModel.text`, which is always available.
        func copyToPasteboard() {
            UIPasteboard.general.string = viewModel.text
        }

        /// Insert the current pasteboard string at the caret position (FR-16 / EC-03).
        ///
        /// No-op when the pasteboard string is `nil` or empty (EC-03).  If `textView` has
        /// been deallocated (EC-13) the method returns silently — no crash.
        func pasteAtCaret() {
            guard let tv = textView else { return }
            guard let paste = UIPasteboard.general.string, !paste.isEmpty else { return }
            // Insert the pasteboard text at the current selectedRange, replacing any selection.
            // `replace(_:withText:)` is the UIKit standard path for insertion at caret.
            let range = tv.selectedRange
            if let textRange = tv.selectedTextRange {
                tv.replace(textRange, withText: paste)
            } else {
                // Fallback: construct a UITextRange-equivalent via the text storage.
                let mutable = NSMutableString(string: tv.text ?? "")
                mutable.replaceCharacters(in: range, with: paste)
                tv.text = mutable as String
                let newLocation = range.location + (paste as NSString).length
                tv.selectedRange = NSRange(location: newLocation, length: 0)
            }
            // Mirror the change into the view model (keystroke-origin equivalent for paste).
            viewModel.updateText(tv.text ?? "")
        }

        /// Resign first responder on the live text view, dismissing the keyboard (FR-16).
        ///
        /// No-op when `textView` is `nil` (EC-13 teardown safety).
        func closeKeyboard() {
            textView?.resignFirstResponder()
        }

        /// Assign the indent/outdent result back to the live text view (FR-17 / §5.1.e).
        ///
        /// Sets both `textView.text` and `textView.selectedRange` atomically.
        /// No-op when `textView` is `nil` (EC-13 teardown safety).
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

        /// The only `UITextViewDelegate` text-gating method (FR-02).
        ///
        /// Implements the §5.1.d decision table exactly.
        /// There is NO post-edit diffing predicate and no boolean-latch re-entrancy flag
        /// (EC-03 / FR-02): a direct UIKit `.text =` assignment bypasses the delegate,
        /// so the hook does not re-enter itself on the continuation branch.
        ///
        /// CM-6 / §5.1.e: `onTyping` is emitted on the continuation branch (the SM must
        /// know the user typed even when UIKit's newline insertion is suppressed).
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

                    // Emit typing event for the chrome-visibility SM (FR-19 / §5.1.e).
                    // The continuation branch returns false (UIKit newline suppressed), so
                    // textViewDidChange will NOT be called — emit here instead.
                    onTyping?()

                    // Return false: suppress UIKit's own "\n" insertion (FR-04).
                    // The direct .text = assignment above does NOT re-enter this hook
                    // (EC-03); no boolean latch is needed or present.
                    return false
                }

                // Nil branch (FR-05 / §5.1.d row 2): let UIKit insert the plain newline.
                // textViewDidChange will fire and emit onTyping there.
                return true
            }

            // Row 3: any other edit — non-newline char, paste, or "\n" with range.length>0
            // (selection active, EC-05).  Passthrough; textViewDidChange mirrors below.
            return true
        }

        // MARK: UITextViewDelegate — committed-text mirror

        /// Mirror committed text into the `BufferViewModel` after every UIKit-applied edit
        /// (FR-13 steady-state typing path), and emit the typing event for the SM (FR-19).
        ///
        /// Called by UIKit only for edits UIKit itself applied (i.e., `shouldChangeTextIn`
        /// returned `true`).  For the continuation branch (return false), the mirror is
        /// done inside `shouldChangeTextIn` immediately after the direct text assignment,
        /// and `onTyping` is emitted there rather than here.
        func textViewDidChange(_ textView: UITextView) {
            viewModel.updateText(textView.text)
            // Emit typing event for the chrome-visibility SM (FR-19 / §5.1.e).
            onTyping?()
        }

        // MARK: UIScrollViewDelegate — scroll-direction tracking (FR-19 / §5.1.e)

        /// Derive scroll direction against the last recorded content offset and emit
        /// `onScroll(_:)` to feed the chrome-visibility SM (FR-19).
        ///
        /// `UITextViewDelegate` inherits from `UIScrollViewDelegate`, so this method is
        /// called automatically when the `UITextView`'s embedded scroll view moves.
        ///
        /// Direction derivation:
        ///   - Content-offset Y **decreased** (user pulled content down → viewport moved up)
        ///     → `.forward` → chrome reveals.
        ///   - Content-offset Y **increased** (user pulled content up → viewport moved down)
        ///     → `.reverse` → chrome hides.
        ///
        /// This is the ONLY place a real scroll event touches the SM (§4.3 data-flow).
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let currentY = scrollView.contentOffset.y
            let direction: ScrollDirection = currentY < lastContentOffsetY ? .forward : .reverse
            lastContentOffsetY = currentY
            onScroll?(direction)
        }

        // MARK: UITextViewDelegate — keyboard-dismiss event (FR-19 / §5.1.e)

        /// Emit `onKeyboardDismiss` when the text view loses first-responder status
        /// (keyboard dismisses).  Feeds the chrome-visibility SM (FR-19).
        ///
        /// Nil-safe: `onKeyboardDismiss` is an optional closure — calling it with `?.()`
        /// is a no-op when not set.
        func textViewDidEndEditing(_ textView: UITextView) {
            onKeyboardDismiss?()
        }
    }
}
