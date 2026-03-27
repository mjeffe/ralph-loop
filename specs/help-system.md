# Help System

## Purpose

Provide operational guidance for Ralph users directly from the CLI. When Ralph is
installed into a parent project, the detailed specs stay in the ralph-loop repo — the
help system makes key guidance discoverable without requiring users to find or read
those specs.

## CLI Interface

```bash
ralph help                  # List available topics with one-line descriptions
ralph help <topic>          # Show detailed help for a topic
ralph help specs            # Writing specs: target-state vs process, best practices
ralph help plan             # Planning modes and when to use each
ralph help build            # Build mode behavior, signals, discoveries
ralph help prompt           # Ad-hoc prompts: custom loop workflows
ralph help sandbox          # Sandbox lifecycle: setup, daily workflow, troubleshooting
ralph help align-specs      # Updating target-state specs after process migrations
ralph help retro            # Post-cycle retrospective guidance
```

`ralph --help` and `ralph -h` continue to show the short usage message (existing
behavior). `ralph help` is a separate mode that shows longer-form guidance.

### Unknown Topic

```
ralph help foo
```

Prints: `Unknown help topic: foo` followed by the topic list (same as `ralph help`).

## Topic Index

`ralph help` with no arguments prints a topic list:

```
Ralph Help — run 'ralph help <topic>' for details.

  specs        Writing specs: target-state vs process, lifecycle, best practices
  plan         Planning modes: gap-driven vs sequence-constrained vs prompt, when to use each
  build        Build mode: task selection, signals, mid-implementation guidance
  prompt       Ad-hoc prompts: when and how to use ralph prompt
  sandbox      Sandbox lifecycle: setup, daily workflow, troubleshooting
  align-specs  Updating target-state specs after process-spec migrations
  retro        Post-cycle retrospective: reviewing results and improving inputs
```

## Topic Content

Each topic is a condensed, operational summary — not a copy of the specs. It should
answer "how do I use this?" and "which option do I pick?" without requiring the user
to read the full specification.

### `ralph help specs`

Cover:
- **Target-state specs** — describe what the system should be (behavior, APIs,
  constraints). You write what you want; the planner figures out what's missing.
  This drives **gap-driven planning** (`ralph plan`), where the planner compares
  your spec to the current code and generates tasks to close the gaps.
- **Process specs** — describe how to get there (phased migrations, ordered
  refactors, incremental rollouts). You define the phases and their ordering; the
  planner decomposes each phase into tasks. This drives **sequence-constrained
  planning** (`ralph plan --process`), where the planner works within your
  human-defined structure.
- Decision table: phases with ordering → process spec; no sequencing → target-state
  spec; single coherent job → ad-hoc prompt
- Target-state specs live in `SPECS_DIR`, process specs live in `PROCESS_DIR`
- Process spec lifecycle: active specs in `PROCESS_DIR`, archive completed specs to
  a subdirectory (e.g., `archive/`). Only top-level `*.md` files are read.
- Brief spec-writing tips: be specific, one feature per spec, include test criteria

### `ralph help plan`

Cover:
- The three planning modes and when to use each
- `ralph plan` — gap-driven planning (compares target-state specs to code, infers tasks)
- `ralph plan --process` — sequence-constrained planning (decomposes human-defined phases into tasks)
- `ralph prompt <file>` — ad-hoc prompts (see `ralph help prompt`)
- How to regenerate: delete `implementation_plan.md` or re-run plan mode
- Discovery/investigation tasks are valid in either planning mode

### `ralph help build`

Cover:
- One task per iteration
- Task selection: highest-priority `planned` task
- Build mode is plan-type agnostic — it respects the plan's structure regardless of how it was created
- Exit signals: `COMPLETE` (all done), `REPLAN` (plan needs restructuring)
- Mid-implementation discoveries: spec gaps, new work, blocked tasks

### `ralph help prompt`

Cover:
- `ralph prompt` runs a custom prompt through the iteration loop — no planner,
  no task selection, no implementation plan. The prompt file replaces the
  built-in plan/build prompts with a custom workflow while still leveraging the
  loop's iteration, logging, and exit-signal machinery.
- When to use: multi-iteration work that doesn't fit the planner's
  task-decomposition model (spec review, test analysis, document assembly,
  codebase audits), or quick one-shot jobs
- Writing multi-iteration prompts: progress tracking files for durable memory
  across iterations, fresh-context reminders, iteration sizing guidance, clear
  modification rules
- Exit signal requirement: the prompt **must** instruct the agent to output
  `<promise>COMPLETE</promise>` when done — this is the only way the loop
  knows to stop. Without it, ralph iterates until `max_iterations` is reached.
- Point users to the built-in prompts in `.ralph/prompts/` as starting templates

### `ralph help sandbox`

Cover:
- Multi-container architecture: the app container runs the project code;
  service containers (database, cache, mail, etc.) run in their own
  containers using official Docker images
- Setup workflow: `ralph sandbox setup` runs a multi-pass pipeline —
  analysis → generation → validation — to produce the sandbox configuration
- `--render-only` flag: edit `project-profile.json` to fix wrong detections,
  then run `ralph sandbox setup --render-only --force` to regenerate the
  sandbox from the corrected profile without re-analyzing
- `sandbox-preferences.sh`: how to customize the sandbox environment — edit
  the script with extra packages or configuration, then rebuild with
  `ralph sandbox up`
- Multi-checkout port collisions: when running multiple checkouts of the
  same project, remap exposed ports in each checkout's `.env` to avoid
  conflicts
- Resetting vs regenerating: `setup` regenerates configuration files
  (Dockerfile, docker-compose.yml, entrypoint.sh); `reset` wipes runtime
  data (Docker volumes) but leaves configuration files untouched
- Troubleshooting: the base image is auto-refreshed on `ralph sandbox up`,
  so changes from `ralph update` take effect automatically — no manual
  image rebuild needed

The troubleshooting section should include an entry like:

```
  Multiple checkouts of the same project?
    SANDBOX_NAME is auto-derived from the checkout path to avoid collisions.
    Override it in .ralph/sandbox/.env if the auto-generated name is not suitable.
```

### `ralph help retro`

Cover:
- When to do a retro: after every significant plan+build cycle, especially
  when builds struggled, blocked frequently, or triggered REPLAN
- What to review: session logs (iterations per task, failures, retries),
  implementation plan (blocked tasks, spec gap notes, conflict notes, tasks
  added during build, task sizing), git history (revert/fixup commits),
  AGENTS.md effectiveness (test commands, conventions), spec quality
  (misinterpretations, unclear verification criteria)
- Common failure patterns and where to fix them: wrong test commands →
  AGENTS.md, unclear done state → spec Verify blocks, agent scope creep →
  spec constraints, repeated mistakes → AGENTS.md pitfalls section
- Where to apply fixes: AGENTS.md (operational), specs (behavioral),
  prompts (structural — change rarely)
- A checklist for working through the retro process
- Agent-assisted analysis: a sample prompt users can paste into an
  interactive agent session to walk through the retro; explains how to
  identify session log files for a cycle (filenames encode mode and
  timestamp, a cycle may span multiple build sessions)
- Sharing feedback with ralph-loop: a sanitization prompt that generates
  a structured summary stripped of project-specific details (no paths,
  domain names, code, or team names); output formatted as a GitHub issue

## Implementation

Help text is defined as functions in the `ralph` script (same pattern as the existing
`sandbox_help()` function). No external files.

```bash
help_plan() {
    cat <<'EOF'
...
EOF
}

help_specs() {
    cat <<'EOF'
...
EOF
}

help_build() {
    cat <<'EOF'
...
EOF
}

help_prompt() {
    cat <<'EOF'
...
EOF
}

help_sandbox() {
    cat <<'EOF'
...
EOF
}

ralph_help() {
    local topic="${1:-}"
    case "$topic" in
        "")          help_index ;;
        specs)       help_specs ;;
        plan)        help_plan ;;
        build)       help_build ;;
        prompt)      help_prompt ;;
        sandbox)     help_sandbox ;;
        align-specs) help_align_specs ;;
        retro)       help_retro ;;
        *)           echo "Unknown help topic: $topic" >&2; echo; help_index ;;
    esac
}
```

## Changes to Existing Specs and Files

### `ralph` script

1. Add `help` as a recognized mode
2. Add `ralph_help` dispatcher and topic functions (`help_specs`, `help_plan`,
   `help_build`, `help_prompt`, `help_sandbox`, `help_align_specs`, `help_retro`)
3. Replace `sandbox_help()` with `help_sandbox()`
4. Remove `ralph sandbox help` — sandbox help is now `ralph help sandbox`
5. Update `usage()` to include `help [topic]` in the modes list

### `specs/loop-behavior.md`

Add `help [topic]` to the CLI interface modes section.

### Installer and Updater

No changes — help text lives in the `ralph` script, which is already a managed file.
