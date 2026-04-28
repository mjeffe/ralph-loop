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
and volume hint.

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

### Destructive-Change Safety

#### Why this rule exists

Process specs describe intent: which files, dependencies, infrastructure, or interfaces
should be removed at each phase. They define the *deletion scope* the author had in mind.
The codebase defines the *actual dependencies* — which other parts of the system still
use those artifacts. The two routinely diverge during long-running migrations: a spec
written when the migration began does not foresee every cross-cutting reference that
exists when the destructive phase actually runs.

The gap-driven planner does not have this problem. Its "Spec alignment" step
(`prompts/plan.md`) structurally requires bidirectional cross-referencing — for each
spec requirement, assess whether the current repo satisfies it in all material ways.
That naturally surfaces shared dependencies. The process planner's survey, by design,
is lighter weight (oriented toward sizing and sequencing) so it can handle large
phased playbooks without exhausting context. That lighter survey is its strength for
sequence-constrained work, but it also means the planner can trust a destructive phase
description without independently verifying that the deletion scope is safe.

Field evidence (issue #31): a process spec for a frontend-framework migration listed
"Remove API Resource classes" as a Phase 3 cleanup step. The process planner created
a task to delete the entire `app/Http/Resources/` directory. Seven of the 38 classes
were still imported by the new frontend's controllers for CSV export — executing the
task would have broken downloads. The same pattern repeated for Form Request
validators (7 of 50 shared) and ~58 API test files. A gap-driven plan generated
against the same codebase caught all three cases because its bidirectional alignment
forced the cross-reference.

The fix is not to make the process planner's general survey deeper — that would erode
its context advantage. Instead, this section adds a narrowly-scoped structural
requirement that fires only on destructive operations against shared or long-lived
artifacts, mirroring the gap-driven planner's rigor exactly where intent and
dependency are most likely to diverge.

The burden could in principle be pushed onto spec authors — write specs that enumerate
every exception. That has worked when used, but it asks humans to anticipate every
cross-dependency that may exist months later, which is precisely the analysis a
codebase-aware agent excels at. The structural prompt requirement keeps the spec
author's job at "describe intent" and lets the planner verify against current reality.

#### Mechanics

When the planner decomposes a phase or step that performs destructive operations
(deleting files or directories, dropping dependencies, removing migrations, removing
shared interfaces, deleting infrastructure), it must independently verify against the
live codebase that no active code outside the deletion scope depends on the items being
removed. The process spec's enumeration of what to delete is treated as intent, not as
an exhaustive dependency list.

When shared dependencies are found:

- Note them as **explicit preserve/delete exceptions** in the task with named files or
  symbols.
- Bundle the removal and any required dependent-code updates into a single task per the
  existing sizing rule on destructive changes.
- If the dependent code is scheduled to be removed by a later phase, do not silently
  reorder. **Prefer splitting** the destructive task so the safely-removable subset
  ships in this phase and the still-used subset is deferred to the appropriate later
  phase. Add a `Conflict:` note describing the cross-phase dependency and a
  `Deferred work:` reference to the later task. Block the destructive task on the
  later phase only when safe partitioning is unclear.

Tasks that perform destructive operations include a **`Pre-check:`** block listing the
specific grep/search commands the build agent must run before executing the deletion,
plus any preserve-exceptions identified during planning. The build agent runs the
pre-check first; if results contradict the planning analysis, the agent marks the task
`blocked` rather than proceeding. If a build agent is assigned a task that performs
destructive operations on shared or long-lived artifacts and no `Pre-check:` block is
present, the agent treats this as a planning defect and marks the task `blocked` with
a `Planning gap: destructive task missing Pre-check` note rather than executing the
destruction.

This requirement is scoped to destructive changes that affect **pre-existing shared or
long-lived artifacts** that may be referenced outside the files being edited. It does
not apply to task-local cleanup of private symbols after all callers are updated in the
same task, scaffolding created earlier in the same task, generated artifacts, or files
the spec explicitly describes as orphan-only.

Distinguishing active references from incidental matches matters. A grep match inside
a comment, a dead module that is itself slated for removal, or a string literal in an
unrelated test fixture is not an active dependency. Use repo conventions and
import/usage analysis rather than treating any text match as a blocker.

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

Build mode reads the `Plan Type:` header from the implementation plan and selects the
appropriate build prompt and task selection strategy:

- `Plan Type: gap-driven` → `prompts/build.md` — agent selects task from the injected
  Task Overview. May choose out of order with a documented reason.
- `Plan Type: process` → `prompts/build-process.md` — ralph infrastructure
  deterministically selects the next task (earliest incomplete section → first planned
  task with resolved dependencies) and injects it into the prompt. The agent implements
  the assigned task without participating in selection. This eliminates the task-ordering
  errors observed in field data (issue #20).

The plan also records `Plan Command:` so that REPLAN signals direct the human to the
correct regeneration command.

See `specs/build-mode.md` for full details on the bifurcated build workflow and
infrastructure-managed plan context.

## Prompt Template

The canonical process planning prompt lives at `prompts/plan-process.md`. It is the source
of truth for the exact prompt wording and is used by the ralph loop to invoke the agent.
It is a separate file from `prompts/plan.md` because the planning job is fundamentally
different — decomposition within a human-defined framework rather than open-ended gap
analysis. Refer to that file directly rather than duplicating it here.

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
