# Specs Index

This directory contains the specifications that define the Ralph Wiggum Loop system.
Specs are the source of truth for desired behavior. When adding or removing a spec, update this index.

| Spec | Description |
|------|-------------|
| [overview.md](overview.md) | System purpose, design principles, and high-level workflow |
| [project-structure.md](project-structure.md) | Directory layout, configuration, and self-hosting vs. parent project structure |
| [loop-behavior.md](loop-behavior.md) | Loop execution, CLI interface, logging, and exit codes |
| [plan-mode.md](plan-mode.md) | Plan mode behavior, implementation plan format, and agent responsibilities |
| [build-mode.md](build-mode.md) | Build mode behavior, task selection, and iteration outcomes |
| [spec-lifecycle.md](spec-lifecycle.md) | How to write, maintain, and evolve specs |
| [installer.md](installer.md) | Installation process, file templates, and post-install configuration |
| [agent-scripts.md](agent-scripts.md) | Agent script contract (`AGENT_OUTPUT_FORMAT`, `agent_invoke`, stock hooks), supported agents, and adding new agents |
| [output-pipeline.md](output-pipeline.md) | Agent output processor `lib/format_output.py`: CLI, summary JSON, screen/log display, signal constraint, and stream formats |
| [updater.md](updater.md) | Update mechanism, manifest tracking, and preserving user customizations |
| [sandbox-cli.md](sandbox-cli.md) | Sandbox lifecycle commands (`up`, `down`, `reset`, `shell`, `status`, `setup`) — implement first |
| [sandbox-setup-prompt.md](sandbox-setup-prompt.md) | Multi-container, multi-pass prompt pipeline: project analysis, file generation, validation, repair, and migration — implement after sandbox-cli |
| [process-planning.md](process-planning.md) | Process planning mode: phased playbooks, CLI flags, plan-type metadata, and prompt template |
| [incremental-planning.md](incremental-planning.md) | Incremental process planning: decomposition ledger, skeleton-first workflow, and volume hint for large spec volumes |
| [align-specs.md](align-specs.md) | Align-specs mode: update target-state specs after process-spec migrations, build-completion nudge |
| [help-system.md](help-system.md) | CLI help system: `ralph help <topic>` for operational guidance on planning, specs, build, and sandbox |
| [adhoc-prompts.md](adhoc-prompts.md) | Shipped ad-hoc prompt set: design intent, structural conventions, durable-state patterns, and contract for `prompts/adhoc-*.md` |
| [tech-debt.md](tech-debt.md) | Known structural debt, brittle areas, and migration strategy — when and how to move beyond bash |
| [known-issues.md](known-issues.md) | User-facing bugs without workarounds that users should know about before they bite |
| [open-questions.md](open-questions.md) | Unresolved questions, speculative ideas, and design tensions needing more thought |
| [proposals/](proposals/) | Design proposals (spec pre-drafts) — provisional, not yet committed to |

## Process Specs

Process specs describe ordered, phased work — migrations, rewrites, staged rollouts. They drive `ralph plan --process`. See `specs/process-planning.md` for the planning mechanics.

| Spec | Description |
|------|-------------|
| [process/output-pipeline-python.md](process/output-pipeline-python.md) | Build lib/format_output.py, the single-pass Python agent output processor (tech-debt item 3); integration is a separate supervised step |
