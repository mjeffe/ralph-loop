#!/bin/bash
# Core tests — config, agent scripts, templates, session log, stack detection,
# prompt template content, managed files sync.

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

test_build_prompt_has_plan_header_injection() {
    echo "--- build.md contains plan header injection ---"
    local template
    template=$(cat "$RALPH_DIR/prompts/build.md")
    assert_contains "build.md has PLAN_HEADER variable" '${PLAN_HEADER}' "$template"
    assert_contains "build.md has TASK_OVERVIEW variable" '${TASK_OVERVIEW}' "$template"
    assert_not_contains "build.md has no phase collapsing" "Phase collapsing" "$template"
}

test_build_process_prompt_has_selected_task() {
    echo "--- build-process.md contains selected task injection ---"
    local template
    template=$(cat "$RALPH_DIR/prompts/build-process.md")
    assert_contains "build-process.md has PLAN_HEADER" '${PLAN_HEADER}' "$template"
    assert_contains "build-process.md has SELECTED_TASK" '${SELECTED_TASK}' "$template"
    assert_contains "build-process.md has ADJACENT_CONTEXT" '${ADJACENT_CONTEXT}' "$template"
    assert_contains "build-process.md has TASK_OVERVIEW" '${TASK_OVERVIEW}' "$template"
}

test_plan_prompts_have_cross_cutting_section() {
    echo "--- plan prompts: cross-cutting constraints section ---"
    local gap_plan process_plan
    gap_plan=$(cat "$RALPH_DIR/prompts/plan.md")
    process_plan=$(cat "$RALPH_DIR/prompts/plan-process.md")
    assert_contains "plan.md mentions cross-cutting" "Cross-cutting constraints" "$gap_plan"
    assert_contains "plan-process.md mentions cross-cutting" "Cross-cutting constraints" "$process_plan"
}

test_plan_process_has_decomposition_ledger() {
    echo "--- plan-process.md contains decomposition ledger ---"
    local template
    template=$(cat "$RALPH_DIR/prompts/plan-process.md")
    assert_contains "plan-process.md has Decomposition Progress heading" "Decomposition Progress" "$template"
    assert_contains "plan-process.md has ledger table headers" "Spec File" "$template"
    assert_contains "plan-process.md mentions skeleton-first workflow" "Skeleton" "$template"
}

test_run_iteration_has_empty_response_check() {
    echo "--- run_iteration has empty response detection ---"
    local ralph_src
    ralph_src=$(cat "$RALPH_DIR/ralph")
    assert_contains "ralph checks for empty response" "agent_extract_response" "$ralph_src"
    assert_contains "ralph logs empty response warning" "Agent produced no response" "$ralph_src"
}

extract_managed_files() {
    sed -n '/^MANAGED_FILES=(/,/^)/p' "$1" | grep -v '^MANAGED_FILES=\|^)' | tr -d ' ' | sort
}

test_managed_files_in_sync() {
    echo "--- Managed files: install.sh and update.sh in sync ---"
    local installer_files updater_files
    installer_files=$(extract_managed_files "$RALPH_DIR/install.sh")
    updater_files=$(extract_managed_files "$RALPH_DIR/update.sh")
    assert_eq "MANAGED_FILES arrays match" "$installer_files" "$updater_files"
}
