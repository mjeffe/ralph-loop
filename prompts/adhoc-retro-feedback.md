You are an expert at writing sanitized, structural feedback reports.

## Goal

Read the existing retro report at `${RALPH_HOME}/retro-report.md` and produce a sanitized version at `${RALPH_HOME}/retro-feedback.md` — stripped of all project-specific details — that the human can paste as a GitHub issue body at https://github.com/mjeffe/ralph-loop/issues.

This is a pure transformation prompt: it sanitizes an existing report, it does not perform analysis. If the retro report is missing or incomplete, exit with a clear error message — do not analyze the cycle from scratch.

The feedback file is a **transient artifact**: gitignored, never committed, and overwritten by the next run.

## Prerequisite

This prompt requires `${RALPH_HOME}/retro-report.md` to exist and be complete. To produce the report, run:

    ralph prompt .ralph/prompts/adhoc-retro-analyze.md

## Pre-flight Checks

Perform these checks first. If any check fails, output the indicated error message and emit the completion signal (see Exit Signal) so the loop exits cleanly without burning retries.

1. **Report file exists** — check that `${RALPH_HOME}/retro-report.md` exists.
   - If missing: print `ERROR: No retro report found at ${RALPH_HOME}/retro-report.md. Run 'ralph prompt .ralph/prompts/adhoc-retro-analyze.md' first.` and emit the completion signal.

2. **Report file is non-empty** — check that the file has content.
   - If empty: print `ERROR: Retro report at ${RALPH_HOME}/retro-report.md is empty. Re-run 'ralph prompt .ralph/prompts/adhoc-retro-analyze.md' to regenerate.` and emit the completion signal.

3. **Report is complete** — search for `<!-- TODO` markers in the report.
   - If any are found: print `ERROR: Retro report at ${RALPH_HOME}/retro-report.md is incomplete (contains TODO markers). Re-run 'ralph prompt .ralph/prompts/adhoc-retro-analyze.md' to finish it.` and emit the completion signal.

## Workflow

1. **Run the pre-flight checks above.** If any fail, exit per the instructions there.
2. **Read** `${RALPH_HOME}/retro-report.md` in full.
3. **Sanitize** by filtering content through the include/exclude rules below. Each rule applies to the entire output.
4. **Write** the sanitized result to `${RALPH_HOME}/retro-feedback.md` using the format specified below.
5. **Self-check** — re-read the output and verify nothing in the EXCLUDE list slipped through. If anything did, fix it before emitting the completion signal.
6. **Do NOT commit.** The feedback file is gitignored and transient.
7. **Emit the completion signal** (see Exit Signal).

## INCLUDE — Structural observations only

- Planning mode used (`gap-driven` / `process` / `incremental process`)
- Number of plan iterations and build iterations
- Iteration-to-task ratio (a measure of cycle efficiency)
- Number of blocked tasks, REPLAN signals, agent retries
- **Categories** of spec gaps encountered (e.g., "missing verification criteria", "ambiguous edge case handling") — never the gaps themselves
- **Categories** of AGENTS.md fixes needed (e.g., "test commands", "environment setup", "naming conventions")
- Task sizing observations (too granular, too coarse, about right)
- Suggestions for ralph-loop prompts, defaults, or behavior
- Agent type used (`amp`, `claude`, `cline`, `codex`, etc.) if it appears in the report

## EXCLUDE — Project secrets

- Project name, domain, business context, industry
- File paths (other than ralph-managed paths like `.ralph/logs/`)
- Module names, class names, function names, API endpoints
- Code snippets or implementation details
- Team member names, GitHub usernames, email addresses
- Specific spec content or task descriptions — only categories, never the actual text
- Identifiable error messages or stack traces
- Specific commit hashes or messages

## Output Format

Write `${RALPH_HOME}/retro-feedback.md` as a GitHub issue body, ready to paste:

```markdown
# Retro feedback: <one-line structural summary, e.g., "Process mode, 14 build iterations, task-sizing concerns">

## Cycle Shape

- Planning mode: <gap-driven | process | incremental process>
- Agent: <amp | claude | cline | codex | unknown>
- Plan iterations: <N>
- Build iterations: <N>
- Tasks: <completed> completed, <blocked> blocked, <added> added during build
- REPLAN signals: <N>
- Agent retries: <N>

## Issue Categories

### Spec gaps
- <category 1, e.g., "Missing verification criteria">
- <category 2>

### AGENTS.md fixes needed
- <category 1, e.g., "Test command flags">
- <category 2>

### Task sizing
<one paragraph: too granular / too coarse / about right, with brief rationale>

## Suggestions for ralph-loop

<bullet list of suggestions for prompts, defaults, or behavior — phrased as suggestions, not project-specific demands>
```

## Rules

- **Do NOT modify** any file other than `${RALPH_HOME}/retro-feedback.md`.
- **Do NOT analyze the cycle from scratch.** Your only input is the existing retro report. If it is missing or incomplete, exit per the pre-flight checks.
- **When in doubt about a detail, omit it.** It is better to under-share than to leak project context.
- **Do not invent observations.** If the retro report does not contain the input for a section, leave that section out — do not pad with generic commentary.
- **No code blocks** in the output other than the ones in this template's format.

## Exit Signal

- **Sanitized feedback written, or pre-flight check failed:** output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it. Pre-flight failures emit the same signal so the loop exits cleanly without retrying a guaranteed failure.
