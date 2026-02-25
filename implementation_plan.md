# Implementation Plan

## Status: Complete

Last Updated: 2026-02-25
All tasks complete.

## Project Overview

Ralph Wiggum Loop is a bash-based iterative development system. The "source code" is the
`ralph` script, `install.sh`, `config`, and `prompts/`. Specs live in `specs/`. There is no
separate `src/` directory.

## Spec Coverage

| Spec | Status |
|------|--------|
| specs/overview.md | ✅ Implemented |
| specs/project-structure.md | ✅ Implemented |
| specs/loop-behavior.md | ✅ Implemented |
| specs/plan-mode.md | ✅ Implemented |
| specs/build-mode.md | ✅ Implemented |
| specs/spec-lifecycle.md | ✅ No code required (process doc) |
| specs/installer.md | ✅ Implemented |

## Tasks

---

### Task 1: Fix prompt mode to run as a loop

**Status:** complete
**Spec:** specs/loop-behavior.md

The spec defines prompt mode as a full loop with `max_iterations`, retries, and completion
signal detection — identical to plan/build modes except it uses a user-supplied prompt file.
The current `run_prompt_mode()` function is a single-shot invocation with no loop, no retries,
and no completion signal check.

**Steps:**
1. In `ralph`, add a pre-flight check at the start of `run_prompt_mode()`: verify the prompt
   file contains `<promise>COMPLETE</promise>` — if absent, exit with code 1 and message:
   "Error: prompt file must contain <promise>COMPLETE</promise>"
2. Replace the single-invocation body of `run_prompt_mode()` with a call to `run_loop()`,
   passing the prompt file as the template. The `MAX_ITERATIONS` variable is already set
   correctly from CLI arg parsing.
3. Remove the now-redundant single-invocation logging in `run_prompt_mode()` (the loop
   handles iteration headers/footers and session summary).
4. Verify the `prompt` case in the entry-point `case` block passes `$PROMPT_FILE` correctly.
5. Manual test: `./ralph prompt prompts/plan.md` should loop up to `DEFAULT_MAX_ITERATIONS`,
   and `./ralph prompt prompts/plan.md 3` should loop up to 3 iterations.

**Notes:**
- `run_loop()` already handles all logging, retries, completion detection, and exit codes.
- The only prompt-mode-specific behavior is the pre-flight `<promise>COMPLETE</promise>` check
  and the fact that the prompt file is user-supplied rather than a fixed template path.
- Exit code 1 for missing completion signal (pre-flight failure) is distinct from exit code 4
  (agent failure exceeded retries).

---

### Task 2: Fix implementation_plan.md template in install.sh

**Status:** complete
**Spec:** specs/installer.md

The spec says the `implementation_plan.md` template should be intentionally minimal:
```
# Implementation Plan
```
The current installer creates a verbose skeleton with "Plan Status", "Project Overview",
"Spec Coverage", "Tasks", and "Notes & Learnings" sections. The spec explicitly notes:
"This is intentionally minimal. Plan mode regenerates the plan from scratch, so there is no
value in pre-populating it with skeleton sections."

**Steps:**
1. In `install.sh`, find the heredoc that creates `$RALPH_DIR/implementation_plan.md`.
2. Replace the verbose template with the minimal one-liner: `# Implementation Plan`
3. No other changes needed.

**Notes:**
- This is a cosmetic/correctness fix. The verbose template doesn't break anything, but it
  contradicts the spec and adds noise that plan mode will overwrite anyway.

---

## Notes & Learnings

- The `ralph` script is well-implemented and closely follows the specs. The main loop,
  logging, completion detection, retry logic, and exit codes all match spec exactly.
- `prompts/plan.md` and `prompts/build.md` match their canonical templates in the specs.
- `install.sh` is complete and correct except for the verbose `implementation_plan.md` template.
- The `config` file in the repo does not have a `#!/bin/bash` shebang (the spec shows one),
  but since `config` is sourced (not executed), this is not a functional gap — it's a style
  preference. Not worth a task.
- The installer checks for `envsubst` as a prerequisite. This is technically a runtime
  dependency of `ralph` rather than the installer itself, but it's harmless and helpful to
  surface early.
