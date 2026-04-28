You are an expert prompt engineer upgrading two existing ad-hoc prompts to follow the patterns established by `prompts/adhoc-retro-analyze.md` and `prompts/adhoc-retro-feedback.md`.

Each iteration starts with **fresh context** — you have no memory of prior iterations. Treat repo files as the sole source of truth.

## Goal

Refactor the following two prompts to adopt the patterns proven in the retro adhocs, **without changing their core behavior or scope**:

1. `prompts/adhoc-test-analysis.md`
2. `prompts/adhoc-process-spec-review.md`

The goal is consistency across all shipped ad-hoc prompts: same exit-signal pattern, same iteration model where applicable, same structural conventions. Do **not** redesign what the prompts do — only how they are written.

## Reference Patterns

Study these two prompts as the authoritative templates **before** editing anything:

- `prompts/adhoc-retro-analyze.md` — multi-iteration with self-managed continuation (TODO markers in the deliverable file itself)
- `prompts/adhoc-retro-feedback.md` — single-iteration sanitization with pre-flight checks
- `prompts/build.md` — the original source of the "Exit Signal as single source of truth" pattern

## Patterns to Apply

For each of the two target prompts, apply these patterns:

### 1. Exit Signal as a single section, referenced elsewhere

**Pattern (from `build.md` and the retro adhocs):**

- Define exit signals once in an `## Exit Signal` (or `## Exit Signals`) section near the bottom.
- Workflow steps reference it as `(see Exit Signal)` rather than restating the signal text inline.
- Repeated mentions of `<promise>COMPLETE</promise>` scattered through the prompt body should collapse into a single authoritative section.

**Why:** Single source of truth; the user has found this materially more reliable.

### 2. Report-as-progress (replace separate progress files where appropriate)

**Current state:**
- `adhoc-test-analysis.md` uses `${RALPH_HOME}/test-analysis-progress.md` as a separate progress file.
- `adhoc-process-spec-review.md` uses `${RALPH_HOME}/process-review-progress.md` as a separate progress file.

**Pattern to apply (from `adhoc-retro-analyze.md`):**

- For `adhoc-process-spec-review.md`: the progress file can likely be eliminated. The work product is the edited process-spec files themselves; resumption is via "look at what's already been edited and continue with what hasn't." Marker comments like `<!-- TODO: not yet reviewed -->` in the process specs (or in a top-level checklist within the process specs) can serve as resumption points.
- For `adhoc-test-analysis.md`: the work product is the enhanced specs themselves, but the **inventory of test files to analyze** is genuinely useful state across iterations. Decide between (a) keeping the progress file but simplifying it, or (b) folding the inventory into a comment block at the top of `${SPECS_DIR}/README.md` or another natural location. Use judgment; if either approach is materially cleaner, pick it. If both are awkward, keep the existing progress file but simplify it.

**Default to safety:** if eliminating the progress file would lose meaningful state or make resumption fragile, keep the file but trim it.

### 3. Self-assessed iteration count

**Pattern (from `adhoc-retro-analyze.md`):**

- Single iteration is the preferred path when the work fits.
- Multi-iteration is a fallback the agent self-selects when inputs exceed context.
- The `## Iteration Strategy` section frames this explicitly: read inputs first, decide whether the work fits, emit COMPLETE if it does, otherwise produce as much as possible with TODO markers and stop without the signal.
- The agent may use subagents to manage context if its agent supports them.

**Application:**

- `adhoc-process-spec-review.md` — usually multi-iteration in practice (the work spans multiple phases). Keep the multi-iteration model but reframe it in self-assessment terms: the agent decides whether to combine phases or split them, based on what fits.
- `adhoc-test-analysis.md` — same. Multi-iteration is realistic for large test suites. Reframe iteration sizing as agent judgment, not prescriptive rules.

Drop hard-coded iteration sizing rubrics (e.g., the "Small (1–2 test files) / Medium (3–6) / Large (7+)" table in `adhoc-test-analysis.md`) in favor of "the agent decides what fits per iteration; safety valve is the loop continuing across iterations."

### 4. Transient artifacts (only if applicable)

The retro prompts emit transient artifacts (gitignored, not committed). The two target prompts produce **persistent** changes (edited specs that should be committed), so the transient-artifact pattern does **not** apply. Leave commit instructions in place.

### 5. Heading and structural consistency

Match the section headings used in the retro adhocs where they apply:

- `## Goal`
- `## Context`
- `## Iteration Strategy` (if multi-iteration)
- `## Workflow`
- `## Rules`
- `## Exit Signal`

The current prompts use somewhat different headings (e.g., `## First Iteration Setup`, `## Progress Tracking`, `## Phase Review Guidelines`). Reorganize so the same conceptual sections appear in the same order across all four shipped adhocs. Domain-specific subsections (e.g., "Phase Completion Criteria", "Cross-Cutting Review") can stay where they make sense — this is about top-level structure, not internal detail.

## Workflow

1. **Read the reference patterns first** — `prompts/adhoc-retro-analyze.md`, `prompts/adhoc-retro-feedback.md`, and `prompts/build.md`. Understand each pattern before editing.
2. **Read the two target prompts in full** — `prompts/adhoc-test-analysis.md` and `prompts/adhoc-process-spec-review.md`. Note what each does and what state it manages across iterations.
3. **Plan the rewrites in your head** — for each target, list the specific changes. If you find a pattern you cannot apply cleanly, document the reason in your commit message rather than forcing a bad fit.
4. **Rewrite the two prompts** — preserve the existing scope, rules, and analytical rigor. Apply only the structural patterns above.
5. **Verify** by reading the rewritten prompts end-to-end. Check that:
   - Exit signal is defined once and referenced elsewhere
   - Progress tracking is either eliminated (in favor of the deliverable as state) or simplified
   - Iteration sizing is framed as agent judgment, not prescriptive rules
   - The top-level section structure matches the retro adhocs
   - No core behavior or scope has changed
6. **Run the test suite** — `./tests/test_ralph.sh`. All tests should still pass.
7. **Commit** with a descriptive message (e.g., `refactor: align existing adhocs with retro-prompt patterns`). One commit for both files is fine; two commits if the changes are large enough that splitting helps reviewability.
8. **Emit the completion signal** (see Exit Signal) only after both prompts have been rewritten, verified, and committed.

## Iteration Strategy

This work probably fits in one or two iterations. If you find the work too large for a single iteration, complete one prompt fully (including commit), then stop without the completion signal. The next iteration will pick up the remaining prompt.

## Rules

- **Preserve scope and behavior.** Do not change what the prompts do — only how they are written.
- **Do not change the prompt filenames.** They are listed in `install.sh` and `update.sh` MANAGED_FILES.
- **Do not change references to the prompts** in `lib/help/prompt.txt`, `specs/`, `README.md`, or other docs.
- **Do not delete domain-specific guidance** (e.g., the marker conventions in `adhoc-process-spec-review.md`, the analysis dimensions in `adhoc-test-analysis.md`). These are core behavior, not structure.
- **If a pattern does not fit cleanly**, prefer keeping the existing wording over forcing a bad fit. Document the reason in the commit message.
- **Run the test suite before committing.** Restructure failures usually surface as missing string assertions — update tests if needed, but only when the change is intentional.
- After this prompt's work is complete and committed, this prompt file itself (`upgrade-existing-adhocs-prompt.md` in the project root) can be deleted by the human.

## Exit Signal

- **Both target prompts rewritten, verified, tests passing, committed:** output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it.
- **Partial progress (one prompt done, one remaining):** stop without any signal so the loop schedules another iteration.
