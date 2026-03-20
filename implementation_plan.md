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
- Process planning mode (`--process` flag, `prompts/plan-process.md`, `PROCESS_DIR` config)
- Help system (`ralph help [topic]`)
- Plan-type-aware build mode (gap-driven vs process task selection)
- REPLAN `Plan Command:` reading
- Tests (77 assertions)

The one remaining spec with implementation gaps is `specs/incremental-planning.md`, which extends process planning for large spec volumes.

---

### Task 1: Add volume hint computation to `ralph` script

**Status:** complete
**Spec:** `specs/incremental-planning.md`

In the `plan --process` code path of the `ralph` script, after validating `PROCESS_DIR`, compute spec volume metrics and generate `SPEC_VOLUME_HINT`:

- Compute `SPEC_BYTES` via `cat "$PROCESS_DIR"/*.md 2>/dev/null | wc -c`
- Compute `SPEC_COUNT` via `find "$PROCESS_DIR" -maxdepth 1 -name '*.md' | wc -l`
- Compute `SPEC_KB` as `$(( SPEC_BYTES / 1024 ))`
- Generate `SPEC_VOLUME_HINT` based on threshold (< 50 KB or < 5 files → single-iteration hint; otherwise → incremental hint)
- Export `SPEC_VOLUME_HINT` for envsubst

The variable must be exported before `prepare_prompt` is called so it's available for `envsubst` substitution.

Add tests:
- Verify `SPEC_VOLUME_HINT` is substituted into the prompt when using `--process` (can be tested by checking the prompt template contains `${SPEC_VOLUME_HINT}` and the script exports it)

**Notes:** Added volume hint computation (SPEC_BYTES, SPEC_COUNT, SPEC_KB, SPEC_VOLUME_HINT) to the `plan --process` code path in `ralph`. Added `${SPEC_VOLUME_HINT}` to the Context section of `prompts/plan-process.md`. Added 3 tests: template variable presence, small-volume hint, large-volume hint (80 total).

---

### Task 2: Update `prompts/plan-process.md` for incremental planning

**Status:** complete
**Spec:** `specs/incremental-planning.md`

Update the process planning prompt to support large spec volumes per the spec. Changes:

1. **Context section** — Add `${SPEC_VOLUME_HINT}` as a line (e.g., `- **Spec Volume:** ${SPEC_VOLUME_HINT}`)

2. **Plan Format section** — Add the decomposition ledger format:
   ```markdown
   ## Decomposition Progress

   | Spec File | Status | Iteration |
   |-----------|--------|-----------|
   | cross-cutting.md | decomposed | 1 |
   | resource-01.md | pending | - |
   ```

3. **Workflow section** — Replace the single-pass workflow with the skeleton-first two-phase approach:
   - Phase A (Skeleton, iteration 1): Read specs shallowly, produce decomposition ledger, optionally produce skeleton phase headings, commit and stop
   - Phase B (Decompose, iterations 2+): Read plan + ledger, pick next `pending` spec, decompose into tasks, mark `decomposed`, commit and stop
   - Small project shortcut: when volume hint says single-iteration is safe, collapse both phases
   - Late-iteration context pressure guidance: when plan exceeds ~40-50 tasks, read only ledger + recent phase tasks

4. **Exit Signal section** — Update completion criteria to include "all spec files in the decomposition ledger are marked `decomposed`"

5. **Regeneration Rules section** — Update to handle ledger (reset all entries to `pending` on regeneration) and collapsed phases (treat as complete unless current specs/codebase contradict)

**Notes:** All 5 changes applied to `prompts/plan-process.md`. Context section already had `${SPEC_VOLUME_HINT}` from Task 1. Added: decomposition ledger format (Plan Format), skeleton-first two-phase workflow with small/large project split and late-iteration context pressure guidance (Workflow), ledger criterion in exit signal (Exit Signal), ledger reset and collapsed phase handling (Regeneration Rules).

---

### Task 3: Add phase collapsing instruction to `prompts/build.md`

**Status:** complete
**Spec:** `specs/incremental-planning.md`

Add a phase collapsing instruction to the build prompt's plan update section (Workflow step 7), gated behind `Plan Type: process`:

- When all tasks in a process plan phase are marked `complete`, collapse the phase to a single summary line: `## Phase N — Name ✅ (X/X complete)`
- This applies only to `Plan Type: process` plans
- Full task history is preserved in git; the collapsed summary saves context for subsequent iterations

**Notes:** Added phase collapsing bullet to Workflow step 7 in `prompts/build.md`, gated behind `Plan Type: process`.

---

### Task 4: Add tests for incremental planning features

**Status:** complete
**Spec:** `specs/incremental-planning.md`

Add tests to `tests/test_ralph.sh`:

- Test that `SPEC_VOLUME_HINT` variable is exported/computed in the `--process` code path (can test by examining the prompt template for the variable placeholder)
- Test that `prompts/plan-process.md` contains `${SPEC_VOLUME_HINT}` (template variable presence check)
- Test that `prompts/build.md` contains phase collapsing instruction
- Test that `prompts/plan-process.md` contains decomposition ledger format/instructions

**Notes:** Added `test_build_prompt_has_phase_collapsing` (2 assertions: phase collapsing mention + Plan Type: process gate) and `test_plan_process_has_decomposition_ledger` (3 assertions: Decomposition Progress heading, Spec File table header, Skeleton workflow mention). The first two bullet points were already covered by existing tests from Task 1. Total: 85 assertions.

---

### Task 5: Update `README.md` to document incremental planning

**Status:** complete
**Spec:** `specs/incremental-planning.md`, `specs/overview.md`

Update the root README to mention incremental process planning capability:
- Note in the process planning section that large spec volumes are handled automatically via decomposition ledger and skeleton-first workflow
- Add `incremental-planning.md` to the Documentation section if not already present

**Notes:** Added comment in Usage section noting automatic incremental decomposition for large spec volumes. Added `incremental-planning.md` entry to the Documentation section.
