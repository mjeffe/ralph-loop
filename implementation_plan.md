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

**Status:** planned
**Spec:** `specs/process-planning.md`, `specs/loop-behavior.md`

Add `--process` flag parsing to the `ralph` script and `PROCESS_DIR` config variable.

Changes needed:
- **`config`**: Add `PROCESS_DIR=""` with comment
- **`ralph` script**:
  - Parse `--process` flag (only valid with `plan` mode; error if used with other modes)
  - Validate `PROCESS_DIR` when `--process` is used: must be set, directory must exist, must contain `*.md` files
  - Export `PROCESS_DIR` for envsubst
  - Select `prompts/plan-process.md` as the prompt template when `--process` is used
  - Update `usage()` to include `plan --process`
- **`prompts/plan-process.md`**: Create from the canonical template in `specs/process-planning.md` (lines 250-403)

**Notes:** The `--process` flag only changes which prompt template is used and validates `PROCESS_DIR`. The loop execution itself is unchanged.

---

### Task 2: Sync `prompts/plan.md` with canonical template in spec

**Status:** planned
**Spec:** `specs/plan-mode.md`

The current `prompts/plan.md` is missing the plan metadata header (`Plan Type: gap-driven`, `Plan Command: ralph plan`) that the canonical template in `specs/plan-mode.md` requires.

Changes needed:
- **`prompts/plan.md`**: Add the `Plan Type:` and `Plan Command:` instructions to the Task Format section, matching the canonical template in `specs/plan-mode.md` lines 128-131:
  ```
  At the top of `${RALPH_HOME}/implementation_plan.md`, include:
  - `Plan Type: gap-driven`
  - `Plan Command: ralph plan`
  ```

---

### Task 3: Sync `prompts/build.md` with canonical template in spec

**Status:** planned
**Spec:** `specs/build-mode.md`

The current `prompts/build.md` is missing plan-type-aware task selection. The canonical template in `specs/build-mode.md` includes:
- Reading `Plan Type:` header from the implementation plan
- Different selection rules for `gap-driven` vs `process` plan types
- REPLAN signal for when only blocked tasks remain
- Guidance that blocked-only → REPLAN (not COMPLETE)

Changes needed:
- **`prompts/build.md`**: Replace with the canonical template from `specs/build-mode.md` (lines 207-303)

---

### Task 4: Add REPLAN `Plan Command:` reading to ralph script

**Status:** planned
**Spec:** `specs/loop-behavior.md`

When the REPLAN signal is detected, the ralph script currently hardcodes "Run 'ralph plan' to regenerate." The spec says it should read the `Plan Command:` line from the implementation plan and use that in the message.

Changes needed:
- **`ralph` script, `run_loop()` function**: When REPLAN is detected (case 3), read `Plan Command:` from `${RALPH_HOME}/implementation_plan.md` and use it in the log message. Fall back to `ralph plan` if not found.

---

### Task 5: Add help system to `ralph` script

**Status:** planned
**Spec:** `specs/help-system.md`

Add `ralph help [topic]` CLI mode with topic functions for plan, specs, build, and sandbox.

Changes needed:
- **`ralph` script**:
  - Add `help` to the recognized modes in argument parsing
  - Add `ralph_help()` dispatcher function
  - Add topic functions: `help_index()`, `help_plan()`, `help_specs()`, `help_build()`, `help_sandbox()`
  - Move existing `sandbox_help()` content to `help_sandbox()`
  - Replace `sandbox help` subcommand to call `help_sandbox()` (or redirect to `ralph help sandbox`)
  - Update `usage()` to include `help [topic]`
- Content for each topic should be condensed operational summaries as described in the spec (not full spec copies)

---

### Task 6: Add `prompts/plan-process.md` and `PROCESS_DIR` to installer and updater

**Status:** planned
**Spec:** `specs/process-planning.md`, `specs/installer.md`, `specs/updater.md`

Add the new process planning prompt to the managed files so it's installed and updated.

Changes needed:
- **`install.sh`**: Add `prompts/plan-process.md` to `MANAGED_FILES` array and `SOURCE_PATHS`
- **`update.sh`**: Add `prompts/plan-process.md` to `MANAGED_FILES` array and `SOURCE_PATHS`
- **`specs/project-structure.md`**: Add `PROCESS_DIR` to config table, add `specs/process/` to layout examples, add `prompts/plan-process.md` to prompts listing

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
  - Test `--process` flag is rejected with non-plan modes
  - Test `--process` requires `PROCESS_DIR` to be configured
  - Test `ralph help` shows topic index
  - Test `ralph help plan` shows plan help content
  - Test `ralph help bogus` shows unknown topic error
  - Test `usage()` output includes `help` and `plan --process`
  - Test `MANAGED_FILES` still in sync between install.sh and update.sh (existing test covers this automatically)

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
