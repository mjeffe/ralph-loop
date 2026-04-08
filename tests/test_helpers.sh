#!/bin/bash
# Shared test helpers — sourced by test_ralph.sh and individual test files.
#
# Provides: assert_eq, assert_contains, assert_not_contains, assert_exit_code,
#           setup, teardown, RALPH_DIR, TMP_DIR, PASS, FAIL, TESTS counters.

set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TESTS=0

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TESTS=$(( TESTS + 1 ))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    TESTS=$(( TESTS + 1 ))
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "    expected to contain: $needle"
        echo "    actual: $haystack"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TESTS=$(( TESTS + 1 ))
    if ! echo "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "    expected NOT to contain: $needle"
        echo "    actual: $haystack"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_exit_code() {
    local label="$1" expected="$2"
    shift 2
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    TESTS=$(( TESTS + 1 ))
    if [[ "$expected" -eq "$actual" ]]; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "    expected exit code: $expected"
        echo "    actual exit code:   $actual"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------
TMP_DIR=""
setup() {
    TMP_DIR="$(mktemp -d)"
    # Create a minimal fake project for ralph to operate in
    git init -q "$TMP_DIR/project"
    mkdir -p "$TMP_DIR/project/specs"
    echo "# Specs Index" > "$TMP_DIR/project/specs/README.md"
}

teardown() {
    rm -rf "$TMP_DIR"
}
