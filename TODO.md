# TODO

This doc is primarily for the humans. It is an active doc to keep current
thoughs, reminders, ideas, things to watch for, etc.

## List of Items to Implement or Refactor

- How can I monitor/track the % of context window used during an iteration?
- how can we reduce token usage. These iterations can get expensive
- tdd approach: write tests before implementation?
- need to modify prompts to say all tasks should be deployable, functional, and tested?
- analyze current ralph implementation, think of it as a prototype, suggest what
  we would do to create a production version. What needs to be cleaned up, what
  would be a more appropriate programming language than bash, what should be
  modularized, etc.
- Make a workdir subdirectory of `.ralph/` so work files such as `implementation_plan.md`,
  `alignment_ledger.md`, `last_agent_output`, etc., do not clutter ralph's root dir.

## Automated Retrospective (`ralph retro`)

`ralph help retro` provides a manual retro process with sample prompts for
agent-assisted analysis. Once we've accumulated experience with manual retros
(via feedback from teams and our own usage), consider a `ralph retro` mode that
automates the analysis phase: the agent reads session logs, the plan, and git
history, then produces a structured retro report. The human still decides what
to act on — same pattern as `ralph align-specs` (agent analyzes, human acts).

Key design questions to answer from experience first:
- Which analysis steps are mechanical enough to automate vs. need discussion?
- What report format is most actionable?
- Should retro produce a file (like alignment_ledger.md) or just terminal output?
- Can the agent reliably identify wasted iterations from logs alone?

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

## Improve `ralph update` for Customized Files

The current updater uses manifest checksums to detect user-modified files and
drops a `.upstream` file for manual diff/merge. This is safe but tedious once
users customize prompts (the common case).

### Option 1: Three-Way Merge (recommended — implement first)

Store the **original upstream version** at install/update time (e.g.,
`.ralph/.originals/prompts/build.md`). On update, perform a three-way merge
using `git merge-file`:

- **base** = upstream version the user started from (`.originals/`)
- **theirs** = new upstream version (fetched)
- **ours** = user's current file

If `git merge-file` succeeds cleanly, apply the result. If there are conflicts,
write the conflict-marked file and inform the user. This resolves most updates
automatically since user changes and upstream changes usually touch different
sections.

### Option 2: Agent-Assisted Merge

When `git merge-file` produces conflicts (or as an opt-in for all modified
files), invoke the configured agent with a merge prompt: provide the user's
version, the new upstream version, and the original base, and ask the agent to
merge upstream improvements while preserving user customizations. Offer as
`ralph update --agent-merge`. Powerful but expensive — best as a complement to
Option 1 for unresolved conflicts.

### Option 3: Structured Prompts with User Override Sections

Redesign prompts with clearly delimited extension points
(`<!-- USER CUSTOMIZATIONS BELOW -->`). The updater replaces everything outside
those markers and preserves what's inside. Constrains where users can customize
but makes updates trivial for common cases.

### Option 4: Layered Prompts (Composition over Modification)

Split prompts into `base` (upstream-managed, always overwritten) and `overrides`
(user-owned, never touched). At runtime, ralph concatenates them. Users never
edit the base files. Updates become zero-friction since base files are always
safe to overwrite. Requires restructuring prompts and changing user habits.

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

