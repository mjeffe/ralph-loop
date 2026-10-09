#!/bin/bash
# Loop tests — run the real ralph script end-to-end in a throwaway project with the
# scripted stub agent (tests/stub_agent.sh). No LLM, no Docker, sub-second per scenario.

loop_invocations() { cat "$LOOP_DIR/stub/count" 2>/dev/null || echo 0; }
loop_prompt() { cat "$LOOP_DIR/stub/prompt-$1.md"; }

# Write a plan with tasks 1..3, each depending on the previous.
# Usage: loop_plan <plan-type> [decorated]   (decorated: "- **Field:** value" Markdown form, #33)
loop_plan() {
    local plan="$LOOP_DIR/project/.ralph/implementation_plan.md"
    cat > "$plan" << EOF
# Plan

Plan Type: $1
Plan Command: ralph plan --test

## Phase 1

### Task 1 — First
**Status:** planned

### Task 2 — Second
**Status:** planned
**Depends on:** Task 1

### Task 3 — Third
**Status:** planned
**Depends on:** Task 2
EOF
    if [[ "${2:-}" == "decorated" ]]; then
        sed -i -E 's/^(Plan Type|Plan Command): (.*)/- **\1:** \2/; s/^\*\*(Status|Depends on):\*\*/- **\1:**/' "$plan"
    fi
}

test_loop_process_build_progresses() {
    echo "--- loop: process build selects the next task each iteration (#35) ---"
    loop_setup progress "mark-selected complete" "mark-selected complete" "mark-selected complete"
    loop_plan process
    loop_run build 8
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_eq "one invocation per task" "3" "$(loop_invocations)"
    assert_contains "iteration 1 gets Task 1" "### Task 1 — First" "$(loop_prompt 1)"
    assert_contains "iteration 2 gets Task 2" "### Task 2 — Second" "$(loop_prompt 2)"
    assert_contains "iteration 3 gets Task 3" "### Task 3 — Third" "$(loop_prompt 3)"
    assert_contains "uses process prompt" "## Selected Task" "$(loop_prompt 1)"
    assert_contains "stops when all complete" "Exit: all tasks complete (code 0)" "$LOOP_OUTPUT"
    assert_contains "suggests align-specs" "ralph align-specs" "$LOOP_OUTPUT"
}

test_loop_process_build_no_progress() {
    echo "--- loop: process build stops when the same task is re-selected ---"
    loop_setup noprogress noop noop
    loop_plan process
    loop_run build 8
    assert_eq "exits 6" "6" "$LOOP_RC"
    assert_eq "stops after one invocation" "1" "$(loop_invocations)"
    assert_contains "reports no progress" "Exit: no progress (code 6)" "$LOOP_OUTPUT"
}

test_loop_process_build_only_blocked() {
    echo "--- loop: process build stops when only blocked tasks remain ---"
    loop_setup blocked "mark-selected blocked"
    loop_plan process
    loop_run build 8
    assert_eq "exits 3" "3" "$LOOP_RC"
    assert_eq "stops after one invocation" "1" "$(loop_invocations)"
    assert_contains "reports no eligible task" "Exit: no eligible task (code 3)" "$LOOP_OUTPUT"
    assert_contains "shows plan command" "Run 'ralph plan --test'" "$LOOP_OUTPUT"
}

test_loop_gap_build_complete_signal() {
    echo "--- loop: gap-driven build exits on COMPLETE signal ---"
    loop_setup complete noop "signal COMPLETE"
    loop_plan gap-driven
    loop_run build 8
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_eq "two invocations" "2" "$(loop_invocations)"
    assert_contains "uses gap-driven prompt" "## Task Overview" "$(loop_prompt 1)"
    assert_not_contains "no selected task section" "## Selected Task" "$(loop_prompt 1)"
    assert_contains "reports completion signal" "Exit: completion signal (code 0)" "$LOOP_OUTPUT"
}

test_loop_build_replan_signal() {
    echo "--- loop: build exits 3 on REPLAN signal ---"
    loop_setup replan "signal REPLAN"
    loop_plan gap-driven
    loop_run build 8
    assert_eq "exits 3" "3" "$LOOP_RC"
    assert_contains "shows replan message" "Agent requested re-planning. Run 'ralph plan --test'" "$LOOP_OUTPUT"
}

test_loop_retries_empty_response() {
    echo "--- loop: empty response is retried within the same iteration ---"
    loop_setup retry empty "signal COMPLETE"
    loop_plan gap-driven
    loop_run build 8
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_contains "warns about empty response" "Agent produced no response" "$LOOP_OUTPUT"
    assert_contains "retries" "retry 1/1" "$LOOP_OUTPUT"
    assert_contains "counts one iteration" "Iterations: 1 " "$LOOP_OUTPUT"
}

test_loop_retries_exhausted() {
    echo "--- loop: exits 4 when agent failures exceed retries ---"
    loop_setup failure fail fail
    loop_plan gap-driven
    loop_run build 8
    assert_eq "exits 4" "4" "$LOOP_RC"
    assert_eq "initial attempt plus one retry" "2" "$(loop_invocations)"
    assert_contains "reports failure" "Exit: agent failure exceeded retries (code 4)" "$LOOP_OUTPUT"
}

test_loop_max_iterations() {
    echo "--- loop: stops at max iterations ---"
    loop_setup maxiter noop noop noop
    loop_plan gap-driven
    loop_run build 2
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_eq "two invocations" "2" "$(loop_invocations)"
    assert_contains "reports max iterations" "Exit: max iterations reached (code 0)" "$LOOP_OUTPUT"
}

test_loop_plan_mode_runs() {
    echo "--- loop: plan mode renders prompt and runs ---"
    loop_setup plan "signal COMPLETE"
    loop_plan gap-driven
    loop_run plan 3
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_eq "one invocation" "1" "$(loop_invocations)"
    assert_not_contains "no unsubstituted SPECS_DIR" '${SPECS_DIR}' "$(loop_prompt 1)"
}

test_loop_plan_mode_rejects_invalid_plan() {
    echo "--- loop: plan mode fails when the finished plan is not parseable ---"
    loop_setup planinvalid "signal COMPLETE"
    loop_plan gap-driven
    sed -i '0,/planned/s//done/' "$LOOP_DIR/project/.ralph/implementation_plan.md"
    loop_run plan 3
    assert_eq "exits 1" "1" "$LOOP_RC"
    assert_contains "names the bad line" "invalid status 'done'" "$LOOP_OUTPUT"
    assert_contains "reports invalid plan" "Exit: completion signal, but plan is invalid (code 1)" "$LOOP_OUTPUT"
}

test_loop_process_build_decorated_header() {
    echo "--- loop: process build accepts Markdown-decorated header and status lines (#33) ---"
    loop_setup decorated "mark-selected complete" "mark-selected complete" "mark-selected complete"
    loop_plan process decorated
    loop_run build 8
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_contains "uses process prompt" "## Selected Task" "$(loop_prompt 1)"
    assert_contains "iteration 3 gets Task 3" "### Task 3 — Third" "$(loop_prompt 3)"
    assert_contains "stops when all complete" "Exit: all tasks complete (code 0)" "$LOOP_OUTPUT"
}

test_loop_build_rejects_invalid_plan() {
    echo "--- loop: build refuses to start on an invalid plan ---"
    loop_setup buildinvalid noop
    loop_plan process
    sed -i '/^Plan Type:/d' "$LOOP_DIR/project/.ralph/implementation_plan.md"
    loop_run build 8
    assert_eq "exits 1" "1" "$LOOP_RC"
    assert_eq "agent never invoked" "0" "$(loop_invocations)"
    assert_contains "names the problem" "missing 'Plan Type:' header line" "$LOOP_OUTPUT"
}

test_loop_build_stops_when_agent_corrupts_plan() {
    echo "--- loop: build stops when an iteration leaves the plan invalid ---"
    loop_setup corrupt "mark-selected done" noop
    loop_plan process
    loop_run build 8
    assert_eq "exits 1" "1" "$LOOP_RC"
    assert_eq "stops after one invocation" "1" "$(loop_invocations)"
    assert_contains "names the bad line" "invalid status 'done'" "$LOOP_OUTPUT"
    assert_contains "reports invalid plan" "Exit: invalid plan (code 1)" "$LOOP_OUTPUT"
}

test_loop_align_specs_decorated_header() {
    echo "--- loop: align-specs accepts a Markdown-decorated process plan (#33) ---"
    loop_setup align "signal COMPLETE"
    echo 'PROCESS_DIR="specs"' >> "$LOOP_DIR/project/.ralph/config"
    loop_plan process decorated
    sed -i '0,/planned/s//complete/' "$LOOP_DIR/project/.ralph/implementation_plan.md"
    loop_run align-specs 3
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_eq "agent invoked" "1" "$(loop_invocations)"
}

test_loop_prompt_mode_substitutes_variables() {
    echo "--- loop: prompt mode substitutes variables and exits on COMPLETE ---"
    loop_setup adhoc "signal COMPLETE"
    printf 'Specs live in ${SPECS_DIR}.\nWhen done output <promise>COMPLETE</promise>\n' \
        > "$LOOP_DIR/project/adhoc.md"
    loop_run prompt adhoc.md 3
    assert_eq "exits 0" "0" "$LOOP_RC"
    assert_contains "substitutes SPECS_DIR" "Specs live in specs." "$(loop_prompt 1)"
}
