# Implementation Plan

## Summary

Most specs are fully implemented. The remaining gaps are all in `specs/sandbox-setup-prompt.md`:
stack detection, playbook injection into the sandbox setup flow, playbook files themselves, and
installer/updater awareness of the new playbook files.

---

### Task 1: Add detect_stack() and STACK_PLAYBOOK injection to ralph script

**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md

Add the `detect_stack()` function to the `ralph` script and update `sandbox_setup()` to call it,
export `STACK_PLAYBOOK`, and pass it through `prepare_prompt` before invoking the agent.

**What to do:**
- Add the `detect_stack()` function (as specified in the spec) to the ralph script, in the sandbox
  lifecycle section before `sandbox_setup()`.
- In `sandbox_setup()`, before the `prepare_prompt` call, add the stack detection and playbook
  resolution logic:
  ```bash
  STACK=$(detect_stack)
  PLAYBOOK_FILE="$RALPH_DIR/prompts/playbooks/${STACK}.md"
  if [[ -n "$STACK" && -f "$PLAYBOOK_FILE" ]]; then
      export STACK_PLAYBOOK="$PLAYBOOK_FILE"
  else
      export STACK_PLAYBOOK=""
  fi
  ```
- Add tests to `tests/test_ralph.sh` for `detect_stack()` (create temp project dirs with
  indicator files like `artisan`, `composer.json`, `package.json`, etc. and verify correct
  stack identification).

---

### Task 2: Create playbooks directory and initial playbook files

**Status:** complete
**Spec:** specs/sandbox-setup-prompt.md

Create the `prompts/playbooks/` directory and write the initial set of stack playbook files.
The spec says to start with the stacks you use most — at minimum `php-laravel.md` since that's
the most fleshed out in the spec examples.

**What to do:**
- Create `prompts/playbooks/` directory.
- Create `prompts/playbooks/php-laravel.md` following the content guidelines in the spec
  (under 50 lines, covers runtime installation, package manager, framework bootstrap,
  migrations, common extensions, workdir convention, sandbox env overrides, long-running
  processes). Do NOT repeat hard constraints from the core prompt.
- Optionally create additional playbooks (`php.md`, `node.md`, `python.md`, `python-django.md`,
  `rails.md`) if time permits — keep them short and stack-specific.

---

### Task 3: Add playbook files to installer and updater MANAGED_FILES

**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md

Add the playbook files to `MANAGED_FILES` and `SOURCE_PATHS` in both `install.sh` and `update.sh`
so they are installed and tracked for updates. Also ensure the `prompts/playbooks/` directory is
created during installation.

**What to do:**
- Add each playbook file (e.g., `prompts/playbooks/php-laravel.md`) to the `MANAGED_FILES` array
  in both `install.sh` and `update.sh`.
- Add corresponding entries in the `SOURCE_PATHS` associative array in both files.
- The `install_ralph_dir()` function in `install.sh` already does `mkdir -p "$dest_dir"` for each
  file, so the `prompts/playbooks/` directory will be created automatically.
- Run `./tests/test_ralph.sh` to verify the `MANAGED_FILES` sync test still passes.

---

### Task 4: Update project-structure.md with playbooks directory

**Status:** planned
**Spec:** specs/sandbox-setup-prompt.md

Update `specs/project-structure.md` to include the `prompts/playbooks/` directory in both the
Ralph project layout and the parent project layout diagrams.

**What to do:**
- In the "Ralph Project Layout" tree, add under `prompts/`:
  ```
  ├── sandbox-setup.md
  └── playbooks/
      ├── php-laravel.md
      └── ...
  ```
- In the "Parent Project Layout" tree, add the same under `.ralph/prompts/`.
- This is a documentation-only change.
