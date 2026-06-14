#!/usr/bin/env bash
# M4 acceptance gate — buffer-mobile
#
# Spec refs: FR-08, FR-17; NFR-01, NFR-03, NFR-04, NFR-05, NFR-06
# Platforms: Android, iOS (runs on Linux CI host — no device needed for source
#            scans or the full `flutter test` suite)
#
# All checks must pass; the script exits non-zero naming the first offender.
# Mirrors the structure and style of tool/m3_gate.sh.
#
# Gate inventory (spec §7.1, TASK-09):
#   Gate 1: dart format — all files formatted
#   Gate 2: flutter analyze — 0 issues
#   Gate 3: full flutter test suite — 0 failures (incl. m4_gate_test.dart)
#   Gate 4: boot-smoke integration test (headless)
#   Source scans (run as part of flutter test via m4_gate_test.dart):
#     S1: find_engine.dart no package:flutter/ import; findMatchesIsolate top-level
#     S2: find_provider.dart no _controller.value = on replace path
#     S3: lib/ exactly one extends TextEditingController
#     S4: buffer_notifier*.dart no find/replace/query/match/search members
#     S5: lib/presentation/find/ no literal Text('…') / Text("…")
#     S6: app_en.arb / app_it.arb identical 8 find keys
#     S7: no bare print( in M4 new files
#     S8: m3_gate_test.dart buildTextSpan assertion revised (old text absent)
#
# Usage:
#   bash tool/m4_gate.sh          # from the project root
#   ./tool/m4_gate.sh

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
# for M4.
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
# test/m4_gate_test.dart (the 8 source-scan sub-gates). The on-device
# integration tests (tagged @Tags(['on-device'])) are excluded from this
# headless run. The boot-smoke integration test (boot_smoke_test.dart) is NOT
# on-device-tagged and runs headlessly via the flutter-tester device.
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
# Verifies the M4 composition root (ProviderScope + BufferApp + BufferScreen +
# all M4 providers including findProvider) mounts without exception using the
# flutter-tester VM device. Requires no physical device or emulator.
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
# so failures are specific). These mirror the m4_gate_test.dart sub-gates and
# provide immediate CI feedback without loading the Dart VM.
# ──────────────────────────────────────────────────────────────────────────────

echo "--- Shell source scans ---"

# S1: find_engine.dart — no package:flutter/ import
echo "--- S1: find_engine.dart no Flutter import ---"
ENGINE="$ROOT/lib/domain/find/find_engine.dart"
if [ ! -f "$ENGINE" ]; then
  fail "S1 FAILED: lib/domain/find/find_engine.dart not found"
fi
if grep -qE "^[^/]*import 'package:flutter/" "$ENGINE" 2>/dev/null; then
  fail "S1 FAILED: find_engine.dart contains a package:flutter/ import (NFR-05 domain purity)"
fi
pass "S1 — find_engine.dart has no package:flutter/ import"

# S2: find_provider.dart — no _controller.value = on replace path
echo "--- S2: find_provider.dart no _controller.value = ---"
PROVIDER="$ROOT/lib/presentation/find/find_provider.dart"
if [ ! -f "$PROVIDER" ]; then
  fail "S2 FAILED: lib/presentation/find/find_provider.dart not found"
fi
# Non-comment lines only: filter out lines starting with // or *
if grep -vE "^\s*(//)|\*" "$PROVIDER" | grep -qE "_controller\.value\s*=[^=]"; then
  fail "S2 FAILED: find_provider.dart contains a direct _controller.value = write (NFR-04)"
fi
pass "S2 — find_provider.dart has no direct _controller.value = write"

# S3: lib/ — exactly one extends TextEditingController
echo "--- S3: exactly one extends TextEditingController in lib/ ---"
subclass_count=$(grep -rln "extends TextEditingController" "$ROOT/lib/" | wc -l)
if [ "$subclass_count" -ne 1 ]; then
  echo "Files with 'extends TextEditingController':" >&2
  grep -rln "extends TextEditingController" "$ROOT/lib/" >&2 || true
  fail "S3 FAILED: lib/ contains $subclass_count file(s) with 'extends TextEditingController' (expected 1, NFR-04)"
fi
pass "S3 — exactly one TextEditingController subclass in lib/"

# S4: buffer_notifier*.dart — no find/replace/query/match/search members
echo "--- S4: buffer_notifier*.dart no find/replace/query/match/search members ---"
NOTIFIER_DIR="$ROOT/lib/domain/buffer"
s4_hits=$(
  for f in "$NOTIFIER_DIR"/buffer_notifier*.dart; do
    [ -f "$f" ] || continue
    # Skip comment and import lines; scan for forbidden member words.
    grep -nE "\b(find|replace|query|match|search)\b" "$f" \
      | grep -vE "^\s*[0-9]+:\s*(//)|\*" \
      | grep -vE "^\s*[0-9]+:\s*import " || true
  done
)
if [ -n "$s4_hits" ]; then
  echo "$s4_hits" >&2
  fail "S4 FAILED: buffer_notifier*.dart contains find/replace/query/match/search member names (NFR-03)"
fi
pass "S4 — buffer_notifier*.dart has no find/replace/query/match/search members"

# S5: lib/presentation/find/ — no literal Text('…') / Text("…")
#
# Skip comment lines (lines whose first non-space token is // or *).
# The grep pattern matches Text('...') or Text("...") with non-empty strings.
echo "--- S5: lib/presentation/find/ no literal Text() ---"
FIND_PRESENTATION="$ROOT/lib/presentation/find"
if [ -d "$FIND_PRESENTATION" ]; then
  literal_hits=$(
    find "$FIND_PRESENTATION" -name "*.dart" | sort | while read -r f; do
      grep -n "Text(['\"][^'\"]\+['\"])" "$f" 2>/dev/null \
        | grep -vE "^\s*[0-9]+:\s*//" \
        | grep -vE "^\s*[0-9]+:\s*\*" || true
    done
  )
  if [ -n "$literal_hits" ]; then
    echo "$literal_hits" >&2
    fail "S5 FAILED: lib/presentation/find/ contains literal Text() strings (NFR-06)"
  fi
fi
pass "S5 — lib/presentation/find/ has no literal Text() strings"

# S6: ARB key parity — 8 find keys in both files, identical sets
echo "--- S6: ARB key parity ---"
EN_ARB="$ROOT/lib/l10n/app_en.arb"
IT_ARB="$ROOT/lib/l10n/app_it.arb"
if [ ! -f "$EN_ARB" ] || [ ! -f "$IT_ARB" ]; then
  fail "S6 FAILED: lib/l10n/app_en.arb or app_it.arb not found"
fi

# Extract find keys (JSON keys starting with "find", excluding @metadata).
en_find_keys=$(python3 -c "
import sys, json
d = json.load(open('$EN_ARB'))
keys = sorted(k for k in d if k.startswith('find') and not k.startswith('@'))
for k in keys: print(k)
")
it_find_keys=$(python3 -c "
import sys, json
d = json.load(open('$IT_ARB'))
keys = sorted(k for k in d if k.startswith('find') and not k.startswith('@'))
for k in keys: print(k)
")

expected_keys="findCloseTooltip
findCountLabel
findHintText
findNextTooltip
findPreviousTooltip
findReplaceButton
findReplaceHintText
findReplaceToggleTooltip"

if [ "$en_find_keys" != "$expected_keys" ]; then
  echo "app_en.arb find keys: $en_find_keys" >&2
  echo "Expected: $expected_keys" >&2
  fail "S6 FAILED: app_en.arb does not have all 8 expected find keys (NFR-06)"
fi
if [ "$it_find_keys" != "$expected_keys" ]; then
  echo "app_it.arb find keys: $it_find_keys" >&2
  echo "Expected: $expected_keys" >&2
  fail "S6 FAILED: app_it.arb does not have all 8 expected find keys (NFR-06)"
fi
if [ "$en_find_keys" != "$it_find_keys" ]; then
  echo "EN keys: $en_find_keys" >&2
  echo "IT keys: $it_find_keys" >&2
  fail "S6 FAILED: find key sets differ between app_en.arb and app_it.arb (NFR-06)"
fi
pass "S6 — both ARB files have all 8 find keys with identical sets"

# S7: no bare print( in M4 new files
echo "--- S7: no bare print() in M4 new files ---"
m4_files=(
  "$ROOT/lib/domain/find/find_engine.dart"
  "$ROOT/lib/domain/find/find_state.dart"
  "$ROOT/lib/presentation/find/find_provider.dart"
  "$ROOT/lib/presentation/find/find_search_bar.dart"
)
s7_hits=""
for f in "${m4_files[@]}"; do
  [ -f "$f" ] || continue
  hits=$(grep -nE "[^/\*]print\(" "$f" \
    | grep -vE "debugPrint\(" || true)
  if [ -n "$hits" ]; then
    s7_hits="$s7_hits\n$f:\n$hits"
  fi
done
if [ -n "$s7_hits" ]; then
  printf "%b\n" "$s7_hits" >&2
  fail "S7 FAILED: bare print() found in M4 new files (NFR-05)"
fi
pass "S7 — no bare print() in M4 new files"

# ──────────────────────────────────────────────────────────────────────────────
# Note on the on-device find-50k-scroll integration test (NFR-01):
#
# integration_test/find_50k_scroll_test.dart is tagged @Tags(['on-device'])
# and requires a running Android/iOS device or emulator. It is NOT run here
# because the gate runs headlessly on CI. Run it manually with:
#
#   flutter test integration_test/find_50k_scroll_test.dart \
#       --device-id <device-id>
#
# This test is the M4 performance gate (FR-17 / NFR-01): it asserts that
# a 50k-char buffer with 200+ matches shows no dropped-frame regression vs
# the pre-find baseline, and that scroll-to-match moves the ScrollController
# offset toward each match on every next() navigation.
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# All gates passed
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "=========================================="
echo "M4 gate: ALL GATES PASSED"
echo "=========================================="
