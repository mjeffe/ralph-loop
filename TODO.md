# TODO

This doc is primarily for the humans. It is an active doc to keep current
thoughs, reminders, ideas, things to watch for, etc.

## List of Items to Implement

- How can I monitor/track the % of context window used during an iteration?
- how can we reduce token usage. These iterations can get expensive
- tdd approach: write tests before implementation?
- need to modify prompts to say all tasks should be deployable, functional, and tested?
- analyze current ralph implementation, think of it as a prototype, suggest what
  we would do to create a production version. What needs to be cleaned up, what
  would be a more appropriate programming language than bash, what should be
  modularized, etc.

## Scoped Process Planning (`ralph plan --process <spec-file>`)

Allow focusing `ralph plan --process` on a single process spec file, ignoring
others. Two changes recommended:

1. **Scoping via shell, not prompt.** Copy the specified file into a temp dir,
   point `PROCESS_DIR` at it. The prompt runs unmodified — zero new branching.
   Inject the original command into `Plan Command:` via a template variable so
   regeneration knows what was scoped.

2. **Split `plan-process.md` by volume (Option A).** The prompt already has 6
   decision points; adding scoping would push it to ~9 interacting branches.
   Split into `plan-process.md` (small/single-iteration) and
   `plan-process-incremental.md` (large/skeleton-first). The shell already
   computes the volume hint, so it can select the right prompt with no new
   detection logic. Accept the duplication of shared reference sections (Task
   Sizing, Discovered Work, Conflicts, etc.) rather than using partial
   templates — partials add indirection that makes it harder for agents working
   on ralph-loop to understand and modify the prompts. Add a sync comment at the
   top of each file.

## Workflow Status Awareness (`ralph status`)

Consider a `ralph status` command that surfaces where the user is in the current workflow
and suggests the next step. Ralph already has the information (plan type, task statuses,
process dir configuration) — it just doesn't present it as workflow guidance.

Example output:
```
Mode: process
Plan: complete (42 tasks)
Build: 38/42 complete, 4 planned
Next: ralph build 4
After build: ralph align-specs
```

This would benefit all modes, not just process workflows. Non-prescriptive — it shows
state and suggests, doesn't automate.

## Test Guidance Policy (prompts/build.md step 7)

Current policy nudges agents toward coverage where it matters most (bug fixes,
behavior changes) while avoiding ritualized test-writing for low-value cases.
Agents document meaningful skipped coverage in the implementation plan.

**If agents repeatedly skip easy, high-value tests**, tighten by adding to
build.md "Critical Rules":

> Add or update targeted tests when your change affects behavior or fixes a bug,
> unless a reliable test would be disproportionately costly; document meaningful
> skipped coverage in the plan.

**If that's still not enough**, escalate to explicit heuristics:

- Bug fix → regression test expected unless impractical
- Behavior change → update or add tests
- Pure refactor / dead code removal → tests optional

**Watch for these failure modes:**

- Bug fixes shipping without regression tests
- Agents repeatedly skipping easy, high-value tests
- Refactors causing regressions in under-tested areas
- Lots of plan notes about skipped coverage with no follow-up

