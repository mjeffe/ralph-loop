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
| [agent-scripts.md](agent-scripts.md) | Agent script contract, required/optional functions, and adding new agents |
| [updater.md](updater.md) | Update mechanism, manifest tracking, and preserving user customizations |
| [sandbox-cli.md](sandbox-cli.md) | Sandbox lifecycle commands (`up`, `down`, `reset`, `shell`, `status`, `setup`) — implement first |
| [sandbox-setup-prompt.md](sandbox-setup-prompt.md) | Multi-container, multi-pass prompt pipeline: project analysis, file generation, validation, repair, and migration — implement after sandbox-cli |
| [process-planning.md](process-planning.md) | Process planning mode: phased playbooks, CLI flags, plan-type metadata, and prompt template |
| [incremental-planning.md](incremental-planning.md) | Incremental process planning: decomposition ledger, skeleton-first workflow, volume hint, and phase collapsing for large spec volumes |
| [align-specs.md](align-specs.md) | Align-specs mode: update target-state specs after process-spec migrations, build-completion nudge |
| [help-system.md](help-system.md) | CLI help system: `ralph help <topic>` for operational guidance on planning, specs, build, and sandbox |
| [plan-context-management.md](plan-context-management.md) | Infrastructure-managed plan views: plan header injection, smart task overview, deterministic task selection for process plans, split build prompts, replacing phase collapsing |
