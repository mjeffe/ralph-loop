# Incremental Process Planning for Large Spec Volumes

## Problem

The process planner (`ralph plan --process`) instructs the agent to read
all top-level process specs, all target-state specs, survey the codebase,
and decompose every phase into build-sized tasks. For projects with large
spec volumes (e.g., 25 files / 400+ KB of process specs), this exceeds
what a single agent iteration can hold in context.

The multi-iteration escape hatch exists (agent stops without
`<promise>COMPLETE</promise>`, loop starts a new iteration), but it has
no **decomposition cursor**. Each fresh iteration re-reads all specs and
tries to figure out where it left off. This means iteration N burns more
context than iteration N-1, not less. The result is degraded planning
quality or outright failure on large projects.

## Proposed Solution

Three changes that compose together:

1. **Decomposition ledger** in the plan file (plan format change)
2. **Skeleton-first workflow** (prompt change)
3. **Volume hint** injected by the shell script (ralph script change)

### 1. Decomposition Ledger

Add a `## Decomposition Progress` section to the plan file format. The
agent records which spec files have been fully decomposed:

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

The ledger is the resumable work queue. On each iteration the agent reads
it, skips files marked `decomposed`, and picks the next `pending` file(s).

The ledger is populated during the skeleton pass (see below) and updated
as each spec is decomposed.

### 2. Skeleton-First Workflow

Replace the current single-mode workflow with a two-phase approach:

**Phase A -- Skeleton (iteration 1):**

1. Read all spec files shallowly -- filenames, headings, any dependency
   declarations between specs.
2. Read the orienting/top-level process spec(s) fully (these are typically
   small and provide the big picture).
3. Produce the decomposition ledger with all spec files listed and ordered.
4. Optionally produce skeleton phase headings in the plan (no tasks yet).
5. Commit and stop (do not emit COMPLETE).

**Phase B -- Decompose (iterations 2+):**

1. Read the plan file (including ledger and all tasks so far).
2. Pick the next `pending` spec file from the ledger.
3. Read that spec file fully. Survey the relevant codebase areas.
4. Decompose it into build-sized tasks. Append tasks to the plan.
5. If the spec introduces a discovered prerequisite or conflict with
   already-decomposed work, use the existing mechanisms (insert
   prerequisite before affected phase, add `Conflict:` note).
6. Mark the spec file `decomposed` in the ledger. Commit and stop.
7. Repeat until all specs are decomposed, then emit COMPLETE.

Key property: each decomposition iteration holds in context only the
prompt + plan-so-far + one spec file + relevant code. The plan-so-far is
the compressed big picture -- it contains the decomposed tasks from all
prior specs, which is a much smaller representation than the raw spec
text.

**Small projects:** When the total spec volume is small enough for a
single iteration, the agent can collapse both phases into one iteration
(skeleton + full decomposition + COMPLETE). The volume hint (below) tells
the agent when this is safe.

### 3. Volume Hint

Before launching the planner agent, the ralph shell script measures spec
volume and injects a hint into the prompt via variable substitution:

```bash
SPEC_BYTES=$(cat "$PROCESS_DIR"/*.md "$PROCESS_DIR"/**/*.md 2>/dev/null | wc -c)
SPEC_COUNT=$(find "$PROCESS_DIR" -name '*.md' | wc -l)
```

Injected into the prompt as `${SPEC_VOLUME_HINT}`:

- **Below threshold** (e.g., <50 KB or <5 files):
  "Total process spec volume: 3 files, ~15 KB. You can likely complete
  planning in one iteration."

- **Above threshold:**
  "Total process spec volume: 25 files, ~390 KB. This exceeds
  single-iteration capacity. Use the decomposition ledger and process
  one spec file per iteration."

The exact threshold does not need to be precise. A rough heuristic is
sufficient -- the cost of unnecessary incremental mode is one extra
iteration (the skeleton pass), which is low.

## Prompt Changes

The changes are isolated to `prompts/plan-process.md`:

1. Add the decomposition ledger to the **Plan Format** section.
2. Replace the **Workflow** section with the skeleton-first two-phase
   workflow described above.
3. Add `${SPEC_VOLUME_HINT}` to the **Context** section.
4. Update the **Exit Signal** completion criteria to include "all spec
   files in the decomposition ledger are marked `decomposed`."
5. Update **Regeneration Rules** to preserve the ledger when regenerating
   a plan that already has decomposition progress.

## Shell Script Changes

In the `ralph` script, in the `plan --process` code path:

1. After validating `PROCESS_DIR`, compute `SPEC_BYTES` and `SPEC_COUNT`.
2. Generate `SPEC_VOLUME_HINT` text based on the threshold.
3. Export `SPEC_VOLUME_HINT` so it is available for prompt variable
   substitution.

## What Does NOT Change

- The loop mechanism, agent scripts, and git commit flow are unchanged.
- The existing plan-process.md mechanisms (discovered prerequisites,
   conflicts, process gaps, manual gates, regeneration rules, multiple
   process specs, target-state validation) are all preserved.
- The gap-driven planner (`plan.md`) is unaffected.
- The build prompt (`build.md`) is unaffected -- it reads tasks from the
  plan file regardless of how they were produced.

## Design Rationale

**Why not physically partition spec files?** That works (moving files in
and out of the directory) but requires human orchestration or a wrapper
script. The ledger approach keeps everything inside ralph's existing
architecture: file-based durable memory read by a fresh-context agent.

**Why a skeleton pass instead of just diving into the first spec?** The
skeleton pass gives the agent one chance to see the forest -- all spec
filenames, their headings, and any cross-spec dependencies. For
well-structured specs this is nearly redundant. For messy specs it is
where the agent flags obvious ordering issues before committing to a
decomposition sequence.

**Why one spec per iteration instead of batching?** Simplicity and
predictability. One spec + plan-so-far + relevant code is a bounded,
predictable context load. Batching reintroduces the "how much fits?"
problem. If a spec is small enough that the agent finishes early, the
iteration is just short -- no harm done. The prompt can note that the
agent may process multiple pending specs in a single iteration if context
permits, but should default to one.
