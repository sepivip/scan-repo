#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

CALIB="$SCRIPT_DIR/../tools/calibration-check.sh"

assert_true "[[ -x '$CALIB' ]]" "calibration-check.sh exists and is executable"

assert_true "bash '$CALIB' --dry-run --good-list /dev/null" \
    "calibration-check.sh --dry-run on empty list returns success"

TMP_GOOD=$(mktemp)
echo "https://github.com/fake/repo1" >> "$TMP_GOOD"
echo "https://github.com/fake/repo2" >> "$TMP_GOOD"
echo "https://github.com/fake/repo3" >> "$TMP_GOOD"

SCAN_REPO_FAKE_WARN_COUNT=1 bash "$CALIB" --dry-run --good-list "$TMP_GOOD" --threshold 3 >/dev/null 2>&1
rc=$?
assert_eq "1" "$rc" "calibration: 3 repos x 1 warn = 3 → exit 1"

SCAN_REPO_FAKE_WARN_COUNT=0 bash "$CALIB" --dry-run --good-list "$TMP_GOOD" --threshold 3 >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "calibration: 0 warns → exit 0"

rm -f "$TMP_GOOD"
report
