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

test_signal_both_complete_and_replan() {
    echo "--- Signal detection: COMPLETE wins when both present ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/both_signals.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>COMPLETE</promise> and also <promise>REPLAN</promise>"}]}}
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
    assert_eq "COMPLETE wins over REPLAN" "2" "$rc"
}

test_signal_in_long_response() {
    echo "--- Signal detection: finds signal in long response ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/long_response.json"
    # Generate a response with lots of filler text before the signal
    local filler
    filler=$(printf 'x%.0s' {1..500})
    cat > "$output_file" <<EOF
{"type":"assistant","message":{"content":[{"type":"text","text":"${filler} <promise>COMPLETE</promise>"}]}}
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
    assert_eq "finds signal in long response" "2" "$rc"
}

test_init_session_log() {
    echo "--- init_session_log: creates log dir and file ---"
    source <(sed -n '/^init_session_log()/,/^}/p' "$RALPH_DIR/ralph")

    local log_dir="$TMP_DIR/test_logs"
    (
        RALPH_DIR="$TMP_DIR"
        mkdir -p "$TMP_DIR/logs"  # init_session_log uses $RALPH_DIR/logs
        MODE="plan"
        init_session_log
        assert_eq "SESSION_LOG is set" "1" "$( [[ -n "$SESSION_LOG" ]] && echo 1 || echo 0 )"
        assert_eq "session log file exists" "1" "$( [[ -f "$SESSION_LOG" ]] && echo 1 || echo 0 )"
        assert_contains "log filename has mode" "-plan.log" "$SESSION_LOG"
    )
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

test_arg_parsing_plan_with_iterations() {
    echo "--- Arg parsing: plan with max_iterations ---"
    # Run from a dir without .git so it fails at validate_prerequisites, not arg parsing
    local output rc=0
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" plan 5 2>&1) || rc=$?
    assert_not_contains "plan 5 does not error on arg parsing" "unknown option" "$output"
    assert_contains "plan 5 gets past arg parsing" "not a git repository" "$output"
}

test_arg_parsing_plan_process_with_iterations() {
    echo "--- Arg parsing: plan --process with max_iterations ---"
    # --process is checked after config load but before prerequisites
    # Running from no-git dir: arg parsing succeeds, then fails at --process validation
    local output rc=0
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" plan --process 5 2>&1) || rc=$?
    assert_not_contains "plan --process 5 does not error on arg parsing" "unknown option" "$output"
}

test_arg_parsing_prompt_with_file_and_iterations() {
    echo "--- Arg parsing: prompt file and iterations ---"
    local prompt="$TMP_DIR/good_prompt.md"
    echo "Do something <promise>COMPLETE</promise>" > "$prompt"
    local output rc=0
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" prompt "$prompt" 5 2>&1) || rc=$?
    assert_not_contains "prompt file+iters does not error on arg parsing" "unknown option" "$output"
    assert_contains "prompt gets past arg parsing" "not a git repository" "$output"
}

test_arg_parsing_help_with_topic() {
    echo "--- Arg parsing: help with topic ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" help specs 2>&1) || rc=$?
    assert_eq "help specs exits 0" "0" "$rc"
    assert_contains "help specs shows spec content" "TARGET-STATE" "$output"
}

test_arg_parsing_help_build_topic() {
    echo "--- Arg parsing: help build topic ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" help build 2>&1) || rc=$?
    assert_eq "help build exits 0" "0" "$rc"
    assert_contains "help build shows task selection" "TASK SELECTION" "$output"
}

test_arg_parsing_help_sandbox_topic() {
    echo "--- Arg parsing: help sandbox topic ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" help sandbox 2>&1) || rc=$?
    assert_eq "help sandbox exits 0" "0" "$rc"
    assert_contains "help sandbox shows first-time setup" "FIRST-TIME SETUP" "$output"
}

test_validate_prerequisites_no_git() {
    echo "--- validate_prerequisites: no .git directory ---"
    local output rc=0
    # Run from a temp dir with no .git
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" plan 2>&1) || rc=$?
    assert_eq "no .git exits 1" "1" "$rc"
    assert_contains "error mentions no git" "not a git repository" "$output"
}

test_validate_prerequisites_no_specs_dir() {
    echo "--- validate_prerequisites: missing specs directory ---"
    local proj="$TMP_DIR/no_specs_project"
    git init -q "$proj"
    local output rc=0
    output=$(cd "$proj" && "$RALPH_DIR/ralph" plan 2>&1) || rc=$?
    assert_contains "error mentions specs dir" "specs directory not found" "$output"
}

test_validate_prerequisites_skipped_for_help() {
    echo "--- validate_prerequisites: skipped for help mode ---"
    local output rc=0
    # Run help from a dir with no .git — should still succeed
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" help 2>&1) || rc=$?
    assert_eq "help without .git exits 0" "0" "$rc"
}

test_validate_prerequisites_skipped_for_sandbox() {
    echo "--- validate_prerequisites: skipped for sandbox mode ---"
    local output rc=0
    # Run sandbox from a dir with no .git — should fail at sandbox level, not prerequisites
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" sandbox status 2>&1) || rc=$?
    assert_not_contains "sandbox skips git check" "not a git repository" "$output"
}

test_prepare_prompt() {
    echo "--- prepare_prompt: substitutes variables ---"
    source <(sed -n '/^prepare_prompt()/,/^}/p' "$RALPH_DIR/ralph")

    local template="$TMP_DIR/prep_template.md"
    local output_file="$TMP_DIR/prep_output.md"
    echo 'Mode: ${MODE} Specs: ${SPECS_DIR} Home: ${RALPH_HOME}' > "$template"

    export MODE="build" SPECS_DIR="specs" RALPH_HOME=".ralph"
    prepare_prompt "$template" "$output_file"
    local result
    result=$(cat "$output_file")
    assert_eq "prepare_prompt substitutes all vars" "Mode: build Specs: specs Home: .ralph" "$result"
}

test_prepare_prompt_preserves_literals() {
    echo "--- prepare_prompt: preserves non-variable text ---"
    source <(sed -n '/^prepare_prompt()/,/^}/p' "$RALPH_DIR/ralph")

    local template="$TMP_DIR/prep_literal.md"
    local output_file="$TMP_DIR/prep_literal_out.md"
    echo 'No variables here, just plain text.' > "$template"

    export MODE="plan" SPECS_DIR="specs" RALPH_HOME=".ralph"
    prepare_prompt "$template" "$output_file"
    local result
    result=$(cat "$output_file")
    assert_eq "prepare_prompt preserves plain text" "No variables here, just plain text." "$result"
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
    assert_contains "shows sandbox stop" "sandbox stop" "$output"
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
    assert_contains "index shows prompt topic" "prompt" "$output"
    assert_contains "index shows sandbox topic" "sandbox" "$output"
    assert_contains "index shows align-specs topic" "align-specs" "$output"
    assert_contains "index shows retro topic" "retro" "$output"
}

test_help_prompt_shows_content() {
    echo "--- ralph help prompt shows prompt content ---"
    local output
    output=$("$RALPH_DIR/ralph" help prompt 2>&1)
    assert_contains "prompt help shows iteration loop" "iteration loop" "$output"
    assert_contains "prompt help shows COMPLETE signal" "COMPLETE" "$output"
    assert_contains "prompt help shows starting templates" "prompts/" "$output"
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

test_spec_volume_hint_in_prompt_template() {
    echo "--- SPEC_VOLUME_HINT in plan-process.md ---"
    local template
    template=$(cat "$RALPH_DIR/prompts/plan-process.md")
    assert_contains "plan-process.md contains SPEC_VOLUME_HINT" '${SPEC_VOLUME_HINT}' "$template"
}

test_spec_volume_hint_small() {
    echo "--- Volume hint: small project ---"
    local process_dir="$TMP_DIR/small_specs"
    mkdir -p "$process_dir"
    echo "# Small spec" > "$process_dir/one.md"
    echo "# Another" > "$process_dir/two.md"

    local SPEC_BYTES SPEC_COUNT SPEC_KB SPEC_VOLUME_HINT
    SPEC_BYTES=$(cat "$process_dir"/*.md 2>/dev/null | wc -c)
    SPEC_COUNT=$(find "$process_dir" -maxdepth 1 -name '*.md' | wc -l)
    SPEC_KB=$(( SPEC_BYTES / 1024 ))
    if [[ "$SPEC_KB" -lt 50 && "$SPEC_COUNT" -lt 5 ]]; then
        SPEC_VOLUME_HINT="Total process spec volume: ${SPEC_COUNT} files, ~${SPEC_KB} KB. You can likely complete planning in one iteration."
    else
        SPEC_VOLUME_HINT="Total process spec volume: ${SPEC_COUNT} files, ~${SPEC_KB} KB. This exceeds single-iteration capacity. Use the decomposition ledger and process one spec file per iteration."
    fi
    assert_contains "small volume gets single-iteration hint" "one iteration" "$SPEC_VOLUME_HINT"
}

test_spec_volume_hint_large() {
    echo "--- Volume hint: large project ---"
    local process_dir="$TMP_DIR/large_specs"
    mkdir -p "$process_dir"
    for i in $(seq 1 6); do
        dd if=/dev/zero bs=10240 count=1 2>/dev/null | tr '\0' 'x' > "$process_dir/spec-${i}.md"
    done

    local SPEC_BYTES SPEC_COUNT SPEC_KB SPEC_VOLUME_HINT
    SPEC_BYTES=$(cat "$process_dir"/*.md 2>/dev/null | wc -c)
    SPEC_COUNT=$(find "$process_dir" -maxdepth 1 -name '*.md' | wc -l)
    SPEC_KB=$(( SPEC_BYTES / 1024 ))
    if [[ "$SPEC_KB" -lt 50 && "$SPEC_COUNT" -lt 5 ]]; then
        SPEC_VOLUME_HINT="Total process spec volume: ${SPEC_COUNT} files, ~${SPEC_KB} KB. You can likely complete planning in one iteration."
    else
        SPEC_VOLUME_HINT="Total process spec volume: ${SPEC_COUNT} files, ~${SPEC_KB} KB. This exceeds single-iteration capacity. Use the decomposition ledger and process one spec file per iteration."
    fi
    assert_contains "large volume gets incremental hint" "decomposition ledger" "$SPEC_VOLUME_HINT"
}

test_build_prompt_has_phase_collapsing() {
    echo "--- build.md contains phase collapsing instruction ---"
    local template
    template=$(cat "$RALPH_DIR/prompts/build.md")
    assert_contains "build.md mentions phase collapsing" "Phase collapsing" "$template"
    assert_contains "build.md gates on Plan Type: process" "Plan Type: process" "$template"
}

test_plan_process_has_decomposition_ledger() {
    echo "--- plan-process.md contains decomposition ledger ---"
    local template
    template=$(cat "$RALPH_DIR/prompts/plan-process.md")
    assert_contains "plan-process.md has Decomposition Progress heading" "Decomposition Progress" "$template"
    assert_contains "plan-process.md has ledger table headers" "Spec File" "$template"
    assert_contains "plan-process.md mentions skeleton-first workflow" "Skeleton" "$template"
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

test_align_specs_requires_process_dir() {
    echo "--- align-specs requires PROCESS_DIR ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" align-specs 2>&1) || rc=$?
    assert_eq "align-specs without PROCESS_DIR exits 1" "1" "$rc"
    assert_contains "error mentions process specs" "align-specs requires process specs" "$output"
}

test_align_specs_requires_process_plan() {
    echo "--- align-specs requires process-type plan ---"
    local config_backup
    config_backup=$(cat "$RALPH_DIR/config")
    echo "PROCESS_DIR=\"$TMP_DIR/project/specs\"" >> "$RALPH_DIR/config"

    local plan_backup=""
    if [[ -f "$RALPH_DIR/implementation_plan.md" ]]; then
        plan_backup=$(cat "$RALPH_DIR/implementation_plan.md")
    fi
    cat > "$RALPH_DIR/implementation_plan.md" <<'PLAN'
# Implementation Plan

Plan Type: gap-driven

### Task 1: Something
**Status:** planned
PLAN

    local output rc=0
    output=$("$RALPH_DIR/ralph" align-specs 2>&1) || rc=$?

    # Restore config and plan
    echo "$config_backup" > "$RALPH_DIR/config"
    if [[ -n "$plan_backup" ]]; then
        echo "$plan_backup" > "$RALPH_DIR/implementation_plan.md"
    fi

    assert_eq "align-specs with gap-driven plan exits 1" "1" "$rc"
    assert_contains "error mentions process-type" "process-type implementation plan" "$output"
}

test_align_specs_requires_completed_tasks() {
    echo "--- align-specs requires completed tasks ---"
    local config_backup
    config_backup=$(cat "$RALPH_DIR/config")
    echo "PROCESS_DIR=\"$TMP_DIR/project/specs\"" >> "$RALPH_DIR/config"

    local plan_backup=""
    if [[ -f "$RALPH_DIR/implementation_plan.md" ]]; then
        plan_backup=$(cat "$RALPH_DIR/implementation_plan.md")
    fi
    cat > "$RALPH_DIR/implementation_plan.md" <<'PLAN'
# Implementation Plan

Plan Type: process

### Task 1: Something
**Status:** planned
PLAN

    local output rc=0
    output=$("$RALPH_DIR/ralph" align-specs 2>&1) || rc=$?

    # Restore
    echo "$config_backup" > "$RALPH_DIR/config"
    if [[ -n "$plan_backup" ]]; then
        echo "$plan_backup" > "$RALPH_DIR/implementation_plan.md"
    fi

    assert_eq "align-specs without completed tasks exits 1" "1" "$rc"
    assert_contains "error mentions completed build work" "align-specs requires completed build work" "$output"
}

test_usage_shows_align_specs() {
    echo "--- Usage output includes align-specs ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows align-specs mode" "align-specs" "$output"
}

test_help_retro_shows_content() {
    echo "--- ralph help retro shows retro content ---"
    local output
    output=$("$RALPH_DIR/ralph" help retro 2>&1)
    assert_contains "retro help shows header" "RETROSPECTIVE" "$output"
    assert_contains "retro help shows when" "WHEN TO DO A RETRO" "$output"
    assert_contains "retro help shows what to review" "WHAT TO REVIEW" "$output"
    assert_contains "retro help shows failure patterns" "COMMON FAILURE PATTERNS" "$output"
    assert_contains "retro help shows where to apply" "WHERE TO APPLY FIXES" "$output"
    assert_contains "retro help shows checklist" "RETRO CHECKLIST" "$output"
    assert_contains "retro help shows agent-assisted" "AGENT-ASSISTED ANALYSIS" "$output"
    assert_contains "retro help shows feedback sharing" "SHARING FEEDBACK" "$output"
}

test_help_align_specs_shows_content() {
    echo "--- ralph help align-specs shows content ---"
    local output
    output=$("$RALPH_DIR/ralph" help align-specs 2>&1)
    assert_contains "align-specs help shows purpose" "ALIGN SPECS" "$output"
    assert_contains "align-specs help shows prerequisites" "PREREQUISITES" "$output"
    assert_contains "align-specs help shows ledger" "ALIGNMENT LEDGER" "$output"
}

test_help_index_shows_align_specs() {
    echo "--- ralph help index includes align-specs ---"
    local output
    output=$("$RALPH_DIR/ralph" help 2>&1)
    assert_contains "index shows align-specs topic" "align-specs" "$output"
}

test_installer_creates_originals() {
    echo "--- Installer creates .originals/ ---"
    # Verify install.sh populates .originals/ by checking the populate_originals function exists
    local has_fn
    has_fn=$(grep -c "populate_originals" "$RALPH_DIR/install.sh")
    assert_eq "install.sh has populate_originals" "true" "$( [[ "$has_fn" -ge 2 ]] && echo true || echo false )"

    # Verify .originals/ is created in install_ralph_dir
    local has_mkdir
    has_mkdir=$(grep -c '\.originals' "$RALPH_DIR/install.sh")
    assert_eq "install.sh references .originals" "true" "$( [[ "$has_mkdir" -ge 1 ]] && echo true || echo false )"
}

test_updater_three_way_merge_clean() {
    echo "--- Three-way merge: clean merge ---"
    # Simulate: originals has base, user modified one section, upstream modified another
    local test_dir="$TMP_DIR/merge_clean"
    mkdir -p "$test_dir"

    # Base (originals)
    cat > "$test_dir/base.md" <<'EOF'
# Config
setting_a=1
setting_b=2
setting_c=3
EOF

    # User's version (modified setting_a)
    cat > "$test_dir/ours.md" <<'EOF'
# Config
setting_a=100
setting_b=2
setting_c=3
EOF

    # Upstream (modified setting_c)
    cat > "$test_dir/theirs.md" <<'EOF'
# Config
setting_a=1
setting_b=2
setting_c=300
EOF

    local merge_rc=0
    git merge-file "$test_dir/ours.md" "$test_dir/base.md" "$test_dir/theirs.md" || merge_rc=$?
    assert_eq "clean merge exits 0" "0" "$merge_rc"
    assert_contains "merge preserves user change" "setting_a=100" "$(cat "$test_dir/ours.md")"
    assert_contains "merge includes upstream change" "setting_c=300" "$(cat "$test_dir/ours.md")"
}

test_updater_three_way_merge_conflict() {
    echo "--- Three-way merge: conflict ---"
    # Both user and upstream modify the same line
    local test_dir="$TMP_DIR/merge_conflict"
    mkdir -p "$test_dir"

    cat > "$test_dir/base.md" <<'EOF'
# Config
setting_a=1
EOF

    cat > "$test_dir/ours.md" <<'EOF'
# Config
setting_a=user_value
EOF

    cat > "$test_dir/theirs.md" <<'EOF'
# Config
setting_a=upstream_value
EOF

    local merge_rc=0
    git merge-file "$test_dir/ours.md" "$test_dir/base.md" "$test_dir/theirs.md" || merge_rc=$?
    assert_eq "conflict merge exits non-zero" "true" "$( [[ "$merge_rc" -gt 0 ]] && echo true || echo false )"
    assert_contains "conflict has markers" "<<<<<<<" "$(cat "$test_dir/ours.md")"
}

test_updater_originals_not_in_gitignore() {
    echo "--- .originals/ NOT in .gitignore (must be committed for sandbox persistence) ---"
    local gitignore
    gitignore=$(cat "$RALPH_DIR/.gitignore")
    local has_originals
    has_originals=$(echo "$gitignore" | grep -c '\.originals/' || true)
    assert_eq ".gitignore does not exclude .originals/" "0" "$has_originals"
}

test_updater_has_merge_logic() {
    echo "--- update.sh contains three-way merge logic ---"
    local updater
    updater=$(cat "$RALPH_DIR/update.sh")
    assert_contains "update.sh uses git merge-file" "git merge-file" "$updater"
    assert_contains "update.sh references .originals" ".originals" "$updater"
    assert_contains "update.sh reports merged status" "done (merged)" "$updater"
    assert_contains "update.sh reports CONFLICT status" "CONFLICT" "$updater"
}

test_sandbox_ensure_name_from_env() {
    echo "--- sandbox_ensure_name: reads SANDBOX_NAME from .env ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    echo "SANDBOX_NAME=my-sandbox" > "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "picks up name from .env" "my-sandbox" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_missing_from_env() {
    echo "--- sandbox_ensure_name: falls back when SANDBOX_NAME missing from .env ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    echo "OTHER_VAR=hello" > "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "derives name (not empty)" "1" "$( [[ -n "$SANDBOX_NAME" ]] && echo 1 || echo 0 )"
        assert_contains "derived name has -sandbox-" "-sandbox-" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_no_env_file() {
    echo "--- sandbox_ensure_name: falls back when no .env file ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    rm -f "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "derives name (not empty)" "1" "$( [[ -n "$SANDBOX_NAME" ]] && echo 1 || echo 0 )"
        assert_contains "derived name has -sandbox-" "-sandbox-" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_already_set() {
    echo "--- sandbox_ensure_name: no-op when SANDBOX_NAME already set ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    (
        export SANDBOX_NAME="pre-existing"
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "preserves existing value" "pre-existing" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_writes_back_to_env() {
    echo "--- sandbox_ensure_name: appends derived name to .env ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    echo "OTHER_VAR=hello" > "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        local written
        written=$(grep '^SANDBOX_NAME=' "$sdir/.env" || true)
        assert_eq "wrote name back to .env" "1" "$( [[ -n "$written" ]] && echo 1 || echo 0 )"
    )
}

test_sandbox_up_no_compose_file() {
    echo "--- sandbox_up: exits when no compose file ---"
    local output rc=0
    local sandbox_dir="$TMP_DIR/no_compose/.ralph/sandbox"
    mkdir -p "$sandbox_dir"
    # Create a .env so that check passes, but no docker-compose.yml
    echo "SANDBOX_NAME=test" > "$sandbox_dir/.env"
    output=$(SANDBOX_NAME=test RALPH_DIR="$TMP_DIR/no_compose/.ralph" \
        bash -c "source <(sed -n '/^sandbox_up()/,/^}/p' \"$RALPH_DIR/ralph\")
                 source <(sed -n '/^sandbox_ensure_name()/,/^}/p' \"$RALPH_DIR/ralph\")
                 sandbox_up" 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions setup first" "sandbox setup" "$output"
}

test_sandbox_up_no_env_file() {
    echo "--- sandbox_up: exits when no .env file ---"
    local sandbox_dir="$TMP_DIR/no_env/.ralph/sandbox"
    mkdir -p "$sandbox_dir"
    # Create compose but no .env
    echo "services:" > "$sandbox_dir/docker-compose.yml"
    cat > "$sandbox_dir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
DOCK
    local output rc=0
    output=$(SANDBOX_NAME=test RALPH_DIR="$TMP_DIR/no_env/.ralph" \
        bash -c "source <(sed -n '/^sandbox_up()/,/^}/p' \"$RALPH_DIR/ralph\")
                 source <(sed -n '/^sandbox_ensure_name()/,/^}/p' \"$RALPH_DIR/ralph\")
                 sandbox_up" 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions .env" ".env" "$output"
}

test_sandbox_status_no_compose_file() {
    echo "--- sandbox_status: exits when no compose file ---"
    local sandbox_dir="$TMP_DIR/no_compose_status/.ralph/sandbox"
    mkdir -p "$sandbox_dir"
    local output rc=0
    output=$(SANDBOX_NAME=test RALPH_DIR="$TMP_DIR/no_compose_status/.ralph" \
        bash -c "source <(sed -n '/^sandbox_status()/,/^}/p' \"$RALPH_DIR/ralph\")
                 source <(sed -n '/^sandbox_ensure_name()/,/^}/p' \"$RALPH_DIR/ralph\")
                 sandbox_status" 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions setup first" "sandbox setup" "$output"
}

test_sandbox_setup_unknown_flag() {
    echo "--- sandbox_setup: rejects unknown flags ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" sandbox setup --bogus 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions unknown option" "unknown option" "$output"
}

test_sandbox_setup_render_only_without_profile() {
    echo "--- sandbox_setup: --render-only without profile exits 1 ---"
    # This tests flag parsing AND the render-only precondition in one shot.
    # No Docker or agent needed — fails before reaching either.
    local output rc=0
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" sandbox setup --render-only 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions missing profile" "project profile" "$output"
}

test_spec_volume_hint_boundary() {
    echo "--- Volume hint: boundary (exactly 5 files under 50KB) ---"
    local process_dir="$TMP_DIR/boundary_specs"
    mkdir -p "$process_dir"
    for i in $(seq 1 5); do
        echo "# Spec $i" > "$process_dir/spec-${i}.md"
    done

    local SPEC_BYTES SPEC_COUNT SPEC_KB SPEC_VOLUME_HINT
    SPEC_BYTES=$(cat "$process_dir"/*.md 2>/dev/null | wc -c)
    SPEC_COUNT=$(find "$process_dir" -maxdepth 1 -name '*.md' | wc -l)
    SPEC_KB=$(( SPEC_BYTES / 1024 ))
    if [[ "$SPEC_KB" -lt 50 && "$SPEC_COUNT" -lt 5 ]]; then
        SPEC_VOLUME_HINT="single"
    else
        SPEC_VOLUME_HINT="incremental"
    fi
    # 5 files triggers the >= 5 branch (not strictly less than)
    assert_eq "5 files triggers incremental hint" "incremental" "$SPEC_VOLUME_HINT"
}

test_sandbox_validate_profile_valid() {
    echo "--- sandbox_validate_profile: valid profile ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/valid-profile.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 1,
    "stack": "php-laravel",
    "runtimes": [{"name": "php", "version": "8.3", "evidence": ["composer.json"]}],
    "package_managers": [{"name": "composer", "install_command": "composer install"}],
    "services": [{"name": "postgres", "image": "postgres:16", "port": 5432, "reason": "DB_CONNECTION=pgsql"}],
    "system_packages": ["libpq-dev"],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/var/www/html",
    "env_overrides": {"DB_HOST": "db"},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "web", "command": "php artisan serve"}],
    "compose_ports": {"http": 80},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_eq "valid profile produces no errors" "" "$output"
}

test_sandbox_validate_profile_missing_fields() {
    echo "--- sandbox_validate_profile: missing required fields ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/missing-fields.json"
    echo '{"schema_version": 1, "stack": "node"}' > "$profile"

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches missing runtimes" "missing required field: runtimes" "$output"
    assert_contains "catches missing services" "missing required field: services" "$output"
    assert_contains "catches missing supervisor_programs" "missing required field: supervisor_programs" "$output"
    assert_contains "catches missing workdir" "missing required field: workdir" "$output"
}

test_sandbox_validate_profile_bad_schema_version() {
    echo "--- sandbox_validate_profile: wrong schema_version ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/bad-version.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 2,
    "stack": "node",
    "runtimes": [{"name": "node", "version": "20", "evidence": ["package.json"]}],
    "package_managers": [{"name": "npm", "install_command": "npm ci"}],
    "services": [],
    "system_packages": [],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/app",
    "env_overrides": {},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "keepalive", "command": "sleep infinity"}],
    "compose_ports": {},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches bad schema_version" "schema_version must be 1" "$output"
}

test_sandbox_validate_profile_empty_runtimes() {
    echo "--- sandbox_validate_profile: empty runtimes ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/empty-runtimes.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 1,
    "stack": "node",
    "runtimes": [],
    "package_managers": [],
    "services": [],
    "system_packages": [],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/app",
    "env_overrides": {},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "keepalive", "command": "sleep infinity"}],
    "compose_ports": {},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches empty runtimes" "runtimes must have at least one entry" "$output"
}

test_sandbox_validate_profile_service_missing_fields() {
    echo "--- sandbox_validate_profile: service missing required fields ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/bad-service.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 1,
    "stack": "node",
    "runtimes": [{"name": "node", "version": "20", "evidence": ["package.json"]}],
    "package_managers": [{"name": "npm", "install_command": "npm ci"}],
    "services": [{"name": "postgres"}],
    "system_packages": [],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/app",
    "env_overrides": {},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "keepalive", "command": "sleep infinity"}],
    "compose_ports": {},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches missing image" "missing required field: image" "$output"
    assert_contains "catches missing port" "missing required field: port or ports" "$output"
    assert_contains "catches missing reason" "missing required field: reason" "$output"
}

test_sandbox_validate_profile_invalid_json() {
    echo "--- sandbox_validate_profile: invalid JSON ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/bad.json"
    echo "not json at all" > "$profile"

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches invalid JSON" "not valid JSON" "$output"
}

test_sandbox_validate_structural() {
    echo "--- sandbox_validate: structural checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_validate_test"
    mkdir -p "$sdir"

    # Missing all files
    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches missing entrypoint" "entrypoint.sh not found" "$output"
    assert_contains "catches missing Dockerfile" "Dockerfile not found" "$output"
    assert_contains "catches missing compose" "docker-compose.yml not found" "$output"

    # Create minimal valid entrypoint
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY

    # Create minimal Dockerfile
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
DOCK

    output=$(sandbox_validate "$sdir")
    # entrypoint and Dockerfile should pass structural checks; compose still missing
    assert_contains "still catches missing compose" "docker-compose.yml not found" "$output"

    rm -rf "$sdir"
}

test_sandbox_setup_render_only_requires_profile() {
    echo "--- sandbox setup --render-only requires existing profile ---"
    local sdir="$TMP_DIR/project/sandbox"
    mkdir -p "$sdir"
    rm -f "$sdir/project-profile.json"

    local output rc=0
    output=$("$RALPH_DIR/ralph" sandbox setup --render-only 2>&1) || rc=$?
    assert_eq "--render-only without profile exits 1" "1" "$rc"
    assert_contains "error mentions missing profile" "no project profile found" "$output"
    assert_contains "suggests running without --render-only" "without --render-only" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_entrypoint_structural() {
    echo "--- sandbox_validate: entrypoint structural checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_entrypoint_test"
    mkdir -p "$sdir"

    # Create Dockerfile to avoid those errors
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
DOCK

    # Create a bad entrypoint missing required elements
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/bin/bash
echo "hello"
ENTRY

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches wrong shebang" "does not start with #!/usr/bin/env bash" "$output"
    assert_contains "catches missing set -euo" "missing set -euo pipefail" "$output"
    assert_contains "catches missing git credential" "missing git credential configuration" "$output"
    assert_contains "catches missing clone logic" "missing clone logic" "$output"
    assert_contains "catches missing exec supervisord" "does not end with exec supervisord" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_compose_structural() {
    echo "--- sandbox_validate: docker-compose.yml structural checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_compose_test"
    mkdir -p "$sdir"

    # Provide valid Dockerfile and entrypoint so we isolate compose checks
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
DOCK
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY

    # Create a compose file missing required elements
    cat > "$sdir/docker-compose.yml" <<'COMPOSE'
services:
  web:
    image: nginx
COMPOSE

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches missing app service" "missing app service" "$output"
    assert_contains "catches missing env_file" "missing env_file" "$output"
    assert_contains "catches missing tty" "missing tty: true" "$output"
    assert_contains "catches missing stdin_open" "missing stdin_open: true" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_cross_file_env_vars() {
    echo "--- sandbox_validate: cross-file env var checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_crossfile_test"
    mkdir -p "$sdir"

    # Minimal valid files
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /app
DOCK
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY
    cat > "$sdir/docker-compose.yml" <<'COMPOSE'
services:
  app:
    build: .
    env_file: .env
    tty: true
    stdin_open: true
    environment:
      - DB_HOST=${DB_HOST}
      - SECRET_KEY=${SECRET_KEY}
COMPOSE
    # .env.example only has DB_HOST, missing SECRET_KEY
    cat > "$sdir/.env.example" <<'ENV'
DB_HOST=localhost
ENV

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches undocumented env var" "SECRET_KEY not documented in .env.example" "$output"

    # Commented-out entries should count as documented
    cat > "$sdir/.env.example" <<'ENV'
DB_HOST=localhost
# SECRET_KEY=my-secret
ENV
    output=$(sandbox_validate "$sdir")
    assert_not_contains "accepts commented-out env var" "SECRET_KEY not documented" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_runtime_manager_refs() {
    echo "--- sandbox_validate: unprovisioned runtime manager checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_rtmgr_test"
    mkdir -p "$sdir"

    # Minimal valid files — entrypoint references nvm.sh but Dockerfile doesn't install it
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /app
DOCK
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
source /usr/local/nvm/nvm.sh
nvm use 12
npm ci
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY
    cat > "$sdir/docker-compose.yml" <<'COMPOSE'
services:
  app:
    build: .
    env_file: .env
    tty: true
    stdin_open: true
    environment:
      - SANDBOX=1
COMPOSE
    cat > "$sdir/.env.example" <<'ENV'
SANDBOX=1
ENV

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches unprovisioned nvm.sh" "nvm.sh" "$output"

    # Now add nvm install to Dockerfile — should pass
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && source /usr/local/nvm/nvm.sh && nvm install 12
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /app
DOCK
    output=$(sandbox_validate "$sdir")
    assert_not_contains "accepts provisioned nvm.sh" "nvm.sh" "$output"

    rm -rf "$sdir"
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
    test_signal_both_complete_and_replan
    test_signal_in_long_response
    test_init_session_log
    test_display_filter_survives_malformed_json
    test_arg_parsing_plan_with_iterations
    test_arg_parsing_plan_process_with_iterations
    test_arg_parsing_prompt_with_file_and_iterations
    test_arg_parsing_help_with_topic
    test_arg_parsing_help_build_topic
    test_arg_parsing_help_sandbox_topic
    test_validate_prerequisites_no_git
    test_validate_prerequisites_no_specs_dir
    test_validate_prerequisites_skipped_for_help
    test_validate_prerequisites_skipped_for_sandbox
    test_prepare_prompt
    test_prepare_prompt_preserves_literals
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
    test_help_prompt_shows_content
    test_help_unknown_topic_exits_zero
    test_spec_volume_hint_in_prompt_template
    test_spec_volume_hint_small
    test_spec_volume_hint_large
    test_spec_volume_hint_boundary
    test_build_prompt_has_phase_collapsing
    test_plan_process_has_decomposition_ledger
    test_managed_files_in_sync
    test_detect_stack
    test_align_specs_requires_process_dir
    test_align_specs_requires_process_plan
    test_align_specs_requires_completed_tasks
    test_usage_shows_align_specs
    test_help_retro_shows_content
    test_help_align_specs_shows_content
    test_help_index_shows_align_specs
    test_installer_creates_originals
    test_updater_three_way_merge_clean
    test_updater_three_way_merge_conflict
    test_updater_originals_not_in_gitignore
    test_updater_has_merge_logic
    test_sandbox_ensure_name_from_env
    test_sandbox_ensure_name_missing_from_env
    test_sandbox_ensure_name_no_env_file
    test_sandbox_ensure_name_already_set
    test_sandbox_ensure_name_writes_back_to_env
    test_sandbox_up_no_compose_file
    test_sandbox_up_no_env_file
    test_sandbox_status_no_compose_file
    test_sandbox_setup_unknown_flag
    test_sandbox_setup_render_only_without_profile
    test_sandbox_validate_profile_valid
    test_sandbox_validate_profile_missing_fields
    test_sandbox_validate_profile_bad_schema_version
    test_sandbox_validate_profile_empty_runtimes
    test_sandbox_validate_profile_service_missing_fields
    test_sandbox_validate_profile_invalid_json
    test_sandbox_validate_structural
    test_sandbox_setup_render_only_requires_profile
    test_sandbox_validate_entrypoint_structural
    test_sandbox_validate_compose_structural
    test_sandbox_validate_cross_file_env_vars
    test_sandbox_validate_runtime_manager_refs

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
