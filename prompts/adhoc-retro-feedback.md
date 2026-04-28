You are an expert at sanitizing structured documents.

## Goal

Read the existing retro report at `${RALPH_HOME}/retro-report.md`, sanitize it for public sharing, and write the result to `${RALPH_HOME}/retro-feedback.md` so the human can paste it as a GitHub issue body at https://github.com/mjeffe/ralph-loop/issues.

The feedback file is a **transient artifact**: gitignored, never committed, and overwritten by the next run.

## Operating Contract

- This is a **content transformation**, not analysis. Do not invent new sections, do not add new conclusions, and do not re-analyze the cycle.
- You have full autonomy on how to apply the sanitization ladder (see Sanitization Principles). Default to safety: when uncertain, generalize or omit.
- Preserve the report's heading hierarchy and section order **where content remains**. You may rewrite details at a higher level of abstraction to preserve the original point safely.
- The feedback file is transient — write it to disk and leave it uncommitted.

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
3. Apply the Sanitization Principles below to every detail in the report.
4. Write the sanitized result to `${RALPH_HOME}/retro-feedback.md`. Preserve the report's heading hierarchy and section order **where content remains**. If an entire section becomes empty after sanitization, omit that section rather than adding filler.
5. Self-check — re-read the output. For anything that remains, ask: could this identify the project, customer, proprietary domain, internal architecture, or operating environment, alone or in combination with other details? If yes, generalize or omit it.
6. Do NOT commit. The feedback file is gitignored and transient.
7. Emit the completion signal (see Exit Signal).

## Sanitization Principles

Your goal is to produce a **public-safe** GitHub issue body that preserves useful feedback about ralph and the build cycle **without exposing project-specific or proprietary details**.

For each detail in the report, apply the **least destructive safe transformation**, in this order:

1. **Preserve** — keep it if it is clearly generic, non-identifying, and analytically useful.
2. **Generalize / abstract** — keep the pattern but strip identifying specifics (rename identifiers, remove domain nouns, drop literals, generalize a finding's wording).
3. **Replace with a labeled placeholder** — when only the category matters, use a short label like `<file path>`, `<symbol>`, `<internal SQL query>`, `<deployment config>`, `<error message>`.
4. **Omit** — drop entirely if nothing useful remains after sanitization.

**Default to safety: when uncertain, generalize or omit.**

The categories below are **illustrative, not exhaustive**.

### Code, config, queries, error text, and stack traces

These often carry useful technical signal. Do not blanket-replace them — apply the ladder:

- **Generalize the pattern**: rename identifiers, remove domain nouns, strip literals, endpoints, schema names, table/column names, internal package names, and business-rule constants. A generic recursive helper, regex shape, or config skeleton may stay in generalized form.
- **Convert to pseudocode or a minimal generic example** when that preserves the technical lesson.
- **Replace with a labeled placeholder** when abstraction would still reveal proprietary logic, internal architecture, or business rules — e.g., a snippet encoding pricing rules, customer states, authorization policies, or internal schemas.
- **Summarize stack traces** to the failure mode plus a generic component label rather than copying verbatim.

### Project-specific content commonly includes

- Product, project, customer, partner, or internal codenames
- Proprietary domain terminology, workflows, state machines, or business rules
- File paths, repo names, branch names, package names, module/class/function/API names
- Code snippets, config blocks, scripts, commands, error text, stack traces (see above)
- SQL queries, migrations, table names, column names, schema details, example records
- Infrastructure details: internal URLs, hostnames, bucket names, queue/topic names, account IDs, cluster/service names, regions, deployment topology
- Secrets-adjacent details: tokens, key IDs, credential formats, env var values, auth scopes/roles/policies
- Tooling and dependency details when identifying: proprietary libraries, internal CLIs, vendor-specific setup, unusual version strings
- Ticket / PR / incident IDs, commit hashes and messages, issue links, internal doc links
- Team-member names, GitHub usernames, email addresses, org names
- Regulatory or compliance context when it identifies the project or customer domain

### Usually safe to preserve (when generic and not identifying)

- Ralph-specific terminology and loop mechanics (`gap-driven`, `process`, `REPLAN`, `COMPLETE`, etc.)
- Numeric counts and rankings (iterations, tasks, retries, REPLAN signals)
- Agent type (`amp`, `claude`, `cline`, `codex`)
- General issue categories and process failures (e.g., "missing verification criteria", "test-command flag mismatch")
- Generic language/tool references when not tied to identifying infrastructure (e.g., "Python version mismatch" or "non-default port" is fine; specific version strings or port numbers tied to an identifiable service are not)
- Suggestions for ralph-loop prompts, defaults, or behavior

### Catch-all

If any content could reasonably identify the project, customer, proprietary domain, internal architecture, or operating environment — whether **alone or in combination** with other details in the report — sanitize it using the same principles, even if it is not listed above. Compositional leaks are real: three innocuous-looking details can together identify the project.

### Human review is a backstop, not a license

The human will review and edit the sanitized output before posting it publicly. Use that as a reason **not to over-sanitize** clearly generic, useful material — useless placeholder spam wastes everyone's time. Do **not** use it as license to retain risky content: if a detail might identify the project, generalize or omit it. The human is the last line of defense, not the first.

## Rules

- **Do NOT modify** any file other than `${RALPH_HOME}/retro-feedback.md`.
- **Do NOT analyze the cycle.** The retro report is your only input.
- **Do NOT add new conclusions.** Restate existing content at a safer level of abstraction; do not draw new inferences.
- **Do NOT invent observations** to fill empty sections. Omit the section instead.

## Exit Signal

- **Sanitized feedback written, or pre-flight check failed:** output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it. Pre-flight failures emit the same signal so the loop exits cleanly without retrying a guaranteed failure.

Begin sanitization now.
