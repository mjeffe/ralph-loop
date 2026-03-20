# Process Planning

## Purpose

Ralph's standard planning mode is **gap-driven**: it compares target-state specs to the
current codebase and infers what work remains. This works well when the goal is a known end
state and the agent can decide how to get there.

Some work is better described as an ordered sequence of steps — migrations, rewrites,
staged rollouts, dependency upgrades with compatibility phases. These documents describe
*how to get there* rather than *what the system should be*. Process planning enables Ralph
to work from these human-authored playbooks by decomposing their phases into
build-iteration-sized tasks while preserving the author's sequencing constraints.

## Planning Mechanics: Why Two Modes

Ralph supports exactly two planning modes because nearly all work falls into one of two
fundamental planning mechanics:

| Mechanic | Mode | How planning works |
|---|---|---|
| **Gap-driven** | `ralph plan` | Agent compares desired state (specs) to current state (code), infers the task list, and decides ordering. |
| **Sequence-constrained** | `ralph plan --process` | Agent decomposes within a human-defined phase structure. Phase ordering is authoritative; the agent decides how to break each phase into tasks. |

Other work types — incident response, performance tuning, compliance audits, documentation
drives, dependency upgrades, testing campaigns — are not separate planning modes. They fit
within one of these two mechanics depending on the nature of the input:

- A **compliance audit** with a defined target state → gap-driven plan against a compliance spec
- A **multi-phase migration** with explicit ordering → sequence-constrained plan
- A **performance investigation** → gap-driven plan with discovery/investigation tasks
- A **dependency upgrade** with compatibility phases → sequence-constrained plan
- A **testing campaign** → gap-driven plan from a coverage spec

Both planning prompts support **discovery and investigation tasks** — tasks whose output is
knowledge rather than code (inventories, measurements, baselines, feasibility assessments).
These are first-class plan items in either mode, enabling research-heavy work without a
dedicated planning mode.

If these two modes prove insufficient in practice, the next generalization step is
metadata-driven strategy selection (e.g., document frontmatter declaring planning
constraints), not additional CLI flags.

## Concepts

| Term | Meaning | Location |
|------|---------|----------|
| **Specs** | Target-state behavior ("what it should be") | `${SPECS_DIR}/*.md` |
| **Process specs** | Ordered playbooks with phases and sequencing ("how to get there") | `${PROCESS_DIR}/*.md` |
| **Implementation plan** | Build-mode execution queue (derived from either source) | `implementation_plan.md` |

For large spec volumes that exceed single-iteration context capacity, see
`specs/incremental-planning.md` for the decomposition ledger, skeleton-first workflow,
volume hint, and phase collapsing mechanisms.

Process specs are not target-state specs. They describe:
- Migration phases and their ordering
- Dependencies between steps
- Rollout strategy and sequencing constraints
- Refactoring steps that must happen in a specific order

They do **not** describe what the system should look like when finished — that remains the
job of target-state specs in `${SPECS_DIR}`.

## Configuration

```bash
# In config
PROCESS_DIR=""    # Path to process specs directory (empty = not used)
```

`PROCESS_DIR` defaults to empty. When unset, `ralph plan --process` exits with an error:
"No PROCESS_DIR configured. Set PROCESS_DIR in config."

If `PROCESS_DIR` is set but the directory does not exist, exit with an error:
"PROCESS_DIR '${PROCESS_DIR}' not found."

If the directory exists but contains no top-level `*.md` files, exit with an error:
"No process specs found in '${PROCESS_DIR}/'."

A typical value is `specs/process`. The directory structure is up to the project:

```
specs/
├── README.md
├── feature-a.md          # target-state spec
├── feature-b.md          # target-state spec
└── process/
    ├── migration-plan.md  # process spec
    ├── phase-0-detail.md  # process spec
    └── archive/           # completed process specs (ignored by planner)
        └── old-spec.md
```

Only top-level `*.md` files in `PROCESS_DIR` are read as process specs. Subdirectories
are ignored. This lets projects use `archive/` for completed specs and other subdirectories
for supporting material (notes, reference docs) without the planner treating them as active
process specs.

## CLI Interface

```bash
ralph plan                  # Gap-driven planning from target-state specs (existing behavior)
ralph plan --process        # Sequence-constrained planning from process specs
```

The `--process` flag is only valid with `ralph plan`. If used with `build`, `prompt`, or
other modes, ralph exits with an error:
"--process is only valid with 'ralph plan'."

The `--process` flag selects the planning prompt and source directory. It does not change
how the loop runs — plan mode still iterates with fresh context, uses the same logging,
and exits on `<promise>COMPLETE</promise>`.

Running `ralph plan` when the current plan was created by `ralph plan --process` (or vice
versa) simply overwrites the plan. The previous plan is recoverable from git history, and
can be regenerated by re-running the original command.

## Planning Behavior

### Gap-Driven Planning (existing, unchanged)

`ralph plan` reads target-state specs, surveys the codebase, identifies gaps between
desired and current behavior, and generates an ordered task list. The agent decides task
ordering. See `specs/plan-mode.md` for full details.

### Sequence-Constrained Planning

`ralph plan --process` reads process specs, surveys the codebase, and decomposes process
phases into build-iteration-sized tasks. Target-state specs in `${SPECS_DIR}` are available
as background context (domain knowledge, naming conventions, architectural patterns) but
are not authoritative for process planning — process specs define their own per-phase
outcomes.

The key difference from gap-driven planning:

| Concern | Gap-driven | Sequence-constrained |
|---|---|---|
| **Primary source** | `${SPECS_DIR}` | `${PROCESS_DIR}` |
| **Codebase survey** | Full | Full |
| **Task discovery** | Infer from spec-vs-code gaps | Decompose within human-defined phases |
| **Ordering authority** | Agent decides | Human's phase structure is authoritative |
| **Target-state specs** | Primary input | Background context (may be pre-migration; not used for validation) |
| **Adding work** | Expected | Discovered prerequisites may be inserted before the affected phase; ancillary work goes in an appendix |

Process specs define the strategy, phases, and sequencing constraints. The agent surveys
the codebase to understand the actual scope of each phase and step, then decomposes them
into tasks that can each be completed in a single build iteration. The agent has full
autonomy in *how* it breaks down each step, but the phase ordering from the process spec
is authoritative.

### Authority Scope

- **Phase order** is always authoritative.
- **Step order within a phase** is authoritative when the process spec makes it explicit
  (numbered sequence, "before/after", "then", "must precede", dependency language, or
  equivalent).
- When step order is not explicit, the agent may regroup or reorder within the phase for
  buildable task sizing, as long as it does not violate stated dependencies or phase intent.
- The agent may split a step into multiple tasks or combine adjacent steps within the same
  phase, but must not cross phase boundaries or violate explicit sequencing.
- If it is unclear whether a step sequence is mandatory and the ambiguity affects safe
  execution, the agent preserves written order and adds a `Process gap:` note.

### Multiple Process Specs

When multiple process specs are present:

- Build one merged plan.
- Any spec that explicitly defines end-to-end phase order controls ordering for those phases.
- A more detailed spec may split or refine a phase from a higher-level spec, but may not
  reorder it.
- If two specs describe disjoint work with no explicit ordering relationship, preserve each
  spec's internal order and keep the phases grouped unless a true prerequisite requires linkage.
- If cross-spec ordering cannot be reconciled, add a `Conflict:` note rather than inventing
  an order.

### Target-State Spec Interaction

Target-state specs from `${SPECS_DIR}` are **background context**, not a validation
source. In practice, target-state specs often describe the pre-migration system and are
not updated until after the migration completes. The process spec itself defines the
intended outcome of each phase.

The agent may read target-state specs for domain knowledge, naming conventions, and
architectural patterns, but does not validate process planning against them or generate
tasks from them.

### Discovery and Investigation Tasks

Both planning modes may emit tasks whose primary output is knowledge rather than code:

- **Inventory tasks** — "Catalog all v1 API consumers and their usage patterns"
- **Measurement tasks** — "Capture baseline p95 latency for the checkout flow"
- **Feasibility tasks** — "Evaluate whether the ORM supports batch upserts"
- **Audit tasks** — "Map current auth flows against the compliance control checklist"

These are legitimate build-iteration tasks. The build agent completes them by producing
documented findings (committed as markdown, plan notes, or code comments) rather than
shipping feature code. They are especially useful for front-loading uncertainty reduction
before committing to an implementation approach.

### Process Spec Lifecycle

Only top-level `*.md` files in `PROCESS_DIR` are active process specs. Subdirectories
are ignored, which enables an `archive/` convention for completed specs.

When the planning agent's codebase survey reveals that all work described by a process
spec is already complete, it skips task generation for that spec and notes it in the plan
as a candidate for archiving. This catches the case where a human forgets to move a
completed spec out of the active directory.

### Regeneration

When `ralph plan --process` finds an existing plan with build progress, it does not
preserve incomplete work blindly:

- **Revalidate** each `complete` task against the current codebase and current process
  specs. Preserve a completed task only if its outcome is still present and still correct.
- **Re-evaluate** each `blocked` task. If the blocker has cleared, return it to `planned`.
  If it still stands, keep it `blocked` with an updated reason.
- **Re-decompose** all remaining incomplete phases from the current process specs rather
  than trusting stale task wording.
- **Add corrective follow-up tasks** when prior completed work is now incomplete,
  invalidated, or contradicted by current reality. Keep the historical record but add a
  new task labeled `Corrective follow-up for Task N` in the earliest valid phase that
  restores the intended state.
- **Preserve the phase ordering** from the process specs.

This differs from gap-driven planning, which rebuilds the entire task list from scratch.

## Build Mode

Build mode reads the `Plan Type:` header from the implementation plan and adjusts task
selection accordingly:

- `Plan Type: gap-driven` — treat the plan as a priority list. The agent may choose a
  different ready task when there is a clear reason, but must document why.
- `Plan Type: process` — treat phase headings as authoritative ordering constraints. The
  agent selects work from the earliest incomplete phase with a ready `planned` task.
  Within that phase, explicit sequencing and `Depends on:` fields are authoritative.

The plan also records `Plan Command:` so that REPLAN signals direct the human to the
correct regeneration command.

This requires small additions to `prompts/build.md` and `specs/build-mode.md` — see the
"Changes to Existing Specs and Files" section below.

## Prompt Template

The process planning prompt lives at `prompts/plan-process.md`. It is a separate file
from `prompts/plan.md` because the planning job is fundamentally different — decomposition
within a human-defined framework rather than open-ended gap analysis.

```markdown
You are an expert software architect working in Ralph process-planning mode.

Each iteration starts with **fresh context** — you have no memory of prior iterations. Treat repo files as the sole source of truth: `${PROCESS_DIR}/`, `AGENTS.md`, git history, and any existing `${RALPH_HOME}/implementation_plan.md`. Target-state specs in `${SPECS_DIR}/` are available as background context but are not authoritative for process planning.

## Operating Contract

- Process specs define the strategy, phases, and sequencing. You must not reorder phases.
- **Phase order** is always authoritative.
- **Step order within a phase** is authoritative when the process spec makes it explicit (numbered sequence, "before/after", "then", "must precede", dependency language, or equivalent). When step order is not explicit, you may regroup or reorder within the phase for buildable task sizing, as long as you do not violate stated dependencies or phase intent.
- You may split a step into multiple tasks or combine adjacent steps within the same phase, but must not cross phase boundaries or violate explicit sequencing.
- If it is unclear whether a step sequence is mandatory and the ambiguity affects safe execution, preserve written order and add a `Process gap:` note.
- You have full autonomy in how you decompose each phase into build-iteration-sized tasks.
- When multiple process specs cover the same phase or step at different levels of detail, the most detailed spec is authoritative for decomposition. Higher-level specs provide context and define phases not covered elsewhere.
- **Do not implement product code** — process planning produces only the implementation plan and commits.
- Commit your plan updates at the end of each iteration with a descriptive commit message.

## Context

- **Process Specifications:** ${PROCESS_DIR}
- **Target-State Specifications (background context):** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${RALPH_HOME}/implementation_plan.md
- **Project instructions:** AGENTS.md

## Workflow

1. **Read inputs** — Study `AGENTS.md`, `${SPECS_DIR}/README.md`, all top-level `*.md` files in `${PROCESS_DIR}/` (not subdirectories), and optionally target-state specs in `${SPECS_DIR}/` for background context (domain knowledge, naming conventions, architectural patterns). If `${RALPH_HOME}/implementation_plan.md` exists, read it to understand prior progress.
2. **Survey the codebase** — Understand the current state of the project, focusing on areas touched by the process specs. Survey enough of the codebase to accurately size remaining phases and identify sequencing-relevant constraints.
3. **Check for completed specs** — If your survey reveals that all work described by a process spec is already complete, do not generate tasks for it. Instead, note it at the top of the plan: "Process spec `<file>` appears complete — consider moving it to `${PROCESS_DIR}/archive/`."
4. **Decompose phases** — For each active process spec, determine whether each phase and step fits in a single build iteration or needs splitting. Split based on independently testable concerns, but keep child tasks adjacent within their parent phase. You may emit **discovery/investigation tasks** (inventories, measurements, feasibility assessments) when a phase requires understanding before implementation.
5. **Write the plan** — Create or update `${RALPH_HOME}/implementation_plan.md`. If the plan already contains build progress, apply the Regeneration Rules below before writing the updated plan.
6. **Commit** all changes with a descriptive commit message.
7. **If planning is complete**, output the completion signal (see Exit Signal).
8. **If planning is not yet complete**, stop without a signal — the loop will start another iteration.

## Exit Signal

When planning is complete, output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it.

Planning is complete when:
- Every active top-level process spec has been reviewed
- Every authored phase is either decomposed into build-sized tasks, noted as already complete, or represented by an explicit blocked/manual gate
- Discovered work has been classified as either `Discovered prerequisite` or `Ancillary / Follow-up Work`
- Phase order and explicit dependencies are clear enough for build mode to choose the next task safely
- Unresolved conflicts and process gaps are called out explicitly
- Previously completed tasks have been revalidated against the current codebase and current process specs

## Plan Format

At the top of the plan, include:
- `Plan Type: process`
- `Plan Command: ralph plan --process`
- `Primary Process Specs:` comma-separated list of active process spec files

Structure the main body using phase headings (e.g., `## Phase 0 — Inventory and safety rails`). Each phase should include its source process spec traceability and an optional `Depends on:` line when helpful.

Each task needs at minimum:
- A short title
- A brief description of what needs to be done
- The **process spec and phase/step** it traces to (e.g., `specs/process/migration-plan.md — Phase 0a, Step 1`)
- A **status**: `planned` | `blocked` | `complete`
- Enough context for a build agent to start work without re-reading the full process spec
- An optional `Depends on:` line when the dependency is not obvious from placement

Order tasks to match the phase ordering from the process specs.

## Task Sizing

- If a process spec step is completable in one build iteration, make it one task.
- If a step is too large (touches multiple independently testable concerns), split it into child tasks. Keep child tasks adjacent and ordered within their parent phase.
- If a step is too small, combine it with adjacent steps in the same phase — but only if they would logically be committed together.
- Each task should be completable in one build iteration and committable as a single logical unit.

## Discovered Work

If you discover work not explicitly written in the process specs, classify it before adding it to the plan:

1. **Discovered prerequisite** — work that must happen for an existing phase/step to be executable, safe, or verifiable. Examples: missing compatibility tests, required adapters, data backfill prerequisites, inventories, baselines, or rollout safety checks.
   - Insert it into the main plan immediately before the earliest affected phase or step.
   - Label it `Discovered prerequisite`.
   - Explain why it is required and what authored phase/step it unblocks.

2. **Ancillary / follow-up work** — cleanup, opportunistic refactors, nice-to-have improvements, or post-migration polish that is not required to execute the authored phase sequence.
   - Do **not** insert it into the main phase sequence.
   - Put it in a clearly labeled `Ancillary / Follow-up Work` section at the end of the plan.
   - Note the suggested placement or trigger for later consideration.

Do not silently expand the process spec. Every discovered item must be clearly classified.

## Conflicts and Process Gaps

### Conflicts
If process specs, code, or tests disagree:

1. Preserve explicit phase ordering from the process spec that defines the sequence.
2. Use the more detailed process spec to refine decomposition, not to silently reorder higher-level phases.
3. If two sources impose incompatible ordering or incompatible required outcomes, do not guess. Add a `Conflict:` note naming the files/sections in conflict.
4. If the conflict prevents safe decomposition, mark the affected work `blocked`. Continue planning unaffected phases.

### Process gaps
If a process spec omits detail you need:

- If the missing detail only affects task sizing or local breakdown, choose the simplest decomposition and note `Process gap:` in the relevant task or phase.
- If it affects sequencing, rollout safety, migration/data semantics, human/manual responsibility, or public/shared interfaces, do not invent it. Add a `Process gap:` note and, if needed, create a blocked prerequisite or manual gate task.

## Manual / Human-Gated Steps

If a process step requires a human decision, external approval, production cutover, or manual verification:

- Represent it as its own task with `Status: blocked`
- Label it `Manual gate — requires human action`
- Put any preparatory automation work before the gate
- Make downstream tasks explicitly depend on that gate task or phase
- Do not rewrite a human decision into autonomous implementation work

## Multiple Process Specs

When multiple process specs are present:

- Build one merged plan.
- Any spec that explicitly defines end-to-end phase order controls ordering for those phases.
- A more detailed spec may split or refine a phase from a higher-level spec, but may not reorder it.
- If two specs describe disjoint work with no explicit ordering relationship, preserve each spec's internal order and keep the phases grouped unless a true prerequisite requires linkage.
- If cross-spec ordering cannot be reconciled, add a `Conflict:` note rather than inventing an order.

## Regeneration Rules

If `${RALPH_HOME}/implementation_plan.md` already exists and contains build progress:

- Revalidate each `complete` task against the current codebase and current process specs before preserving it.
- Keep a `complete` task only if its intended outcome still exists and is still correct.
- If previously completed work is no longer satisfied, do not silently trust it. Keep the historical record, and add a new task labeled `Corrective follow-up for Task N` in the earliest valid phase that restores the intended state.
- Re-evaluate each `blocked` task. If the blocker is gone, return it to `planned`. If the blocker still stands, keep it `blocked` with an updated reason. If the blocker was based on an outdated assumption, replace it with the correct prerequisite or manual gate.
- Re-decompose all remaining incomplete phases from the current process specs rather than trusting stale task wording.

## Task Status Values

- `planned` — ready to work on
- `blocked` — cannot proceed (document why in the task)
- `complete` — finished and committed

Begin planning now.
```

## Changes to Existing Specs and Files

### Spec changes (done)

- ✅ `specs/build-mode.md` — plan-type-aware task selection, all-blocked → REPLAN, updated prompt template
- ✅ `specs/loop-behavior.md` — `--process` flag docs, REPLAN reads `Plan Command:` from plan header
- ✅ `specs/plan-mode.md` — `Plan Type: gap-driven` / `Plan Command: ralph plan` in format, prompt, and example
- ✅ `specs/spec-lifecycle.md` — "Target-State Specs vs. Process Specs" section with decision table

### Implementation changes (not yet done)

- `ralph` script — add `--process` flag parsing, select `prompts/plan-process.md`, export `PROCESS_DIR`, read `Plan Command:` for REPLAN message
- `config` — add `PROCESS_DIR=""` with comment
- `prompts/plan.md` — add plan metadata header, note that discovery/investigation tasks are valid
- `prompts/build.md` — sync with canonical template in `specs/build-mode.md`
- `prompts/plan-process.md` — create from canonical template in this spec
- `specs/project-structure.md` — add `PROCESS_DIR` to config table, `specs/process/` to layout examples
- Installer and Updater — add `prompts/plan-process.md` to managed files

## Example Process Spec

Process specs describe *how to get there* — phased, ordered playbooks. They range from
high-level phase outlines to detailed step-by-step instructions. Here is a condensed
example based on a real framework migration:

~~~markdown
# Inertia Migration Plan

Migrate from a separate Laravel API + Vue 2 SPA to a Laravel monolith with Inertia.js
+ Vue 3. Evolve the repo in-place — the Laravel backend (models, services, state machine,
events, migrations) is the valuable part. The frontend is a full rewrite.

---

## Phase 0 — Prep (before introducing the new stack)

Each step is independently shippable. Complete all before starting Phase 1.

### 0a. Remove Dead Code

1. Drop 5 unused tables via migration
2. Delete associated models, seeders, and factories
3. Clean up store — remove dead getters
4. Simplify affected Vue components

### 0b. Remove Realms Abstraction

The `realm_id` concept appears on 15+ tables but only one realm has ever existed.

1. Restructure `ApiService.currentRealm()` to read config directly
2. Drop `realm_id` FK from central auth table, remove from all persona logic
3. Remove realm filtering from permission system
4. Simplify factory classes that dynamically resolve by realm
5. Drop `realm_id` columns from ~15 tables, drop `realms` table
6. Clean up frontend: remove realm selection page, clean auth store
7. Remove realm-specific test data providers

### 0c. Consolidate Directory Structure

Merge the `api/` directory into standard Laravel project root layout. The `clients/`
directory stays intact until Phase 2 is done.

---

## Phase 1 — Install New Stack Alongside Old

Both systems coexist: old Vue 2 SPA serves all routes while Inertia is available for
new pages.

### 1a. Install Dependencies

- Inertia server-side + client-side, Vue 3, Vite, CSS framework

### 1b. Configure Inertia

- Add middleware, create root Blade template, create Vue 3 entry point, configure Vite

### 1c. Build Shared Layout Components

- Navigation, sidebar, common UI components, flash messaging

### 1d. Build Auth Flow

- Login page, session-based auth, persona switching

### 1e. Verify Coexistence

- Old SPA still works, new Inertia pages accessible, both usable simultaneously

---

## Phase 2 — Migrate Resource by Resource

Convert one resource at a time. For each: convert controllers to return
`Inertia::render()`, build Vue 3 pages, fix bugs inline, delete old SPA code.

Migration order (simplest → most complex):
1. Announcements — simple CRUD warm-up
2. Admin / Users — wires up auth/persona in Inertia
3. EYPR Narrative — simplest lifecycle resource
4. Local Application — 21 modules, two-tier review
5. Activities + Costs — core complexity: budgets, post-approval editing
6. Inbox — cross-cutting aggregator, convert last

---

## Phase 3 — Cleanup

After all resources are migrated:

1. Delete `clients/` directory entirely
2. Remove API-only JSON routes replaced by Inertia
3. Remove API infrastructure (resource classes, token auth)
4. Consolidate Docker setup to single app container
5. Update CI/CD for Vite
~~~

Note how this spec defines phases with explicit ordering, steps within phases that are
sometimes explicitly sequential (Phase 0b) and sometimes not (Phase 1), and enough
context for a planner to decompose each step into build-iteration-sized tasks. Target-state
specs elsewhere would describe what each resource *should* look like after migration.

## Example Workflow

```bash
# Human creates process specs
mkdir -p specs/process
vim specs/process/migration-plan.md
vim specs/process/phase-0-detail.md

# Configure ralph to find them
echo 'PROCESS_DIR="specs/process"' >> .ralph/config

# Run process planning
.ralph/ralph plan --process

# Review the generated plan
cat .ralph/implementation_plan.md

# Run build iterations
.ralph/ralph build 20

# If process specs change, regenerate
.ralph/ralph plan --process

# To switch to gap-driven planning instead
rm .ralph/implementation_plan.md
.ralph/ralph plan
```
