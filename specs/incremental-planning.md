# Incremental Process Planning

## Purpose

Process planning (`ralph plan --process`) instructs the agent to read all process specs,
all target-state specs, survey the codebase, and decompose every phase into build-sized
tasks. For projects with large spec volumes (e.g., 25 files / 400+ KB of process specs),
this exceeds what a single agent iteration can hold in context.

The multi-iteration escape hatch exists (agent stops without `<promise>COMPLETE</promise>`,
loop starts a new iteration), but it has no decomposition cursor. Each fresh iteration
re-reads all specs and tries to figure out where it left off. Iteration N burns more
context than iteration N-1, not less. The result is degraded planning quality or outright
failure on large projects.

This spec defines three composable mechanisms that enable reliable incremental process
planning, plus a plan compaction convention that keeps the plan file manageable for build
agents on large projects.

See `specs/process-planning.md` for the base process planning specification. Everything
in that spec remains in effect; this spec extends it for large-volume scenarios.

## Decomposition Ledger

Add a `## Decomposition Progress` section to the plan file. The agent records which spec
files have been fully decomposed:

```markdown
## Decomposition Progress

| Spec File | Status | Iteration |
|-----------|--------|-----------|
| cross-cutting.md | decomposed | 1 |
| resource-01-announcements.md | decomposed | 2 |
| resource-02-admin-users.md | decomposed | 2 |
| resource-03-eypr-narrative.md | pending | - |
| resource-04-eypr-data.md | pending | - |
```

The ledger is the resumable work queue. On each iteration the agent reads it, skips files
marked `decomposed`, and picks the next `pending` file(s).

The ledger is populated during the skeleton pass (see below) and updated as each spec is
decomposed.

### Regeneration

When regenerating a plan that already has decomposition progress, reset all ledger entries
to `pending`. Regeneration implies re-assessment — the agent re-decomposes each spec
against the current codebase and current specs. Previously completed tasks that survive
revalidation (per the regeneration rules in `specs/process-planning.md`) are preserved in
the plan body, but the ledger drives fresh decomposition passes over each spec.

## Skeleton-First Workflow

Replace the single-pass workflow with a two-phase approach when spec volume is large.

### Phase A — Skeleton (iteration 1)

1. Read all spec files shallowly — filenames, headings, any dependency declarations
   between specs.
2. Read the orienting/top-level process spec(s) fully (these are typically small and
   provide the big picture).
3. Produce the decomposition ledger with all spec files listed and ordered.
4. Optionally produce skeleton phase headings in the plan (no tasks yet).
5. Commit and stop (do not emit `COMPLETE`).

### Phase B — Decompose (iterations 2+)

1. Read the plan file (including ledger and all tasks so far).
2. Pick the next `pending` spec file from the ledger.
3. Read that spec file fully. Survey the relevant codebase areas.
4. Decompose it into build-sized tasks. Append tasks to the plan.
5. If the spec introduces a discovered prerequisite or conflict with already-decomposed
   work, use the existing mechanisms (insert prerequisite before affected phase, add
   `Conflict:` note).
6. Mark the spec file `decomposed` in the ledger. Commit and stop.
7. Repeat until all specs are decomposed, then emit `COMPLETE`.

### Context Budget Per Decomposition Iteration

Each decomposition iteration holds in context only:

- The prompt
- The plan-so-far (compressed big picture — decomposed tasks from prior specs, which is
  much smaller than the raw spec text)
- One spec file
- Relevant codebase areas

### Late-Iteration Context Pressure

As more specs are decomposed, the plan-so-far grows. When the plan exceeds ~40–50 tasks,
the agent should read only the ledger, phase headings, and the tasks from the immediately
preceding phase (for dependency context) rather than all tasks. Cross-phase dependencies
are declared in the process spec, not discovered by re-reading old tasks.

### Small Projects

When the total spec volume is small enough for a single iteration, the agent can collapse
both phases into one iteration (skeleton + full decomposition + `COMPLETE`). The volume
hint (below) tells the agent when this is safe.

### Multiple Specs Per Iteration

The agent may process multiple pending specs in a single iteration if context permits, but
should default to one. The cost of unnecessary single-spec iterations is low; the cost of
exceeding context is high.

## Volume Hint

Before launching the planner agent, the ralph script measures spec volume and injects a
hint into the prompt via variable substitution.

### Shell Script Changes

In the `ralph` script, in the `plan --process` code path, after validating `PROCESS_DIR`:

```bash
SPEC_BYTES=$(cat "$PROCESS_DIR"/*.md 2>/dev/null | wc -c)
SPEC_COUNT=$(find "$PROCESS_DIR" -maxdepth 1 -name '*.md' | wc -l)
```

Generate `SPEC_VOLUME_HINT` based on a threshold:

- **Below threshold** (< 50 KB or < 5 files):
  `"Total process spec volume: ${SPEC_COUNT} files, ~${SPEC_KB} KB. You can likely
  complete planning in one iteration."`

- **Above threshold:**
  `"Total process spec volume: ${SPEC_COUNT} files, ~${SPEC_KB} KB. This exceeds
  single-iteration capacity. Use the decomposition ledger and process one spec file
  per iteration."`

Export `SPEC_VOLUME_HINT` so it is available for prompt variable substitution via
`envsubst`.

The exact threshold does not need to be precise. A rough heuristic is sufficient — the
cost of unnecessary incremental mode is one extra iteration (the skeleton pass), which is
low.

### Prompt Variable

The `${SPEC_VOLUME_HINT}` variable is added to the Context section of
`prompts/plan-process.md`.

## Phase Collapsing (Build Mode)

For process plans on large projects, the implementation plan can grow large enough to
pressure build agent context. Since the build agent reads `implementation_plan.md` every
iteration, a 100-task plan burns significant context before the agent opens a spec or code
file.

### Convention

When all tasks in a process plan phase are marked `complete`, the build agent collapses
the phase to a single summary line:

```markdown
## Phase 0 — Prep ✅ (8/8 complete)
```

Full task history is preserved in git. The collapsed summary tells subsequent build agents
(and plan agents) that the phase is done without consuming context on individual task
details.

This applies only to `Plan Type: process` plans. Gap-driven plans are flat priority lists
with no phase structure to collapse.

### Regeneration

The process planning agent treats collapsed phases as complete. It only re-expands a
collapsed phase if current specs or codebase state contradict the phase's outcomes — in
that case, it re-decomposes the phase and adds corrective follow-up tasks per the
regeneration rules in `specs/process-planning.md`.

## Changes to Existing Specs and Files

### Prompt changes

- `prompts/plan-process.md` — Add the decomposition ledger to the Plan Format section.
  Replace the Workflow section with the skeleton-first two-phase workflow. Add
  `${SPEC_VOLUME_HINT}` to the Context section. Update Exit Signal completion criteria to
  include "all spec files in the decomposition ledger are marked `decomposed`." Update
  Regeneration Rules to handle the ledger and collapsed phases.
- `prompts/build.md` — Add phase collapsing instruction to the plan update section, gated
  behind `Plan Type: process`.

### Shell script changes

- `ralph` script — In the `plan --process` code path, compute `SPEC_BYTES` and
  `SPEC_COUNT`, generate `SPEC_VOLUME_HINT`, and export it for prompt substitution.

### Spec cross-references

- `specs/process-planning.md` — Add a cross-reference: "For large spec volumes, see
  `specs/incremental-planning.md` for the decomposition ledger, skeleton-first workflow,
  and volume hint."

## What Does NOT Change

- The loop mechanism, agent scripts, and git commit flow are unchanged.
- The existing `plan-process.md` mechanisms (discovered prerequisites, conflicts, process
  gaps, manual gates, regeneration rules, multiple process specs, target-state validation)
  are all preserved.
- The gap-driven planner (`plan.md`) is unaffected.
- The build prompt (`build.md`) is unaffected beyond the phase collapsing addition — it
  reads tasks from the plan file regardless of how they were produced.
- CLI interface is unchanged — no new flags or commands.

## Design Rationale

**Why not physically partition spec files?** That works (moving files in and out of the
directory) but requires human orchestration or a wrapper script. The ledger approach keeps
everything inside ralph's existing architecture: file-based durable memory read by a
fresh-context agent.

**Why a skeleton pass instead of just diving into the first spec?** The skeleton pass
gives the agent one chance to see the forest — all spec filenames, their headings, and any
cross-spec dependencies. For well-structured specs this is nearly redundant. For messy
specs it is where the agent flags obvious ordering issues before committing to a
decomposition sequence.

**Why one spec per iteration instead of batching?** Simplicity and predictability. One
spec + plan-so-far + relevant code is a bounded, predictable context load. Batching
reintroduces the "how much fits?" problem. If a spec is small enough that the agent
finishes early, the iteration is just short — no harm done.

**Why collapse completed phases instead of splitting the plan file?** Splitting the plan
into per-phase files would scale cleanly but is a significant architectural change to how
ralph works — build mode, plan mode, and the ralph script all assume a single plan file.
Collapsing is a prompt convention that achieves the same context savings without structural
changes. If collapsing proves insufficient in practice, file splitting is the next step.
