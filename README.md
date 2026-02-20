# Ralph Wiggum Loop

> [!CAUTION]
> **This is my sandbox for learning the Ralph Wiggum approach to using an LLM coding agent. It is a research project. DO NOT USE.**
>
> This software is experimental, unstable, and under active development. There is no support, no documentation guarantees, and no warranty of any kind. Use at your own risk.

## Overview

The Ralph Wiggum Loop is an iterative development system that enables LLM coding agents to work on large projects by breaking work into discrete, manageable chunks with fresh context per iteration.

### The Core Problem

Large Language Models have context window limitations that prevent them from maintaining coherence across large codebases. The Ralph Wiggum Loop addresses this by:

- **Fresh Context Per Iteration** - Each loop iteration starts the agent with a clean slate
- **Persistent Memory** - Critical information persists in files between iterations
- **Incremental Progress** - Agent completes one focused task per iteration
- **Self-Documenting** - All decisions and progress tracked in version control

This enables agents to work on projects of arbitrary size while maintaining coherence through persistent documentation.

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

## Quick Start

### Installation

```bash
# In your project directory (must be a git repository)
curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh | bash
```

### Initial Setup

1. **Review configuration:**
   ```bash
   vim ralph/config
   ```

2. **Create specifications:**
   ```bash
   vim specs/my-feature.md
   ```

3. **Configure tests in AGENTS.md:**
   ```bash
   vim AGENTS.md
   ```

4. **Commit Ralph to your project:**
   ```bash
   git add ralph/ specs/ AGENTS.md
   git commit -m "Add Ralph iterative development system"
   ```

### Usage

```bash
# Generate implementation plan
ralph/bin/ralph plan

# Run build iterations (default: 10)
ralph/bin/ralph build

# Run specific number of iterations
ralph/bin/ralph build 20

# Run custom prompt
ralph/bin/ralph prompt path/to/custom-prompt.md
```

### Workflow Example

```bash
# 1. Human creates/updates specs
vim specs/authentication.md

# 2. Run plan mode to analyze and create implementation plan
ralph/bin/ralph plan

# 3. Run build iterations to implement tasks
ralph/bin/ralph build 10

# 4. Review progress
git log
cat ralph/logs/session-*.log
cat ralph/implementation_plan.md
```

## Design Principles

1. **Agent Autonomy** - Agents run in YOLO mode with full autonomy to implement
2. **Human Orchestration** - Humans control when and how the loop runs
3. **Incremental Progress** - One task per build iteration
4. **Durable Memory** - All state persists in files between iterations
5. **Cost Consciousness** - Minimize token usage through focused iterations
6. **Extensibility** - Support multiple agent types (Cline, future agents)

## Project Structure

```
project-root/
├── specs/                          # Specification documents
│   └── feature.md
├── ralph/                          # Ralph system directory
│   ├── README.md                   # This file (copied during install)
│   ├── config                      # Project configuration
│   ├── implementation_plan.md      # Current implementation plan
│   ├── prompts/                    # Agent prompt templates
│   │   ├── plan.md
│   │   └── build.md
│   ├── logs/                       # Session logs
│   └── bin/
│       └── ralph                   # Main CLI script
├── src/                            # Your project source code
├── AGENTS.md                       # Agent configuration
└── .git/                           # Git repository
```

## Documentation

Comprehensive specifications are available in the `specs/` directory:

- **[overview.md](specs/overview.md)** - System overview and design principles
- **[project-structure.md](specs/project-structure.md)** - Directory layout and configuration
- **[loop-behavior.md](specs/loop-behavior.md)** - Loop execution and CLI interface
- **[plan-mode.md](specs/plan-mode.md)** - Plan mode behavior and responsibilities
- **[build-mode.md](specs/build-mode.md)** - Build mode behavior and responsibilities
- **[spec-lifecycle.md](specs/spec-lifecycle.md)** - How to write and maintain specs
- **[installer.md](specs/installer.md)** - Installation process and templates
- **[AGENTS.md](AGENTS.md)** - Agent configuration and test setup

## Prerequisites

- Git repository initialized (`git init`)
- Bash shell
- Agent CLI installed and available in PATH (e.g., Cline)
- At least one specification document in `specs/`

## Coding Agents

I have invested several months in working with Cline in VSCode so for now, I'd like to stick with it.
However, here are some alternatives I may investigate:

**Free/OSS:**

- [Cline](https://docs.cline.bot/introduction/welcome)
- [Roo](https://github.com/RooCodeInc/Roo-Code?ref=ghuntley.com) - a fork of Cline
- [Crush](https://github.com/charmbracelet/crush)
- [Qwen Code](https://github.com/QwenLM/qwen-code)

**Paid:**
- [Claude Code](https://claude.com/product/claude-code)
- [amp](https://ampcode.com/)

## Exit Codes

Ralph uses specific exit codes to indicate different outcomes:

- `0` - Success (task complete or max iterations reached)
- `1` - General error
- `2` - Implementation plan not found (build mode)
- `3` - Test failures exceeded retries
- `4` - Agent failures exceeded retries
- `5` - Git operation failure

## Future Enhancements

- **Containerization** - Sandbox environment for safe agent execution
- **Multi-agent support** - Additional agent integrations beyond Cline
- **Enhanced statistics** - Better cost and performance tracking
- **Upgrade mechanism** - In-place upgrades without losing customizations

## References

- [Original Ralph post](https://ghuntley.com/ralph/)
- [Geoffrey Huntley's Loom project](https://github.com/ghuntley/loom/)
- [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook)
- [Accountability project](https://github.com/mikearnaldi/accountability)
- [The Real Ralph Wiggum Loop](https://thetrav.substack.com/p/the-real-ralph-wiggum-loop-what-everyone)

## License

See LICENSE file for details.
