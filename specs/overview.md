# Ralph Wiggum Loop - Overview

## Purpose

The Ralph Wiggum Loop is an iterative development system that enables LLM coding agents to work on large projects by breaking work into discrete, manageable chunks with fresh context per iteration.

## Core Problem

Large Language Models have context window limitations that prevent them from maintaining coherence across large codebases. The Ralph Wiggum Loop addresses this by:

- **Fresh Context Per Iteration** - Each loop iteration starts the agent with a clean slate
- **Persistent Memory** - Critical information persists in files between iterations
- **Incremental Progress** - Agent completes one focused task per iteration
- **Self-Documenting** - All decisions and progress tracked in version control

## How It Works

### The Loop

Ralph operates in two primary modes within an iterative loop:

1. **Plan Mode** - Agent analyzes specs and source code to create/update an implementation plan
2. **Build Mode** - Agent selects one task from the plan, implements it, and commits

Each iteration:
- Starts with fresh agent context
- Reads persistent state from files (specs, plan, code)
- Makes incremental progress
- Commits changes to git
- Logs all activity

### Key Components

- **Specs** (`specs/`) - Source of truth for desired behavior; `specs/README.md` is the index
- **Implementation Plan** (`implementation_plan.md`) - Ordered task list with status tracking
- **Session Log** - Complete record of all iterations in a run
- **Git Commits** - Audit trail of all changes

### Why Plan and Build Are Separate

The separation is deliberate:

- **Context efficiency.** Planning requires reading all specs and surveying the entire codebase. If every build iteration also re-analyzed everything, it would burn enormous context (and cost) on repeated analysis.
- **Persistent memory.** The implementation plan is the compressed, durable memory that survives across fresh-context iterations. Without it, each build iteration would need to rediscover what work remains.
- **Focus.** Build agents produce better work when they have a single, well-defined task rather than simultaneously analyzing the whole project and deciding what to build.

To prevent plan staleness, build agents review remaining tasks after each implementation and can signal `<promise>REPLAN</promise>` when the plan needs significant restructuring.

## Design Principles

1. **Agent Autonomy** - Agents run in YOLO mode with full autonomy to implement
2. **Human Orchestration** - Humans control when and how the loop runs
3. **Incremental Progress** - One task per build iteration
4. **Durable Memory** - All state persists in files between iterations
5. **Cost Consciousness** - Minimize token usage through focused iterations
6. **Extensibility** - Support multiple agent types via `AGENT_TYPE` presets (amp, claude, cline, codex)

## Workflow Example

```bash
# Human creates/updates specs
vim specs/feature.md

# Run plan mode to analyze and create implementation plan
./ralph plan

# Run build iterations to implement tasks
./ralph build 10

# Review progress
git log
cat logs/session-*.log          # ralph-loop repo
cat .ralph/logs/session-*.log   # parent project
```

## Two Deployment Scenarios

### Ralph Project (ralph-loop repo)
Ralph lives at the project root and operates on itself. The `ralph` script, `prompts/`, `logs/`, and `config` all live at the root alongside `specs/`.

### Parent Project (after installation)
Ralph is installed into `.ralph/` at the project root. The `specs/` directory and `AGENTS.md` live outside `.ralph/` and are project-specific — they are never overwritten by the installer.

See `specs/project-structure.md` for full details.

## Non-Goals (This Phase)

- Multi-agent coordination
- Parallel task execution
- Web UI
- Cloud deployment
- Containerization/sandboxing (future feature)
