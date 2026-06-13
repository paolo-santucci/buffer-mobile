#!/usr/bin/env bash
# M2 acceptance gate — buffer-mobile
#
# Spec refs: FR-M2-04, FR-M2-09, FR-M2-14, NFR-M2-01, NFR-M2-02,
#            NFR-M2-04, NFR-M2-05, §7.1, §7.2
# Platforms: Android, iOS (runs on Linux CI host — no device needed for source
#            scans or the full `flutter test` suite)
#
# All checks must pass; the script exits non-zero naming the first offender.
# Mirrors the structure and style of tool/m1_gate.sh.
#
# Usage:
#   bash tool/m2_gate.sh          # from the project root
#   ./tool/m2_gate.sh

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
# Gate 1 — dart format: no files need reformatting  (NFR-M2-01)
#
# Scans lib/, test/, and integration_test/ — all three directories are in scope
# for M2.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 1: dart format ---"
format_dirs="$ROOT/lib $ROOT/test"
if [ -d "$ROOT/integration_test" ]; then
  format_dirs="$format_dirs $ROOT/integration_test"
fi

if dart format --set-exit-if-changed $format_dirs > /dev/null 2>&1; then
  pass "dart format — all files formatted"
else
  fail "Gate 1 FAILED: dart format would change files; run 'dart format lib/ test/ integration_test/' (NFR-M2-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 2 — flutter analyze: exit 0, zero issues  (NFR-M2-01)
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 2: flutter analyze ---"
analyze_output=$(flutter analyze --no-pub 2>&1)
if echo "$analyze_output" | grep -qE "^No issues found"; then
  pass "flutter analyze — 0 issues"
else
  echo "$analyze_output" >&2
  fail "Gate 2 FAILED: flutter analyze reported issues (NFR-M2-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 3 — full flutter test suite: 0 failures  (NFR-M2-01)
#
# Runs the entire test/ directory (unit + widget + gate tests). The on-device
# integration test (integration_test/recovery_persistence_test.dart) is tagged
# @Tags(['on-device']) and excluded from this headless run. The boot-smoke
# integration test (boot_smoke_test.dart) is NOT on-device-tagged and runs
# headlessly via the flutter-tester device.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 3: full flutter test suite ---"
if flutter test --no-pub 2>&1; then
  pass "flutter test — all tests passed"
else
  fail "Gate 3 FAILED: flutter test reported failures (NFR-M2-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 4 — boot-smoke integration test (headless)
#
# Verifies the M2 composition root (ProviderScope + BufferApp + BufferScreen +
# all M2 providers) mounts without exception using the flutter-tester VM device.
# Requires no physical device or emulator.
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
# Note on the on-device recovery persistence test (NFR-M2-02):
#
# integration_test/recovery_persistence_test.dart is tagged @Tags(['on-device'])
# and requires a running Android/iOS device or emulator. It is NOT run here
# because the gate runs headlessly on CI. Run it manually with:
#
#   flutter test integration_test/recovery_persistence_test.dart \
#       --device-id <device-id>
#
# This is documented per OQ-M2-10: the on-device gate runs per-device-farm
# schedule, not per-PR.
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# All gates passed
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "M2 gate: ALL GATES PASSED"
echo "=========================================="
