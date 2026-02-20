# Implementation Plan

## Plan Status

Status: Complete
Last Updated: 2026-02-20 17:02:00
Phases Completed: Inventory, Spec Alignment, Task Decomposition, Ordering

## Project Overview

The Ralph Wiggum Loop is an iterative development system for LLM coding agents. It enables agents
to work on large projects by breaking work into discrete, manageable chunks with fresh context per
iteration. Ralph operates in two modes: plan mode (creates/updates an implementation plan) and
build mode (implements one task per iteration).

This is a self-hosting project — Ralph is being used to build itself. The "source code" is the
specs (`specs/`) and the ralph scripts. There is no separate `src/` directory. The project is
written in Bash and targets standard POSIX environments.

Key technologies: Bash, Git, envsubst, Cline (agent CLI).

## Spec Coverage

- [x] specs/overview.md - Analyzed
- [x] specs/project-structure.md - Analyzed
- [x] specs/loop-behavior.md - Analyzed
- [x] specs/plan-mode.md - Analyzed
- [x] specs/build-mode.md - Analyzed
- [x] specs/installer.md - Analyzed
- [x] specs/spec-lifecycle.md - Analyzed (guidance only, no implementation gaps)

## Tasks

### Task 1: Create prompt templates and supporting files
**Status:** complete
**Spec:** specs/plan-mode.md, specs/build-mode.md, specs/project-structure.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Create `prompts/` directory
2. Create `prompts/plan.md` using the canonical template from `specs/plan-mode.md`
3. Create `prompts/build.md` using the canonical template from `specs/build-mode.md`
4. Verify `.gitignore` excludes `logs/` (add entry if missing)
5. Commit with message: `feat: add prompt templates and gitignore for logs`

**Notes:**
The canonical prompt content is defined verbatim in the specs under "Prompt Template" sections.
The `logs/` directory itself does not need to be created — ralph creates it at runtime.

---

### Task 2: Implement the `ralph` main executable
**Status:** complete
**Spec:** specs/loop-behavior.md, specs/project-structure.md
**Dependencies:** Task 1
**Estimated Complexity:** high

**Steps:**
1. Create `ralph` script at the project root (make executable with `chmod +x`)
2. Implement self-relative path resolution: `RALPH_DIR="$(dirname "$(readlink -f "$0")")"`
3. Implement CLI argument parsing:
   - Positional arg 1: mode (`plan`, `build`, `prompt`)
   - Positional arg 2: optional max_iterations (default from config)
   - `--config PATH` option
4. Implement config loading (source the config file)
5. Implement prerequisite validation:
   - Git repository exists (`.git/` directory)
   - Agent CLI is available in PATH
   - Required directories exist
6. Implement session log initialization: `logs/session-YYYYMMDD-HHMMSS.log`
7. Implement build mode pre-check: verify `implementation_plan.md` exists (exit code 2 if not)
8. Implement template variable substitution via `envsubst` before agent invocation
9. Implement agent invocation pattern (pipe prompt to agent stdin, tee to terminal and log)
10. Implement completion signal detection (`<promise>COMPLETE</promise>`)
11. Implement iteration loop with header/footer logging
12. Implement session summary logging on exit
13. Implement all exit codes (0, 1, 2, 4, 5)
14. Implement `prompt` mode (single invocation, no loop, no completion signal check)
15. Implement retry logic (up to MAX_RETRIES per iteration, exit code 4 on exhaustion)
16. Manual verification: run `./ralph` with no args and confirm usage message; run `./ralph plan`
    and confirm it invokes the agent
17. Commit with message: `feat: implement ralph main executable`

**Notes:**
- The agent is invoked with the **project root as working directory** — this is always `.` from
  the agent's perspective, regardless of where the ralph script lives.
- The loop does NOT commit on behalf of the agent; the agent commits its own work.
- For the `prompt` mode, the agent decides whether to commit based on the prompt's instructions.
- `envsubst` substitutes all variables from `config` plus runtime variables (`${MODE}`).
- Agent invocation pattern from spec:
  `output=$(cat "$PROMPT_FILE" | $AGENT_CLI $AGENT_ARGS 2>&1 | tee /dev/stderr | tee -a "$SESSION_LOG")`

---

### Task 3: Create `install.sh`
**Status:** complete
**Spec:** specs/installer.md, specs/project-structure.md
**Dependencies:** None
**Estimated Complexity:** medium

**Steps:**
1. Create `install.sh` at the project root (make executable with `chmod +x`)
2. Implement pre-installation checks:
   - Refuse if `.ralph/` already exists (exit code 1 with message)
   - Verify `.git/` directory exists
   - Verify required tools: bash, mkdir, cp, envsubst
3. Implement directory structure creation under `.ralph/`:
   - `.ralph/ralph` (copy from project root `ralph`, make executable)
   - `.ralph/config` (copy from template)
   - `.ralph/implementation_plan.md` (empty template)
   - `.ralph/prompts/plan.md` (copy from `prompts/plan.md`)
   - `.ralph/prompts/build.md` (copy from `prompts/build.md`)
   - `.ralph/logs/` (create directory)
   - `.ralph/.gitignore` (create with `logs/` entry)
4. Implement additive-only policy for files outside `.ralph/`:
   - Create `specs/` if missing
   - Create `specs/README.md` from template if missing
   - Create `AGENTS.md` from template if missing
5. Display post-install success message (per spec)
6. Manual verification: run installer in a temp directory and confirm structure
7. Commit with message: `feat: add install.sh installer script`

**Notes:**
- The installer is additive only outside `.ralph/` — never overwrites existing files.
- `.ralph/` is all-or-nothing: if it exists, abort entirely.
- File templates (config, implementation_plan.md, specs/README.md, AGENTS.md) are defined
  verbatim in `specs/installer.md`.
- The installer copies `ralph` from the project root into `.ralph/ralph`, so Task 2 (ralph
  script) must exist before the installer can be fully tested end-to-end. However, the installer
  itself can be written and structurally verified independently.

## Notes & Learnings

- This project is self-hosting: ralph runs from the project root (not `.ralph/`). The `ralph`
  script, `prompts/`, `logs/`, `config`, and `implementation_plan.md` all live at the root.
- The `AGENTS.md` notes that manual verification is `./ralph plan` or `./ralph build` — there is
  no automated test suite yet.
- Task 3 (install.sh) has no dependency on Task 2 (ralph) for writing the code, but does depend
  on it for full end-to-end testing. Tasks can be done in any order (1, 2, 3 or 1, 3, 2).
- The `prompts/` directory in this repo is the **canonical source** for prompt templates. When
  installed into a parent project, they are copied to `.ralph/prompts/` and can be customized.
