# Implementation Plan

Plan Type: gap-driven
Plan Command: ralph plan

---

## Summary

This plan covers gaps between the specs and the current implementation. The codebase already implements:
- Core loop (plan, build, prompt modes)
- Agent script system (amp, claude, cline/codex stubs)
- Installer with manifest/version tracking
- Updater with checksum-based customization preservation
- Sandbox CLI (all lifecycle commands: setup, up, down, reset, shell, status)
- Sandbox setup prompt template with stack playbooks
- Stack detection (detect_stack function)
- Signal detection (COMPLETE, REPLAN)
- Template variable substitution
- Session logging
- Tests

Remaining gaps are concentrated in: process planning mode, help system, plan-type-aware build mode, and prompt template sync.

---

### Task 1: Add process planning support to `ralph` script and `config`

**Status:** complete
**Spec:** `specs/process-planning.md`, `specs/loop-behavior.md`

Add `--process` flag parsing to the `ralph` script and `PROCESS_DIR` config variable.

Changes made:
- **`config`**: Added `PROCESS_DIR=""` with comment
- **`ralph` script**:
  - Added `PROCESS_FLAG` variable and `--process` parsing in argument loop
  - Validates `--process` is only used with `plan` mode (error otherwise)
  - Validates `PROCESS_DIR` when `--process` is used: must be set, directory must exist, must contain `*.md` files
  - Exports `PROCESS_DIR` for envsubst
  - Selects `prompts/plan-process.md` as the prompt template when `--process` is used
  - Updated `usage()` to include `plan --process`
- **`prompts/plan-process.md`**: Created from the canonical template in `specs/process-planning.md`
- **`tests/test_ralph.sh`**: Added 5 tests for `--process` flag validation; fixed `assert_contains` to handle `--` prefixed needles
- **`tests/test_ralph.sh`**: Fixed `assert_contains` grep to use `--` separator (prevents flags like `--process` being interpreted as grep options)

---

### Task 2: Sync `prompts/plan.md` with canonical template in spec

**Status:** complete
**Spec:** `specs/plan-mode.md`

The current `prompts/plan.md` was missing the plan metadata header (`Plan Type: gap-driven`, `Plan Command: ralph plan`) that the canonical template in `specs/plan-mode.md` requires.

Changes made:
- **`prompts/plan.md`**: Added `Plan Type:` and `Plan Command:` instructions to the Task Format section, matching the canonical template in the spec.

---

### Task 3: Sync `prompts/build.md` with canonical template in spec

**Status:** complete
**Spec:** `specs/build-mode.md`

Replaced `prompts/build.md` with the canonical template from `specs/build-mode.md`. Key additions:
- Plan-type-aware task selection in Operating Contract (`gap-driven` vs `process`)
- Updated Workflow step 1 to read `Plan Type:` header
- Updated Workflow step 2 with plan-type-specific selection rules
- Updated Workflow steps 9-11 with blocked-only → REPLAN logic
- Updated Exit Signals to clarify blocked tasks should not trigger COMPLETE

---

### Task 4: Add REPLAN `Plan Command:` reading to ralph script

**Status:** complete
**Spec:** `specs/loop-behavior.md`

When the REPLAN signal is detected, the ralph script now reads the `Plan Command:` line from the implementation plan instead of hardcoding `ralph plan`.

Changes made:
- **`ralph` script, `run_loop()` function**: REPLAN case (rc=3) now greps `Plan Command:` from `${RALPH_HOME}/implementation_plan.md`, strips the prefix, and uses it in the log message. Falls back to `ralph plan` if not found or file is missing. Message also updated to match spec wording: "...to regenerate the implementation plan."
- Testing note: This logic is inside `run_loop` which requires full agent invocation to exercise. Unit-level testing deferred to Task 8.

---

### Task 5: Add help system to `ralph` script

**Status:** complete
**Spec:** `specs/help-system.md`

Add `ralph help [topic]` CLI mode with topic functions for plan, specs, build, and sandbox.

Changes made:
- **`ralph` script**:
  - Added `help` to recognized modes in argument parsing, with `HELP_TOPIC` capture that handles topic names that overlap mode names (e.g., `ralph help plan`)
  - Added `ralph_help()` dispatcher and topic functions: `help_index()`, `help_plan()`, `help_specs()`, `help_build()`, `help_sandbox()`
  - Moved existing `sandbox_help()` content to `help_sandbox()`
  - Removed `sandbox help` subcommand — sandbox help is now `ralph help sandbox`
  - Updated `usage()` to include `help [topic]` and remove `sandbox help`
  - Help mode skips agent script loading, prerequisite validation, and session log init
  - Unknown topics print error to stderr then show the topic index
  - Updated `sandbox_setup` message to reference `ralph help sandbox` instead of `ralph sandbox help`
  - Each topic contains condensed operational summaries as described in the spec

---

### Task 6: Add `prompts/plan-process.md` and `PROCESS_DIR` to installer and updater

**Status:** complete
**Spec:** `specs/process-planning.md`, `specs/installer.md`, `specs/updater.md`

Add the new process planning prompt to the managed files so it's installed and updated.

Changes made:
- **`install.sh`**: Added `prompts/plan-process.md` to `MANAGED_FILES` array and `SOURCE_PATHS`
- **`update.sh`**: Added `prompts/plan-process.md` to `MANAGED_FILES` array and `SOURCE_PATHS`
- **`specs/project-structure.md`**: Added `PROCESS_DIR` to config table and template variables table, added `specs/process/` to both layout diagrams, added `prompts/plan-process.md` to prompts listing in both layouts

---

### Task 7: Add `help` mode to `specs/loop-behavior.md`

**Status:** planned
**Spec:** `specs/help-system.md`, `specs/loop-behavior.md`

The help-system spec says to add `help [topic]` to the CLI interface modes section of `specs/loop-behavior.md`.

Changes needed:
- **`specs/loop-behavior.md`**: Add `help [topic]` to the Modes section

---

### Task 8: Update tests for new features

**Status:** planned
**Spec:** `specs/process-planning.md`, `specs/help-system.md`, `specs/loop-behavior.md`

Add tests for the new functionality.

Changes needed:
- **`tests/test_ralph.sh`**:
  - Test `ralph help` shows topic index
  - Test `ralph help plan` shows plan help content
  - Test `ralph help bogus` shows unknown topic error
  - Test `usage()` output includes `help`
  - Test `MANAGED_FILES` still in sync between install.sh and update.sh (existing test covers this automatically)

Note: `--process` flag tests were already added in Task 1. `--process` usage test already exists.

---

### Task 9: Update `README.md` to document process planning and help

**Status:** planned
**Spec:** `specs/overview.md`, `specs/process-planning.md`, `specs/help-system.md`

Update the root README to reflect the new features.

Changes needed:
- **`README.md`**:
  - Add `ralph plan --process` to the Usage section
  - Add `ralph help [topic]` to the Usage section
  - Add `prompts/plan-process.md` to the Project Structure tree
  - Add process-planning.md and help-system.md to the Documentation section (they're already listed in the specs index but not in README)
