# Align Specs

## Purpose

After a process-spec-driven migration completes, target-state specs in `${SPECS_DIR}/`
typically describe the pre-migration system. `ralph align-specs` invokes an agent to
update target-state specs so they reflect the post-migration system, using process specs
and the implementation plan as context for design intent — not just observed code behavior.

This mode exists because target-state specs are rarely updated before a migration begins.
Without alignment, future `ralph plan` (gap-driven) runs generate nonsense tasks against
stale specs.

## CLI Interface

```bash
ralph align-specs [max_iterations]
```

`align-specs` is a standalone mode, like `plan` or `build`. It uses the same loop
mechanics: fresh context per iteration, completion signal to exit, same logging and retry
behavior.

## Prerequisites

`ralph align-specs` requires all three of:

1. **`PROCESS_DIR` configured and non-empty** — process specs provide the strategic
   intent, architectural rationale, and the "why" behind the migration.
2. **`${RALPH_HOME}/implementation_plan.md` exists with `Plan Type: process`** — the
   implementation plan provides build notes, decisions made during implementation, and
   evidence that the migration was executed through Ralph's loop.
3. **At least one `complete` task in the plan** — confirms that build work actually
   happened. A plan with only `planned` tasks means the migration hasn't started.

If any prerequisite is missing, exit with an informative error:

- No `PROCESS_DIR`: "align-specs requires process specs. Set PROCESS_DIR in config."
- No plan or wrong plan type: "align-specs requires a process-type implementation plan.
  Run 'ralph plan --process' and 'ralph build' first."
- No completed tasks: "align-specs requires completed build work. Run 'ralph build' first."

These prerequisites prevent misuse as a general-purpose "generate specs from code" tool.
The user must have done the disciplined work (write process specs, plan, build) before
alignment is available.

## Behavior

### Agent Inputs

The agent reads, in order of authority:

1. **Process specs** (`${PROCESS_DIR}/`) — strategic intent, phases, rationale, constraints.
   These explain *why* the system changed and what the migration aimed to achieve.
2. **Implementation plan** (`${RALPH_HOME}/implementation_plan.md`) — what was actually
   built, build notes, discovered prerequisites, decisions made during implementation.
3. **Codebase** — current reality, the ground truth for what the system actually does now.
4. **Existing target-state specs** (`${SPECS_DIR}/`) — what needs updating. The specs
   index (`${SPECS_DIR}/README.md`) maps what specs exist.

### Agent Responsibilities

1. **Read all inputs** — process specs, implementation plan, existing target-state specs
   index, and `AGENTS.md`.
2. **Identify stale specs** — determine which target-state specs describe behavior that
   was changed by the process-spec migration.
3. **Update stale specs** — revise spec content to reflect the post-migration system.
   Use process specs for intent and rationale, the implementation plan for build decisions,
   and the codebase for current reality.
4. **Create new specs** — when the migration introduced components or features that have
   no existing target-state spec, create new spec files following the project's existing
   spec conventions (format, granularity, naming).
5. **Remove obsolete specs** — when the migration fully replaced a feature and no trace
   of the old behavior remains, remove the spec file.
6. **Update the specs index** — keep `${SPECS_DIR}/README.md` current with any additions
   or removals.
7. **Commit** with a descriptive commit message.
8. **Output completion signal** when alignment is complete.

### Scope Constraints

- Only update specs for areas covered by the process spec phases. Do not opportunistically
  rewrite unrelated specs.
- Follow existing spec file boundaries. If a migration touched behavior described in
  `specs/auth.md`, update that file — do not reorganize into new files unless the old
  structure no longer makes sense.
- Preserve spec sections that were not affected by the migration.
- Do not implement code changes. This mode only updates spec files.

### What Good Aligned Specs Look Like

Agent-generated spec updates should capture:
- **What the system does now** (from codebase survey)
- **Why it does it that way** (from process specs — architectural rationale, constraints)
- **What decisions were made** (from implementation plan — build notes, assumptions)
- **What the constraints are** (from process specs and build discoveries)

This is richer than pure code-survey specs because the process specs and plan provide the
design intent that code alone cannot express.

### Iterative Alignment

For large migrations with many affected specs, the agent may need multiple iterations.
The agent uses its judgment on how to break up the work. The existing target-state specs
provide a natural work queue — each spec file is a unit of work.

The agent should not output `<promise>COMPLETE</promise>` until all affected specs have
been reviewed and updated.

## Completion

The agent outputs `<promise>COMPLETE</promise>` when:
- All target-state specs affected by the process-spec migration have been reviewed
- Stale specs have been updated, new specs created, obsolete specs removed
- `${SPECS_DIR}/README.md` is current
- All changes are committed

## Build Completion Nudge

When a `ralph build` run ends with all tasks complete on a `Plan Type: process` plan,
ralph prints a prominent reminder after the session summary:

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║  Process-plan build complete. Target-state specs may need updating.            ║
║  Run: ralph align-specs                                                       ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

This nudge appears only when:
- The exit reason is COMPLETE (all tasks done)
- The plan type is `process`

It is printed to both the terminal and the session log, after the session summary.

### Implementation

In the `ralph` script, after writing the session summary and before exiting, check:

```bash
if [[ "$MODE" == "build" && "$EXIT_REASON" == "COMPLETE" ]]; then
    plan_type=$(grep -m1 '^Plan Type:' "$RALPH_HOME/implementation_plan.md" 2>/dev/null \
        | sed 's/^Plan Type:[[:space:]]*//')
    if [[ "$plan_type" == "process" ]]; then
        # print nudge banner
    fi
fi
```

## Prompt Template

The prompt lives at `prompts/align-specs.md`. See the Prompt Template section below for
the canonical template.

```markdown
You are an expert software architect working in Ralph align-specs mode.

Each iteration starts with **fresh context** — you have no memory of prior iterations.

## Purpose

Update target-state specs in `${SPECS_DIR}/` to reflect the current system after a
process-spec-driven migration. Use the process specs for design intent, the
implementation plan for build decisions, and the codebase for current reality.

## Context

- **Process Specifications:** ${PROCESS_DIR}
- **Implementation Plan:** ${RALPH_HOME}/implementation_plan.md
- **Target-State Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Project instructions:** AGENTS.md

## Workflow

1. **Read inputs** — Study `AGENTS.md`, process specs in `${PROCESS_DIR}/`, the
   implementation plan at `${RALPH_HOME}/implementation_plan.md` (including build notes
   and completed task details), and the specs index at `${SPECS_DIR}/README.md`.
2. **Identify affected specs** — Determine which target-state specs describe behavior
   that was changed by the migration. List them.
3. **Survey the codebase** — For each affected area, understand the current post-migration
   state.
4. **Update specs** — For each affected spec:
   - Revise content to reflect current system behavior
   - Incorporate design rationale from process specs (the "why")
   - Incorporate relevant build decisions from the implementation plan
   - Preserve sections not affected by the migration
   - If a spec is entirely obsolete (feature fully replaced, no trace remains), remove it
5. **Create new specs** — If the migration introduced components with no existing spec,
   create new spec files following the project's existing conventions.
6. **Update the index** — Keep `${SPECS_DIR}/README.md` current with any additions or
   removals.
7. **Commit** all changes with a descriptive commit message.
8. **If alignment is complete**, output the completion signal (see Exit Signal).
9. **If alignment is not yet complete**, stop without a signal — the loop will start
   another iteration.

## Exit Signal

When alignment is complete, output exactly `<promise>COMPLETE</promise>` — the loop
cannot exit without it.

Alignment is complete when:
- All target-state specs affected by the migration have been reviewed and updated
- New specs have been created for components introduced by the migration
- Obsolete specs have been removed
- `${SPECS_DIR}/README.md` is current
- All changes are committed

## Scope

- Only update specs for areas covered by process spec phases. Do not rewrite unrelated
  specs.
- Follow existing spec file boundaries and conventions.
- Preserve spec sections not affected by the migration.
- **Do not implement code changes.** This mode only updates spec files.

## Spec Quality

Updated and new specs should capture:
- **What** the system does now (from codebase)
- **Why** it does it that way (from process specs)
- **Decisions made** during implementation (from the implementation plan's build notes)
- **Constraints** that apply (from process specs and build discoveries)

Match the format and depth of the project's existing specs.

Begin alignment now.
```

## Changes to Existing Specs and Files

### `ralph` script

1. Add `align-specs` as a recognized mode
2. Add prerequisite checks (PROCESS_DIR, plan type, completed tasks)
3. Use `prompts/align-specs.md` as the prompt template
4. Add build-completion nudge after session summary for process-plan builds

### `specs/loop-behavior.md`

Add `align-specs [max_iterations]` to the CLI modes section.

### `specs/overview.md`

Add a brief mention of align-specs in the workflow section as an optional post-migration
step.

### `specs/spec-lifecycle.md`

Add guidance in the "When to Update Specs" section about using `ralph align-specs` after
process-spec migrations.

### `specs/help-system.md`

Add align-specs guidance to the `ralph help specs` topic.

### Installer and Updater

Add `prompts/align-specs.md` to managed files.
