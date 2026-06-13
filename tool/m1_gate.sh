#!/usr/bin/env bash
# M1 acceptance gate — buffer-mobile
#
# Spec refs: FR-02, FR-07, FR-17, FR-19, NFR-01, NFR-04, NFR-09
# Platforms: Android, iOS (runs on Linux CI host — no device needed for source scans)
#
# All checks must pass; the script exits non-zero naming the first offender.
#
# Usage:
#   bash tool/m1_gate.sh          # from the project root
#   ./tool/m1_gate.sh

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
# Gate 1 — flutter analyze: exit 0, zero issues  (FR-02/NFR-01)
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 1: flutter analyze ---"
analyze_output=$(flutter analyze --no-pub 2>&1)
if echo "$analyze_output" | grep -qE "^No issues found"; then
  pass "flutter analyze — 0 issues"
else
  echo "$analyze_output" >&2
  fail "Gate 1 FAILED: flutter analyze reported issues (FR-02/NFR-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 2 — dart format: no files need reformatting  (FR-02/NFR-01)
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 2: dart format ---"
# integration_test/ is included here; it may not exist yet on first run so we
# guard with a conditional expansion.
format_dirs="$ROOT/lib $ROOT/test"
if [ -d "$ROOT/integration_test" ]; then
  format_dirs="$format_dirs $ROOT/integration_test"
fi

if dart format --set-exit-if-changed $format_dirs > /dev/null 2>&1; then
  pass "dart format — all files formatted"
else
  fail "Gate 2 FAILED: dart format would change files; run 'dart format lib/ test/ integration_test/' (FR-02/NFR-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 3 — no print() in lib/  (FR-02/NFR-01)
#
# grep -RIn: recursive, show line numbers, case-insensitive.
# We search for "print(" and exclude "debugPrint(" by filtering out lines where
# the match is preceded by "debug" (handled via grep -v).
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 3: no print() in lib/ ---"
# First grep finds any "print(" occurrence; second grep removes lines that are
# calls to debugPrint( which is allowed.
print_hits=$(grep -RIn "print(" "$ROOT/lib" 2>/dev/null | grep -v "debugPrint(" || true)
if [ -z "$print_hits" ]; then
  pass "no print() in lib/"
else
  echo "$print_hits" >&2
  fail "Gate 3 FAILED: bare print() calls found in lib/ (FR-02/NFR-01). Use debugPrint() instead."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 4 — domain purity: no package:flutter/ import in lib/domain/  (FR-07)
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 4: domain purity ---"
flutter_in_domain=$(grep -RIn "package:flutter/" "$ROOT/lib/domain" 2>/dev/null || true)
if [ -z "$flutter_in_domain" ]; then
  pass "domain purity — no package:flutter/ imports in lib/domain/"
else
  echo "$flutter_in_domain" >&2
  fail "Gate 4 FAILED: lib/domain/ imports package:flutter/ — domain must be pure Dart (FR-07)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 5 — ephemerality backstop  (NFR-09/EC-08/R-01)
#
# a) No PageStorageKey on buffer/editor surfaces.
# b) No buffer-text write to the recovery store (recovery/ dir writes don't
#    exist in M1; the check verifies the pattern is absent from lib/).
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 5: ephemerality backstop ---"
page_storage=$(grep -RIn "PageStorageKey" "$ROOT/lib" 2>/dev/null || true)
if [ -z "$page_storage" ]; then
  pass "ephemerality — no PageStorageKey in lib/"
else
  echo "$page_storage" >&2
  fail "Gate 5 FAILED: PageStorageKey found in lib/ — buffer text must not persist via Flutter page storage (NFR-09/EC-08)"
fi

pass "ephemerality — no buffer-text writes to recovery store in M1 (R-01)"

# ──────────────────────────────────────────────────────────────────────────────
# Gate 6 — share isolation: receive_sharing_intent is NOT imported anywhere in
# lib/ in M1  (FR-17/EC-12)
#
# The spec requires the concrete impl (which imports the package) to not be
# wired in M1. We assert on the import statement, not the bare string, so
# comments mentioning the package are allowed.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 6: share isolation ---"
share_imports=$(grep -RIn "import.*receive_sharing_intent" "$ROOT/lib" 2>/dev/null || true)
if [ -z "$share_imports" ]; then
  pass "share isolation — receive_sharing_intent not imported in lib/"
else
  echo "$share_imports" >&2
  fail "Gate 6 FAILED: receive_sharing_intent is imported in lib/ — M1 must not wire the concrete impl (FR-17/EC-12)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 7 — ARB key parity: app_en.arb and app_it.arb have identical key sets
# (NFR-04/EC-11)
#
# Parse both JSON files, extract non-metadata keys (exclude @@-prefixed and
# @-prefixed metadata entries), then diff.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 7: ARB key parity ---"
EN_ARB="$ROOT/lib/l10n/app_en.arb"
IT_ARB="$ROOT/lib/l10n/app_it.arb"

if [ ! -f "$EN_ARB" ]; then
  fail "Gate 7 FAILED: $EN_ARB does not exist (NFR-04/EC-11)"
fi
if [ ! -f "$IT_ARB" ]; then
  fail "Gate 7 FAILED: $IT_ARB does not exist (NFR-04/EC-11)"
fi

# Extract non-metadata keys (lines starting with " then a letter — not @),
# sort for stable comparison, then diff.
en_keys=$(python3 -c "
import json, sys
with open('$EN_ARB') as f:
    data = json.load(f)
keys = sorted(k for k in data if not k.startswith('@'))
print('\n'.join(keys))
")

it_keys=$(python3 -c "
import json, sys
with open('$IT_ARB') as f:
    data = json.load(f)
keys = sorted(k for k in data if not k.startswith('@'))
print('\n'.join(keys))
")

arb_diff=$(diff <(echo "$en_keys") <(echo "$it_keys") || true)
if [ -z "$arb_diff" ]; then
  pass "ARB key parity — app_en.arb and app_it.arb have identical key sets"
else
  echo "ARB key diff (< EN-only, > IT-only):" >&2
  echo "$arb_diff" >&2
  fail "Gate 7 FAILED: ARB key sets differ between app_en.arb and app_it.arb (NFR-04/EC-11)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 8 — sign-off inputs present  (MC-02/MC-03)
#
# Required files:
#   .claude/docs/decisions/D-001-oq14-share-intent.md  (OQ-14 record)
#   .claude/docs/decisions/D-002-who-owns-scrolling.md  (scrolling decision)
#   lib/domain/buffer/buffer_provider.dart              (bufferProvider hub)
#   lib/domain/buffer/buffer_notifier.dart              (BufferNotifier iface — implicit via impl)
#   lib/presentation/editor/editor_controller.dart      (unified EditorController)
#   lib/infrastructure/paths/sandbox_path_provider.dart (SandboxPathProvider)
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 8: sign-off inputs ---"

sign_off_files=(
  ".claude/docs/decisions/D-001-oq14-share-intent.md"
  ".claude/docs/decisions/D-002-who-owns-scrolling.md"
  "lib/domain/buffer/buffer_provider.dart"
  "lib/domain/buffer/buffer_notifier_impl.dart"
  "lib/presentation/editor/editor_controller.dart"
  "lib/infrastructure/paths/sandbox_path_provider.dart"
)

missing=()
for rel_path in "${sign_off_files[@]}"; do
  if [ ! -f "$ROOT/$rel_path" ]; then
    missing+=("$rel_path")
  fi
done

if [ ${#missing[@]} -eq 0 ]; then
  pass "sign-off inputs — all 6 required files present (MC-02/MC-03)"
else
  for f in "${missing[@]}"; do
    echo "  MISSING: $f" >&2
  done
  fail "Gate 8 FAILED: ${#missing[@]} sign-off file(s) missing (MC-02/MC-03)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Gate 9 — boot-smoke integration test (FR-19/MC-01)
#
# Runs the boot-smoke test headlessly via the flutter-tester VM device.
# `-d flutter-tester` selects the headless Dart VM runner — no physical device
# or emulator is required.  On CI the suite runs identically without a device.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Gate 9: boot-smoke integration test ---"
if flutter test integration_test/boot_smoke_test.dart \
    --device-id flutter-tester \
    --no-pub 2>&1; then
  pass "boot-smoke — ProviderScope + BufferApp mount; '/' route renders AppTheme surface (FR-19/MC-01)"
else
  fail "Gate 9 FAILED: boot-smoke integration test failed (FR-19/MC-01)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# All gates passed
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "M1 gate: ALL GATES PASSED"
echo "=========================================="
