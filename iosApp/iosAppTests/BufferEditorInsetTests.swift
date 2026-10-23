// BufferEditorInsetTests.swift
// iosAppTests
//
// XCTest coverage for the shared chrome geometry contract and the editor inset seam:
//   - the `ChromeMetrics` lockstep cases (§7.1), and
//   - the `BufferEditor` inset cases (§5.1.d): the token-derived `kEditorTopInset`
//     seam, `BufferTextView` reconciliation, and the `updateUIView` leg seam.
//
// Strategy:
//   The lockstep and formula cases are pure value assertions against the shared
//   geometry tokens — no window, no view, no async. They exist as the tripwire for
//   the FR-10 lockstep rule: the chrome pill geometry the editor's first-line inset
//   is computed from must never drift from the inline gated tap-target frames that
//   decide the rendered capsule height.
//
//   The reconciliation cases drive `BufferTextView` through a test window whose
//   safe-area top is fixed by the test double below, so the inset contract is
//   asserted against the window's live value on any simulator device — never
//   against a hard-coded constant (EC-24/EC-25).
//
// M3 CI conventions (MANDATORY):
//   @MainActor at class level; no async/await, no Task, no wall-clock sleeps;
//   import shared + @testable import iosApp.
//
// Spec refs: §5.1.d, §5.1.f, §5.2, §7.1, §7.2; FR-09, FR-09n, FR-10, FR-10n, FR-12,
//            FR-14n, FR-21; NFR-01, NFR-03, NFR-04, NFR-06; EC-12, EC-24, EC-25.
// CI-verified on macos-26 iOS Simulator — not locally compilable (no macOS host).

import XCTest
import UIKit
@testable import iosApp
import shared

// ---------------------------------------------------------------------------
// MARK: - Window test double
// ---------------------------------------------------------------------------

/// `UIWindow` whose safe-area top inset is fixed by the test.
///
/// A real window's safe-area top is device-driven and cannot be assigned, so the
/// reconciliation cases drive this double instead. Expectations are still always
/// derived from `window.safeAreaInsets.top` — the live value under test — so the
/// cases hold on every simulator device profile (EC-25).
@MainActor
private final class TestSafeAreaWindow: UIWindow {

    var safeAreaTop: CGFloat

    init(safeAreaTop: CGFloat) {
        self.safeAreaTop = safeAreaTop
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used by these tests")
    }

    override var safeAreaInsets: UIEdgeInsets {
        UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 0, right: 0)
    }
}

/// Build a `BufferTextView` attached to a window with the given safe-area top.
///
/// Attachment matters: `didMoveToWindow` is what drives the first real reconciliation
/// (EC-24), so the returned view has already been reconciled once by the window.
@MainActor
private func makeAttachedTextView(
    safeAreaTop: CGFloat
) -> (view: BufferEditor.BufferTextView, window: TestSafeAreaWindow) {
    let window = TestSafeAreaWindow(safeAreaTop: safeAreaTop)
    let view = BufferEditor.BufferTextView(frame: window.bounds)
    window.addSubview(view)
    return (view, window)
}

// ---------------------------------------------------------------------------
// MARK: - BufferEditorInsetTests
// ---------------------------------------------------------------------------

/// The `ChromeMetrics` lockstep contract and the `BufferEditor` inset seam: the shared
/// geometry tokens behind the chrome pill layout, the editor's first-line inset formula,
/// and the window-attached reconciliation that keeps the first line beneath the pill.
@MainActor
final class BufferEditorInsetTests: XCTestCase {

    // -----------------------------------------------------------------------
    // MARK: - ChromeMetrics lockstep

    /// The token must equal the inline gated 44pt button frames that decide the
    /// rendered capsule height (§5.1.c lockstep; NFR-04/m6-11).
    func testPillHeightMatchesGatedTapTargetLiteral() {
        XCTAssertEqual(ChromeMetrics.pillHeight, 44)
    }

    /// The full-bleed formula basis: the editor's only top geometry token is the
    /// breathing gap below the safe area (glass-over-content supersession).
    func testContentTopGapMatchesEditorInsetFormulaBasis() {
        XCTAssertEqual(ChromeMetrics.contentTopGap, 4)
    }

    // -----------------------------------------------------------------------
    // MARK: - kEditorTopInset — purity and totality (FR-09n / EC-25)

    /// Pure and total: each reference safe-area input maps to safe area + the 4 pt
    /// breathing gap, covering the Dynamic-Island class (59), the provisional
    /// pre-attachment input (0), SE-class (20), and iPad-class (24) devices.
    func test_kEditorTopInset_referencePointsAreTotal() {
        XCTAssertEqual(kEditorTopInset(safeAreaTop: 59), 63)
        XCTAssertEqual(kEditorTopInset(safeAreaTop: 0), 4)
        XCTAssertEqual(kEditorTopInset(safeAreaTop: 20), 24)
        XCTAssertEqual(kEditorTopInset(safeAreaTop: 24), 28)
    }

    /// FR-10n: the seam reads the live token at call time, so a token value change
    /// flows into the editor inset with no edit in the editor file. Asserted at two
    /// inputs, and coupled to the token the formula basis must keep.
    func test_kEditorTopInset_derivesFromLiveChromeTokens() {
        let safeAreaTops: [CGFloat] = [59, 20]
        for safeAreaTop in safeAreaTops {
            XCTAssertEqual(
                kEditorTopInset(safeAreaTop: safeAreaTop),
                safeAreaTop + ChromeMetrics.contentTopGap,
                "the inset must be the live token expression, never a copied literal (FR-10n)"
            )
        }
        XCTAssertEqual(
            ChromeMetrics.contentTopGap,
            4,
            "the formula basis must still be the breathing-gap token"
        )
    }

    /// FR-09: a zero safe area must not reproduce the removed fixed fallback value,
    /// so the deleted constant cannot have been re-baked into the seam.
    func test_kEditorTopInset_zeroSafeAreaIsNotTheDeletedFallback() {
        XCTAssertNotEqual(kEditorTopInset(safeAreaTop: 0), 127)
        XCTAssertNotEqual(
            kEditorTopInset(safeAreaTop: 0),
            kEditorTopInset(safeAreaTop: 59),
            "a zero safe area must shift the inset, not fall back to the 59 pt constant"
        )
    }

    // -----------------------------------------------------------------------
    // MARK: - BufferTextView reconciliation (EC-12 / EC-24 / EC-25)

    /// A divergent inset on an attached view converges on the window's live safe area:
    /// top from the token seam, sides from the shared horizontal token, bottom zero.
    func test_reconcileTopInset_attachedView_convergesOnWindowSafeArea() {
        let (view, window) = makeAttachedTextView(safeAreaTop: 59)
        view.textContainerInset = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

        view.reconcileTopInset()

        XCTAssertEqual(view.textContainerInset.top, kEditorTopInset(safeAreaTop: window.safeAreaInsets.top))
        XCTAssertEqual(view.textContainerInset.left, ChromeMetrics.chromeHorizontalInset)
        XCTAssertEqual(view.textContainerInset.right, ChromeMetrics.chromeHorizontalInset)
        XCTAssertEqual(view.textContainerInset.bottom, 0)
        XCTAssertNotEqual(view.textContainerInset.top, 1, "the divergent top must have been rewritten")
    }

    /// Detached view: reconciliation returns early and the last applied inset stands —
    /// no fallback re-substitution after detach (EC-24).
    func test_reconcileTopInset_detachedView_keepsLastAppliedInset() {
        let view = BufferEditor.BufferTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertNil(view.window)
        let applied = UIEdgeInsets(
            top: kEditorTopInset(safeAreaTop: 0),
            left: ChromeMetrics.chromeHorizontalInset,
            bottom: 0,
            right: ChromeMetrics.chromeHorizontalInset
        )
        view.textContainerInset = applied

        view.reconcileTopInset()

        XCTAssertEqual(view.textContainerInset, applied)
    }

    /// The normal-launch ordering (EC-24): the provisional token-derived inset holds
    /// before attachment, the window attachment replaces it with the real safe-area
    /// value, and detaching afterwards keeps that value.
    func test_textViewAttachment_lifecycleProvisionalThenAttachedThenDetached() {
        let view = BufferEditor.BufferTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.textContainerInset = UIEdgeInsets(
            top: kEditorTopInset(safeAreaTop: 0),
            left: ChromeMetrics.chromeHorizontalInset,
            bottom: 0,
            right: ChromeMetrics.chromeHorizontalInset
        )

        view.reconcileTopInset()
        XCTAssertEqual(view.textContainerInset.top, 4, "pre-attachment the provisional value stands")
        XCTAssertNotEqual(view.textContainerInset.top, 127, "the removed fixed fallback must never ship")

        let window = TestSafeAreaWindow(safeAreaTop: 59)
        window.addSubview(view)
        XCTAssertEqual(view.textContainerInset.top, kEditorTopInset(safeAreaTop: window.safeAreaInsets.top))

        let applied = view.textContainerInset
        view.removeFromSuperview()
        view.reconcileTopInset()
        XCTAssertEqual(view.textContainerInset, applied, "detach keeps the last applied inset (EC-24)")
    }

    /// Divergence-only: once top matches the window's safe area, a further call writes
    /// nothing at all — the sentinel side values survive, proving the guard returned
    /// before rewriting the inset (no redundant layout invalidation).
    func test_reconcileTopInset_convergedTop_makesNoWrite() {
        let (view, window) = makeAttachedTextView(safeAreaTop: 59)
        view.reconcileTopInset()
        let convergedTop = view.textContainerInset.top
        XCTAssertEqual(convergedTop, kEditorTopInset(safeAreaTop: window.safeAreaInsets.top))

        view.textContainerInset = UIEdgeInsets(top: convergedTop, left: 999, bottom: 999, right: 999)
        view.reconcileTopInset()

        XCTAssertEqual(view.textContainerInset.top, convergedTop)
        XCTAssertEqual(view.textContainerInset.left, 999, "a convergent top must short-circuit the write")
        XCTAssertEqual(view.textContainerInset.right, 999, "a convergent top must short-circuit the write")
        XCTAssertEqual(view.textContainerInset.bottom, 999, "a convergent top must short-circuit the write")
    }

    /// Clobber-free (EC-12): with user text and a mid-edit selection present, the
    /// reconciliation writes only `textContainerInset` — text, selection, and typing
    /// attributes come back untouched.
    func test_reconcileTopInset_divergentInset_preservesTextSelectionAndTypingAttributes() {
        let (view, window) = makeAttachedTextView(safeAreaTop: 59)
        view.text = "mid-edit content"
        view.selectedRange = NSRange(location: 4, length: 7)
        view.typingAttributes = [.font: UIFont.monospacedSystemFont(ofSize: 21, weight: .regular)]
        view.textContainerInset = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

        let text = view.text
        let selection = view.selectedRange
        let typing = view.typingAttributes as NSDictionary

        view.reconcileTopInset()

        XCTAssertEqual(view.textContainerInset.top, kEditorTopInset(safeAreaTop: window.safeAreaInsets.top))
        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.selectedRange, selection)
        XCTAssertEqual(view.selectedRange.length, 7, "the mid-edit selection must not be collapsed")
        XCTAssertEqual(view.typingAttributes as NSDictionary, typing)
    }

    /// Rotation (EC-25): a safe-area change re-reconciles the inset from the new value
    /// and leaves text and selection untouched.
    func test_safeAreaInsetsDidChange_reconcilesFromNewSafeAreaAndPreservesText() {
        let (view, window) = makeAttachedTextView(safeAreaTop: 59)
        view.text = "rotation keeps my text"
        view.selectedRange = NSRange(location: 9, length: 4)
        let text = view.text
        let selection = view.selectedRange

        window.safeAreaTop = 0
        view.textContainerInset = UIEdgeInsets(top: 999, left: 999, bottom: 999, right: 999)

        view.safeAreaInsetsDidChange()

        XCTAssertEqual(view.textContainerInset.top, kEditorTopInset(safeAreaTop: window.safeAreaInsets.top))
        XCTAssertEqual(view.textContainerInset.left, ChromeMetrics.chromeHorizontalInset)
        XCTAssertEqual(view.textContainerInset.right, ChromeMetrics.chromeHorizontalInset)
        XCTAssertEqual(view.textContainerInset.bottom, 0)
        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.selectedRange, selection)
    }

    // -----------------------------------------------------------------------
    // MARK: - updateUIView reconciliation leg (EC-12 / EC-24)

    /// The update leg routes through the window-guarded, divergence-only reconciliation:
    /// the inset converges and a mid-edit state survives with zero writes to text,
    /// selection, or typing attributes.
    func test_updateUIViewReconcileLeg_convergesAndPreservesMidEditState() {
        let (view, window) = makeAttachedTextView(safeAreaTop: 59)
        view.text = "tick"
        view.selectedRange = NSRange(location: 2, length: 1)
        view.typingAttributes = [.font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)]
        view.textContainerInset = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)

        let text = view.text
        let selection = view.selectedRange
        let typing = view.typingAttributes as NSDictionary

        BufferEditor.reconcileInset(of: view)

        XCTAssertEqual(view.textContainerInset.top, kEditorTopInset(safeAreaTop: window.safeAreaInsets.top))
        XCTAssertEqual(view.textContainerInset.left, ChromeMetrics.chromeHorizontalInset)
        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.selectedRange, selection)
        XCTAssertEqual(view.typingAttributes as NSDictionary, typing)
    }

    /// A view that is not the editor's text view is left untouched by the leg.
    func test_updateUIViewReconcileLeg_ignoresOtherTextViews() {
        let plain = UITextView()
        let applied = plain.textContainerInset

        BufferEditor.reconcileInset(of: plain)

        XCTAssertEqual(plain.textContainerInset, applied)
    }
}
