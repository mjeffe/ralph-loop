# Implementation Plan

Plan Type: gap-driven
Plan Command: ralph plan

---

## Summary

This plan closes the gaps between the current codebase and the specifications. The major
outstanding work is the **multi-pass sandbox setup pipeline** (the largest feature gap),
plus several smaller alignment issues across the installer, updater, managed files, and
sandbox lifecycle commands.

---

### Task 1: Rename `sandbox-preferences.md` to `sandbox-preferences.sh`
**Status:** complete
**Spec:** specs/sandbox-cli.md, specs/sandbox-setup-prompt.md, specs/project-structure.md, specs/installer.md

The specs consistently refer to `sandbox-preferences.sh` (an executable bash script), but the
repo has `sandbox-preferences.md` (a markdown file). This is a foundational rename that
affects managed file lists, installer, updater, prompts, and the sandbox setup function.

What to do:
- Rename `sandbox-preferences.md` → `sandbox-preferences.sh` at the repo root
- Make it executable (`chmod +x`)
- Convert the content from markdown prose to an executable bash script that can be COPY'd
  into the Docker build context and run with `bash`. The current markdown describes packages
  to install, bashrc customizations, vim config, and gitconfig — translate these into bash
  commands.
- Update `MANAGED_FILES` and `SOURCE_PATHS` in `install.sh` and `update.sh` to reference
  `sandbox-preferences.sh` instead of `sandbox-preferences.md`
- Update `prompts/sandbox-setup.md` references from `sandbox-preferences.md` to
  `sandbox-preferences.sh`
- Run tests (`./tests/test_ralph.sh`)

**Completed:** Renamed `sandbox-preferences.md` → `sandbox-preferences.sh`, converted markdown
prose to an executable bash script (apt-get install, bashrc append, vim config via curl, gitconfig
creation), made executable, updated `MANAGED_FILES`/`SOURCE_PATHS` in both `install.sh` and
`update.sh`, updated all four references in `prompts/sandbox-setup.md`, added `chmod +x` for the
file in the installer. All 108 tests pass.

---

### Task 2: Create `prompts/templates/Dockerfile.base`
**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md, specs/sandbox-cli.md

The specs define a managed base image Dockerfile at `prompts/templates/Dockerfile.base`.
This file does not exist yet. It provides the invariant layer (OS, system tools, Node.js,
Amp CLI, non-root user) that every sandbox needs.

What to do:
- Create `prompts/templates/` directory
- Create `prompts/templates/Dockerfile.base` with the content specified in the
  sandbox-setup-prompt.md spec (ubuntu:24.04 base, system essentials, Node.js, Amp CLI,
  ralph user, etc.)
- Add `prompts/templates/Dockerfile.base` to `MANAGED_FILES` and `SOURCE_PATHS` in both
  `install.sh` and `update.sh`
- Ensure `install.sh` creates the `prompts/templates/` directory during installation
- Run tests (`./tests/test_ralph.sh`)

**Completed:** Created `prompts/templates/Dockerfile.base` with the exact content from the
spec (ubuntu:24.04, system essentials, Node.js LTS, Amp CLI, UID 1000 ralph user). Added
to `MANAGED_FILES` and `SOURCE_PATHS` in both `install.sh` and `update.sh`. Updated
`install.sh` to create `prompts/templates/` directory (changed `mkdir -p "$RALPH_DIR/prompts"`
to `mkdir -p "$RALPH_DIR/prompts/templates"` which also creates the parent). All 108 tests pass.

---

### Task 3: Create multi-pass sandbox prompt templates
**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md

The specs call for three separate prompt files replacing the single `prompts/sandbox-setup.md`:
- `prompts/sandbox-analyze.md` — Pass 1: project analysis → project profile JSON
- `prompts/sandbox-render.md` — Pass 2: generate sandbox files from profile
- `prompts/sandbox-repair.md` — Pass 3: fix validation failures

**Completed:** Created all three prompt files derived from the spec:
- `prompts/sandbox-analyze.md` — sources to read, conclusions to extract, decision rules,
  full profile schema (required/optional fields), PHP/Laravel example profile, multi-container
  model constraints, uses `${RALPH_HOME}` and `${STACK_PLAYBOOK}` template vars
- `prompts/sandbox-render.md` — profile-only generation rules, four output file templates
  (Dockerfile, entrypoint.sh, docker-compose.yml, .env.example), hard constraints, all four
  appendices (git credentials, YAML syntax, idempotency, non-interactive builds),
  self-validation checklist
- `prompts/sandbox-repair.md` — concise targeted repair prompt using `${VALIDATION_FAILURES}`
  template var, reads generated files and profile, makes minimal fixes
- Updated `MANAGED_FILES` and `SOURCE_PATHS` in both `install.sh` and `update.sh`: removed
  `prompts/sandbox-setup.md`, added the three new prompts
- `prompts/sandbox-setup.md` kept on disk for Task 9 cleanup
- All 108 tests pass

---

### Task 4: Implement `sandbox_validate_profile()` and `sandbox_validate()` in `ralph`
**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md

The specs define two validation functions that run between pipeline passes:
- `sandbox_validate_profile()` — validates the project profile JSON schema before Pass 2
- `sandbox_validate()` — validates generated sandbox files for structural correctness

What to do:
- Implement `sandbox_validate_profile()` in the `ralph` script — checks required fields,
  schema_version, non-empty arrays as specified in the profile schema section of the spec
- Implement `sandbox_validate()` in the `ralph` script — performs syntax checks
  (`bash -n`, `docker compose config`), structural checks (FROM, ENTRYPOINT, WORKDIR, etc.),
  cross-file consistency checks (ports, env vars, services), and profile consistency checks
  as specified in the Machine Validator section of the spec
- Both functions output failure messages to stdout (empty = pass)
- Run tests (`./tests/test_ralph.sh`)

**Completed:** Implemented both functions in the `ralph` script, placed between
`detect_stack()` and `sandbox_setup()`. `sandbox_validate_profile()` checks all 14
required top-level fields, schema_version == 1, non-empty runtimes/supervisor_programs,
and service entry required fields (name, image, port/ports, reason).
`sandbox_validate()` performs syntax checks (bash -n, docker compose config), structural
checks on Dockerfile (FROM, ENTRYPOINT, WORKDIR, sandbox-preferences.sh, entrypoint.sh),
entrypoint.sh (shebang, set -euo pipefail, git credentials, .git/HEAD clone logic,
exec supervisord), docker-compose.yml (app service, list env syntax, named volumes,
env_file, tty, stdin_open), cross-file consistency (EXPOSE ports, env vars in
.env.example), and profile consistency (services match). Added 7 test functions covering
valid profile, missing fields, bad schema_version, empty runtimes, service field
validation, invalid JSON, and structural file checks. All 123 tests pass.

---

### Task 5: Rewrite `sandbox_setup()` for multi-pass pipeline with `--render-only`
**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md, specs/sandbox-cli.md

The current `sandbox_setup()` function uses a single-pass approach with
`prompts/sandbox-setup.md`. The specs require a multi-pass pipeline:
base image build → analyze → profile validate → render → file validate → repair.

What to do:
- Rewrite `sandbox_setup()` to match the pipeline specified in the sandbox-setup-prompt spec:
  1. Parse `--force` and `--render-only` flags
  2. Load agent script and validate CLI
  3. Handle `--render-only` requiring existing profile
  4. Handle existing files (error without `--force`; preserve `.env` and optionally profile)
  5. Copy `Dockerfile.base` and `sandbox-preferences.sh` into build context
  6. Build base image (`docker build -t ralph-sandbox-base`)
  7. Detect stack and resolve playbook (if not `--render-only`)
  8. Pass 1: Analyze (skip if `--render-only`)
  9. Validate profile schema
  10. Pass 2: Render
  11. Validate generated files
  12. Pass 3: Repair (if validation failed, single attempt)
  13. Re-validate and report remaining issues
  14. Restore `.env` if preserved
  15. Print next-steps guidance
- The spec in sandbox-setup-prompt.md provides the full reference implementation for
  `sandbox_setup()` — follow it closely
- Run tests (`./tests/test_ralph.sh`)

**Completed:** Rewrote `sandbox_setup()` to match the spec's reference implementation.
Added `--render-only` flag parsing, `--render-only` profile existence check, profile
preservation during `--render-only --force`, base image build step (copy Dockerfile.base
and sandbox-preferences.sh then docker build), multi-pass pipeline (analyze → profile
validate → render → file validate → repair), and spec-matching error messages/next-steps
guidance. Removed old single-prompt-template reference and the AGENTS.md note at the end.
All 123 tests pass.

---

### Task 6: Update `sandbox_up()` with base image auto-refresh
**Status:** complete
**Spec:** specs/sandbox-cli.md

The spec requires `sandbox_up()` to auto-refresh the base image on every invocation by
copying `Dockerfile.base` and `sandbox-preferences.sh` from managed sources and rebuilding
`ralph-sandbox-base`. The current implementation does not do this.

**Completed:** Added three-line auto-refresh block before `docker compose up`: copies
`Dockerfile.base` from `prompts/templates/` and `sandbox-preferences.sh` from the ralph
dir into the sandbox build context, then runs `docker build -t ralph-sandbox-base`. Docker
layer cache makes this instant when nothing has changed. All 123 tests pass.

---

### Task 7: Fix `sandbox_reset()` to match spec
**Status:** complete
**Spec:** specs/sandbox-cli.md

The current `sandbox_reset()` implementation diverges from the spec in the non-`--all` case.
The spec says: stop only the app service, remove its codebase volume, then restart only app.
The current code does `docker compose down` (stops all services) then `docker compose up -d --build`
(rebuilds all).

What to do:
- Fix the non-`--all` branch to:
  1. `docker compose stop app`
  2. `docker volume rm "${project_name}_sandbox-codebase"`
  3. `docker compose up -d --build app`
- Update the user messaging to match spec language about "codebase volume" and
  "service volumes"
- Run tests (`./tests/test_ralph.sh`)

**Completed:** Fixed non-`--all` branch to `stop app` / `volume rm` / `up -d --build app`
instead of `down` / `up -d --build` (which stopped and rebuilt all services). Moved
`up -d --build` inside the `else` branch so `--all` only does `down -v` without restart.
Updated user messaging to match spec language ("sandbox volumes", "app codebase volume",
"Service volumes"). All 123 tests pass.

---

### Task 8: Fix `sandbox_container_name()` to accept service name argument
**Status:** complete
**Spec:** specs/sandbox-cli.md

The spec shows `sandbox_container_name()` takes a service argument (e.g., `sandbox_container_name "app"`),
but the current implementation takes no arguments.

What to do:
- Update `sandbox_container_name()` to accept an optional service name argument
- Update the call in `sandbox_shell()` to pass `"app"`
- Run tests (`./tests/test_ralph.sh`)

**Completed:** Updated `sandbox_container_name()` to accept an optional service name
argument (defaults to `"app"`). Changed jq query to look up the specific service by
name instead of grabbing the first entry. Updated fallback to derive container name as
`${project_name}-${service}-1`. Updated `sandbox_shell()` to pass `"app"` explicitly
as the spec requires. All 123 tests pass.

---

### Task 9: Remove `sandbox-setup.md` prompt and clean up managed files
**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md, specs/installer.md, specs/updater.md

After the multi-pass prompts are created (Task 3), the old single-pass prompt
`prompts/sandbox-setup.md` should be removed. The managed files list needs to reflect
all current specs: add the three new prompts, `Dockerfile.base`, and remove the old one.

What to do:
- Delete `prompts/sandbox-setup.md`
- Verify `MANAGED_FILES` and `SOURCE_PATHS` in `install.sh` and `update.sh` are correct
  (should already be updated by Tasks 1, 2, 3 — this task is the final verification)
- Ensure the `test_managed_files_in_sync` test still passes
- Add `prompts/templates/` directory creation to `install.sh` if not already present
- Run tests (`./tests/test_ralph.sh`)

---

### Task 10: Add `ralph help retro` topic
**Status:** planned
**Spec:** specs/help-system.md

The spec defines `retro` as a help topic covering post-cycle retrospective guidance. The
current `ralph` script already has `help_retro()` implemented and `retro` is already in
the `ralph_help()` dispatcher. However, it should be verified against the spec and the
help index should include `retro`.

What to do:
- Verify `help_retro()` content covers all spec requirements: when to retro, what to review,
  common failure patterns, where to apply fixes, retro checklist, agent-assisted analysis
  prompt, sanitized feedback prompt
- Verify `help_index()` includes `retro` topic
- Verify `ralph_help()` routes `retro` correctly
- Add test for `ralph help retro` if not present
- Run tests (`./tests/test_ralph.sh`)

**Note:** After reviewing the codebase, the help_retro() function already exists with
comprehensive content. The help_index() already lists retro. This task may be confirmed
as already satisfied — the build agent should verify and mark complete if so.

---

### Task 11: Add test coverage for new sandbox setup features
**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md, specs/sandbox-cli.md

Add tests for the new sandbox setup functionality to ensure correctness.

What to do:
- Add test for `--render-only` flag rejection without existing profile
- Add test that `sandbox_validate_profile()` catches missing required fields
- Add test that `sandbox_validate()` catches structural issues (if feasible
  without Docker)
- Verify managed files test still covers the updated file lists
- Add test for `sandbox_container_name` with service argument (if testable)
- Run tests (`./tests/test_ralph.sh`)

---

## Spec Alignment Notes

### Already Satisfied

The following spec areas are fully implemented in the current codebase:

- **specs/overview.md** — System overview matches current implementation
- **specs/project-structure.md** — Directory layout, config, self-relative paths all implemented
  (project-structure.md lists `prompts/templates/` and `sandbox-preferences.sh` which are covered
  by Tasks 1 and 2)
- **specs/loop-behavior.md** — CLI interface, loop execution, signal detection, logging, error
  handling, ad-hoc prompt mode all implemented
- **specs/plan-mode.md** — Gap-driven planning, plan format, prompt template, iterative planning
  all implemented. Prompt at `prompts/plan.md` matches canonical template.
- **specs/build-mode.md** — Build mode, task selection, plan-type awareness, signals, prompt
  template all implemented. Prompt at `prompts/build.md` matches canonical template.
- **specs/spec-lifecycle.md** — Spec format guidance, no code to implement
- **specs/agent-scripts.md** — Agent script contract fully implemented (amp.sh, claude.sh,
  cline.sh, codex.sh)
- **specs/process-planning.md** — Process planning mode, `--process` flag, PROCESS_DIR config,
  prompt template all implemented
- **specs/incremental-planning.md** — Decomposition ledger, skeleton-first workflow, volume hint,
  phase collapsing all implemented in prompts and ralph script
- **specs/align-specs.md** — Align-specs mode, prerequisites, prompt template, build completion
  nudge, alignment ledger all implemented
- **specs/help-system.md** — Help system with all topics (plan, specs, build, sandbox,
  align-specs, retro) implemented
- **specs/installer.md** — Installer working correctly (pending managed files update)
- **specs/updater.md** — Updater with three-way merge, manifest, originals all implemented
  (pending managed files update)

### Conflicts

None identified. Specs, code, and tests are consistent except for the gaps listed as tasks above.
