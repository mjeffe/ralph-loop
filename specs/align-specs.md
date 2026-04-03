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

## Alignment Ledger

The alignment ledger (`${RALPH_HOME}/alignment_ledger.md`) tracks which target-state specs
have been reviewed and updated. It serves the same role as `implementation_plan.md` does
for build mode — persistent memory across fresh-context iterations.

The ledger is a separate file from the implementation plan because the two have independent
lifecycles. `ralph plan` regenerates `implementation_plan.md` from scratch; alignment
progress must survive that. The typical lifecycle is sequential and non-overlapping:

```
ralph plan --process  →  creates implementation_plan.md
ralph build           →  consumes/updates implementation_plan.md
ralph align-specs     →  creates/updates alignment_ledger.md
ralph plan            →  regenerates implementation_plan.md (ledger untouched)
```

### Ledger Format

```markdown
# Alignment Ledger

Process Specs: specs/process/
Created: YYYY-MM-DD

## Affected Specs

### 1. specs/loop-behavior.md
Status: complete
Changes: Added align-specs to CLI modes section
Commit: a1b2c3d

### 2. specs/overview.md
Status: complete
Changes: Added align-specs as optional post-migration step
Commit: a1b2c3d

### 3. specs/spec-lifecycle.md
Status: planned
Scope: Add guidance on using ralph align-specs after process migrations

### 4. specs/auth.md
Status: blocked
Reason: Process specs contradict on auth delegation approach — needs human clarification

### 5. specs/notifications.md
Status: new
Scope: Migration introduced notification system with no existing spec — create from scratch
```

### Ledger Lifecycle

**First iteration (no ledger exists):**

1. Agent reads all inputs (process specs, plan, existing target-state specs)
2. Surveys which specs are affected by the migration
3. Verifies completeness by grepping specs for key terms from the process specs
4. Creates the alignment ledger with all affected specs listed
5. Begins aligning specs, marking completed ones in the ledger
6. Commits updated spec files + ledger

**Subsequent iterations (ledger exists):**

1. Agent reads the ledger — knows exactly what's done and what remains
2. Picks the next `planned` spec(s), aligns them, updates ledger status
3. Commits updated spec files + ledger

**Already complete (ledger exists, no `planned` specs remain):**

1. Agent reads the ledger, confirms nothing remains
2. Outputs `<promise>COMPLETE</promise>`

This matches how build mode handles an all-complete plan — the agent reads state, confirms
there's no work, and exits. One cheap iteration, no bash-level pre-checks needed.

### Status Values

- `planned` — identified as affected, not yet aligned
- `complete` — reviewed and updated (or confirmed unchanged), committed
- `blocked` — cannot be aligned without human intervention (document reason)
- `new` — migration introduced a component with no existing spec, needs creation

### Blocked Specs

When the agent encounters irreconcilable conflicts (e.g., process specs contradict each
other on a design decision, or the codebase diverged from process spec intent in a way
that requires a human judgment call), it marks the spec as `blocked` in the ledger with
a reason.

The agent continues aligning non-blocked specs. When all non-blocked specs are `complete`
and only `blocked` specs remain, the agent outputs `<promise>COMPLETE</promise>`. The
human reviews the ledger, resolves the conflicts, and re-runs if needed.

This keeps blocking at the task level (in the ledger) rather than introducing a new
loop-level signal, matching how build mode handles blocked tasks in the implementation
plan.

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
5. **Alignment ledger** (`${RALPH_HOME}/alignment_ledger.md`) — if it exists, the
   persistent record of alignment progress from prior iterations.

### Agent Responsibilities

1. **Read all inputs** — process specs, implementation plan, existing target-state specs
   index, alignment ledger (if present), and `AGENTS.md`.
2. **Create or read the alignment ledger** — on the first iteration, survey all inputs
   and create the ledger listing all affected specs. On subsequent iterations, read the
   existing ledger to determine remaining work.
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
7. **Update the alignment ledger** — mark completed specs, note changes and commit hashes.
8. **Commit** all changes (spec files + ledger) with a descriptive commit message. One
   commit per iteration containing all spec files aligned in that iteration plus the
   updated ledger.
9. **Output completion signal** when alignment is complete (see Completion).

### Scope Constraints

- Only update specs for areas covered by the process spec phases. Do not opportunistically
  rewrite unrelated specs. Grep verification is a completeness check, not a license to
  expand scope — incidental references to concepts changed by a process-spec phase are
  in scope, but unrelated mentions are not.
- Follow existing spec file boundaries. If a migration touched behavior described in
  `specs/auth.md`, update that file — do not reorganize into new files unless the old
  structure no longer makes sense.
- Preserve spec sections that were not affected by the migration.
- Do not implement code changes. This mode only updates spec files and the alignment
  ledger.

### What Good Aligned Specs Look Like

Agent-generated spec updates should capture:
- **What the system does now** (from codebase survey)
- **Why it does it that way** (from process specs — architectural rationale, constraints)
- **What decisions were made** (from implementation plan — build notes, assumptions)
- **What the constraints are** (from process specs and build discoveries)

This is richer than pure code-survey specs because the process specs and plan provide the
design intent that code alone cannot express.

### Iterative Alignment

For large migrations with many affected specs, the agent uses multiple iterations. The
alignment ledger provides the persistent work queue — the agent uses its judgment on how
many specs to align per iteration (small specs may be batched, large ones get a solo
iteration).

Each iteration follows the same pattern: read the ledger, pick `planned` work, align
specs, update the ledger, commit.

## Completion

The agent outputs `<promise>COMPLETE</promise>` when:
- All `planned` and `new` specs in the alignment ledger have been processed (moved to
  `complete` or `blocked`)
- `${SPECS_DIR}/README.md` is current
- All changes are committed
- The ledger reflects final state

Blocked specs do not prevent completion. The agent completes all actionable work and
leaves the ledger as a record of what remains for human resolution.

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

In `run_loop()`, after writing the session summary and before the `exit` call. All
needed state (`$exit_reason`, `$MODE`) is already local to `run_loop()`:

```bash
if [[ "$MODE" == "build" && "$exit_reason" == "completion signal" ]]; then
    plan_type=$(grep -m1 '^Plan Type:' "$RALPH_HOME/implementation_plan.md" 2>/dev/null \
        | sed 's/^Plan Type:[[:space:]]*//')
    if [[ "$plan_type" == "process" ]]; then
        log ""
        log "╔══════════════════════════════════════════════════════════════════════════════════╗"
        log "║  Process-plan build complete. Target-state specs may need updating.            ║"
        log "║  Run: ralph align-specs                                                       ║"
        log "╚══════════════════════════════════════════════════════════════════════════════════╝"
    fi
fi
exit "$exit_code"
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
- **Alignment Ledger:** ${RALPH_HOME}/alignment_ledger.md
- **Target-State Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Project instructions:** AGENTS.md

## Workflow

### First Iteration (no alignment ledger exists)

1. **Read inputs** — Study `AGENTS.md`, process specs in `${PROCESS_DIR}/`, the
   implementation plan at `${RALPH_HOME}/implementation_plan.md` (including build notes
   and completed task details), and the specs index at `${SPECS_DIR}/README.md`.
2. **Identify affected specs** — Determine which target-state specs describe behavior
   that was changed by the migration. Include specs that need updating, new specs that
   need creating, and obsolete specs that should be removed.
3. **Verify completeness with grep** — Build a short list of concrete, high-signal stale
   terms from the process specs and implementation plan: old/removed identifiers, column
   names, filenames, config keys, API fields, and renamed concepts. Prefer exact tokens
   (e.g., `realm_id`, `realms.csv`) over broad domain words. Search all spec files under
   `${SPECS_DIR}/` for those terms. Treat each match as a **review candidate**, not an
   automatic inclusion — add a spec to the affected list only if the match shows that
   its behavior, terminology, examples, or constraints need updating due to a
   process-spec phase. This catches specs that *incidentally reference* changed concepts,
   not just specs that are *about* them.
4. **Create the alignment ledger** — Write `${RALPH_HOME}/alignment_ledger.md` listing
   all affected specs with status `planned` (or `new` for specs that need creating).
5. **Begin alignment** — Survey the codebase for affected areas and start updating specs.
   For each spec you complete, update its ledger entry to `complete` with a brief summary
   of changes.
6. **Commit** all changes (spec files + ledger) with a descriptive commit message.
7. **If all specs are aligned**, output the completion signal (see Exit Signal).
8. **If work remains**, stop without a signal — the loop will start another iteration.

### Subsequent Iterations (alignment ledger exists)

1. **Read the alignment ledger** at `${RALPH_HOME}/alignment_ledger.md` to determine
   what work remains.
2. **If no `planned` or `new` specs remain**, output the completion signal.
3. **Pick the next spec(s)** — select `planned` or `new` entries from the ledger. Use
   your judgment on how many to tackle this iteration (small specs may be batched, large
   ones deserve a solo iteration).
4. **Read inputs for context** — process specs, implementation plan, and the relevant
   sections of the codebase.
5. **Align the selected specs** — update, create, or remove spec files as needed.
6. **Update the ledger** — mark completed specs, note changes and commit hash.
7. **Update the specs index** if any specs were added or removed.
8. **Commit** all changes (spec files + ledger) with a descriptive commit message.
9. **If all specs are aligned**, output the completion signal.
10. **If work remains**, stop without a signal.

## Exit Signal

When alignment is complete, output exactly `<promise>COMPLETE</promise>` — the loop
cannot exit without it.

Alignment is complete when:
- All `planned` and `new` specs in the ledger have been processed
- Stale specs have been updated, new specs created, obsolete specs removed
- `${SPECS_DIR}/README.md` is current
- All changes are committed
- The ledger reflects final state

Blocked specs do not prevent completion. Complete all actionable work and leave the
ledger as a record for human review.

## Blocked Specs

If you encounter irreconcilable conflicts — process specs contradict each other, the
codebase diverged from process spec intent in ways requiring human judgment, or you
lack enough information to write an accurate spec — mark the spec as `blocked` in the
ledger with a clear reason. Continue aligning non-blocked specs.

## Scope

- Only update specs for areas covered by process spec phases. Do not rewrite unrelated
  specs. Grep verification is a completeness check, not a license to expand scope —
  incidental references to concepts changed by a process-spec phase are in scope, but
  unrelated mentions are not.
- Follow existing spec file boundaries and conventions.
- Preserve spec sections not affected by the migration.
- **Do not implement code changes.** This mode only updates spec files and the ledger.

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
4. Add build-completion nudge inside `run_loop()` before `exit`

### `specs/loop-behavior.md`

Add `align-specs [max_iterations]` to the CLI modes section.

### `specs/overview.md`

Add a brief mention of align-specs in the workflow section as an optional post-migration
step.

### `specs/spec-lifecycle.md`

Add guidance in the "When to Update Specs" section about using `ralph align-specs` after
process-spec migrations.

### `specs/help-system.md`

1. Add `align-specs` as a new help topic (`ralph help align-specs`) covering:
   - Purpose: updating target-state specs after process-spec migrations
   - Prerequisites (PROCESS_DIR, process-type plan, completed tasks)
   - The alignment ledger: what it is, how to reset (delete and re-run)
   - Workflow: runs iteratively, creates ledger on first iteration, picks up where it left off
   - Blocked specs: resolved by human, then re-run
2. Add a brief mention of `ralph align-specs` to the `ralph help specs` topic under
   spec maintenance.

### Installer and Updater

Add `prompts/align-specs.md` to managed files.
