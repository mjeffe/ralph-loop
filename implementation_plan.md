# Implementation Plan

Plan Type: gap-driven
Plan Command: ralph plan

## Spec Alignment Summary

All specs have been reviewed against the current codebase. The project is mature — the
vast majority of specs are fully implemented. The single remaining feature is the
**align-specs mode** defined in `specs/align-specs.md`. Everything else (loop behavior,
plan mode, build mode, process planning, incremental planning, sandbox CLI, sandbox
setup prompt, help system, agent scripts, installer, updater, spec lifecycle, project
structure) is implemented and passing all 85 tests.

---

### Task 1: Add `align-specs` mode to the `ralph` script
**Status:** complete
**Spec:** specs/align-specs.md

Add the `align-specs` CLI mode to the `ralph` script:

1. Add `align-specs` to the argument parser alongside `plan`, `build`, `prompt`, etc.
   It accepts `[max_iterations]` like other loop modes.
2. Add prerequisite checks (runs before the loop, after config loading):
   - `PROCESS_DIR` must be configured and non-empty → error: "align-specs requires
     process specs. Set PROCESS_DIR in config."
   - `${RALPH_HOME}/implementation_plan.md` must exist with `Plan Type: process` →
     error: "align-specs requires a process-type implementation plan. Run
     'ralph plan --process' and 'ralph build' first."
   - At least one `complete` task in the plan → error: "align-specs requires completed
     build work. Run 'ralph build' first."
3. Use `prompts/align-specs.md` as the prompt template (created in Task 2).
4. Export `PROCESS_DIR` for prompt substitution.
5. Run `run_loop` with the align-specs prompt template.
6. Update `usage()` to include `align-specs [max_iterations]`.
7. Load the agent script for `align-specs` mode (currently excluded for `update`,
   `sandbox`, `help` — `align-specs` needs agent access like `plan`/`build`).
8. Add tests to `tests/test_ralph.sh`:
   - `ralph align-specs` without `PROCESS_DIR` exits with error
   - `ralph align-specs` without process-type plan exits with error
   - `ralph align-specs` without completed tasks exits with error
   - Usage output includes `align-specs`

**Notes:** Added `align-specs` to argument parser, usage output, and entry point case
statement. Three prerequisite checks validate PROCESS_DIR, process-type plan, and at
least one completed task. Agent script loads normally (not excluded). Exports PROCESS_DIR
for prompt template substitution. 7 new test assertions (4 test functions) added, all 92
tests pass.

---

### Task 2: Create `prompts/align-specs.md` prompt template
**Status:** complete
**Spec:** specs/align-specs.md

Create `prompts/align-specs.md` using the canonical prompt template from the spec
(`specs/align-specs.md` → "Prompt Template" section). The template uses `envsubst`
variables: `${PROCESS_DIR}`, `${RALPH_HOME}`, `${SPECS_DIR}`.

This is a new file — no existing file needs modification.

**Notes:** Created `prompts/align-specs.md` with the canonical template from the spec.
Template covers first-iteration and subsequent-iteration workflows, exit signal,
blocked specs handling, scope constraints, and spec quality guidelines. All 92 tests pass.

---

### Task 3: Add build-completion nudge for process plans
**Status:** planned
**Spec:** specs/align-specs.md

In `run_loop()`, after writing the session summary and before the `exit` call, add the
build-completion nudge. When `$MODE == "build"` and `$exit_reason == "completion signal"`,
read `Plan Type:` from the implementation plan. If it's `process`, print the nudge box
to both terminal and log:

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║  Process-plan build complete. Target-state specs may need updating.            ║
║  Run: ralph align-specs                                                       ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

The spec provides the exact implementation snippet. All needed state (`$exit_reason`,
`$MODE`) is already local to `run_loop()`.

---

### Task 4: Add `align-specs` to installer/updater managed files and help system
**Status:** planned
**Spec:** specs/align-specs.md, specs/help-system.md

1. Add `prompts/align-specs.md` to `MANAGED_FILES` and `SOURCE_PATHS` in both
   `install.sh` and `update.sh`. Keep arrays in sync (validated by existing test
   `test_managed_files_in_sync`).
2. Add `help_align_specs()` function to the `ralph` script with content covering:
   - Purpose (updating target-state specs after process-spec migrations)
   - Prerequisites (PROCESS_DIR, process-type plan, completed tasks)
   - The alignment ledger
   - Workflow
   - Blocked specs
3. Add `align-specs` to `help_index()` topic list.
4. Add `align-specs` case to `ralph_help()` dispatcher.
5. Add brief mention of `ralph align-specs` to `help_specs()` under spec maintenance.
6. Add tests for `ralph help align-specs`.
