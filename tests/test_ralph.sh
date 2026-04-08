#!/bin/bash
# Ralph unit tests — deterministic, no agent invocation, zero cost.
#
# Usage:
#   ./tests/test_ralph.sh              Run all tests
#   ./tests/test_ralph.sh sandbox      Run only sandbox tests
#   ./tests/test_ralph.sh cli core     Run CLI and core tests
#
# Run from the ralph-loop project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Load helpers (assertions, setup/teardown, RALPH_DIR)
# ---------------------------------------------------------------------------
source "$SCRIPT_DIR/test_helpers.sh"

# ---------------------------------------------------------------------------
# Load test files
# ---------------------------------------------------------------------------
source "$SCRIPT_DIR/test_cli.sh"
source "$SCRIPT_DIR/test_signals.sh"
source "$SCRIPT_DIR/test_core.sh"
source "$SCRIPT_DIR/test_install_update.sh"
source "$SCRIPT_DIR/test_sandbox.sh"

# ---------------------------------------------------------------------------
# Test groups
# ---------------------------------------------------------------------------
run_cli_tests() {
    test_usage_output
    test_bad_mode_exits_nonzero
    test_no_mode_exits_nonzero
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
    test_build_requires_plan
    test_prompt_requires_completion_signal
    test_process_flag_rejected_with_non_plan_modes
    test_process_requires_process_dir
    test_process_dir_must_exist
    test_process_dir_must_have_md_files
    test_usage_shows_process
    test_usage_shows_help
    test_usage_shows_align_specs
    test_help_shows_topic_index
    test_help_plan_shows_content
    test_help_prompt_shows_content
    test_help_unknown_topic_exits_zero
    test_help_retro_shows_content
    test_help_align_specs_shows_content
    test_help_index_shows_align_specs
    test_align_specs_requires_process_dir
    test_align_specs_requires_process_plan
    test_align_specs_requires_completed_tasks
}

run_signal_tests() {
    test_signal_detection_complete
    test_signal_detection_replan
    test_signal_detection_no_signal
    test_signal_ignores_user_messages
    test_signal_survives_malformed_json
    test_signal_both_complete_and_replan
    test_signal_in_long_response
    test_display_filter_survives_malformed_json
}

run_core_tests() {
    test_config_loading
    test_agent_script_loading
    test_template_substitution
    test_prepare_prompt
    test_prepare_prompt_preserves_literals
    test_init_session_log
    test_claude_agent_script
    test_stub_agent_scripts
    test_detect_stack
    test_spec_volume_hint_in_prompt_template
    test_spec_volume_hint_small
    test_spec_volume_hint_large
    test_spec_volume_hint_boundary
    test_build_prompt_has_phase_collapsing
    test_plan_process_has_decomposition_ledger
    test_managed_files_in_sync
}

run_install_update_tests() {
    test_installer_creates_originals
    test_updater_three_way_merge_clean
    test_updater_three_way_merge_conflict
    test_updater_originals_not_in_gitignore
    test_updater_has_merge_logic
}

run_sandbox_tests() {
    test_sandbox_usage_output
    test_sandbox_no_subcommand_exits_nonzero
    test_sandbox_bad_subcommand_exits_nonzero
    test_sandbox_guard_inside_sandbox
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
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "Ralph Test Suite"
    echo "========================================"
    echo ""

    setup

    if [[ $# -eq 0 ]]; then
        # Run all groups
        run_cli_tests
        run_signal_tests
        run_core_tests
        run_install_update_tests
        run_sandbox_tests
    else
        # Run only requested groups
        for group in "$@"; do
            case "$group" in
                cli)            run_cli_tests ;;
                signals)        run_signal_tests ;;
                core)           run_core_tests ;;
                install_update) run_install_update_tests ;;
                sandbox)        run_sandbox_tests ;;
                *)
                    echo "Unknown test group: $group" >&2
                    echo "Available groups: cli, signals, core, install_update, sandbox" >&2
                    exit 1
                    ;;
            esac
        done
    fi

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
