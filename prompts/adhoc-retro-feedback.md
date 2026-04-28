You are an expert at sanitizing structured documents.

## Goal

Read the existing retro report at `${RALPH_HOME}/retro-report.md`, redact project-specific details, and write the sanitized result to `${RALPH_HOME}/retro-feedback.md` so the human can paste it as a GitHub issue body at https://github.com/mjeffe/ralph-loop/issues.

This is a pure content transformation — preserve the report's headings and structure exactly, replacing only project-specific content with generic placeholders or category labels. Do not analyze the cycle, do not change the structure, do not invent sections the report does not have.

The feedback file is a **transient artifact**: gitignored, never committed, and overwritten by the next run.

## Pre-flight Checks

Perform these checks first. If any check fails, print the indicated error message and emit the completion signal (see Exit Signal) so the loop exits cleanly without burning retries.

1. **Report file exists** — check that `${RALPH_HOME}/retro-report.md` exists.
   - If missing: `ERROR: No retro report found at ${RALPH_HOME}/retro-report.md. Run 'ralph prompt .ralph/prompts/adhoc-retro-analyze.md' first.`

2. **Report file is non-empty** — check that the file has content.
   - If empty: `ERROR: Retro report at ${RALPH_HOME}/retro-report.md is empty. Re-run 'ralph prompt .ralph/prompts/adhoc-retro-analyze.md' to regenerate.`

3. **Report is complete** — search for `<!-- TODO` markers in the report.
   - If any are found: `ERROR: Retro report at ${RALPH_HOME}/retro-report.md is incomplete (contains TODO markers). Re-run 'ralph prompt .ralph/prompts/adhoc-retro-analyze.md' to finish it.`

## Workflow

1. Run the pre-flight checks above. If any fail, exit per the instructions there.
2. Read `${RALPH_HOME}/retro-report.md` in full.
3. Apply the Sanitization Rules below to every section of the report.
4. Write the sanitized result to `${RALPH_HOME}/retro-feedback.md`, preserving the report's headings and section order.
5. Self-check — re-read the output and verify nothing in the rules slipped through. Fix anything that did before emitting the completion signal.
6. Do NOT commit. The feedback file is gitignored and transient.
7. Emit the completion signal (see Exit Signal).

## Sanitization Rules

For each item below, **replace** with a generic placeholder, **generalize** to its category, or **omit** if no useful generic remains. Preserve the report's structure — sanitization is a content transformation, not a restructuring.

| Project-specific content | Treatment |
|---|---|
| Project name, domain, business context, industry | Omit or replace with `<project>` |
| File paths (other than ralph-managed paths like `.ralph/logs/`) | Replace with `<file path>` |
| Module / class / function / API names | Replace with `<symbol>` or generalize ("the auth module" → "an internal module") |
| Code snippets, error messages, stack traces | Replace with `<code snippet>` / `<error message>` |
| Team-member names, GitHub usernames, email addresses | Omit |
| Specific spec content or task descriptions | Generalize to a category — e.g., "User.email uniqueness across soft-deleted records" → "missing edge-case handling for soft-deleted records" |
| Specific commit hashes or messages | Omit or generalize ("3 revert commits" is fine; the hashes and messages are not) |

**Always preserve unchanged** (these are not project-specific):
- Ralph-specific terminology, modes, signals (`gap-driven`, `process`, `REPLAN`, `COMPLETE`, etc.)
- Numeric counts (iterations, tasks, retries, REPLAN signals)
- Agent type used (`amp`, `claude`, `cline`, `codex`)
- Categories of issues (e.g., "missing verification criteria", "test command flags")
- Suggestions for ralph-loop prompts, defaults, or behavior

## Rules

- **Do NOT modify** any file other than `${RALPH_HOME}/retro-feedback.md`.
- **Do NOT analyze the cycle.** The retro report is your only input.
- **Do NOT invent observations.** If a section in the report has no content after sanitization (everything in it was project-specific), omit the section rather than padding with generic commentary.
- **When in doubt, omit.** It is better to under-share than to leak project context.

## Exit Signal

- **Sanitized feedback written, or pre-flight check failed:** output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it. Pre-flight failures emit the same signal so the loop exits cleanly without retrying a guaranteed failure.
