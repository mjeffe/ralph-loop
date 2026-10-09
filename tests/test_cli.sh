#!/bin/bash
# CLI tests — argument parsing, usage output, prerequisites, help system.

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

test_build_requires_plan() {
    echo "--- Build mode requires implementation plan ---"
    loop_setup noplan
    loop_run build 1
    assert_eq "build without plan exits 2" "2" "$LOOP_RC"
}

test_prompt_requires_completion_signal() {
    echo "--- Prompt mode requires completion signal ---"
    local prompt="$TMP_DIR/no_signal.md"
    echo "Do something" > "$prompt"
    assert_exit_code "prompt without signal exits 1" 1 \
        "$RALPH_DIR/ralph" prompt "$prompt" 1
}

test_process_flag_rejected_with_non_plan_modes() {
    echo "--- --process flag rejected with non-plan modes ---"
    assert_exit_code "--process with build exits 1" 1 "$RALPH_DIR/ralph" build --process
    assert_exit_code "--process with prompt exits 1" 1 "$RALPH_DIR/ralph" prompt --process
}

test_process_requires_process_dir() {
    echo "--- --process requires PROCESS_DIR ---"
    loop_setup noprocdir
    loop_run plan --process
    assert_eq "--process without PROCESS_DIR exits 1" "1" "$LOOP_RC"
    assert_contains "error mentions PROCESS_DIR" "No PROCESS_DIR configured" "$LOOP_OUTPUT"
}

test_process_dir_must_exist() {
    echo "--- --process validates PROCESS_DIR exists ---"
    loop_setup procdirmissing
    echo 'PROCESS_DIR="/nonexistent/dir"' >> "$LOOP_DIR/project/.ralph/config"
    loop_run plan --process
    assert_eq "--process with missing dir exits 1" "1" "$LOOP_RC"
    assert_contains "error mentions dir not found" "not found" "$LOOP_OUTPUT"
}

test_process_dir_must_have_md_files() {
    echo "--- --process validates *.md files in PROCESS_DIR ---"
    loop_setup procdirempty
    mkdir -p "$LOOP_DIR/project/process"
    echo 'PROCESS_DIR="process"' >> "$LOOP_DIR/project/.ralph/config"
    loop_run plan --process
    assert_eq "--process with empty dir exits 1" "1" "$LOOP_RC"
    assert_contains "error mentions no process specs" "No process specs found" "$LOOP_OUTPUT"
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

test_usage_shows_align_specs() {
    echo "--- Usage output includes align-specs ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows align-specs mode" "align-specs" "$output"
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

test_help_retro_shows_content() {
    echo "--- ralph help retro shows retro content ---"
    local output
    output=$("$RALPH_DIR/ralph" help retro 2>&1)
    assert_contains "retro help shows header" "RETROSPECTIVE" "$output"
    assert_contains "retro help shows when" "WHEN TO DO A RETRO" "$output"
    assert_contains "retro help shows three-stage workflow" "THREE-STAGE WORKFLOW" "$output"
    assert_contains "retro help shows analyze prompt" "adhoc-retro-analyze.md" "$output"
    assert_contains "retro help shows feedback prompt" "adhoc-retro-feedback.md" "$output"
    assert_contains "retro help shows what analysis covers" "WHAT THE ANALYSIS COVERS" "$output"
    assert_contains "retro help shows failure patterns" "COMMON FAILURE PATTERNS" "$output"
    assert_contains "retro help shows where to apply" "WHERE TO APPLY FIXES" "$output"
    assert_contains "retro help shows checklist" "RETRO CHECKLIST" "$output"
    assert_contains "retro help shows interactive discussion prompt" "INTERACTIVE DISCUSSION PROMPT" "$output"
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

test_align_specs_requires_process_dir() {
    echo "--- align-specs requires PROCESS_DIR ---"
    loop_setup alignnoprocdir
    loop_run align-specs
    assert_eq "align-specs without PROCESS_DIR exits 1" "1" "$LOOP_RC"
    assert_contains "error mentions process specs" "align-specs requires process specs" "$LOOP_OUTPUT"
}

test_align_specs_requires_process_plan() {
    echo "--- align-specs requires process-type plan ---"
    loop_setup aligngap
    echo 'PROCESS_DIR="specs"' >> "$LOOP_DIR/project/.ralph/config"
    printf '# Plan\n\nPlan Type: gap-driven\n\n### Task 1: Something\n**Status:** complete\n' \
        > "$LOOP_DIR/project/.ralph/implementation_plan.md"
    loop_run align-specs
    assert_eq "align-specs with gap-driven plan exits 1" "1" "$LOOP_RC"
    assert_contains "error mentions process-type" "process-type implementation plan" "$LOOP_OUTPUT"
}

test_align_specs_requires_completed_tasks() {
    echo "--- align-specs requires completed tasks ---"
    loop_setup alignnocomplete
    echo 'PROCESS_DIR="specs"' >> "$LOOP_DIR/project/.ralph/config"
    printf '# Plan\n\nPlan Type: process\n\n### Task 1: Something\n**Status:** planned\n' \
        > "$LOOP_DIR/project/.ralph/implementation_plan.md"
    loop_run align-specs
    assert_eq "align-specs without completed tasks exits 1" "1" "$LOOP_RC"
    assert_contains "error mentions completed build work" "align-specs requires completed build work" "$LOOP_OUTPUT"
}

test_version_reports_installed_version() {
    echo "--- ralph version reports the installed version ---"
    loop_setup version
    echo "abc1234" > "$LOOP_DIR/project/.ralph/.version"
    loop_run version
    assert_eq "prints .version contents" "ralph abc1234" "$LOOP_OUTPUT"
    rm "$LOOP_DIR/project/.ralph/.version"
    loop_run --version
    assert_eq "falls back to unknown without .version" "ralph (unknown version)" "$LOOP_OUTPUT"
}
