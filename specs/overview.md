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

- **Specs** (`specs/`) - Source of truth for desired behavior
- **Implementation Plan** (`ralph/implementation_plan.md`) - Ordered task list with status tracking
- **Session Log** - Complete record of all iterations in a run
- **Git Commits** - Audit trail of all changes

## Design Principles

1. **Agent Autonomy** - Agents run in YOLO mode with full autonomy to implement
2. **Human Orchestration** - Humans control when and how the loop runs
3. **Incremental Progress** - One task per build iteration
4. **Durable Memory** - All state persists in files between iterations
5. **Cost Consciousness** - Minimize token usage through focused iterations
6. **Extensibility** - Support multiple agent types (Cline, future agents)

## Workflow Example

```bash
# Human creates/updates specs
vim specs/feature.md

# Run plan mode to analyze and create implementation plan
ralph plan

# Run build iterations to implement tasks
ralph build 10

# Review progress
git log
cat ralph/logs/session-*.log
```

## Non-Goals (This Phase)

- Multi-agent coordination
- Parallel task execution
- Web UI
- Cloud deployment
- Containerization/sandboxing (future feature)
