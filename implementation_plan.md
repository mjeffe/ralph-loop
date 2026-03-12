# Implementation Plan

## Learnings & Gotchas

- The ralph-loop repo is self-hosting: RALPH_DIR resolves to the project root, so `last_agent_output`, `implementation_plan.md`, etc. all live at root level.
- The canonical prompt templates live in the specs (plan-mode.md, build-mode.md). The actual prompt files (prompts/plan.md, prompts/build.md) must match them.
- The installer spec (installer.md) lists agent scripts `claude.sh`, `cline.sh`, `codex.sh` and the project-structure spec shows them in the directory tree, but they don't exist yet. The installer currently only copies `amp.sh`.
- The installer spec's `.gitignore` template only has `logs/`, but the actual installed `.gitignore` also has `last_agent_output` and `*.upstream` — the spec is out of date, the code is correct. The spec should be updated to match.
- The iteration log header/footer format in loop-behavior.md uses a structured multi-line format with separators. The actual `ralph` script uses a more compact format. This is cosmetic and acceptable as-is — the spec describes an ideal; the code captures the essential info.
- Sandbox specs (`sandbox-cli.md`, `sandbox-setup-prompt.md`) are entirely new features — no code exists yet.
- The `sandbox-cli.md` spec explicitly says it must be implemented before `sandbox-setup-prompt.md`.

---

## Completed Tasks (Previous Plan)

### Task 1: Fix prompt mode max_iterations parsing
**Status:** complete
**Spec:** specs/loop-behavior.md

### Task 3: Resolve `text` agent type spec inconsistency
**Status:** complete
**Spec:** specs/overview.md, specs/project-structure.md, specs/loop-behavior.md

### Task 4: Clean up .gitignore and add generated file exclusions
**Status:** complete
**Spec:** specs/project-structure.md, specs/loop-behavior.md

### Task 5: Update installer to generate .version and .manifest
**Status:** complete
**Spec:** specs/updater.md

### Task 6: Add `update` mode to ralph script
**Status:** complete
**Spec:** specs/updater.md

### Task 7: Create update.sh
**Status:** complete
**Spec:** specs/updater.md

### Task 8: Sync README.md with current project state
**Status:** complete
**Spec:** specs/overview.md, specs/project-structure.md

---

## New Tasks

### Task 9: Update installer spec `.gitignore` template
**Status:** complete
**Spec:** specs/installer.md
**Priority:** low (spec housekeeping)

The installer spec (installer.md, section "File Templates → .ralph/.gitignore") shows only `logs/` in the `.gitignore` template. The actual installer code already writes `last_agent_output` and `*.upstream` entries too. Update the spec to match the implemented code so they stay in sync.

Also, `sandbox-cli.md` requires adding `sandbox/.env` to the `.gitignore` template — this should be included when the sandbox CLI is implemented (Task 10), but the base `.gitignore` spec should be corrected now.

---

### Task 10: Implement sandbox CLI lifecycle commands
**Status:** complete
**Spec:** specs/sandbox-cli.md
**Priority:** high (implement before Task 11)

Add the `sandbox` subcommand to the `ralph` script with all lifecycle functions:

1. **Argument parsing:** Add `sandbox` to the mode case statement. Parse subcommands: `setup`, `up`, `down`, `reset`, `shell`, `status`.
2. **SANDBOX=1 guard:** If `SANDBOX=1` is set in the environment, print error and exit.
3. **Lifecycle functions:** Implement `sandbox_up`, `sandbox_down`, `sandbox_reset`, `sandbox_shell`, `sandbox_status`, `sandbox_setup` as specified.
4. **sandbox_setup:** Use `agent_invoke` with the `prompts/sandbox-setup.md` template. Check for existing sandbox files. Create `.ralph/sandbox/` directory.
5. **sandbox_container_name helper:** Read container name from compose file or derive from project name.
6. **Installer changes:** Add `prompts/sandbox-setup.md` to managed files list in `install.sh`. Create `.ralph/sandbox/` directory. Add `sandbox/.env` to `.ralph/.gitignore`.
7. **Updater changes:** Add `prompts/sandbox-setup.md` to `MANAGED_FILES` and `SOURCE_PATHS` in `update.sh`.
8. **Usage text:** Update `usage()` to include `sandbox` subcommands.
9. **Prerequisite validation:** Sandbox mode should skip agent CLI validation (Docker is needed instead, but per spec ralph doesn't validate Docker — compose commands will fail with their own error messages).
10. **Update tests:** Add tests for sandbox argument parsing, SANDBOX=1 guard.

**Notes:**
- The `sandbox setup` command is a single agent invocation (no loop). It calls `prepare_prompt` + `agent_invoke` + `agent_format_display` directly, so it does need the agent script loaded.
- The `read -p` in `sandbox_reset` means it requires an interactive terminal.
- The sandbox subcommand should not enter `run_loop` — it's a direct command.

---

### Task 11: Create sandbox setup prompt template
**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md
**Depends on:** Task 10

Create `prompts/sandbox-setup.md` with the canonical prompt template from the spec. This is the prompt that `ralph sandbox setup` sends to the agent.

The prompt template content is fully specified in `specs/sandbox-setup-prompt.md` under "Prompt Template Content". Copy it into `prompts/sandbox-setup.md`.

---

### Task 12: Add placeholder agent scripts for claude, cline, codex
**Status:** complete
**Spec:** specs/agent-scripts.md, specs/project-structure.md, specs/installer.md

The project-structure spec and installer spec list `claude.sh`, `cline.sh`, and `codex.sh` as agent scripts that should exist. Currently only `amp.sh` exists.

Options:
1. Create stub scripts that set `AGENT_CLI` and define the required functions with placeholder implementations that echo a "not yet implemented" message.
2. Remove references from specs if we don't want to support them yet.

Recommend option 1 — create minimal stubs so the directory structure matches specs and the installer can copy them. Each stub should set `AGENT_CLI` to the expected binary name and have the three required functions print a "not yet implemented" error and exit 1.

Also update `install.sh` to copy these scripts during installation, and update `update.sh` `MANAGED_FILES`/`SOURCE_PATHS` to include them.

---

### Task 13: Sync README.md with sandbox feature
**Status:** planned
**Spec:** specs/overview.md, specs/project-structure.md
**Depends on:** Tasks 10-11

After sandbox implementation:
- Update README.md to document sandbox commands in the Usage section
- Update the project structure diagram to include `sandbox/` directory and `prompts/sandbox-setup.md`
- Update the "Future Enhancements" section — containerization is no longer future
- Add sandbox-related specs to the Documentation section
