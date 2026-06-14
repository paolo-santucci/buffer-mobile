#!/usr/bin/env bash
# M5 acceptance gate — buffer-mobile
#
# Spec refs: NFR-M5-01, NFR-M5-02, NFR-M5-03, NFR-M5-04, NFR-M5-05,
#            FR-M5-03, FR-M5-07, FR-M5-17
# Platforms: Android, iOS (runs on Linux CI host — no device needed for source
#            scans or the full `flutter test` suite)
#
# All checks must pass; the script exits non-zero naming the first offender.
# Mirrors the structure and style of tool/m4_gate.sh.
#
# Gate inventory (spec §7.1, TASK-14):
#   Gate 1: dart format — all files formatted
#   Gate 2: flutter analyze — 0 issues
#   Gate 3: full flutter test suite — 0 failures (incl. m5_gate_test.dart)
#   Shell source scans (complement m5_gate_test.dart Dart-level scans):
#     S1: no requireValue in lifecycle_buffer_host.dart (NFR-M5-03)
#     S2: no mtime-based sort in file_recovery_repository.dart (NFR-M5-01)
#     S3: no literal Text('…')/Text("…") in lib/presentation/recovery/ (NFR-M5-05)
#     S4: recovery_screen.dart calls populate( (FR-M5-07)
#     S5: save_buffer_to_recovery.dart calls trim(10) (FR-M5-03)
#     S6: no persist|write|store|share member names in recovery provider/repo (NFR-M5-02)
#     S7: no bare print( in M5 new files (NFR-M5-04)
#
# Usage:
#   bash tool/m5_gate.sh          # from the project root
#   ./tool/m5_gate.sh

set -euo pipefail

# Resolve project root relative to this script's location so it works from any
# working directory.
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
# Scans lib/, test/, and integration_test/ — all three directories are in scope
# for M5.
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
# test/m5_gate_test.dart (the 9 source-scan sub-gates). The on-device
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
# Shell-level source scans (fast, no flutter required — run after test suite
# so failures are specific). These complement the m5_gate_test.dart sub-gates
# and provide immediate CI feedback without loading the Dart VM.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Shell source scans ---"

# S1: lifecycle_buffer_host.dart — no requireValue (NFR-M5-03)
echo "--- S1: lifecycle_buffer_host.dart no requireValue ---"
LIFECYCLE_HOST="$ROOT/lib/presentation/lifecycle/lifecycle_buffer_host.dart"
if [ ! -f "$LIFECYCLE_HOST" ]; then
  fail "S1 FAILED: lib/presentation/lifecycle/lifecycle_buffer_host.dart not found"
fi
if grep -vE "^\s*(//)|\*" "$LIFECYCLE_HOST" | grep -q "requireValue"; then
  fail "S1 FAILED: lifecycle_buffer_host.dart contains requireValue (NFR-M5-03 crash-safety violation)"
fi
pass "S1 — lifecycle_buffer_host.dart has no requireValue"

# S2: file_recovery_repository.dart — no mtime-based sort (NFR-M5-01)
echo "--- S2: file_recovery_repository.dart no mtime sort ---"
FILE_REPO="$ROOT/lib/infrastructure/recovery/file_recovery_repository.dart"
if [ ! -f "$FILE_REPO" ]; then
  fail "S2 FAILED: lib/infrastructure/recovery/file_recovery_repository.dart not found"
fi
if grep -vE "^\s*(//)|\*" "$FILE_REPO" \
    | grep -qE "\b(lastModifiedSync|lastModified|statSync|mtime)\b|\.changed\b"; then
  fail "S2 FAILED: file_recovery_repository.dart uses mtime-based sort (NFR-M5-01 — use lexicographic filename sort)"
fi
pass "S2 — file_recovery_repository.dart has no mtime-based sort"

# S3: lib/presentation/recovery/ — no literal Text('…') / Text("…") (NFR-M5-05)
echo "--- S3: lib/presentation/recovery/ no literal Text() ---"
RECOVERY_PRESENTATION="$ROOT/lib/presentation/recovery"
if [ -d "$RECOVERY_PRESENTATION" ]; then
  literal_hits=$(
    find "$RECOVERY_PRESENTATION" -name "*.dart" | sort | while read -r f; do
      grep -n "Text(['\"][^'\"]\+['\"])" "$f" 2>/dev/null \
        | grep -vE "^\s*[0-9]+:\s*//" \
        | grep -vE "^\s*[0-9]+:\s*\*" || true
    done
  )
  if [ -n "$literal_hits" ]; then
    echo "$literal_hits" >&2
    fail "S3 FAILED: lib/presentation/recovery/ contains literal Text() strings (NFR-M5-05)"
  fi
fi
pass "S3 — lib/presentation/recovery/ has no literal Text() strings"

# S4: recovery_screen.dart — calls populate( (FR-M5-07)
echo "--- S4: recovery_screen.dart calls populate( ---"
RECOVERY_SCREEN="$ROOT/lib/presentation/recovery/recovery_screen.dart"
if [ ! -f "$RECOVERY_SCREEN" ]; then
  fail "S4 FAILED: lib/presentation/recovery/recovery_screen.dart not found"
fi
# Note: avoid `if ! pipeline | grep -q` with pipefail — early-exit grep -q
# causes SIGPIPE on the first grep and pipefail interprets it as failure.
# Use grep -c with process substitution instead (exit 0 always, count only).
s4_count=$(grep -vE "^\s*(//)|\*" "$RECOVERY_SCREEN" | grep -c "populate(" || true)
if [ "$s4_count" -eq 0 ]; then
  fail "S4 FAILED: recovery_screen.dart does not call populate( (FR-M5-07 restore-via-populate only)"
fi
pass "S4 — recovery_screen.dart calls populate("

# S5: save_buffer_to_recovery.dart — calls trim(10) (FR-M5-03)
echo "--- S5: save_buffer_to_recovery.dart calls trim(10) ---"
SAVE_USE_CASE="$ROOT/lib/domain/recovery/save_buffer_to_recovery.dart"
if [ ! -f "$SAVE_USE_CASE" ]; then
  fail "S5 FAILED: lib/domain/recovery/save_buffer_to_recovery.dart not found"
fi
# Note: same pipefail issue as S4 — use grep -c with || true.
s5_count=$(grep -vE "^\s*(//)|\*" "$SAVE_USE_CASE" | grep -c "trim(10)" || true)
if [ "$s5_count" -eq 0 ]; then
  fail "S5 FAILED: save_buffer_to_recovery.dart does not call trim(10) (FR-M5-03 trim-to-10)"
fi
pass "S5 — save_buffer_to_recovery.dart calls trim(10)"

# S6: recovery_list_provider.dart and recovery_repository.dart — no
#     persist|write|store|share member/method names (NFR-M5-02)
echo "--- S6: no persist|write|store|share member names in recovery provider/repo ---"
s6_files=(
  "$ROOT/lib/presentation/recovery/recovery_list_provider.dart"
  "$ROOT/lib/domain/recovery/recovery_repository.dart"
)
s6_hits=""
for f in "${s6_files[@]}"; do
  [ -f "$f" ] || continue
  hits=$(grep -nE "\b(persist|write|store|share)\b" "$f" \
    | grep -vE "^\s*[0-9]+:\s*(//)|\*" \
    | grep -vE "^\s*[0-9]+:\s*import " || true)
  if [ -n "$hits" ]; then
    s6_hits="$s6_hits\n$f:\n$hits"
  fi
done
if [ -n "$s6_hits" ]; then
  printf "%b\n" "$s6_hits" >&2
  fail "S6 FAILED: recovery_list_provider.dart or recovery_repository.dart contains persist|write|store|share member names (NFR-M5-02)"
fi
pass "S6 — no persist|write|store|share member names in recovery provider/repo"

# S7: no bare print( in M5 new files (NFR-M5-04)
echo "--- S7: no bare print() in M5 new files ---"
m5_files=(
  "$ROOT/lib/domain/recovery/recovery_repository.dart"
  "$ROOT/lib/domain/recovery/save_buffer_to_recovery.dart"
  "$ROOT/lib/infrastructure/recovery/file_recovery_repository.dart"
  "$ROOT/lib/presentation/lifecycle/lifecycle_buffer_host.dart"
  "$ROOT/lib/presentation/recovery/recovery_list_provider.dart"
  "$ROOT/lib/presentation/recovery/recovery_screen.dart"
)
s7_hits=""
for f in "${m5_files[@]}"; do
  [ -f "$f" ] || continue
  # Exclude lines that are full-line comments (starting with // or ///,
  # with optional leading whitespace) before scanning for bare print().
  # This avoids false positives from "No print()." or "NEVER print()."
  # appearing in doc comment text.
  hits=$(grep -nE "print\(" "$f" \
    | grep -vE "^\s*[0-9]+:\s*(//)|\*" \
    | grep -vE "debugPrint\(" || true)
  if [ -n "$hits" ]; then
    s7_hits="$s7_hits\n$f:\n$hits"
  fi
done
if [ -n "$s7_hits" ]; then
  printf "%b\n" "$s7_hits" >&2
  fail "S7 FAILED: bare print() found in M5 new files (NFR-M5-04)"
fi
pass "S7 — no bare print() in M5 new files"

# ──────────────────────────────────────────────────────────────────────────────
# Note on the on-device 12-saves-trim integration test (NFR-M5-01 / MC-01):
#
# integration_test/recovery_12saves_trim_test.dart is tagged @Tags(['on-device'])
# and requires a running Android/iOS device or emulator. It is NOT run here
# because the gate runs headlessly on CI. Run it manually with:
#
#   flutter test integration_test/recovery_12saves_trim_test.dart \
#       --device-id <device-id>
#
# This test is the M5 trim gate (NFR-M5-01 / MC-01): it drives 12 save calls
# through the real FileRecoveryRepository against a temp dir and asserts
# exactly 10 .txt files remain, with the 2 lexicographically-smallest original
# filenames deleted.
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# All gates passed
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "M5 gate: ALL GATES PASSED"
echo "=========================================="
