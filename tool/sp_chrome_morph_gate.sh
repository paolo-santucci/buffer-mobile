#!/usr/bin/env bash
# tool/sp_chrome_morph_gate.sh — SP KMP iOS Chrome Morph + Layout Polish regression gate
#
# Asserts the source-scan markers pinned in §3.1 of the Quick Plan
# qp-20260621-kmp-ios-chrome-morph-layout.md (checks a–d).
# Run from the repo root: bash tool/sp_chrome_morph_gate.sh
#
# Exit 0 only when ALL checks (a)–(d) pass.
# Each check prints a labelled PASS/FAIL line; the script exits 1 on any FAIL.
#
# Design rules (mirror m4_gate.sh idioms exactly):
#   - result()/finish() helpers accumulate PASS/FAIL counts.
#   - Presence checks use git ls-files + grep.
#   - Absence checks use grep -RIn + grep -Ev '^[[:space:]]*//' (comment-exclusion)
#     so a doc-comment mentioning the forbidden token does not trip the gate.
#   - Order checks grep -n the relevant identifiers, exclude comment lines, then
#     compare the first-occurrence line numbers arithmetically.
#   - No network access; no xcodebuild/plutil (macOS-only — runs on ubuntu-latest).
#   - chain: m4_gate.sh (which chains m1_gate.sh) is invoked last (check d) so
#     an earlier invariant cannot regress while this gate is green.
#
# §3.1 pinned source-scan markers:
#   Token                          Where                     Asserted
#   GlassEffectContainer           ChromeOverlay.swift       PRESENT
#   glassEffectID                  Chrome/ (any file)        PRESENT
#   .popover(                      ChromeOverlay.swift       ABSENT  (code lines only)
#   accessibilityReduceMotion      ChromeOverlay.swift       PRESENT
#   textContainerInset (non-.zero) BufferEditor.swift        PRESENT and not = .zero
#   lineFragmentPadding = 0        BufferEditor.swift        PRESENT
#   body: closeKeyboardButton      BottomToolbar.swift body  BEFORE copyButton
#
# Spec refs: qp-20260621 §3.1; C-03, C-06, C-07, C-08; EC-14; NFR-01/02/03/04.

set -uo pipefail

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# result <label> <ok|fail> [detail]
#   Print a labelled PASS/FAIL line.  Accumulate counts; call finish() at end.
# ---------------------------------------------------------------------------
result() {
    local label="$1"
    local status="$2"
    local detail="${3:-}"
    if [[ "$status" == "ok" ]]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label${detail:+ — $detail}" >&2
        FAIL=$((FAIL + 1))
    fi
}

finish() {
    echo ""
    echo "=== SP Chrome-Morph gate: $PASS passed, $FAIL failed ==="
    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

echo "=== SP Chrome-Morph gate: starting source-scan verification ==="
echo ""

# ---------------------------------------------------------------------------
# (a) BottomToolbar.swift body order: closeKeyboardButton before copyButton
#
# §3.1 marker: body order `closeKeyboardButton` before `copyButton`
# Strategy:
#   - grep -n both identifiers in BottomToolbar.swift, excluding comment lines.
#   - Extract the FIRST occurrence line number of each.
#   - Assert line(closeKeyboardButton) < line(copyButton).
#
# "First occurrence" is used so that the computed-var DECLARATION lines (which
# appear later in the file) do not interfere: the body references appear first
# at the HStack rows, and the declarations follow.  Comment lines are excluded
# via grep -Ev '^[[:space:]]*//' so a doc-comment that mentions either name
# (e.g. in the struct-level doc block) does not pollute the comparison.
#
# If the file is not tracked (pre-M4 scaffold missing), vacuously PASS.
# ---------------------------------------------------------------------------
echo "[a] BottomToolbar body order: closeKeyboardButton before copyButton ..."

bt_file="iosApp/iosApp/Chrome/BottomToolbar.swift"
if git ls-files --error-unmatch -- "$bt_file" > /dev/null 2>&1; then
    # First occurrence of each identifier on a non-comment line.
    # grep -n returns "line:content"; we take the first match's line number.
    close_line=$(grep -n "closeKeyboardButton" "$bt_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' \
        | head -1 \
        | cut -d: -f1)
    copy_line=$(grep -n "copyButton" "$bt_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' \
        | head -1 \
        | cut -d: -f1)

    if [[ -z "$close_line" ]] || [[ -z "$copy_line" ]]; then
        result "BottomToolbar-body-order" fail \
            "closeKeyboardButton (line=${close_line:-MISSING}) or copyButton (line=${copy_line:-MISSING}) not found in $bt_file"
    elif [[ "$close_line" -lt "$copy_line" ]]; then
        result "BottomToolbar-body-order" ok \
            "(closeKeyboardButton @L${close_line} < copyButton @L${copy_line})"
    else
        result "BottomToolbar-body-order" fail \
            "closeKeyboardButton @L${close_line} is NOT before copyButton @L${copy_line} in $bt_file (§3.1 body order)"
    fi
else
    result "BottomToolbar-body-order" ok "(vacuous: $bt_file not yet tracked)"
fi

# ---------------------------------------------------------------------------
# (b-1) BufferEditor.swift: textContainerInset present AND not = .zero
#
# §3.1 marker: textContainerInset (non-.zero) PRESENT
# Strategy:
#   - Assert at least one non-comment code line contains "textContainerInset".
#   - Assert NO non-comment code line contains "textContainerInset" followed by
#     "= .zero" (the old initialiser that the inset rewrite replaces).
#
# If the file is not tracked, vacuously PASS.
# ---------------------------------------------------------------------------
echo "[b1] BufferEditor.swift: textContainerInset present ..."

be_file="iosApp/iosApp/Editor/BufferEditor.swift"
if git ls-files --error-unmatch -- "$be_file" > /dev/null 2>&1; then
    # Non-comment lines that mention textContainerInset
    tci_present=$(grep -n "textContainerInset" "$be_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' || true)
    # Non-comment lines that assign textContainerInset to .zero
    tci_zero=$(grep -n "textContainerInset" "$be_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' \
        | grep "= \.zero" || true)

    if [[ -z "$tci_present" ]]; then
        result "BufferEditor-textContainerInset-present" fail \
            "textContainerInset not found on any non-comment code line in $be_file (§3.1)"
    elif [[ -n "$tci_zero" ]]; then
        result "BufferEditor-textContainerInset-present" fail \
            "textContainerInset is still '= .zero' on non-comment code line(s) in $be_file (§3.1):
$tci_zero"
    else
        result "BufferEditor-textContainerInset-present" ok
    fi
else
    result "BufferEditor-textContainerInset-present" ok "(vacuous: $be_file not yet tracked)"
fi

# ---------------------------------------------------------------------------
# (b-2) BufferEditor.swift: lineFragmentPadding = 0 present
#
# §3.1 marker: lineFragmentPadding = 0 PRESENT (side inset stays exactly 16 pt)
# ---------------------------------------------------------------------------
echo "[b2] BufferEditor.swift: lineFragmentPadding = 0 present ..."

if git ls-files --error-unmatch -- "$be_file" > /dev/null 2>&1; then
    lfp_hits=$(grep -n "lineFragmentPadding = 0" "$be_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' || true)
    if [[ -n "$lfp_hits" ]]; then
        result "BufferEditor-lineFragmentPadding-zero" ok
    else
        result "BufferEditor-lineFragmentPadding-zero" fail \
            "'lineFragmentPadding = 0' not found on any non-comment code line in $be_file (§3.1)"
    fi
else
    result "BufferEditor-lineFragmentPadding-zero" ok "(vacuous: $be_file not yet tracked)"
fi

# ---------------------------------------------------------------------------
# (c-1) ChromeOverlay.swift: NO .popover( on non-comment code lines
#
# §3.1 marker: .popover( ABSENT
# Strategy: grep -RIn the file for '.popover(' then strip comment lines.
# Any remaining hit is a violation.
# Comment-exclusion uses grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' (the grep -n
# output format is "filename:lineno:content"; we exclude lines whose content
# portion starts with whitespace+//).
#
# If the file is not tracked, vacuously PASS (nothing to violate).
# ---------------------------------------------------------------------------
echo "[c1] ChromeOverlay.swift: no .popover( on non-comment code lines ..."

co_file="iosApp/iosApp/Chrome/ChromeOverlay.swift"
if git ls-files --error-unmatch -- "$co_file" > /dev/null 2>&1; then
    # grep -In (case-sensitive, line numbers); exclude comment lines.
    # grep -n output: "lineno:content" (single-file); exclude lines whose
    # content portion starts with optional-whitespace + //.
    popover_hits=$(grep -n "\.popover(" "$co_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' || true)
    if [[ -z "$popover_hits" ]]; then
        result "ChromeOverlay-no-popover" ok
    else
        result "ChromeOverlay-no-popover" fail \
            "'.popover(' found on non-comment code line(s) in $co_file (§3.1 — must be replaced by GlassEffectContainer morph):
$popover_hits"
    fi
else
    result "ChromeOverlay-no-popover" ok "(vacuous: $co_file not yet tracked)"
fi

# ---------------------------------------------------------------------------
# (c-2) Chrome/: glassEffectID present anywhere under iosApp/iosApp/Chrome/
#
# §3.1 marker: glassEffectID PRESENT (may live in TopPill/MenuBubble/ChromeOverlay)
# ---------------------------------------------------------------------------
echo "[c2] Chrome/: glassEffectID present (anywhere under iosApp/iosApp/Chrome/) ..."

chrome_dir="iosApp/iosApp/Chrome"
if [[ -d "$chrome_dir" ]]; then
    geid_hits=$(grep -RIn "glassEffectID" "$chrome_dir/" 2>/dev/null \
        | grep -Ev '^[^:]+:[0-9]+:[[:space:]]*//' || true)
    if [[ -n "$geid_hits" ]]; then
        result "Chrome-glassEffectID-present" ok
    else
        result "Chrome-glassEffectID-present" fail \
            "'glassEffectID' not found on any non-comment code line under $chrome_dir/ (§3.1)"
    fi
else
    result "Chrome-glassEffectID-present" ok "(vacuous: $chrome_dir/ does not exist yet)"
fi

# ---------------------------------------------------------------------------
# (c-3) ChromeOverlay.swift: GlassEffectContainer present
#
# §3.1 marker: GlassEffectContainer PRESENT (iOS 26 native glass morph — C-03)
# ---------------------------------------------------------------------------
echo "[c3] ChromeOverlay.swift: GlassEffectContainer present ..."

if git ls-files --error-unmatch -- "$co_file" > /dev/null 2>&1; then
    gec_hits=$(grep -n "GlassEffectContainer" "$co_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' || true)
    if [[ -n "$gec_hits" ]]; then
        result "ChromeOverlay-GlassEffectContainer-present" ok
    else
        result "ChromeOverlay-GlassEffectContainer-present" fail \
            "'GlassEffectContainer' not found on any non-comment code line in $co_file (§3.1 — C-03)"
    fi
else
    result "ChromeOverlay-GlassEffectContainer-present" ok "(vacuous: $co_file not yet tracked)"
fi

# ---------------------------------------------------------------------------
# (c-4) ChromeOverlay.swift: accessibilityReduceMotion present
#
# §3.1 marker: accessibilityReduceMotion PRESENT (C-07 reduce-motion gate)
# ---------------------------------------------------------------------------
echo "[c4] ChromeOverlay.swift: accessibilityReduceMotion present ..."

if git ls-files --error-unmatch -- "$co_file" > /dev/null 2>&1; then
    arm_hits=$(grep -n "accessibilityReduceMotion" "$co_file" 2>/dev/null \
        | grep -Ev '^[0-9]+:[[:space:]]*//' || true)
    if [[ -n "$arm_hits" ]]; then
        result "ChromeOverlay-accessibilityReduceMotion-present" ok
    else
        result "ChromeOverlay-accessibilityReduceMotion-present" fail \
            "'accessibilityReduceMotion' not found on any non-comment code line in $co_file (§3.1 — C-07)"
    fi
else
    result "ChromeOverlay-accessibilityReduceMotion-present" ok "(vacuous: $co_file not yet tracked)"
fi

# ---------------------------------------------------------------------------
# (d) Chain m4_gate.sh (which itself chains m1_gate.sh)
#
# Ensures no earlier invariant can regress while this gate is green.
# m4_gate chains m1 internally, so a single invocation covers both.
# ---------------------------------------------------------------------------
echo "[d] Chaining tool/m4_gate.sh (includes m1_gate chain) ..."
echo ""

m4_gate="tool/m4_gate.sh"
if [[ -f "$m4_gate" ]]; then
    if bash "$m4_gate"; then
        result "m4-gate-chain" ok
    else
        result "m4-gate-chain" fail \
            "tool/m4_gate.sh (or its chained m1_gate) reported failures — earlier invariant regressed"
    fi
else
    result "m4-gate-chain" fail \
        "tool/m4_gate.sh not found — cannot assert m1/m4 invariant chain"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
finish
