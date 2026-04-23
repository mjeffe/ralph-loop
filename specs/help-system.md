# Help System

## Purpose

Provide operational guidance for Ralph users directly from the CLI. When Ralph is
installed into a parent project, the detailed specs stay in the ralph-loop repo — the
help system makes key guidance discoverable without requiring users to find or read
those specs.

## CLI Interface

```bash
ralph help                  # Overview + list of help topics
ralph help <topic>          # Show detailed help for a topic
ralph help overview         # How Ralph works: core cycle, all modes, getting started
ralph help specs            # Writing specs: target-state vs process, best practices
ralph help plan             # Planning modes and when to use each
ralph help build            # Build mode behavior, signals, discoveries
ralph help prompt           # Ad-hoc prompts: custom loop workflows
ralph help sandbox          # Sandbox lifecycle: setup, daily workflow, troubleshooting
ralph help align-specs      # Updating target-state specs after process migrations
ralph help retro            # Post-cycle retrospective guidance
```

`ralph --help` and `ralph -h` show the short CLI usage message with a pointer to
`ralph help` for the overview and guides. `ralph help` is a separate mode that shows
the overview followed by the topic index.

### Unknown Topic

```
ralph help foo
```

Prints: `Unknown help topic: foo` followed by the topic list (same as `ralph help`).

## Overview and Topic Index

`ralph help` with no arguments shows the overview (`lib/help/overview.txt`) followed by
the topic index (`lib/help/index.txt`). The overview covers the core cycle, all modes at
a glance, a "which mode do I use?" decision guide, key concepts, and getting started
instructions. The topic index lists all available help topics with one-line descriptions.

The overview does not contain a copy of the topic index — the dispatcher concatenates
the two files programmatically to avoid duplication.

`ralph help overview` also works as a standalone topic (shows the overview without the
appended index).

## Topic Content

Each topic is a condensed, operational summary — not a copy of the specs. It should
answer "how do I use this?" and "which option do I pick?" without requiring the user
to read the full specification.

### `ralph help overview`

Cover:
- What Ralph is (one sentence)
- The core cycle: specs → plan → build → test → retro → repeat
- All modes at a glance with one-line descriptions
- "Which mode do I use?" decision guide (situation → mode → command)
- Why plan and build are separate (context efficiency, durable memory, focus)
- Key concepts: specs, process specs, implementation plan, AGENTS.md, cross-cutting
  constraints
- Getting started walkthrough (install, configure, write spec, plan, build, commit,
  review)

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
- Brief spec-writing tips: be specific, one feature per spec, include test criteria,
  express actionable instructions as phases/steps (not decisions in orienting sections)

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
- `sandbox-setup.md`: a user-owned file for documenting sandbox fixes and
  bootstrap steps. Created by `sandbox setup`, never overwritten. Reference
  it from `AGENTS.md` if you want agents to act on the notes.
- `ralph sandbox name [service]`: prints the resolved container name for
  use with standard docker commands. Include a "Docker Tips" section
  showing common recipes using `$(ralph sandbox name)` — copy files into
  the container, tail logs, exec commands, inspect stats.
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

Help topic content lives in plain text files under `lib/help/`. The `ralph_help()`
dispatcher stays in the `ralph` script and uses file-based dispatch — no sourcing
needed.

### Directory structure

```
lib/
└── help/
    ├── index.txt        # Topic list (appended after overview by dispatcher)
    ├── overview.txt     # Overview (shown by `ralph help` and `ralph help overview`)
    ├── specs.txt
    ├── plan.txt
    ├── build.txt
    ├── prompt.txt
    ├── sandbox.txt
    ├── align-specs.txt
    └── retro.txt
```

### Dispatcher in `ralph`

```bash
ralph_help() {
    local topic="${1:-}"
    local help_dir="$RALPH_DIR/lib/help"
    if [[ -z "$topic" ]]; then
        cat "$help_dir/overview.txt"
        echo
        cat "$help_dir/index.txt"
    elif [[ -f "$help_dir/${topic}.txt" ]]; then
        cat "$help_dir/${topic}.txt"
    else
        echo "Unknown help topic: $topic" >&2; echo
        cat "$help_dir/index.txt"
    fi
}
```

`ralph help` with no arguments shows the overview followed by the topic index
(concatenated programmatically — no duplication). `ralph help overview` shows the
overview alone via the standard file-based dispatch.

Adding a new help topic requires only dropping a new `.txt` file into `lib/help/`
and updating `index.txt` — no code changes to the dispatcher.

### CLI usage message

The short `usage()` function (shown by `ralph --help`, `ralph -h`, or bare `ralph`)
is CLI synopsis, not help content. It ends with a pointer to the help system:
`Run 'ralph help' for an overview and guides.` followed by the project URL.

## Changes to Existing Specs and Files

### `ralph` script

1. Add `help` as a recognized mode
2. Add `ralph_help` dispatcher (file-based, ~10 lines) — concatenates overview + index
   for bare `ralph help`
3. Remove all `help_*()` heredoc functions — content moves to `lib/help/*.txt`
4. Remove `ralph sandbox help` — sandbox help is now `ralph help sandbox`
5. Update `usage()` to include `help [topic]` in the modes list, add pointer to
   `ralph help` and project URL at the bottom

### `specs/loop-behavior.md`

Add `help [topic]` to the CLI interface modes section.

### Installer and Updater

Add all `lib/help/*.txt` files (including `overview.txt`) to `MANAGED_FILES` and
`SOURCE_PATHS` in both `install.sh` and `update.sh`. These are core (upstream-managed)
files — users are not expected to customize help content.
