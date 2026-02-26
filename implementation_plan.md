# Implementation Plan

## Bug Fixes

#### Task 1: Redesign output pipeline and remove text agent type
- **Status:** complete
- **Spec:** `specs/loop-behavior.md` (Agent Invocation, Agent Types, Completion Detection)
- **Steps:**
  1. Update `invoke_agent` to use the new pipeline:
     - Route agent stderr to session log (`2>>"$SESSION_LOG"`) instead of `2>&1`
     - Write raw output to `$RALPH_DIR/last_agent_output` instead of `$output` variable
     - Wrap display filter with drain fallback (`cat >/dev/null`) to prevent SIGPIPE
  2. Update `check_completion` to read from `last_agent_output` file instead of `$output`
  3. Remove `text` agent type from `load_agent_defaults`
  4. Remove `AGENT_OUTPUT_FORMAT` variable and all branching on it
  5. Clean up `run_iteration` to remove `output=""` initialization and use file path
     for `check_completion`

#### Task 2: Fix `set -e` bypassing retry logic in `run_loop`
- **Status:** complete
- **Spec:** `specs/loop-behavior.md` (Error Handling / Retry Strategy)
- **Problem:** In `run_loop`, `run_iteration` is called as a bare command (not in a
  conditional context). With `set -euo pipefail`, when `run_iteration` returns non-zero,
  the shell exits immediately — `local result=$?` on the next line never executes. The
  entire retry loop is dead code. No retries occur, no session summary is written.
- **Fix:** Capture the exit code in a way that doesn't trigger `set -e`. For example:
  `run_iteration "$iteration" "$prompt_template" || true; local result=$?` — or use an
  `if/else` construct to branch on the return value.
