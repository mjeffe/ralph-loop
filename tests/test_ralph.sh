#!/bin/bash
# Ralph unit tests — deterministic, no agent invocation, zero cost.
#
# Usage: ./tests/test_ralph.sh
#
# Run from the ralph-loop project root.

set -euo pipefail

RALPH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TESTS=0

# ---------------------------------------------------------------------------
# Test helpers
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
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "    expected to contain: $needle"
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

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
test_usage_output() {
    echo "--- Usage output ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows plan mode" "plan" "$output"
    assert_contains "shows build mode" "build" "$output"
    assert_contains "shows prompt mode" "prompt" "$output"
    assert_contains "shows update mode" "update" "$output"
}

test_bad_mode_exits_nonzero() {
    echo "--- Bad mode handling ---"
    assert_exit_code "unknown mode exits 1" 1 "$RALPH_DIR/ralph" bogus
}

test_no_mode_exits_nonzero() {
    echo "--- No mode handling ---"
    assert_exit_code "no mode exits 1" 1 "$RALPH_DIR/ralph"
}

test_config_loading() {
    echo "--- Config loading ---"
    local output
    output=$(bash -c "source '$RALPH_DIR/config' && echo \$AGENT")
    assert_eq "AGENT is set" "amp" "$output"

    output=$(bash -c "source '$RALPH_DIR/config' && echo \$SPECS_DIR")
    assert_eq "SPECS_DIR is set" "specs" "$output"

    output=$(bash -c "source '$RALPH_DIR/config' && echo \$MAX_RETRIES")
    assert_eq "MAX_RETRIES is set" "3" "$output"
}

test_agent_script_loading() {
    echo "--- Agent script loading ---"
    local output
    output=$(bash -c "source '$RALPH_DIR/agents/amp.sh' && echo \$AGENT_CLI")
    assert_eq "AGENT_CLI is amp" "amp" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/amp.sh' && type -t agent_invoke")
    assert_eq "agent_invoke is defined" "function" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/amp.sh' && type -t agent_extract_response")
    assert_eq "agent_extract_response is defined" "function" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/amp.sh' && type -t agent_format_display")
    assert_eq "agent_format_display is defined" "function" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/amp.sh' && type -t agent_pre_iteration")
    assert_eq "agent_pre_iteration is defined" "function" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/amp.sh' && type -t agent_post_iteration")
    assert_eq "agent_post_iteration is defined" "function" "$output"
}

test_template_substitution() {
    echo "--- Template substitution ---"
    local template="$TMP_DIR/template.md"
    local output_file="$TMP_DIR/output.md"
    echo 'Specs: ${SPECS_DIR} Mode: ${MODE} Home: ${RALPH_HOME}' > "$template"

    export MODE="build" SPECS_DIR="specs" RALPH_HOME=".ralph"
    envsubst < "$template" > "$output_file"
    local result
    result=$(cat "$output_file")
    assert_eq "envsubst replaces variables" "Specs: specs Mode: build Home: .ralph" "$result"
}

test_signal_detection_complete() {
    echo "--- Signal detection: COMPLETE ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/complete_output.json"
    cat > "$output_file" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"prompt text with <promise>COMPLETE</promise>"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"All done. <promise>COMPLETE</promise>"}]}}
EOF
    # Source check_signals from ralph context
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "detects COMPLETE signal" "2" "$rc"
}

test_signal_detection_replan() {
    echo "--- Signal detection: REPLAN ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/replan_output.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Plan needs work. <promise>REPLAN</promise>"}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "detects REPLAN signal" "3" "$rc"
}

test_signal_detection_no_signal() {
    echo "--- Signal detection: no signal ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/nosignal_output.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Still working on things."}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "no signal returns 0" "0" "$rc"
}

test_signal_ignores_user_messages() {
    echo "--- Signal detection: ignores user messages ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/user_signal.json"
    # Prompt (user message) contains the signal, but agent response does not
    cat > "$output_file" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"When done output: <promise>COMPLETE</promise>"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will keep working."}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "ignores COMPLETE in user message" "0" "$rc"
}

test_signal_survives_malformed_json() {
    echo "--- Signal detection: survives malformed JSON ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/malformed_output.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Working..."}]}}
THIS IS NOT JSON
{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>COMPLETE</promise>"}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "detects signal despite malformed lines" "2" "$rc"
}

test_display_filter_survives_malformed_json() {
    echo "--- Display filter: survives malformed JSON ---"
    source "$RALPH_DIR/agents/amp.sh"
    local input_file="$TMP_DIR/display_input.json"
    cat > "$input_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"line 1"}]}}
NOT JSON
{"type":"assistant","message":{"content":[{"type":"text","text":"line 3"}]}}
EOF
    local output
    output=$(agent_format_display < "$input_file")
    assert_contains "displays line 1" "line 1" "$output"
    assert_contains "displays line 3" "line 3" "$output"
}

test_build_requires_plan() {
    echo "--- Build mode requires implementation plan ---"
    # Temporarily hide the plan file to test the missing-plan check.
    # RALPH_DIR resolves from the script's own location, so we must move
    # the actual file rather than changing the working directory.
    local plan="$RALPH_DIR/implementation_plan.md"
    local stash="$RALPH_DIR/implementation_plan.md.teststash"
    if [[ -f "$plan" ]]; then
        mv "$plan" "$stash"
    fi
    assert_exit_code "build without plan exits 2" 2 \
        "$RALPH_DIR/ralph" build 1
    if [[ -f "$stash" ]]; then
        mv "$stash" "$plan"
    fi
}

test_prompt_requires_completion_signal() {
    echo "--- Prompt mode requires completion signal ---"
    local prompt="$TMP_DIR/no_signal.md"
    echo "Do something" > "$prompt"
    assert_exit_code "prompt without signal exits 1" 1 \
        "$RALPH_DIR/ralph" prompt "$prompt" 1
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "Ralph Test Suite"
    echo "========================================"
    echo ""

    setup

    test_usage_output
    test_bad_mode_exits_nonzero
    test_no_mode_exits_nonzero
    test_config_loading
    test_agent_script_loading
    test_template_substitution
    test_signal_detection_complete
    test_signal_detection_replan
    test_signal_detection_no_signal
    test_signal_ignores_user_messages
    test_signal_survives_malformed_json
    test_display_filter_survives_malformed_json
    test_build_requires_plan
    test_prompt_requires_completion_signal

    teardown

    echo ""
    echo "========================================"
    echo "Results: ${PASS} passed, ${FAIL} failed, ${TESTS} total"
    echo "========================================"

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
