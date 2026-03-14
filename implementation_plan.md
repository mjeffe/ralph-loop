# Implementation Plan

### Task 1: Add detect_stack() and playbook injection to sandbox_setup()
**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md

The `sandbox-setup-prompt.md` spec requires `detect_stack()` — a deterministic bash function
that identifies the project's primary stack (php-laravel, php, rails, ruby, python-django,
python, go, rust, node). It also requires `sandbox_setup()` to call `detect_stack()`, resolve
the playbook path, and export `STACK_PLAYBOOK` for `envsubst` before `prepare_prompt`.

**What to do:**
1. Add the `detect_stack()` function to `ralph` (place it in the sandbox lifecycle section,
   before `sandbox_setup()`). Use the exact detection logic from the spec.
2. Update `sandbox_setup()` to call `detect_stack()` and export `STACK_PLAYBOOK` before
   `prepare_prompt`.
3. Add tests for `detect_stack()` to `tests/test_ralph.sh` — create temp projects with
   marker files (composer.json, artisan, package.json, etc.) and verify correct stack output.

### Task 2: Create playbooks directory and initial playbook(s)
**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md
**Dependencies:** Task 1

Create `prompts/playbooks/` directory with at least one initial playbook (e.g.,
`php-laravel.md`) as a reference implementation. The spec provides content guidelines:
under 50 lines, covering runtime installation, package manager, framework bootstrap,
migrations, extensions, workdir, env overrides, and long-running processes.

**What to do:**
1. Create `prompts/playbooks/` directory.
2. Write `prompts/playbooks/php-laravel.md` following the content guidelines in the spec.
3. Add playbook files to `MANAGED_FILES` in `install.sh` and `update.sh`, and to `SOURCE_PATHS`
   in `update.sh`.
4. Add `mkdir -p "$RALPH_DIR/prompts/playbooks"` to `install_ralph_dir()` in `install.sh`.
5. Update `specs/project-structure.md` directory layouts (both ralph-loop and parent project)
   to include `prompts/playbooks/`.

### Task 3: Align iteration logging with spec format
**Status:** planned
**Spec:** specs/loop-behavior.md

The `loop-behavior.md` spec defines a detailed iteration header/footer format and session
summary format. The current `run_iteration()` and `run_loop()` in `ralph` use a simplified
format that doesn't match.

**What to do:**
1. Update `run_iteration()` header to match the spec format:
   ```
   ================================================================================
   ITERATION ${ITERATION}
   ================================================================================
   Mode: ${MODE}
   Start Time: ${TIMESTAMP}
   --------------------------------------------------------------------------------
   ```
2. Update `run_iteration()` footer to match the spec format:
   ```
   --------------------------------------------------------------------------------
   ITERATION ${ITERATION} COMPLETE
   End Time: ${TIMESTAMP}
   Duration: ${DURATION}
   Status: ${STATUS}
   ================================================================================
   ```
3. Update session summary labels to match spec:
   ```
   Total Iterations: ${TOTAL}
   Successful: ${SUCCESS_COUNT}
   Failed: ${FAIL_COUNT}
   Total Duration: ${TOTAL_DURATION}
   Exit Reason: ${EXIT_REASON}
   Exit Code: ${EXIT_CODE}
   ```
4. The cost/balance lines come from `agent_post_iteration()` which logs via `log` —
   ensure they appear between Duration and Status in the footer. Currently
   `agent_post_iteration` is called after the footer; reorder so it's called after
   Duration is logged but before Status.
5. Update any tests that assert on log output format.

**Gotcha:** The spec says "Iteration Cost" and "Balance" lines appear only "if usage
tracking configured" — the current `agent_post_iteration` hook already handles this
conditionally. The main change is reordering when it's called and updating the
header/footer framing.

### Task 4: Consolidate sandbox-setup prompt (v1 → v2)
**Status:** done

Replaced `prompts/sandbox-setup.md` with the v2 restructured prompt and removed the
v2 file. The `${STACK_PLAYBOOK}` and `${RALPH_HOME}` template variables are present.
