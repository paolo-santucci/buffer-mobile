#!/usr/bin/env bash
# M6 acceptance gate — buffer-mobile
#
# Spec refs: FR-M6-11, FR-M6-12, FR-M6-16, FR-M6-18, FR-M6-19, FR-M6-23,
#            NFR-M6-01, NFR-M6-02, NFR-M6-07, NFR-M6-08, OQ-M6-15
# Platforms: Android, iOS (runs on Linux CI host — no device needed for source
#            scans or the full `flutter test` suite)
#
# All checks must pass; the script exits non-zero naming the first offender.
# Mirrors the structure and style of tool/m5_gate.sh.
#
# Gate inventory (spec §7.1, TASK-15):
#   Gate 1: dart format — all files formatted
#   Gate 2: flutter analyze — 0 issues
#   Gate 3: full flutter test suite — 0 failures (incl. m6_gate_test.dart)
#   Gate 4: boot-smoke integration test (headless)
#   Shell source scans (complement m6_gate_test.dart Dart-level scans):
#     S1: no requireValue in settings_provider.dart (NFR-M6-07 / EC-08)
#     S2: no literal Text()/Semantics(label:)/tooltip:/hintText: strings in
#         lib/presentation/shell/, lib/presentation/settings/, lib/presentation/about/
#         (NFR-M6-01 widened NFR-10 gate)
#     S3: ARB key parity — app_en.arb and app_it.arb key sets are equal
#         (NFR-M6-02)
#     S4: exactly one fontSizeToast emitter in lib/presentation/ (FR-M6-16; M7-inverted)
#     S5: no kDebugMode nav block in buffer_screen.dart (FR-M6-23)
#     S6: AndroidManifest.xml contains android.intent.action.VIEW + https
#         (FR-M6-11, NFR-M6-08)
#
# Critical patterns to avoid (learned from M4/M5 shell-gate experience):
#   (a) Filter comment lines (strip lines where first non-space token is //)
#       before scanning so comments referencing a forbidden token don't
#       false-positive.
#   (b) Use `grep -c ... || true` pattern — NOT `if ! pipeline | grep -q`
#       which breaks under `set -o pipefail` because grep -q exits early via
#       SIGPIPE, causing the upstream pipeline to receive SIGPIPE and fail.
#
# Usage:
#   bash tool/m6_gate.sh          # from the project root
#   ./tool/m6_gate.sh

set -euo pipefail

# Resolve project root relative to this script's location so it works from
# any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ──────────────────────────────────────────────────────────────────────────────
# Utilities
# ──────────────────────────────────────────────────────────────────────────────

pass() { echo "[PASS] $*"; }
fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# Gate 1 — dart format: no files need reformatting
#
# Scans lib/, test/, and integration_test/ — all three directories are in
# scope for M6.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 1: dart format ---"
format_dirs="$ROOT/lib $ROOT/test"
if [ -d "$ROOT/integration_test" ]; then
  format_dirs="$format_dirs $ROOT/integration_test"
fi

if dart format --set-exit-if-changed $format_dirs > /dev/null 2>&1; then
  pass "dart format — all files formatted"
else
  fail "Gate 1 FAILED: dart format would change files; run 'dart format lib/ test/ integration_test/'"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 2 — flutter analyze: exit 0, zero issues
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 2: flutter analyze ---"
analyze_output=$(flutter analyze --no-pub 2>&1)
if echo "$analyze_output" | grep -qE "^No issues found"; then
  pass "flutter analyze — 0 issues"
else
  echo "$analyze_output" >&2
  fail "Gate 2 FAILED: flutter analyze reported issues"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 3 — full flutter test suite: 0 failures
#
# Runs the entire test/ directory (unit + widget + gate tests), which includes
# test/m6_gate_test.dart (the 10 source-scan sub-gates). The on-device
# integration tests (tagged @Tags(['on-device'])) are excluded from this
# headless run.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 3: full flutter test suite ---"
if flutter test --no-pub 2>&1; then
  pass "flutter test — all tests passed"
else
  fail "Gate 3 FAILED: flutter test reported failures"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 4 — boot-smoke integration test (headless)
#
# Verifies the M6 composition root (ProviderScope + BufferApp now as
# ConsumerWidget reading themeModeProvider + all M6 providers) mounts without
# exception using the flutter-tester VM device.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 4: boot-smoke integration test (headless) ---"
if flutter test integration_test/boot_smoke_test.dart \
    --device-id flutter-tester \
    --no-pub 2>&1; then
  pass "boot-smoke — ProviderScope + BufferApp + BufferScreen mount; '/' route renders AppTheme surface"
else
  fail "Gate 4 FAILED: boot-smoke integration test failed"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Shell-level source scans (fast, no flutter required — run after test suite
# so failures are specific). These complement the m6_gate_test.dart sub-gates
# and provide immediate CI feedback without loading the Dart VM.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Shell source scans ---"

# S1: settings_provider.dart — no requireValue (NFR-M6-07 / EC-08)
#
# themeModeProvider and setColorScheme must read `state.value ?? const
# AppSettings()` — never requireValue — so they don't throw during AsyncLoading
# on first frame.
echo "--- S1: settings_provider.dart no requireValue ---"
SETTINGS_PROVIDER="$ROOT/lib/presentation/settings/settings_provider.dart"
if [ ! -f "$SETTINGS_PROVIDER" ]; then
  fail "S1 FAILED: lib/presentation/settings/settings_provider.dart not found"
fi
# Note: use grep -vE "comment lines" | grep -c || true pattern (pipefail-safe).
# Avoid `if ! pipeline | grep -q` which breaks under pipefail via SIGPIPE.
s1_count=$(grep -vE "^\s*(//)|\*" "$SETTINGS_PROVIDER" \
  | grep -c "requireValue" || true)
if [ "$s1_count" -gt 0 ]; then
  fail "S1 FAILED: settings_provider.dart contains requireValue (NFR-M6-07 / EC-08 — must use .value ?? const AppSettings())"
fi
pass "S1 — settings_provider.dart has no requireValue"

# S2: no literal display strings in M6 presentation dirs (NFR-M6-01 widened)
#
# Checks lib/presentation/shell/, lib/presentation/settings/, and
# lib/presentation/about/ for:
#   - Text('...')  / Text("...")
#   - Semantics(label: '...') / Semantics(label: "...")
#   - tooltip: '...' / tooltip: "..."
#   - hintText: '...' / hintText: "..."
# Comment lines are stripped before scanning.
echo "--- S2: no literal display strings in M6 presentation dirs ---"
m6_dirs=(
  "$ROOT/lib/presentation/shell"
  "$ROOT/lib/presentation/settings"
  "$ROOT/lib/presentation/about"
)
s2_hits=""
for dir in "${m6_dirs[@]}"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    file_hits=$(
      grep -vE "^\s*(//)|\*" "$f" 2>/dev/null \
        | grep -E "Text\(['\"][^'\"]+['\"\)]|Semantics\s*\([^)]*label\s*:\s*['\"][^'\"]+['\"]|tooltip\s*:\s*['\"][^'\"]+['\"]|hintText\s*:\s*['\"][^'\"]+['\"]" \
        || true
    )
    if [ -n "$file_hits" ]; then
      s2_hits="$s2_hits\n$f:\n$file_hits"
    fi
  done < <(find "$dir" -name "*.dart" | sort)
done
if [ -n "$s2_hits" ]; then
  printf "%b\n" "$s2_hits" >&2
  fail "S2 FAILED: M6 presentation dirs contain literal display strings (NFR-M6-01 / FR-M6-19)"
fi
pass "S2 — no literal display strings in M6 presentation dirs"

# S3: ARB key parity — app_en.arb and app_it.arb key sets are equal
#
# Uses python3 to parse JSON and compare key sets. Strips @-prefixed metadata
# keys before comparison. (NFR-M6-02)
echo "--- S3: ARB key parity ---"
EN_ARB="$ROOT/lib/l10n/app_en.arb"
IT_ARB="$ROOT/lib/l10n/app_it.arb"
if [ ! -f "$EN_ARB" ] || [ ! -f "$IT_ARB" ]; then
  fail "S3 FAILED: lib/l10n/app_en.arb or app_it.arb not found"
fi

arb_diff=$(python3 -c "
import json, sys

def non_meta_keys(path):
    with open(path) as f:
        d = json.load(f)
    return sorted(k for k in d if not k.startswith('@'))

en_keys = non_meta_keys('$EN_ARB')
it_keys = non_meta_keys('$IT_ARB')

en_set = set(en_keys)
it_set = set(it_keys)

only_en = sorted(en_set - it_set)
only_it = sorted(it_set - en_set)

if only_en:
    print('ONLY_IN_EN:', ','.join(only_en))
if only_it:
    print('ONLY_IN_IT:', ','.join(only_it))
")

if [ -n "$arb_diff" ]; then
  echo "$arb_diff" >&2
  fail "S3 FAILED: app_en.arb and app_it.arb key sets differ (NFR-M6-02)"
fi
pass "S3 — app_en.arb and app_it.arb have identical key sets"

# S4: exactly one fontSizeToast emitter in lib/presentation/ (FR-M6-16 / D2; M7-inverted)
#
# M6 pre-defined the fontSizeToast ARB key as the toast MECHANISM and forbade
# any caller. M7 is the first (and only) legitimate emitter: the single
# ref.listen in buffer_screen.dart. This gate (inverted from "zero emitters"
# to "exactly one, in buffer_screen.dart") guards against accidental duplicate
# emitters elsewhere in the presentation layer.
echo "--- S4: exactly one fontSizeToast emitter in lib/presentation/ (M7 seam) ---"
s4_hits=""
s4_count=0
while IFS= read -r f; do
  file_hits=$(
    grep -vE "^\s*(//)|\*" "$f" 2>/dev/null \
      | grep -E "fontSizeToast\s*\(" \
      || true
  )
  if [ -n "$file_hits" ]; then
    n=$(printf "%s\n" "$file_hits" | grep -c "fontSizeToast")
    s4_count=$((s4_count + n))
    s4_hits="$s4_hits\n$f:\n$file_hits"
  fi
done < <(find "$ROOT/lib/presentation" -name "*.dart" | sort)

if [ "$s4_count" -ne 1 ]; then
  printf "%b\n" "$s4_hits" >&2
  fail "S4 FAILED: expected exactly 1 fontSizeToast() emitter in lib/presentation/ (the M7 buffer_screen.dart ref.listen), found ${s4_count}"
fi
if ! printf "%b" "$s4_hits" | grep -q "buffer_screen.dart"; then
  printf "%b\n" "$s4_hits" >&2
  fail "S4 FAILED: the single fontSizeToast() emitter must be in buffer_screen.dart"
fi
pass "S4 — exactly one fontSizeToast emitter (buffer_screen.dart M7 seam)"

# S5: no kDebugMode nav block in buffer_screen.dart (FR-M6-23)
#
# The kDebugMode debug nav Row was removed in TASK-12. buffer_screen.dart must
# contain 0 non-comment lines with kDebugMode. The menu sheet is now the sole
# navigation entry point. (FR-M6-23, OQ-M6-15)
echo "--- S5: no kDebugMode nav block in buffer_screen.dart ---"
BUFFER_SCREEN="$ROOT/lib/presentation/editor/buffer_screen.dart"
if [ ! -f "$BUFFER_SCREEN" ]; then
  fail "S5 FAILED: lib/presentation/editor/buffer_screen.dart not found"
fi
# Note: pipefail-safe grep -c || true pattern.
s5_count=$(grep -vE "^\s*(//)|\*" "$BUFFER_SCREEN" \
  | grep -c "kDebugMode" || true)
if [ "$s5_count" -gt 0 ]; then
  fail "S5 FAILED: buffer_screen.dart contains kDebugMode (FR-M6-23 — debug nav row must be removed; menu sheet is sole nav entry)"
fi
pass "S5 — buffer_screen.dart has no kDebugMode"

# S6: AndroidManifest.xml contains VIEW+https (FR-M6-11, NFR-M6-08)
#
# The <queries> block must declare android.intent.action.VIEW with https (and
# http) scheme so url_launcher.canLaunchUrl succeeds on Android 11+.
echo "--- S6: AndroidManifest.xml has VIEW+https in <queries> ---"
MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  fail "S6 FAILED: android/app/src/main/AndroidManifest.xml not found"
fi
# Check for VIEW action — use grep -c || true (pipefail-safe).
view_count=$(grep -c "android.intent.action.VIEW" "$MANIFEST" || true)
if [ "$view_count" -eq 0 ]; then
  fail "S6 FAILED: AndroidManifest.xml missing android.intent.action.VIEW in <queries> (FR-M6-11)"
fi
https_count=$(grep -c 'android:scheme="https"' "$MANIFEST" || true)
if [ "$https_count" -eq 0 ]; then
  fail "S6 FAILED: AndroidManifest.xml missing android:scheme=\"https\" in <queries> (FR-M6-11, NFR-M6-08)"
fi
pass "S6 — AndroidManifest.xml has VIEW+https in <queries>"

# ──────────────────────────────────────────────────────────────────────────────
# Note on the on-device M6 shell smoke integration test (§7.2):
#
# integration_test/m6_shell_smoke_test.dart is tagged @Tags(['on-device'])
# and requires a running Android/iOS device or emulator. It is NOT run here
# because the gate runs headlessly on CI. Run it manually with:
#
#   flutter test integration_test/m6_shell_smoke_test.dart \
#       --device-id <device-id>
#
# This test is the M6 end-to-end shell smoke (FR-M6-03/08/09/10):
#   boot → open menu sheet → change theme (assert themeMode reacts)
#   → navigate /settings → /about → back → no crash.
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# All gates passed
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "M6 gate: ALL GATES PASSED"
echo "=========================================="
