#!/bin/bash
# Plan filter tests — exercises lib/plan-filter.sh modes against synthetic plans.

FILTER="$RALPH_DIR/lib/plan-filter.sh"

# ---------------------------------------------------------------------------
# Helper: create a process plan with mixed statuses
# ---------------------------------------------------------------------------
create_process_plan() {
    cat > "$TMP_DIR/process_plan.md" << 'EOF'
# Implementation Plan

Plan Type: process
Plan Command: ralph plan --process
Primary Process Specs: migration.md

## Summary

Migrate the database and build API endpoints.

## Cross-cutting constraints

- All migrations must be reversible

## Phase 1 — Database

### Task 1 — Create users table
**Status:** complete

Created users table.

### Task 2 — Create posts table
**Status:** complete
**Depends on:** Task 1

Created posts table.

## Phase 2 — API

### Task 3 — User endpoint
**Status:** complete
**Depends on:** Task 1

Implemented user endpoint.

### Task 4 — Post endpoint
**Status:** planned
**Depends on:** Task 3

Implement post endpoint.

### Task 5 — Search endpoint
**Status:** planned
**Depends on:** Task 4

Implement search.

## Phase 3 — Frontend

### Task 6 — Setup router
**Status:** planned

Setup Vue router.

### Task 7 — User page
**Status:** planned
**Depends on:** Task 6

Build user page.
EOF
}

# ---------------------------------------------------------------------------
# Helper: create a gap-driven plan
# ---------------------------------------------------------------------------
create_gap_plan() {
    cat > "$TMP_DIR/gap_plan.md" << 'EOF'
# Implementation Plan

Plan Type: gap-driven
Plan Command: ralph plan

## Summary

Close spec gaps.

## Cross-cutting constraints

- Follow existing patterns

### Task 1: Fix authentication
**Status:** complete
**Spec:** specs/auth.md

Fixed auth.

### Task 2: Add logging
**Status:** planned
**Spec:** specs/logging.md

Add structured logging.

### Task 3: Update docs
**Status:** planned
**Spec:** specs/docs.md

Update documentation.
EOF
}

# ---------------------------------------------------------------------------
# Helper: create a plan with bare status format
# ---------------------------------------------------------------------------
create_bare_format_plan() {
    cat > "$TMP_DIR/bare_plan.md" << 'EOF'
# Plan

Plan Type: process

## Phase 1

### Task 1 — Foo
Status: complete

Done.

### Task 2: Bar
Status: planned
Depends on: Task 1

Do bar.
EOF
}

# ---------------------------------------------------------------------------
# Helper: create a plan with collapsed phases
# ---------------------------------------------------------------------------
create_two_phase_plan() {
    cat > "$TMP_DIR/two_phase_plan.md" << 'EOF'
# Plan

Plan Type: process

## Phase 1 — Prep

### Task 1 — Setup
**Status:** complete

Done.

## Phase 2 — Build

### Task 9 — Build feature
**Status:** planned

Build it.
EOF
}

# ---------------------------------------------------------------------------
# Tests: header mode
# ---------------------------------------------------------------------------
test_filter_header_extracts_above_first_task() {
    echo "--- filter header: extracts content above first task ---"
    create_process_plan
    local output
    output=$(bash "$FILTER" header "$TMP_DIR/process_plan.md")
    assert_contains "header includes Plan Type" "Plan Type: process" "$output"
    assert_contains "header includes summary" "Migrate the database" "$output"
    assert_contains "header includes cross-cutting" "All migrations must be reversible" "$output"
    assert_contains "header includes phase heading" "## Phase 1" "$output"
    assert_not_contains "header excludes task heading" "### Task 1" "$output"
}

test_filter_header_gap_driven() {
    echo "--- filter header: gap-driven plan ---"
    create_gap_plan
    local output
    output=$(bash "$FILTER" header "$TMP_DIR/gap_plan.md")
    assert_contains "header includes Plan Type" "Plan Type: gap-driven" "$output"
    assert_contains "header includes cross-cutting" "Follow existing patterns" "$output"
    assert_not_contains "header excludes tasks" "### Task 1" "$output"
}

# ---------------------------------------------------------------------------
# Tests: overview mode
# ---------------------------------------------------------------------------
test_filter_overview_summarizes_complete_sections() {
    echo "--- filter overview: summarizes complete sections ---"
    create_process_plan
    local output
    output=$(bash "$FILTER" overview "$TMP_DIR/process_plan.md")
    assert_contains "complete section is summarized" "(2/2 complete)" "$output"
    assert_not_contains "complete task details hidden" "Create users table" "$output"
}

test_filter_overview_expands_incomplete_sections() {
    echo "--- filter overview: expands incomplete sections ---"
    create_process_plan
    local output
    output=$(bash "$FILTER" overview "$TMP_DIR/process_plan.md")
    assert_contains "incomplete section shows task" "### Task 4" "$output"
    assert_contains "incomplete section shows status" "planned" "$output"
    assert_contains "incomplete section shows depends" "Depends on:" "$output"
}

test_filter_overview_includes_line_numbers() {
    echo "--- filter overview: includes line numbers ---"
    create_process_plan
    local output
    output=$(bash "$FILTER" overview "$TMP_DIR/process_plan.md")
    # Line numbers appear as "  NN:### Task"
    local has_line_nums=0
    if echo "$output" | grep -qP '^\s+\d+:###'; then
        has_line_nums=1
    fi
    assert_eq "overview includes line numbers" "1" "$has_line_nums"
}

test_filter_overview_gap_driven() {
    echo "--- filter overview: gap-driven plan ---"
    create_gap_plan
    local output
    output=$(bash "$FILTER" overview "$TMP_DIR/gap_plan.md")
    assert_contains "shows planned task" "### Task 2" "$output"
    assert_contains "shows complete task in incomplete section" "### Task 1" "$output"
}

test_filter_overview_bare_format() {
    echo "--- filter overview: bare status format ---"
    create_bare_format_plan
    local output
    output=$(bash "$FILTER" overview "$TMP_DIR/bare_plan.md")
    assert_contains "bare format shows task" "### Task 2" "$output"
    assert_contains "bare format shows status" "planned" "$output"
}

test_filter_overview_complete_phase_summarized() {
    echo "--- filter overview: complete phase shown as summary ---"
    create_two_phase_plan
    local output
    output=$(bash "$FILTER" overview "$TMP_DIR/two_phase_plan.md")
    assert_contains "complete phase is summarized" "(1/1 complete)" "$output"
    assert_contains "next section shows task" "### Task 9" "$output"
}

test_filter_overview_empty_plan_fails() {
    echo "--- filter overview: empty plan exits non-zero ---"
    echo "# No tasks here" > "$TMP_DIR/empty_plan.md"
    local rc=0
    bash "$FILTER" overview "$TMP_DIR/empty_plan.md" >/dev/null 2>&1 || rc=$?
    assert_eq "empty plan exits 1" "1" "$rc"
}

# ---------------------------------------------------------------------------
# Tests: select mode
# ---------------------------------------------------------------------------
test_filter_select_picks_correct_task() {
    echo "--- filter select: picks first planned task with resolved deps ---"
    create_process_plan
    local output selected
    output=$(bash "$FILTER" select "$TMP_DIR/process_plan.md")
    # Extract only the selected task block
    selected=$(echo "$output" | sed -n '/^---SELECTED_TASK---$/,/^---END_SELECTED_TASK---$/{ /^---.*---$/d; p; }')
    assert_contains "selects Task 4" "### Task 4" "$selected"
    assert_not_contains "selected is not Task 5" "### Task 5" "$selected"
}

test_filter_select_includes_adjacent_context() {
    echo "--- filter select: includes adjacent context ---"
    create_process_plan
    local output
    output=$(bash "$FILTER" select "$TMP_DIR/process_plan.md")
    assert_contains "adjacent includes completed task" "### Task 3" "$output"
    assert_contains "adjacent includes next task" "### Task 5" "$output"
}

test_filter_select_bare_format() {
    echo "--- filter select: bare status format ---"
    create_bare_format_plan
    local output
    output=$(bash "$FILTER" select "$TMP_DIR/bare_plan.md")
    assert_contains "selects correct task" "### Task 2" "$output"
}

test_filter_select_skips_complete_phase() {
    echo "--- filter select: skips complete phases ---"
    create_two_phase_plan
    local output
    output=$(bash "$FILTER" select "$TMP_DIR/two_phase_plan.md")
    assert_contains "selects from incomplete phase" "### Task 9" "$output"
}

test_filter_select_no_eligible_task() {
    echo "--- filter select: no eligible task ---"
    cat > "$TMP_DIR/blocked_plan.md" << 'EOF'
# Plan

Plan Type: process

## Phase 1

### Task 1 — Blocked task
**Status:** blocked

Blocked by external dependency.
EOF
    local output
    output=$(bash "$FILTER" select "$TMP_DIR/blocked_plan.md")
    assert_contains "reports no eligible task" "NO_ELIGIBLE_TASK" "$output"
}

test_filter_select_empty_plan_fails() {
    echo "--- filter select: empty plan exits non-zero ---"
    echo "# No tasks" > "$TMP_DIR/empty_plan.md"
    local rc=0
    bash "$FILTER" select "$TMP_DIR/empty_plan.md" >/dev/null 2>&1 || rc=$?
    assert_eq "empty plan exits 1" "1" "$rc"
}

# ---------------------------------------------------------------------------
# Tests: error handling
# ---------------------------------------------------------------------------
test_filter_bad_mode_fails() {
    echo "--- filter: bad mode exits non-zero ---"
    create_process_plan
    local rc=0
    bash "$FILTER" badmode "$TMP_DIR/process_plan.md" >/dev/null 2>&1 || rc=$?
    assert_eq "bad mode exits 1" "1" "$rc"
}

test_filter_missing_file_fails() {
    echo "--- filter: missing file exits non-zero ---"
    local rc=0
    bash "$FILTER" header "$TMP_DIR/nonexistent.md" >/dev/null 2>&1 || rc=$?
    assert_eq "missing file exits 1" "1" "$rc"
}

test_filter_no_args_fails() {
    echo "--- filter: no args exits non-zero ---"
    local rc=0
    bash "$FILTER" >/dev/null 2>&1 || rc=$?
    assert_eq "no args exits 1" "1" "$rc"
}

# ---------------------------------------------------------------------------
# Tests: progressive disclosure
# ---------------------------------------------------------------------------
test_filter_overview_progressive_disclosure() {
    echo "--- filter overview: progressive disclosure for >30 incomplete tasks ---"
    # Create a plan with 35 incomplete tasks across 5 sections
    local plan="$TMP_DIR/large_plan.md"
    echo "# Plan" > "$plan"
    echo "" >> "$plan"
    echo "Plan Type: gap-driven" >> "$plan"
    echo "" >> "$plan"
    local task_num=1
    for section in $(seq 1 5); do
        echo "## Section ${section}" >> "$plan"
        echo "" >> "$plan"
        for task in $(seq 1 7); do
            echo "### Task ${task_num}: Item ${task_num}" >> "$plan"
            echo "**Status:** planned" >> "$plan"
            echo "" >> "$plan"
            task_num=$(( task_num + 1 ))
        done
    done
    local output
    output=$(bash "$FILTER" overview "$plan")
    assert_contains "progressive shows summary of remaining" "+2 more sections" "$output"
    assert_contains "progressive shows remaining count" "planned tasks" "$output"
}
