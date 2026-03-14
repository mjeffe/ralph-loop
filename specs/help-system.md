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
ralph help plan             # Planning modes and when to use each
ralph help specs            # Writing specs: target-state vs process, best practices
ralph help build            # Build mode behavior, signals, discoveries
ralph help sandbox          # Sandbox lifecycle (existing sandbox_help, moved here)
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

  plan      Planning modes: gap-driven vs sequence-constrained vs prompt, when to use each
  specs     Writing specs: target-state vs process, lifecycle, best practices
  build     Build mode: task selection, signals, mid-implementation guidance
  sandbox   Sandbox lifecycle: setup, daily workflow, troubleshooting
```

## Topic Content

Each topic is a condensed, operational summary — not a copy of the specs. It should
answer "how do I use this?" and "which option do I pick?" without requiring the user
to read the full specification.

### `ralph help plan`

Cover:
- The three planning modes and when to use each
- `ralph plan` — gap-driven planning (compares target-state specs to code, infers tasks)
- `ralph plan --process` — sequence-constrained planning (decomposes human-defined phases into tasks)
- `ralph prompt <file>` — ad-hoc single-job prompts
- How to regenerate: delete `implementation_plan.md` or re-run plan mode
- Discovery/investigation tasks are valid in either planning mode

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

### `ralph help build`

Cover:
- One task per iteration
- Task selection: highest-priority `planned` task
- Build mode is plan-type agnostic — it respects the plan's structure regardless of how it was created
- Exit signals: `COMPLETE` (all done), `REPLAN` (plan needs restructuring)
- Mid-implementation discoveries: spec gaps, new work, blocked tasks

### `ralph help sandbox`

The existing `sandbox_help()` content, moved into the help system. No content
changes — accessed via `ralph help sandbox`.

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

help_sandbox() {
    # existing sandbox_help() content
    cat <<'EOF'
...
EOF
}

ralph_help() {
    local topic="${1:-}"
    case "$topic" in
        "")       help_index ;;
        plan)     help_plan ;;
        specs)    help_specs ;;
        build)    help_build ;;
        sandbox)  help_sandbox ;;
        *)        echo "Unknown help topic: $topic" >&2; echo; help_index ;;
    esac
}
```

## Changes to Existing Specs and Files

### `ralph` script

1. Add `help` as a recognized mode
2. Add `ralph_help` dispatcher and topic functions (`help_plan`, `help_specs`,
   `help_build`, `help_sandbox`)
3. Replace `sandbox_help()` with `help_sandbox()`
4. Remove `ralph sandbox help` — sandbox help is now `ralph help sandbox`
5. Update `usage()` to include `help [topic]` in the modes list

### `specs/loop-behavior.md`

Add `help [topic]` to the CLI interface modes section.

### Installer and Updater

No changes — help text lives in the `ralph` script, which is already a managed file.
