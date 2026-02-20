# Implementation Plan

## Plan Status

Status: Complete
Last Updated: 2026-02-20 16:27:00
Phases Completed: Inventory, Spec Alignment, Task Decomposition, Dependency Ordering

## Project Overview

The Ralph Wiggum Loop is a bash-based iterative development system that enables LLM coding agents
to work on large projects by breaking work into discrete, manageable chunks with fresh context per
iteration. Ralph operates in two primary modes: **plan mode** (analyze specs → create task list)
and **build mode** (pick one task → implement → commit). A third **prompt mode** supports one-off
ad-hoc agent invocations.

The project is self-hosting: Ralph lives at the root of the `ralph-loop` repo and operates on
itself. The same files are installed into parent projects via `install.sh`, which copies Ralph into
a hidden `.ralph/` directory.

Key technologies: Bash, `envsubst`, `tee`, `git`, and a pluggable agent CLI (default: `cline`).

## Spec Coverage

- [x] specs/overview.md — Analyzed
- [x] specs/project-structure.md — Analyzed
- [x] specs/loop-behavior.md — Analyzed
- [x] specs/plan-mode.md — Analyzed
- [x] specs/build-mode.md — Analyzed
- [x] specs/installer.md — Analyzed
- [x] specs/spec-lifecycle.md — Analyzed

## Tasks

### Task 1: Create `config` file
**Status:** planned
**Spec:** specs/project-structure.md, specs/installer.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Create `config` at the project root (this is the ralph-loop repo, so ralph lives at root)
2. Include all variables defined in the spec:
   - `SPECS_DIR="specs"`
   - `DEFAULT_MAX_ITERATIONS=10`
   - `MAX_RETRIES=3`
   - `AGENT_CLI="cline"`
   - `AGENT_ARGS="--yolo"`
3. Add a shebang (`#!/bin/bash`) and descriptive comments
4. Commit the file

---

### Task 2: Create `prompts/plan.md`
**Status:** planned
**Spec:** specs/plan-mode.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Create `prompts/` directory at the project root
2. Copy the canonical plan prompt template from `specs/plan-mode.md` (under "Prompt Template")
   into `prompts/plan.md`
3. The template uses `${SPECS_DIR}` and `${MODE}` variables — preserve them as-is (envsubst
   will substitute at runtime)
4. Commit the file

---

### Task 3: Create `prompts/build.md`
**Status:** planned
**Spec:** specs/build-mode.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Copy the canonical build prompt template from `specs/build-mode.md` (under "Prompt Template")
   into `prompts/build.md`
2. The template uses `${SPECS_DIR}` and `${MODE}` variables — preserve them as-is
3. Commit the file

---

### Task 4: Create `logs/` directory and supporting gitignore entries
**Status:** planned
**Spec:** specs/project-structure.md, specs/installer.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Create `logs/` directory at the project root
2. Add a `.gitkeep` file inside `logs/` so git tracks the directory
3. Verify the root `.gitignore` excludes `logs/` session log files (e.g., `logs/*.log`)
   — add the entry if missing
4. Commit the changes

---

### Task 5: Implement the `ralph` main executable script
**Status:** planned
**Spec:** specs/loop-behavior.md, specs/project-structure.md, specs/plan-mode.md, specs/build-mode.md
**Dependencies:** Task 1, Task 2, Task 3, Task 4
**Estimated Complexity:** high

**Steps:**
1. Create `ralph` at the project root; make it executable (`chmod +x ralph`)
2. Add shebang `#!/bin/bash` and `set -euo pipefail`
3. Implement self-relative path resolution:
   ```bash
   RALPH_DIR="$(dirname "$(readlink -f "$0")")"
   ```
4. Implement CLI argument parsing:
   - Positional arg 1: mode (`plan`, `build`, `prompt`)
   - Positional arg 2 (optional): max iterations (integer)
   - `--max-iterations N` flag
   - `--config PATH` flag (default: `$RALPH_DIR/config`)
   - `prompt` mode requires a file path argument
   - Print usage and exit 1 on invalid args
5. Load configuration by sourcing the config file:
   ```bash
   source "$CONFIG_FILE"
   ```
6. Implement prerequisite validation:
   - Git repository exists (`.git/` directory present in working dir)
   - Agent CLI is available in PATH
   - Required directories exist (`$SPECS_DIR`, `$RALPH_DIR/prompts/`)
7. Implement session log initialization:
   - Create `$RALPH_DIR/logs/` if it doesn't exist
   - Create log file: `$RALPH_DIR/logs/session-YYYYMMDD-HHMMSS.log`
   - Record session start metadata
8. Implement template variable substitution using `envsubst`:
   - Export all config variables + runtime variables (`MODE`, etc.)
   - Substitute into the prompt file before passing to agent
9. Implement agent invocation pattern (pipe substituted prompt to agent via stdin):
   ```bash
   output=$(envsubst < "$PROMPT_FILE" | $AGENT_CLI $AGENT_ARGS 2>&1 | tee /dev/stderr | tee -a "$SESSION_LOG")
   ```
10. Implement completion signal detection — scan `$output` for `<promise>COMPLETE</promise>`
11. Implement the iteration loop:
    - Pre-iteration check for build mode: verify `$RALPH_DIR/implementation_plan.md` exists;
      exit code 2 if missing
    - Write iteration header to log (format per spec)
    - Invoke agent
    - Check for completion signal
    - Write iteration footer to log (format per spec)
    - Check exit conditions (completion, max iterations, failures)
12. Implement retry logic:
    - Per-iteration retry counter (up to `$MAX_RETRIES`)
    - Reset retry counter on successful iteration
    - Exit code 4 if retries exhausted
13. Implement `prompt` mode (single invocation, no loop, no completion signal check)
14. Write session summary to log on exit (format per spec)
15. Implement all exit codes: 0 (success), 1 (general error), 2 (plan missing), 4 (agent
    failure), 5 (git failure)
16. Commit the script

---

### Task 6: Create `implementation_plan.md` empty template
**Status:** planned
**Spec:** specs/installer.md, specs/plan-mode.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Create `implementation_plan.md` at the project root using the template defined in
   `specs/installer.md` (under "File Templates → .ralph/implementation_plan.md")
2. Note: this file will be overwritten by plan mode when ralph runs — the template is just
   a placeholder so the file exists in the repo as a starting point for installed projects
3. Commit the file

**Notes:**
This task can be done at any time — it has no code dependencies. The current
`implementation_plan.md` (this file) will be replaced by the next plan-mode run once `ralph`
is implemented.

---

### Task 7: Implement `install.sh`
**Status:** planned
**Spec:** specs/installer.md, specs/project-structure.md
**Dependencies:** Task 1, Task 2, Task 3, Task 5, Task 6
**Estimated Complexity:** medium

**Steps:**
1. Create `install.sh` at the project root; make it executable (`chmod +x install.sh`)
2. Add shebang `#!/bin/bash` and `set -euo pipefail`
3. Implement pre-installation checks:
   - If `.ralph/` directory exists: print error and exit 1
   - If `.git/` directory does not exist: print error and exit 1
   - Check for required tools: `bash`, `mkdir`, `cp`, `envsubst`, `git`
4. Implement directory structure creation:
   ```
   .ralph/
   ├── ralph               (executable)
   ├── config
   ├── implementation_plan.md
   ├── prompts/
   │   ├── plan.md
   │   └── build.md
   ├── logs/
   └── .gitignore
   ```
5. Copy files from the ralph-loop repo into `.ralph/`:
   - `ralph` → `.ralph/ralph` (set executable bit)
   - `config` → `.ralph/config`
   - `prompts/plan.md` → `.ralph/prompts/plan.md`
   - `prompts/build.md` → `.ralph/prompts/build.md`
   - `implementation_plan.md` → `.ralph/implementation_plan.md`
6. Create `.ralph/.gitignore` with content:
   ```
   # Ralph session logs (generated, not committed)
   logs/
   ```
7. Create `specs/` directory if it doesn't exist
8. Create `specs/README.md` if it doesn't exist (use template from spec)
9. Create `AGENTS.md` if it doesn't exist (use template from spec)
10. Print success message with next steps (exact text per spec)
11. Handle errors gracefully: permission errors, missing dependencies — exit with non-zero
    code and clear message
12. Commit the script

---

## Notes & Learnings

- The `ralph` script is the most complex piece. It is pure bash and should be ~200–400 lines.
  If implementation proves unwieldy in one iteration, split into: (a) CLI/config/validation
  skeleton, and (b) loop logic, logging, and agent invocation.
- `envsubst` substitutes only variables that are exported. The ralph script must `export` all
  config variables after sourcing the config file.
- The agent invocation pattern uses `tee /dev/stderr` to stream output to the terminal in
  real-time while also capturing it in `$output` for completion signal scanning. This is a
  subtle but important detail — test it carefully.
- `install.sh` is designed to be piped from `curl`. It must be self-contained and must not
  assume it is run from the ralph-loop repo directory. It downloads/copies from wherever it
  is invoked. **Clarification needed:** the spec says the installer "copies Ralph files into
  a host project" but the curl invocation pipes the script directly — the installer will need
  to either (a) download individual files from GitHub raw URLs, or (b) assume it is run from
  within a cloned ralph-loop repo. This ambiguity should be resolved before implementing Task 7.
- Task 6 (`implementation_plan.md` template) will be superseded by the first real plan-mode
  run. It exists only as a placeholder for installed projects.
- No automated test suite exists yet. Manual verification: run `./ralph plan` and `./ralph build`
  and confirm expected behavior per AGENTS.md.
