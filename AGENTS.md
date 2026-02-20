# Agent Configuration

## Project Overview

This is the Ralph Wiggum Loop project — an iterative development system for LLM coding agents.
The "source code" for this project is the specs (`specs/`) and the ralph scripts themselves.
There is no separate `src/` directory.

## Build & Test

This project has no automated test suite yet.

Manual verification: run `./ralph plan` or `./ralph build` and confirm expected behavior.

## Project-Specific Guidelines

- **Specs are the source of truth.** When changing behavior, update the relevant spec first.
- **Keep `specs/README.md` current.** If you add or remove a spec file, update the index.
- **Keep the root `README.md` in sync** with any significant structural or behavioral changes.
- **The ralph script lives at the project root** (`./ralph`), not in a subdirectory.
- **No `ralph/` or `.ralph/` directory exists in this project** — ralph runs from its own root.
- When modifying prompt templates in `prompts/`, also update the canonical template
  definitions: `specs/plan-mode.md` (plan prompt) and `specs/build-mode.md` (build prompt).
