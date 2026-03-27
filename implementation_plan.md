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
**Status:** planned
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

---

### Task 3: Create multi-pass sandbox prompt templates
**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md

The specs call for three separate prompt files replacing the single `prompts/sandbox-setup.md`:
- `prompts/sandbox-analyze.md` — Pass 1: project analysis → project profile JSON
- `prompts/sandbox-render.md` — Pass 2: generate sandbox files from profile
- `prompts/sandbox-repair.md` — Pass 3: fix validation failures

What to do:
- Create `prompts/sandbox-analyze.md` following the spec's guidance for Pass 1 (analysis
  prompt content — project scanning, profile schema, output format)
- Create `prompts/sandbox-render.md` following the spec's guidance for Pass 2 (generation
  prompt — reads profile, generates Dockerfile, entrypoint.sh, docker-compose.yml,
  .env.example)
- Create `prompts/sandbox-repair.md` following the spec's guidance for Pass 3 (repair
  prompt — reads validation failures and generated files, makes targeted fixes)
- Keep `prompts/sandbox-setup.md` for now (it will be removed when managed files are updated)
- Add `prompts/sandbox-analyze.md`, `prompts/sandbox-render.md`, and
  `prompts/sandbox-repair.md` to `MANAGED_FILES` and `SOURCE_PATHS` in both `install.sh`
  and `update.sh`
- Remove `prompts/sandbox-setup.md` from `MANAGED_FILES` and `SOURCE_PATHS` in both
  `install.sh` and `update.sh`
- Run tests (`./tests/test_ralph.sh`)

**Note:** The prompt content should be derived from the detailed specifications in
`specs/sandbox-setup-prompt.md`. The analyze prompt includes sources to read, decision rules,
and the profile schema. The render prompt includes hard constraints, file responsibilities,
and appendices for git credentials, YAML syntax, idempotency, and non-interactive builds.
The repair prompt receives validation failures and asks for targeted fixes.

---

### Task 4: Implement `sandbox_validate_profile()` and `sandbox_validate()` in `ralph`
**Status:** planned
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

---

### Task 5: Rewrite `sandbox_setup()` for multi-pass pipeline with `--render-only`
**Status:** planned
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

---

### Task 6: Update `sandbox_up()` with base image auto-refresh
**Status:** planned
**Spec:** specs/sandbox-cli.md

The spec requires `sandbox_up()` to auto-refresh the base image on every invocation by
copying `Dockerfile.base` and `sandbox-preferences.sh` from managed sources and rebuilding
`ralph-sandbox-base`. The current implementation does not do this.

What to do:
- Add base image auto-refresh logic to `sandbox_up()` before `docker compose up`:
  ```
  cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$RALPH_DIR/sandbox/Dockerfile.base"
  cp "$RALPH_DIR/sandbox-preferences.sh" "$RALPH_DIR/sandbox/sandbox-preferences.sh"
  docker build -t ralph-sandbox-base -f "$RALPH_DIR/sandbox/Dockerfile.base" "$RALPH_DIR/sandbox/"
  ```
- Run tests (`./tests/test_ralph.sh`)

---

### Task 7: Fix `sandbox_reset()` to match spec
**Status:** planned
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

---

### Task 8: Fix `sandbox_container_name()` to accept service name argument
**Status:** planned
**Spec:** specs/sandbox-cli.md

The spec shows `sandbox_container_name()` takes a service argument (e.g., `sandbox_container_name "app"`),
but the current implementation takes no arguments.

What to do:
- Update `sandbox_container_name()` to accept an optional service name argument
- Update the call in `sandbox_shell()` to pass `"app"`
- Run tests (`./tests/test_ralph.sh`)

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
