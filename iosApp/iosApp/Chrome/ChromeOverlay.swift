// Chrome/ChromeOverlay.swift
// Foglietto — KMP Milestone 4: Liquid Glass Chrome (T-01 morph + top-pad)
//
// Container view composing TopPill + MenuBubble over the editor.
// Reads ChromeVisibility.isVisible and crossfades the chrome layer.
// Owns the GlassEffectContainer and morph namespace so the pill capsule
// and the menu panel share one glass identity and morph capsule↔panel.
//
// EC-14: isMenuPresented is written by EXACTLY two sources —
//   (1) the overflow toggle inside TopPill (via the $isMenuPresented binding)
//   (2) the full-screen transparent tap-catcher rendered when the menu is open
// SM events (injectTyping/injectScroll/injectKeyboardDismiss) and MenuViewModel
// NEVER reference or mutate isMenuPresented. The tap-catcher (not a .popover)
// is the outside-tap dismiss mechanism.
//
// EC-16: the tap-catcher sits INSIDE the chromeVisibility.isVisible crossfaded
// layer, so the menu is dismissed together with the chrome when chrome hides.
//
// ChromeOverlay also owns the CoordinatorBox — a lightweight reference-type
// bridge that lets ContentView publish the live BufferEditor.Coordinator to
// the BottomToolbar closure wiring. BufferEditor sets coordinatorBox.coordinator
// in makeUIView (once, at creation time). ChromeOverlay's closures then capture
// [weak coordinatorBox] to read the coordinator safely at toolbar-tap time.
//
// CANON GAP CG-1: native Liquid Glass material on the chrome layer supersedes
// ui-design-bible §"Auto-hiding overlay chrome" --view-bg-color@90% fill (OQ-01).
// GlassEffectContainer is the single glass grouping for the pill + menu morph.
//
// Spec refs: FR-02, FR-18, FR-19, FR-20, NFR-01, NFR-07;
//            EC-13, EC-14, EC-16, EC-17; CG-1.
// Contract: §3.1 (morph identity seam), §4.1, §4.3.
//
// ⚠️ DEBUG HARNESS (TEMPORARY — REMOVE BEFORE MERGE)
// This file has a diagnostic harness bolted on to find why the overflow menu
// does not open. Everything debug-related is grouped in the "DEBUG HARNESS"
// MARK sections and gated by the three flags in `DebugFlags` below. Set
// `enableDebug = false` (or delete the marked regions) to restore production.

import SwiftUI
import shared

// MARK: - CoordinatorBox

/// Lightweight reference-type bridge that publishes the live `BufferEditor.Coordinator`
/// once it is available (set by `BufferEditor.makeUIView`).
///
/// This avoids a hard dependency between `ContentView`/`ChromeOverlay` and the
/// internal `UIViewRepresentable` coordinator lifecycle. The box is owned as `@State`
/// in `ContentView` and passed to both `BufferEditor` (which writes) and
/// `ChromeOverlay` (which reads for toolbar-closure wiring).
///
/// `coordinator` is declared `weak` so the box does not extend the coordinator's
/// lifetime beyond the UIViewRepresentable's natural teardown.
final class CoordinatorBox {
    /// The live `BufferEditor.Coordinator`. Set once in `BufferEditor.makeUIView`;
    /// cleared automatically when the coordinator deallocates (weak ref). All
    /// toolbar closures guard against `nil` before use (EC-13).
    weak var coordinator: BufferEditor.Coordinator?
}

// MARK: - ChromeOverlay

/// Non-visual composition container for the Liquid Glass chrome controls.
///
/// Lays out:
///   - `TopPill` (top-trailing, within safe area) — Share + overflow `…` toggle.
///   - `MenuBubble` (inline, morphing from the pill) — shown when `isMenuPresented`.
///   - Transparent full-screen tap-catcher — rendered behind the bubble when open
///     to handle outside-tap dismiss (EC-14).
///
/// Reads `chromeVisibility.isVisible` to crossfade the entire chrome layer in/out.
/// Applies `.opacity` + `.animation` so SM transitions animate smoothly (FR-20).
///
/// **Glass morph (§3.1 morph identity seam):**
/// Owns `glassNamespace` (`@Namespace`) and the `chromeGlassID` string constant.
/// Both `TopPill` and `MenuBubble` receive these values and attach
/// `.glassEffectID(chromeGlassID, in: glassNamespace)` so the capsule morphs
/// into the panel and back inside the single `GlassEffectContainer`.
///
/// **Reduce Motion (C-07):**
/// Reads `@Environment(\.accessibilityReduceMotion)`. When true, the morph
/// toggle uses an instantaneous `.identity` / `.opacity` transition instead of
/// the capsule↔panel shape morph.
///
/// **Bubble dismiss contract (EC-14):**
/// `isMenuPresented` is written by EXACTLY two sources — the overflow toggle in
/// `TopPill` and the tap-catcher below. SM events (`injectTyping`, `injectScroll`,
/// `injectKeyboardDismiss`) and `MenuViewModel` NEVER write to `isMenuPresented`.
struct ChromeOverlay: View {

    // MARK: - Inputs (from ContentView / composition root)

    /// Current buffer text — forwarded to `TopPill` for the Share disabled gate (EC-01/FR-08).
    let text: String

    /// The menu view model — forwarded to `MenuBubble` (ctor-injected DIP).
    let menuVM: MenuViewModel

    /// Chrome auto-hide/reveal state machine — drives the crossfade (FR-19/FR-20).
    let chromeVisibility: ChromeVisibility

    /// Coordinator box — read by toolbar closures to dispatch actions (EC-13).
    let coordinatorBox: CoordinatorBox

    /// The `BufferViewModel` — passed through for indent/outdent closures (FR-17).
    let viewModel: BufferViewModel

    // MARK: - Local state

    /// Controls the `MenuBubble` presented state.
    ///
    /// EC-14: written by EXACTLY two sources —
    ///   (1) the overflow button toggle inside `TopPill` (via `$isMenuPresented`)
    ///   (2) the full-screen transparent tap-catcher (sets to `false`)
    /// SM events and `MenuViewModel` NEVER mutate this state.
    @State private var isMenuPresented: Bool = false

    // MARK: - Morph identity (§3.1 morph identity seam)

    /// Namespace that binds the pill capsule and the menu panel into one
    /// shared glass identity, enabling the capsule↔panel morph inside
    /// `GlassEffectContainer` (iOS 26 native glass morph — C-03).
    @Namespace private var glassNamespace

    /// The shared glass effect ID passed to both `TopPill` and `MenuBubble`.
    /// Both call `.glassEffectID(chromeGlassID, in: glassNamespace)` so the
    /// material morphs between the pill's capsule shape and the menu panel shape.
    private static let chromeGlassID = "chrome.morph"

    // MARK: - Accessibility

    /// When `true`, the morph animation is replaced by an instantaneous/opacity
    /// transition (C-07 / `prefers-reduce-motion`).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation seam (§3.1 / C-05 / C-06)

    /// Resolved morph animation — computed once so BOTH `isMenuPresented` write-sites
    /// (C-05) use an identical spring, and `TopPill` receives the same value without
    /// needing its own `@Environment(\.accessibilityReduceMotion)` reader (C-06).
    ///
    /// `nil` when Reduce Motion is enabled (instantaneous toggle); a bouncy spring
    /// otherwise to drive the glass capsule↔panel morph.
    ///
    /// The `.bouncy` curve is the elastic settle that sells the liquid-glass
    /// "drop" feel (per the Liquid Glass morph reference); a linear/critically-
    /// damped curve kills the metaball stretch.
    private var menuToggleAnimation: Animation? {
        reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.15)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - DEBUG HARNESS · flags
    // ════════════════════════════════════════════════════════════════════════
    //
    // Run order:
    //   1. Leave only `enableDebug = true`. Tap the `…`. Read the console + screen.
    //   2. Based on what you see, flip ONE of the other two flags and re-run.
    //
    // What each console line / colour tells you is documented at each call site
    // and summarised in the chat message that produced this file.
    private enum DebugFlags {
        /// Master switch: console prints (state flips, lifecycle, taps) + a
        /// purple full-screen tint shown whenever `isMenuPresented == true`.
        /// The tint is INSIDE the crossfaded layer on purpose: if tapping also
        /// collapses `chromeVisibility.isVisible`, you'll see purple flash then
        /// vanish — that means chrome auto-hide is eating the menu.
        static let enableDebug = true

        /// Flip to `true` if the console shows `isMenuPresented = true` but you
        /// see no menu. Replaces `MenuBubble` with an opaque red placeholder that
        /// carries the SAME glassEffectID. If the red box appears and morphs, the
        /// bug is INSIDE MenuBubble (layout / `menuVM` DI), not the morph plumbing.
        /// If the red box does NOT appear either, the bug is the morph/container.
        static let useDebugPanel = false

        /// Flip to `true` if NOTHING prints and no purple appears on tap. Replaces
        /// `TopPill` with a bare, glass-free `Button`. If the bare button opens the
        /// menu, the glass pill is stealing the tap from its inner `.plain` buttons
        /// (the structural hit-testing problem) — fix is to make the glass a
        /// background sibling, not the ancestor of the buttons.
        static let useBareToggleButton = true
    }

    /// Gated logger — the print is compiled out of release builds entirely.
    private func dbg(_ message: @autoclosure () -> String) {
        #if DEBUG
        if DebugFlags.enableDebug { print("🟣 [ChromeOverlay]", message()) }
        #endif
    }
    // ════════════════════════════════════════════════════════════════════════

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-screen tap-catcher: rendered only when the menu is open,
            // above the editor and behind the bubble (EC-14 outside-tap dismiss).
            // Lives inside this crossfaded layer so EC-16 holds — when chrome
            // crossfades out the tap-catcher disappears with it.
            if isMenuPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // EC-14 writer #2: the tap-catcher closes the menu.
                        // Identical bouncy curve to the TopPill overflow toggle (C-05).
                        dbg("tap-catcher → dismiss")   // DEBUG
                        withAnimation(menuToggleAnimation) {
                            isMenuPresented = false
                        }
                    }
            }

            // ───────────── DEBUG: purple "isMenuPresented" state marker ─────────────
            // No hit-testing, so it never interferes with taps. It sits INSIDE the
            // .opacity(...) layer below, so it also reveals chrome-visibility collapse.
            if DebugFlags.enableDebug && isMenuPresented {
                Color.purple.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            // ────────────────────────────────────────────────────────────────────────

            // Chrome controls: pill + morph container, top-trailing.
            VStack {
                HStack {
                    Spacer()
                    pillAndBubble
                }
                Spacer()
            }
            .padding(.top, 6)
            .padding(.horizontal, 16)
        }
        // Crossfade the chrome layer (including the tap-catcher) with
        // ChromeVisibility.isVisible (FR-20 / EC-16).
        // EC-14: crossfade is purely visual — it does NOT mutate isMenuPresented.
        .opacity(chromeVisibility.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: chromeVisibility.isVisible)
        // ───────────────────────────── DEBUG: state probes ─────────────────────────
        // (1) Does the toggle actually flip the state when you tap the `…`?
        .onChange(of: isMenuPresented) { oldValue, newValue in
            dbg("isMenuPresented: \(oldValue) → \(newValue)")
        }
        // (2) Does tapping secretly collapse the chrome layer (opacity → 0)?
        //     If isVisible flips to false on tap, a *working* menu would still
        //     vanish. They report seeing the pill, so this should stay true.
        .onChange(of: chromeVisibility.isVisible) { oldValue, newValue in
            dbg("chromeVisibility.isVisible: \(oldValue) → \(newValue)")
        }
        // ────────────────────────────────────────────────────────────────────────────
    }

    // MARK: - Pill + morph container (§3.1 morph identity seam)

    /// `GlassEffectContainer` wrapping either `TopPill` (closed) or `MenuBubble`
    /// (open) — never both simultaneously.
    ///
    /// iOS 26 `glassEffectID` morph requires the source and destination glass
    /// surfaces to be **mutually exclusive**: exactly one view bears the shared ID
    /// at any point in time. When `isMenuPresented` flips, SwiftUI removes the
    /// old view and inserts the new one inside the same transaction; the glass
    /// system interpolates the capsule geometry into the panel geometry and back.
    ///
    /// If both children were mounted together (e.g. in a VStack) the system
    /// would find two views with the same ID and skip the morph entirely,
    /// producing the "panel pops in below the pill" symptom observed on-device.
    ///
    /// Both children attach `.glassEffectID(chromeGlassID, in: glassNamespace)`
    /// internally (TopPill.swift:123 / MenuBubble.swift:164) — no change needed
    /// in their bodies.
    ///
    /// The `withAnimation` wrapping `isMenuPresented` changes is Reduce-Motion
    /// gated: when `reduceMotion` is true `menuToggleAnimation` is `nil` and
    /// the swap is instantaneous (C-07).
    @ViewBuilder
    private var pillAndBubble: some View {
        // CANON GAP CG-1: GlassEffectContainer is the iOS 26 native grouping
        // API — no hand-rolled blur/fill/shadow (C-03 / NFR-01/02).
        //
        // `spacing:` is the metaball merge threshold: the larger it is, the more
        // the capsule and panel stay "stuck together" and the liquid stretch
        // reads during the capsule↔panel morph. Without it (default) the shapes
        // hand off too far apart and the morph degrades to a plain swap — the
        // "menu pops under the pill" symptom. 30–45 matches the Apple Notes feel.
        GlassEffectContainer(spacing: 35) {
            if isMenuPresented {
                openContent
            } else {
                closedContent
            }
        }
    }

    // MARK: Open state (menu)

    /// The destination glass surface when the menu is open.
    /// Normally `MenuBubble`; swapped for a debug placeholder when
    /// `DebugFlags.useDebugPanel` is set (see flags).
    @ViewBuilder
    private var openContent: some View {
        if DebugFlags.useDebugPanel {
            // DEBUG: opaque placeholder carrying the SAME morph id, to test the
            // container/morph independently of MenuBubble's internals.
            debugPanel
                .onAppear { dbg("debugPanel onAppear") }
                .onDisappear { dbg("debugPanel onDisappear") }
        } else {
            // Menu open — panel is the sole bearer of chromeGlassID.
            // No explicit .transition on the panel container: .glassEffectID
            // owns the capsule↔panel geometry morph (C-04). Inner menu rows
            // carry .transition(.opacity) in MenuBubble.swift (T-04).
            MenuBubble(
                menuVM: menuVM,
                isPresented: $isMenuPresented,
                glassNamespace: glassNamespace,
                glassID: Self.chromeGlassID
            )
            .onAppear { dbg("MenuBubble onAppear") }     // DEBUG
            .onDisappear { dbg("MenuBubble onDisappear") } // DEBUG
        }
    }

    // MARK: Closed state (pill)

    /// The source glass surface when the menu is closed.
    /// Normally `TopPill`; swapped for a bare glass-free `Button` when
    /// `DebugFlags.useBareToggleButton` is set (see flags).
    @ViewBuilder
    private var closedContent: some View {
        if DebugFlags.useBareToggleButton {
            // DEBUG: no glass, no morph id — pure hit-testing probe.
            // If THIS opens the menu but TopPill doesn't, the glass pill is
            // swallowing the tap meant for its inner .plain buttons.
            Button("TAP (debug)") {
                dbg("bare debug button tapped")
                withAnimation(menuToggleAnimation) { isMenuPresented.toggle() }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .onAppear { dbg("bare debug button onAppear") }
        } else {
            // Menu closed — pill is the sole bearer of chromeGlassID.
            // withAnimation at the overflow toggle site is applied inside
            // TopPill using the resolved menuToggleAnimation from here (C-06).
            // The tap-catcher above uses the same spring value (C-05).
            TopPill(
                text: text,
                isMenuPresented: $isMenuPresented,
                glassNamespace: glassNamespace,
                glassID: Self.chromeGlassID,
                menuToggleAnimation: menuToggleAnimation
            )
            .onAppear { dbg("TopPill onAppear") }   // DEBUG
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - DEBUG HARNESS · views  (delete this whole region to go back to prod)
    // ════════════════════════════════════════════════════════════════════════

    /// Opaque red placeholder used when `DebugFlags.useDebugPanel` is set.
    /// Carries the same morph id as MenuBubble so the capsule↔panel morph still
    /// has a destination. If this appears and morphs, MenuBubble's internals are
    /// the suspect, not the morph plumbing.
    private var debugPanel: some View {
        Color.red.opacity(0.9)
            .frame(width: 280, height: 320)
            .overlay(
                Text("DEBUG PANEL")
                    .font(.headline)
                    .foregroundStyle(.white)
            )
            .glassEffect(in: .rect(cornerRadius: 28))
            .glassEffectID(Self.chromeGlassID, in: glassNamespace)
    }
    // ════════════════════════════════════════════════════════════════════════
}
