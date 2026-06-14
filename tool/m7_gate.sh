#!/usr/bin/env bash
# M7 acceptance gate — buffer-mobile
#
# Spec refs: NFR-M7-01, NFR-M7-03, NFR-M7-04, FR-M7-03, FR-M7-05, FR-M7-09,
#            AD-M7-01
# Platforms: Android, iOS (runs on Linux CI host — no device needed for source
#            scans or the full `flutter test` suite)
#
# All checks must pass; the script exits non-zero naming the first offender.
# Mirrors the structure and style of tool/m6_gate.sh.
#
# Gate inventory (spec §6.1 "New gate", TASK-14):
#   Gate 1: dart format — all files formatted
#   Gate 2: flutter analyze — 0 issues
#   Gate 3: full flutter test suite — 0 failures (incl. m7_gate_test.dart)
#   Gate 4: boot-smoke integration test (headless)
#   Shell source scans (complement m7_gate_test.dart Dart-level scans):
#     S1: zero textScaleFactor in lib/ (NFR-M7-01 — deprecated; use textScaler)
#     S2: pointerCount guard (== 2 or != 2) present in buffer_screen.dart
#         (NFR-M7-03, FR-M7-05 — prevents single-finger font-size change)
#     S3: 'monospace' and 'sans-serif' literals both present in buffer_screen.dart
#         (FR-M7-09 — font-family fallback chains required for gate scan)
#     S4: 'font-size' key referenced in shared_preferences_settings_repository.dart
#         (FR-M7-03 — eighth persisted key; must survive app restarts)
#     S5: zero TypographySettings references in lib/ (AD-M7-01 retirement)
#     S6: zero typographyProvider references in lib/ (AD-M7-01 retirement)
#     S7: slotList present in app_settings.dart (AD-M7-01 relocation verified)
#
# Critical patterns to avoid (learned from M4/M5/M6 shell-gate experience):
#   (a) Filter comment lines (strip lines where first non-space token is //)
#       before scanning so comments referencing a forbidden token don't
#       false-positive.
#   (b) Use `grep -c ... || true` pattern — NOT `if ! pipeline | grep -q`
#       which breaks under `set -o pipefail` because grep -q exits early via
#       SIGPIPE, causing the upstream pipeline to receive SIGPIPE and fail.
#
# Usage:
#   bash tool/m7_gate.sh          # from the project root
#   ./tool/m7_gate.sh

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
# scope for M7.
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
# test/m7_gate_test.dart (the 7 source-scan sub-gates). The on-device
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
# Verifies the composition root (ProviderScope + BufferApp + all M7 providers)
# mounts without exception using the flutter-tester VM device.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 4: boot-smoke integration test (headless) ---"
if flutter test integration_test/boot_smoke_test.dart \
    --device-id flutter-tester \
    --no-pub 2>&1; then
  pass "boot-smoke — ProviderScope + BufferApp + BufferScreen mount; '/' route renders"
else
  fail "Gate 4 FAILED: boot-smoke integration test failed"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Shell-level source scans (fast, no flutter required — run after test suite
# so failures are specific). These complement the m7_gate_test.dart sub-gates
# and provide immediate CI feedback without loading the Dart VM.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Shell source scans ---"

BUFFER_SCREEN="$ROOT/lib/presentation/editor/buffer_screen.dart"
APP_SETTINGS="$ROOT/lib/domain/settings/app_settings.dart"
REPOSITORY="$ROOT/lib/infrastructure/settings/shared_preferences_settings_repository.dart"

# S1: zero textScaleFactor in lib/ (NFR-M7-01)
#
# The deprecated textScaleFactor must not appear anywhere in lib/ code.
# OS font scaling goes through TextField.textScaler /
# MediaQuery.textScalerOf(context) exclusively.
echo "--- S1: zero textScaleFactor in lib/ ---"
s1_count=0
while IFS= read -r f; do
  # Use grep -c || true (pipefail-safe).
  file_count=$(grep -vE "^\s*(//)|\*" "$f" 2>/dev/null \
    | grep -c "textScaleFactor" || true)
  s1_count=$((s1_count + file_count))
done < <(find "$ROOT/lib" -name "*.dart" | sort)

if [ "$s1_count" -gt 0 ]; then
  fail "S1 FAILED: lib/ contains $s1_count occurrence(s) of textScaleFactor " \
       "(NFR-M7-01 — deprecated; use textScaler / MediaQuery.textScalerOf)"
fi
pass "S1 — zero textScaleFactor in lib/"

# S2: pointerCount guard present in buffer_screen.dart (NFR-M7-03, FR-M7-05)
#
# The guard may be written as `== 2` or `!= 2` depending on the branch
# direction. Both encode the two-finger requirement.
echo "--- S2: pointerCount guard in buffer_screen.dart ---"
if [ ! -f "$BUFFER_SCREEN" ]; then
  fail "S2 FAILED: buffer_screen.dart not found"
fi
# Note: pipefail-safe grep -c || true pattern.
s2_count=$(grep -vE "^\s*(//)|\*" "$BUFFER_SCREEN" \
  | grep -cE "pointerCount\s*[!=]=\s*2\b" || true)
if [ "$s2_count" -eq 0 ]; then
  fail "S2 FAILED: buffer_screen.dart has no pointerCount guard " \
       "(NFR-M7-03, FR-M7-05 — single-finger drags must not change font size)"
fi
pass "S2 — pointerCount guard found in buffer_screen.dart"

# S3: 'monospace' and 'sans-serif' literals in buffer_screen.dart (FR-M7-09)
#
# These literal strings are required so the M7 gate scan can confirm the
# font-family fallback chains are wired. Both must be present.
echo "--- S3: 'monospace' and 'sans-serif' literals in buffer_screen.dart ---"
if [ ! -f "$BUFFER_SCREEN" ]; then
  fail "S3 FAILED: buffer_screen.dart not found"
fi
mono_count=$(grep -vE "^\s*(//)|\*" "$BUFFER_SCREEN" \
  | grep -c "'monospace'" || true)
if [ "$mono_count" -eq 0 ]; then
  fail "S3 FAILED: 'monospace' literal not found in buffer_screen.dart " \
       "(FR-M7-09 — mono-font fallback chain absent)"
fi
sans_count=$(grep -vE "^\s*(//)|\*" "$BUFFER_SCREEN" \
  | grep -c "'sans-serif'" || true)
if [ "$sans_count" -eq 0 ]; then
  fail "S3 FAILED: 'sans-serif' literal not found in buffer_screen.dart " \
       "(FR-M7-09 — document-font fallback chain absent)"
fi
pass "S3 — 'monospace' and 'sans-serif' literals found in buffer_screen.dart"

# S4: 'font-size' key referenced in repository (FR-M7-03, TASK-02)
#
# Confirms the eighth persisted key is present in the repository file.
# Accepts either the literal 'font-size' string or AppSettings.kFontSize.
echo "--- S4: 'font-size' key in shared_preferences_settings_repository.dart ---"
if [ ! -f "$REPOSITORY" ]; then
  fail "S4 FAILED: shared_preferences_settings_repository.dart not found"
fi
s4_count=$(grep -vE "^\s*(//)|\*" "$REPOSITORY" \
  | grep -cE "'font-size'|kFontSize" || true)
if [ "$s4_count" -eq 0 ]; then
  fail "S4 FAILED: 'font-size' key not referenced in repository " \
       "(FR-M7-03 — fontSizeIndex must be persisted; TASK-02 may be absent)"
fi
pass "S4 — 'font-size' key referenced in shared_preferences_settings_repository.dart"

# S5: zero TypographySettings references in lib/ (AD-M7-01)
#
# The duplicate TypographySettings model was retired in TASK-03. Any
# remaining reference in lib/ code (excluding comments) is a regression.
echo "--- S5: zero TypographySettings in lib/ ---"
s5_count=0
while IFS= read -r f; do
  file_count=$(grep -vE "^\s*(//)|\*" "$f" 2>/dev/null \
    | grep -c "TypographySettings" || true)
  s5_count=$((s5_count + file_count))
done < <(find "$ROOT/lib" -name "*.dart" | sort)

if [ "$s5_count" -gt 0 ]; then
  fail "S5 FAILED: lib/ contains $s5_count occurrence(s) of TypographySettings " \
       "(AD-M7-01 retirement incomplete — repoint readers to AppSettings)"
fi
pass "S5 — zero TypographySettings in lib/"

# S6: zero typographyProvider references in lib/ (AD-M7-01)
#
# The typographyProvider was retired in TASK-03. Any remaining reference
# in lib/ code (excluding comments) is a regression.
echo "--- S6: zero typographyProvider in lib/ ---"
s6_count=0
while IFS= read -r f; do
  file_count=$(grep -vE "^\s*(//)|\*" "$f" 2>/dev/null \
    | grep -c "typographyProvider" || true)
  s6_count=$((s6_count + file_count))
done < <(find "$ROOT/lib" -name "*.dart" | sort)

if [ "$s6_count" -gt 0 ]; then
  fail "S6 FAILED: lib/ contains $s6_count occurrence(s) of typographyProvider " \
       "(AD-M7-01 retirement incomplete — repoint readers to settingsProvider)"
fi
pass "S6 — zero typographyProvider in lib/"

# S7: slotList present in app_settings.dart (AD-M7-01 relocation confirmed)
#
# The 21-slot list was relocated from TypographySettings to AppSettings in
# TASK-01. Absence in app_settings.dart means the relocation regressed.
echo "--- S7: slotList declared in app_settings.dart ---"
if [ ! -f "$APP_SETTINGS" ]; then
  fail "S7 FAILED: app_settings.dart not found"
fi
s7_count=$(grep -vE "^\s*(//)|\*" "$APP_SETTINGS" \
  | grep -c "slotList" || true)
if [ "$s7_count" -eq 0 ]; then
  fail "S7 FAILED: slotList not found in app_settings.dart " \
       "(AD-M7-01 — 21-slot list must be declared on AppSettings, not TypographySettings)"
fi
pass "S7 — slotList declared in app_settings.dart"

# ──────────────────────────────────────────────────────────────────────────────
# Note on the on-device M7 pinch/scale integration test (§7.2):
#
# integration_test/m7_pinch_zoom_test.dart is tagged @Tags(['on-device'])
# and requires a running Android/iOS device or emulator. It is NOT run here
# because the gate runs headlessly on CI. Run it manually with:
#
#   flutter test integration_test/m7_pinch_zoom_test.dart \
#       --device-id <device-id>
#
# This test covers MC-01 (OS-scale no restart), MC-02 (pinch persist-on-end),
# MC-03 (single-finger no-change regression guard).
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# All gates passed
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "M7 gate: ALL GATES PASSED"
echo "=========================================="
