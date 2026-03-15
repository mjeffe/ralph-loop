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

test_claude_agent_script() {
    echo "--- Claude agent script ---"
    local output
    output=$(bash -c "source '$RALPH_DIR/agents/claude.sh' && echo \$AGENT_CLI")
    assert_eq "claude AGENT_CLI is claude" "claude" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/claude.sh' && type -t agent_invoke")
    assert_eq "claude agent_invoke is defined" "function" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/claude.sh' && type -t agent_extract_response")
    assert_eq "claude agent_extract_response is defined" "function" "$output"

    output=$(bash -c "source '$RALPH_DIR/agents/claude.sh' && type -t agent_format_display")
    assert_eq "claude agent_format_display is defined" "function" "$output"
}

test_stub_agent_scripts() {
    echo "--- Stub agent scripts (cline, codex) ---"
    for agent in cline codex; do
        local output
        output=$(bash -c "source '$RALPH_DIR/agents/${agent}.sh' && echo \$AGENT_CLI")
        assert_eq "${agent} AGENT_CLI is ${agent}" "$agent" "$output"

        local rc=0
        bash -c "source '$RALPH_DIR/agents/${agent}.sh' && agent_invoke /dev/null" 2>/dev/null || rc=$?
        assert_eq "${agent} agent_invoke exits 1" "1" "$rc"
    done
}

test_sandbox_usage_output() {
    echo "--- Sandbox usage in help ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows sandbox setup" "sandbox setup" "$output"
    assert_contains "shows sandbox up" "sandbox up" "$output"
    assert_contains "shows sandbox down" "sandbox down" "$output"
    assert_contains "shows sandbox reset" "sandbox reset" "$output"
    assert_contains "shows sandbox shell" "sandbox shell" "$output"
    assert_contains "shows sandbox status" "sandbox status" "$output"
}

test_sandbox_no_subcommand_exits_nonzero() {
    echo "--- Sandbox with no subcommand ---"
    assert_exit_code "sandbox without subcommand exits 1" 1 "$RALPH_DIR/ralph" sandbox
}

test_sandbox_bad_subcommand_exits_nonzero() {
    echo "--- Sandbox with bad subcommand ---"
    assert_exit_code "sandbox bogus exits 1" 1 "$RALPH_DIR/ralph" sandbox bogus
}

test_sandbox_guard_inside_sandbox() {
    echo "--- Sandbox guard: SANDBOX=1 ---"
    local rc=0
    local output
    output=$(SANDBOX=1 "$RALPH_DIR/ralph" sandbox up 2>&1) || rc=$?
    assert_eq "SANDBOX=1 exits 1" "1" "$rc"
    assert_contains "error message mentions already inside" "already inside the sandbox" "$output"
}

extract_managed_files() {
    sed -n '/^MANAGED_FILES=(/,/^)/p' "$1" | grep -v '^MANAGED_FILES=\|^)' | tr -d ' ' | sort
}

test_process_flag_rejected_with_non_plan_modes() {
    echo "--- --process flag rejected with non-plan modes ---"
    assert_exit_code "--process with build exits 1" 1 "$RALPH_DIR/ralph" build --process
    assert_exit_code "--process with prompt exits 1" 1 "$RALPH_DIR/ralph" prompt --process
}

test_process_requires_process_dir() {
    echo "--- --process requires PROCESS_DIR ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" plan --process 2>&1) || rc=$?
    assert_eq "--process without PROCESS_DIR exits 1" "1" "$rc"
    assert_contains "error mentions PROCESS_DIR" "No PROCESS_DIR configured" "$output"
}

test_process_dir_must_exist() {
    echo "--- --process validates PROCESS_DIR exists ---"
    local config_backup
    config_backup=$(cat "$RALPH_DIR/config")
    echo 'PROCESS_DIR="/nonexistent/dir"' >> "$RALPH_DIR/config"
    local output rc=0
    output=$("$RALPH_DIR/ralph" plan --process 2>&1) || rc=$?
    echo "$config_backup" > "$RALPH_DIR/config"
    assert_eq "--process with missing dir exits 1" "1" "$rc"
    assert_contains "error mentions dir not found" "not found" "$output"
}

test_process_dir_must_have_md_files() {
    echo "--- --process validates *.md files in PROCESS_DIR ---"
    local empty_dir="$TMP_DIR/empty_process"
    mkdir -p "$empty_dir"
    local config_backup
    config_backup=$(cat "$RALPH_DIR/config")
    echo "PROCESS_DIR=\"$empty_dir\"" >> "$RALPH_DIR/config"
    local output rc=0
    output=$("$RALPH_DIR/ralph" plan --process 2>&1) || rc=$?
    echo "$config_backup" > "$RALPH_DIR/config"
    assert_eq "--process with empty dir exits 1" "1" "$rc"
    assert_contains "error mentions no process specs" "No process specs found" "$output"
}

test_usage_shows_process() {
    echo "--- Usage output includes --process ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows --process flag" "--process" "$output"
}

test_usage_shows_help() {
    echo "--- Usage output includes help ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows help mode" "help" "$output"
}

test_help_shows_topic_index() {
    echo "--- ralph help shows topic index ---"
    local output
    output=$("$RALPH_DIR/ralph" help 2>&1)
    assert_contains "index shows plan topic" "plan" "$output"
    assert_contains "index shows specs topic" "specs" "$output"
    assert_contains "index shows build topic" "build" "$output"
    assert_contains "index shows sandbox topic" "sandbox" "$output"
}

test_help_plan_shows_content() {
    echo "--- ralph help plan shows plan content ---"
    local output
    output=$("$RALPH_DIR/ralph" help plan 2>&1)
    assert_contains "plan help shows gap-driven" "Gap-driven" "$output"
    assert_contains "plan help shows --process" "--process" "$output"
}

test_help_unknown_topic_exits_zero() {
    echo "--- ralph help bogus shows error and index ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" help bogus 2>&1) || rc=$?
    assert_eq "help bogus exits 0" "0" "$rc"
    assert_contains "error mentions unknown topic" "Unknown help topic" "$output"
    assert_contains "falls back to index" "ralph help <topic>" "$output"
}

test_managed_files_in_sync() {
    echo "--- Managed files: install.sh and update.sh in sync ---"
    local installer_files updater_files
    installer_files=$(extract_managed_files "$RALPH_DIR/install.sh")
    updater_files=$(extract_managed_files "$RALPH_DIR/update.sh")
    assert_eq "MANAGED_FILES arrays match" "$installer_files" "$updater_files"
}

test_detect_stack() {
    echo "--- Stack detection ---"

    # Source detect_stack from ralph (extract it as a function)
    source <(sed -n '/^detect_stack()/,/^}/p' "$RALPH_DIR/ralph")

    local proj="$TMP_DIR/detect_stack_project"

    # PHP/Laravel via artisan
    mkdir -p "$proj" && touch "$proj/artisan"
    assert_eq "artisan -> php-laravel" "php-laravel" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # PHP/Laravel via composer.json
    mkdir -p "$proj"
    echo '{"require":{"laravel/framework":"^11.0"}}' > "$proj/composer.json"
    assert_eq "composer laravel -> php-laravel" "php-laravel" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # PHP generic
    mkdir -p "$proj"
    echo '{"require":{"slim/slim":"^4.0"}}' > "$proj/composer.json"
    assert_eq "composer non-laravel -> php" "php" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Rails via bin/rails
    mkdir -p "$proj/bin" && touch "$proj/bin/rails"
    assert_eq "bin/rails -> rails" "rails" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Rails via Gemfile
    mkdir -p "$proj"
    echo "gem 'rails', '~> 7.0'" > "$proj/Gemfile"
    assert_eq "Gemfile with rails -> rails" "rails" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Ruby generic
    mkdir -p "$proj"
    echo "gem 'sinatra'" > "$proj/Gemfile"
    assert_eq "Gemfile without rails -> ruby" "ruby" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Python/Django
    mkdir -p "$proj"
    echo 'import django; django.setup()' > "$proj/manage.py"
    assert_eq "manage.py with django -> python-django" "python-django" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Python generic (requirements.txt)
    mkdir -p "$proj" && touch "$proj/requirements.txt"
    assert_eq "requirements.txt -> python" "python" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Python generic (pyproject.toml)
    mkdir -p "$proj" && touch "$proj/pyproject.toml"
    assert_eq "pyproject.toml -> python" "python" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Go
    mkdir -p "$proj" && touch "$proj/go.mod"
    assert_eq "go.mod -> go" "go" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Rust
    mkdir -p "$proj" && touch "$proj/Cargo.toml"
    assert_eq "Cargo.toml -> rust" "rust" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Node.js
    mkdir -p "$proj" && touch "$proj/package.json"
    assert_eq "package.json alone -> node" "node" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Laravel with package.json — should detect php-laravel, not node
    mkdir -p "$proj"
    touch "$proj/artisan" "$proj/package.json"
    assert_eq "artisan + package.json -> php-laravel" "php-laravel" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"

    # Empty project
    mkdir -p "$proj"
    assert_eq "empty project -> empty string" "" "$(cd "$proj" && detect_stack)"
    rm -rf "$proj"
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
    test_claude_agent_script
    test_stub_agent_scripts
    test_sandbox_usage_output
    test_sandbox_no_subcommand_exits_nonzero
    test_sandbox_bad_subcommand_exits_nonzero
    test_sandbox_guard_inside_sandbox
    test_process_flag_rejected_with_non_plan_modes
    test_process_requires_process_dir
    test_process_dir_must_exist
    test_process_dir_must_have_md_files
    test_usage_shows_process
    test_usage_shows_help
    test_help_shows_topic_index
    test_help_plan_shows_content
    test_help_unknown_topic_exits_zero
    test_managed_files_in_sync
    test_detect_stack

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
