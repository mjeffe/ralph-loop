# Agent Configuration

- Prioritize pragmatic simplicity over theoretical purity — prefer boring, readable code
- Follow SOLID principles but don't over-engineer; only add abstraction when it provides clear, immediate benefit
- Use subagents for self-contained subtasks (searches, independent edits, exploratory analysis) so their verbose output doesn't consume your main context window

## Project Overview

This is the Ralph Wiggum Loop project — an iterative development system for LLM coding agents.
The "source code" for this project is the specs (`specs/`) and the ralph scripts themselves.
There is no separate `src/` directory.

## Build & Test

Run the test suite:
```bash
./tests/test_ralph.sh
```

Running ralph itself can be expensive and time consuming. If you need to run it for testing
purposes, ONLY run it after temporarily inserting debug statements or bypasses to
short-circuit expensive operations.

## Project-Specific Guidelines

- **Specs are the source of truth.** When changing behavior, update the relevant spec first — then update the corresponding prompt template in `prompts/` to match.
- **Keep `specs/README.md` current.** If you add or remove a spec file, update the index.
- **Keep the root `README.md` in sync** with any significant structural or behavioral changes.
- The `ralph` script lives at the project root — there is no `ralph/` subdirectory.

## Commit Messages

- No agent attribution or "Generated with" footers
- Use conventional commits (feat:, fix:, etc.)
- First line under 72 characters followed by a blank line.
- Do not include `Closes #N` or `Fixes #N` in commit messages — issues often have
  multiple gaps to address across several commits. Auto-close would prematurely close
  the issue. Instead, close issues manually via `gh issue close --comment` once all
  gaps are addressed.
- Reference the issue number in commit messages (e.g., `fix: add bundling constraint (#1)`)
  so GitHub creates cross-reference links on the issue.

## GitHub CLI

When using `gh` to view issues or PRs, always use `--json` to select specific fields (e.g.,
`gh issue view 3 --json title,body,state,comments`). The default pretty-print format queries
the deprecated Projects (classic) API, which produces GraphQL warnings and may fail.

## Code Style

- Indent with 4 spaces, 120 max line length
- Use snake_case for variables and functions
- Only add comments when code is complex and requires context for future developers

