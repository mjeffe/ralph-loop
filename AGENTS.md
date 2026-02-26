# Agent Configuration

- You are an expert software developer
- You always strive for simple and elegant solutions using SOLID programming principles and good object oriented design
- You prioritize pragmatic simplicity over theoretical purity, unless the distinction provides significant practical benefits
- DO NOT over-engineer
- Follow SOLID programming principles
- Keep solutions simple and direct
- Prefer boring, readable code

## Project Overview

This is the Ralph Wiggum Loop project — an iterative development system for LLM coding agents.
The "source code" for this project is the specs (`specs/`) and the ralph scripts themselves.
There is no separate `src/` directory.

## Build & Test

This project has no automated test suite yet.

Running ralph can be expensive and time consuming. If you need to run it for testing purposes,
**only** run it after temporarily inserting debug statements or bypasses, or swap out the default
prompts with something very simple.

## Project-Specific Guidelines

- **Specs are the source of truth.** When changing behavior, update the relevant spec first.
- **Keep `specs/README.md` current.** If you add or remove a spec file, update the index.
- **Keep the root `README.md` in sync** with any significant structural or behavioral changes.
- **The ralph script lives at the project root** (`./ralph`), not in a subdirectory.
- **No `ralph/` or `.ralph/` directory exists in this project** — ralph runs from its own root.
- When modifying prompt templates in `prompts/`, also update the canonical template
  definitions: `specs/plan-mode.md` (plan prompt) and `specs/build-mode.md` (build prompt).

## Commit Messages

- NO agent attribution
- NO "Generated with" footers
- Use conventional commits (feat:, fix:, etc.)
- First line under 72 characters followed by a blank line.

## Code Style

-**Formatting**: indent with 4 spaces, 120 max char line length
-**Naming**: favor snake_case in shell and python, and follow Laravel conventions for PHP
-**Comments**: Only add comments when code is complex and requires context for future developers

