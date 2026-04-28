# TODO

This doc is primarily for the humans. It is an active doc to keep current
thoughs, reminders, ideas, things to watch for, etc.

## List of Items to Implement or Refactor

- process-planner-prompt-improvements.md is unimplemented but has been updated with advice from an analysis. The agent said:
  "The proposed changes in the doc are raw prompt text — they were written before the canonical template moved into the spec. The implementing agent will need to adapt them to the spec's structure (prose + embedded template) rather than copy-pasting the code blocks directly."
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
- Discuss pros and cons of converting the sandbox to multi-service rather than a single monolitic container.
- Sandbox integration tests: add `tests/test_sandbox_snippets.sh` that runs
  the "use exact" entrypoint snippets from prompt appendices inside
  `docker run --user ralph ralph-sandbox-base` to catch runtime failures
  (e.g., `su - ralph` hanging). No agent invocation, just Docker + bash.
- Smoke-test sandbox: ship a fixture `tests/fixtures/hello-project/` with a
  minimal pre-baked profile and generated files. Test does `docker compose up`,
  waits for healthy, asserts basics (user is ralph, git works, supervisord is
  PID 1), then tears down. Gate behind `--integration` flag since it's slow.

## Update bug (`ralph update`)

If the `ralph` script itself has been changed and a project with ralph-loop
installed runs `ralph update`, it will finish with something like:
```
./ralph: line 1663: unexpected EOF while looking for matching `''
```
I'm fairly certain this happens because the running script (`ralph`) is
modified as part of the update itself.

## Promote Retro Adhocs to a Formal `ralph retro` Command

The retro workflow is now shipped as ad-hoc prompts:

- `ralph prompt .ralph/prompts/adhoc-retro-analyze.md` — produces a structured
  retro report at `.ralph/retro-report.md`
- `ralph prompt .ralph/prompts/adhoc-retro-feedback.md` — sanitizes the report
  into `.ralph/retro-feedback.md` for sharing as a ralph-loop GitHub issue
- An interactive discussion prompt in `lib/help/retro.txt` for stage 2

Once we've accumulated real-world experience with this workflow, consider
promoting it to a formal top-level command. **This would be a purely
mechanical change to invocation** — the underlying prompts and behavior stay
the same.

Possible CLI shape (mirrors `ralph plan` / `ralph plan --process`):
- `ralph retro` → invokes the analyze prompt
- `ralph retro --feedback` → invokes the feedback prompt
- `ralph help retro` → already covers the full three-stage workflow

Pros:
- Discoverability: `ralph --help` lists it next to plan/build/align-specs
- Shorter to type than the full adhoc path
- Conceptually elevates retro to a first-class capability

Cons:
- Adds another top-level command to maintain
- Demotes "adhoc prompts as first-class workflows" — currently the retro
  adhocs are the most polished example of that pattern
- Forces a choice on the `--feedback` flag shape; alternatives (e.g.,
  `ralph retro feedback` as a subcommand) each carry their own trade-offs

Decide after using the adhoc workflow on several real plan+build cycles. If
the bare `ralph prompt .ralph/prompts/adhoc-retro-analyze.md` invocation feels
like friction, promote. If it feels fine, leave it alone — the adhoc form
already works.

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

## Generalize `ralph align-specs` with `--process` flag

Today `ralph align-specs` only handles post-process-cycle alignment using the
decomposition ledger. But spec/code drift also accumulates from interactive
sessions, ad-hoc edits, and `ralph prompt` runs that bypass the planner —
and there is no equivalent reconciliation pass for those.

Refactor to follow the `ralph plan` / `ralph plan --process` pattern:

| Today | Proposed |
|---|---|
| `ralph align-specs` (only mode, post-process-cycle) | `ralph align-specs` — **NEW**: general spec/code drift reconciliation (interactive sessions, ad-hoc edits, anything that bypasses the planner) |
| — | `ralph align-specs --process` — current behavior (post-process-cycle alignment using the decomposition ledger) |

Implementation outline:
1. Move existing `prompts/align-specs.md` → `prompts/align-specs-process.md`.
2. Create new `prompts/align-specs.md` (general drift) — substantive design work:
   survey recent changes, identify which specs they touch, update specs to match
   reality, flag conflicts.
3. Update `ralph` dispatcher to select template by flag.
4. Update `specs/align-specs.md` to document both modes.
5. Update `lib/help/align-specs.txt`.
6. Update `install.sh` / `update.sh` MANAGED_FILES.
7. Update tests.

Trade-offs:
- Breaking change: `ralph align-specs` today means "align after process cycle";
  after the change, it means "align after general drift." Anyone with muscle
  memory or scripts using the bare command needs to add `--process`.
- Why not an adhoc instead: spec/code alignment is a core ralph capability
  (same category as plan/build/sandbox), not a user-defined workflow. Pushing
  it to an adhoc demotes it conceptually and loses help-system integration.

The new general-drift prompt is the hard part — worth its own design pass
before implementation.

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

