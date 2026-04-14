#!/usr/bin/env bash
# Tiny assertion helpers. No external deps.
# Usage:
#   source tests/test-framework.sh
#   assert_eq "expected" "$actual" "description"
#   assert_true 'some_command arg' "description"
#   assert_false 'some_command arg' "description"
#   report   # exits non-zero if any FAIL

PASS=0
FAIL=0

assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n' "$desc"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
    fi
}

assert_true() {
    local cmd="$1" desc="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected success)\n' "$desc"
    fi
}

assert_false() {
    local cmd="$1" desc="$2"
    if ! eval "$cmd" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected failure)\n' "$desc"
    fi
}

report() {
    printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
    [[ "$FAIL" -eq 0 ]]
}
