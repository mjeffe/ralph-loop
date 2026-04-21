# Implementation Plan

Plan Type: gap-driven
Plan Command: ralph plan

## Summary

This plan addresses three structural gaps between the specs and the current codebase:

1. **Help system extraction** — The spec (`help-system.md`, `project-structure.md`) requires help content in `lib/help/*.txt` files with a file-based dispatcher. The current implementation uses heredoc functions inline in `ralph`. The functional content is correct; the architecture is wrong.

2. **Sandbox module extraction** — The spec (`sandbox-cli.md`, `project-structure.md`) requires sandbox functions in `lib/sandbox.sh`, sourced eagerly at startup. Currently all sandbox functions (~500 lines) are inline in `ralph`. Again, the behavior is correct; the structure doesn't match spec.

3. **`sandbox_up` missing `wait-for-db` refresh** — The spec (`sandbox-cli.md`) says `sandbox_up` should auto-refresh `wait-for-db` alongside `Dockerfile.base` and `sandbox-preferences.sh`. The current `sandbox_up` copies only the latter two.

These three gaps also cascade into the installer and updater: `lib/sandbox.sh` and `lib/help/*.txt` are missing from `MANAGED_FILES` and `SOURCE_PATHS` in both `install.sh` and `update.sh`.

All other specs are satisfied by the current codebase (evidence in the Spec Alignment section below).

## Spec Alignment

### specs/overview.md — Already Satisfied
System purpose, design principles, workflow, two deployment scenarios all match. The README.md and project structure reflect this spec. Sandbox section mentions multi-container architecture, lifecycle commands, and `sandbox-setup.md` — all implemented.

### specs/project-structure.md — Gaps
- Directory layouts: match except `lib/help/` directory doesn't exist, `lib/sandbox.sh` doesn't exist.
- Config: matches (SPECS_DIR, PROCESS_DIR, DEFAULT_MAX_ITERATIONS, MAX_RETRIES, AGENT). Self-relative path resolution, template variable substitution, portability — all correct.
- Spec says `lib/sandbox.sh` is sourced eagerly at startup — it's inline instead.
- Spec says `lib/help/*.txt` files exist and are `cat`'d — they're heredocs instead.

### specs/loop-behavior.md — Already Satisfied
CLI interface with all modes (plan, plan --process, build, prompt, help, align-specs, sandbox, update). Loop execution (init, iteration flow, pre-iteration checks, template substitution, agent invocation pipeline, completion/replan detection, retry strategy, error handling, logging, session summary, context tracking) all implemented correctly. `--process` flag validation, REPLAN reading `Plan Command:`, empty response detection, exit codes — all match.

### specs/plan-mode.md — Already Satisfied
Planning phases, plan regeneration, iterative planning, task sizing heuristic, completion signal, plan format with metadata header and cross-cutting constraints section. Prompt template at `prompts/plan.md` exists.

### specs/build-mode.md — Already Satisfied
Infrastructure-managed plan context (PLAN_HEADER, TASK_OVERVIEW, SELECTED_TASK, ADJACENT_CONTEXT via lib/plan-filter.sh). Bifurcated prompt selection based on Plan Type. Gap-driven vs process task selection. Build completion nudge for process plans. Both build prompts (build.md, build-process.md) exist.

### specs/spec-lifecycle.md — Already Satisfied
Target-state vs process specs distinction, spec evolution rules, spec format guidance, specs index convention. All present in existing specs and README.

### specs/installer.md — Gaps
- Installer doesn't include `lib/sandbox.sh` or `lib/help/*.txt` in MANAGED_FILES/SOURCE_PATHS.
- All other behavior (pre-checks, directory creation, file copying, no-overwrite policy, templates, version/manifest/originals, success message) matches spec.

### specs/agent-scripts.md — Already Satisfied
Function contract (agent_invoke, agent_extract_response, agent_format_display), required variables (AGENT_CLI), optional hooks (agent_pre_iteration, agent_post_iteration), all four agent scripts exist. Per-line processing, context tracking — all correct.

### specs/updater.md — Gaps
- Updater doesn't include `lib/sandbox.sh` or `lib/help/*.txt` in MANAGED_FILES/SOURCE_PATHS.
- All other behavior (pre-update checks, version tracking, manifest, originals, three-way merge, .upstream files, removed-upstream detection, edge cases, output format) matches spec.

### specs/sandbox-cli.md — Gaps
- All lifecycle commands implemented (setup, up, stop, reset, shell, status).
- sandbox_ensure_name, sandbox_container_name, detect_stack, sandbox_validate_profile, sandbox_validate, sandbox_setup — all correct.
- `sandbox_up` missing `wait-for-db` auto-refresh (spec says copy `wait-for-db` alongside Dockerfile.base and sandbox-preferences.sh).
- Functions live inline in `ralph` rather than in `lib/sandbox.sh` as spec requires.
- sandbox-setup.md creation logic present in sandbox_setup.

### specs/sandbox-setup-prompt.md — Already Satisfied
Multi-pass pipeline (analyze → validate → render → validate → repair) implemented in sandbox_setup. Profile validation, file validation, detect_stack, base image build, Dockerfile.base template, wait-for-db utility. All three prompt templates exist (sandbox-analyze.md, sandbox-render.md, sandbox-repair.md). Playbook directory with php-laravel.md exists.

### specs/process-planning.md — Already Satisfied
--process flag parsing, PROCESS_DIR validation (empty, missing dir, no .md files), SPEC_VOLUME_HINT computation and export, prompts/plan-process.md exists, prompts/build-process.md exists. Cross-references to incremental-planning.md present in the spec.

### specs/incremental-planning.md — Already Satisfied
Volume hint (SPEC_BYTES, SPEC_COUNT, SPEC_VOLUME_HINT) computed in ralph script. Decomposition ledger and skeleton-first workflow are prompt-level concerns documented in the spec and implemented in `prompts/plan-process.md`.

### specs/align-specs.md — Already Satisfied
align-specs mode recognized, prerequisite checks (PROCESS_DIR, process plan type, completed tasks), prompt template exists (prompts/align-specs.md), build completion nudge implemented in run_loop. Help topic for align-specs present.

### specs/help-system.md — Gaps
- Topic content is correct and comprehensive (specs, plan, build, prompt, sandbox, align-specs, retro).
- Spec requires help content in `lib/help/*.txt` files, dispatcher uses file-based lookup (`cat "$help_dir/${topic}.txt"`). Current implementation uses heredoc functions and a case-based dispatcher. The spec explicitly says: "Remove all `help_*()` heredoc functions — content moves to `lib/help/*.txt`".
- `usage()` function remains in ralph as-is — correct per spec.

## Cross-cutting constraints

- The test suite (230 tests) must continue to pass after every change. Tests validate help system behavior, sandbox functions, CLI parsing, installer/updater MANAGED_FILES consistency.
- `lib/sandbox.sh` must be sourced eagerly at startup, after config but before mode dispatch — matching the pattern for agent scripts.
- `lib/help/*.txt` files must not be sourced — they're plain text files read with `cat`.
- MANAGED_FILES arrays must stay in sync between install.sh and update.sh — tests enforce this.

---

### Task 1: Extract help content to lib/help/*.txt files
**Status:** complete
**Spec:** specs/help-system.md, specs/project-structure.md

Extract all help topic content from heredoc functions in `ralph` into plain text files under `lib/help/`. Replace the case-based `ralph_help()` dispatcher with the file-based dispatcher specified in `help-system.md`.

**Files to inspect/change:**
- `ralph` — remove `help_index()`, `help_plan()`, `help_specs()`, `help_build()`, `help_prompt()`, `help_sandbox()`, `help_align_specs()`, `help_retro()` heredoc functions; replace `ralph_help()` with file-based dispatcher
- `lib/help/index.txt` — create (content from `help_index()`)
- `lib/help/specs.txt` — create (content from `help_specs()`)
- `lib/help/plan.txt` — create (content from `help_plan()`)
- `lib/help/build.txt` — create (content from `help_build()`)
- `lib/help/prompt.txt` — create (content from `help_prompt()`)
- `lib/help/sandbox.txt` — create (content from `help_sandbox()`)
- `lib/help/align-specs.txt` — create (content from `help_align_specs()`)
- `lib/help/retro.txt` — create (content from `help_retro()`)

**Key symbols:** `ralph_help()`, `help_index()`, `help_plan()`, `help_specs()`, `help_build()`, `help_prompt()`, `help_sandbox()`, `help_align_specs()`, `help_retro()`

**End state:** `ralph` contains only the file-based `ralph_help()` dispatcher (~10 lines). All help content lives in `lib/help/*.txt`. Running `ralph help`, `ralph help plan`, `ralph help sandbox`, etc. produces identical output to the current heredoc implementation. Unknown topic handling (`ralph help foo`) works per spec.

**Verify:**
- `./tests/test_ralph.sh` — all tests pass
- `grep -c 'help_index\|help_plan\|help_specs\|help_build\|help_prompt\|help_sandbox\|help_align_specs\|help_retro' ralph` returns 0 (no heredoc functions remain)
- `ls lib/help/*.txt | wc -l` returns 8
- `grep -c 'cat.*lib/help' ralph` returns at least 1 (file-based dispatcher present)

**Exclusions:** Do not change installer/updater MANAGED_FILES in this task — that's Task 4.

---

### Task 2: Extract sandbox functions to lib/sandbox.sh
**Status:** complete
**Spec:** specs/sandbox-cli.md, specs/project-structure.md

Extract all sandbox-related functions from `ralph` into `lib/sandbox.sh`. Add a `source "$RALPH_DIR/lib/sandbox.sh"` line in `ralph` after config loading but before mode dispatch, matching the eager-source pattern used for agent scripts.

**Files to inspect/change:**
- `ralph` — extract functions, add source line
- `lib/sandbox.sh` — create with extracted functions

**Key symbols to extract:** `sandbox_ensure_name()`, `sandbox_container_name()`, `detect_stack()`, `sandbox_validate_profile()`, `sandbox_validate()`, `sandbox_setup()`, `sandbox_up()`, `sandbox_stop()`, `sandbox_reset()`, `sandbox_shell()`, `sandbox_status()`

**End state:** `lib/sandbox.sh` contains all sandbox functions. `ralph` sources it eagerly at startup. The sandbox case in ralph's argument dispatcher still calls these functions — only the function definitions move. All sandbox behavior is identical.

**Verify:**
- `./tests/test_ralph.sh` — all tests pass
- `grep -c 'sandbox_ensure_name\|sandbox_up\|sandbox_stop\|sandbox_reset\|sandbox_shell\|sandbox_status\|sandbox_setup\|sandbox_validate\|detect_stack\|sandbox_container_name\|sandbox_validate_profile' lib/sandbox.sh` shows all 11 functions present
- `grep 'source.*lib/sandbox.sh' ralph` confirms sourcing line exists
- Function definitions are absent from `ralph` (only calls remain in the sandbox case dispatcher)

**Exclusions:** Do not change installer/updater MANAGED_FILES in this task — that's Task 4.

**Notes:** Extracted all 11 functions to `lib/sandbox.sh`. Source line added after config loading (line 131). Updated tests in `test_sandbox.sh` and `test_core.sh` to source functions from `lib/sandbox.sh` instead of `ralph`. All 230 tests pass.

---

### Task 3: Add wait-for-db auto-refresh to sandbox_up
**Status:** complete
**Spec:** specs/sandbox-cli.md

Add `wait-for-db` to the auto-refresh block in `sandbox_up()`, alongside the existing `Dockerfile.base` and `sandbox-preferences.sh` copies.

**Files to inspect/change:**
- `lib/sandbox.sh` (or `ralph` if Task 2 isn't complete yet) — `sandbox_up()` function

**End state:** `sandbox_up()` copies `wait-for-db` from `prompts/templates/` to `sandbox/` before building the base image, matching the spec's auto-refresh block:
```bash
cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$RALPH_DIR/sandbox/Dockerfile.base"
cp "$RALPH_DIR/prompts/templates/wait-for-db" "$RALPH_DIR/sandbox/wait-for-db"
cp "$RALPH_DIR/sandbox-preferences.sh" "$RALPH_DIR/sandbox/sandbox-preferences.sh"
```

**Verify:**
- `./tests/test_ralph.sh` — all tests pass
- `grep -A3 'Auto-refresh' lib/sandbox.sh` shows all three cp lines including wait-for-db

**Notes:** Added one cp line for wait-for-db in sandbox_up(), matching sandbox_setup() which already had all three copies. Updated comment to mention wait-for-db.

---

### Task 4: Update installer and updater MANAGED_FILES for lib/sandbox.sh and lib/help/*.txt
**Status:** planned
**Spec:** specs/installer.md, specs/updater.md, specs/help-system.md, specs/project-structure.md

Add `lib/sandbox.sh` and all `lib/help/*.txt` files to `MANAGED_FILES` and `SOURCE_PATHS` in both `install.sh` and `update.sh`. Also add `mkdir -p "$RALPH_DIR/lib/help"` to the installer's directory creation.

**Files to inspect/change:**
- `install.sh` — add to MANAGED_FILES array, add to SOURCE_PATHS associative array, add mkdir for lib/help
- `update.sh` — add to MANAGED_FILES array, add to SOURCE_PATHS associative array

**Key entries to add:**
- `lib/sandbox.sh` → source `lib/sandbox.sh`
- `lib/help/index.txt` → source `lib/help/index.txt`
- `lib/help/specs.txt` → source `lib/help/specs.txt`
- `lib/help/plan.txt` → source `lib/help/plan.txt`
- `lib/help/build.txt` → source `lib/help/build.txt`
- `lib/help/prompt.txt` → source `lib/help/prompt.txt`
- `lib/help/sandbox.txt` → source `lib/help/sandbox.txt`
- `lib/help/align-specs.txt` → source `lib/help/align-specs.txt`
- `lib/help/retro.txt` → source `lib/help/retro.txt`

**End state:** Both install.sh and update.sh include lib/sandbox.sh and all lib/help/*.txt files in their managed files lists. The installer creates the lib/help/ directory. Tests that validate MANAGED_FILES consistency between install.sh and update.sh continue to pass.

**Verify:**
- `./tests/test_ralph.sh` — all tests pass (specifically the install_update group validates MANAGED_FILES sync)
- `grep 'lib/sandbox.sh' install.sh update.sh` shows entries in both files
- `grep 'lib/help/' install.sh | wc -l` shows 8+ entries (one per help file)
