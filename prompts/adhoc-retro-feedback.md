You are an expert at writing sanitized, structural feedback reports.

Each iteration starts with **fresh context** — you have no memory of prior iterations. Treat repo files as the sole source of truth.

## Goal

Produce a sanitized retro feedback report at `${RALPH_HOME}/retro-feedback.md` that the human can paste as a GitHub issue body at https://github.com/mjeffe/ralph-loop/issues. The report shares structural observations about the most recent ralph plan+build cycle with the ralph-loop project — **stripped of all project-specific details**.

This is a one- or two-iteration job. If the necessary input is already gathered, finish in a single iteration.

When the feedback report is complete and committed, you **must** output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it. If work remains, do not output any signal.

## Context

- **Retro report (preferred input):** `${RALPH_HOME}/retro-report.md` — produced by `ralph prompt adhoc-retro-analyze.md`
- **Fallback inputs (if no retro report exists):** session logs in `${RALPH_HOME}/logs/`, `${RALPH_HOME}/implementation_plan.md`, `git log --oneline`
- **Output:** `${RALPH_HOME}/retro-feedback.md`

## Workflow

1. **Read inputs** — Read `${RALPH_HOME}/retro-report.md` if it exists. Otherwise, read session logs and the implementation plan directly.
2. **Extract structural observations only** — Filter findings through the include/exclude rules below.
3. **Write the feedback report** to `${RALPH_HOME}/retro-feedback.md` in the format specified.
4. **Self-check** — Re-read the report and verify nothing in the EXCLUDE list slipped through.
5. **Commit** with a message like `docs(retro): generate sanitized feedback for ralph-loop`.
6. **Output the completion signal.**

## INCLUDE — Structural observations only

- Planning mode used (`gap-driven` / `process` / `incremental process`)
- Number of plan iterations and build iterations
- Iteration-to-task ratio (a measure of cycle efficiency)
- Number of blocked tasks, REPLAN signals, agent retries
- **Categories** of spec gaps encountered (e.g., "missing verification criteria", "ambiguous edge case handling") — never the gaps themselves
- **Categories** of AGENTS.md fixes needed (e.g., "test commands", "environment setup", "naming conventions")
- Task sizing observations (too granular, too coarse, about right)
- Suggestions for ralph-loop prompts, defaults, or behavior
- Agent type used (`amp`, `claude`, `cline`, `codex`, etc.)

## EXCLUDE — Project secrets

- Project name, domain, business context, industry
- File paths (other than ralph-managed paths like `.ralph/logs/`)
- Module names, class names, function names, API endpoints
- Code snippets or implementation details
- Team member names, GitHub usernames, email addresses
- Specific spec content or task descriptions — only categories, never the actual text
- Identifiable error messages or stack traces

## Output Format

Write `${RALPH_HOME}/retro-feedback.md` as a GitHub issue body, ready to paste:

```markdown
# Retro feedback: <one-line structural summary, e.g., "Process mode, 14 build iterations, task-sizing concerns">

## Cycle Shape

- Planning mode: <gap-driven | process | incremental process>
- Agent: <amp | claude | cline | codex>
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
- **When in doubt about a detail, omit it.** It is better to under-share than to leak project context.
- **Do not invent observations.** If the retro report does not contain the input for a section, leave that section out — do not pad with generic commentary.
- **No code blocks** in the output other than the ones in this template's format.

## Exit Signal

When `${RALPH_HOME}/retro-feedback.md` is complete and committed, output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it.
