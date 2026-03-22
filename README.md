# Ralph Wiggum Loop

> [!CAUTION]
> **This is my sandbox for developing and experimenting with loop-based, LLM
> coding agent workflows (based on Geoffrey Huntley's [Ralph Wiggum post](https://ghuntley.com/ralph/)).
> I am actively using it in several projects, but it is essentially _a research project_.
> USE AT YOUR OWN RISK.**
>
> This software is experimental, unstable, and under active development. There is no support, no documentation guarantees, and no warranty of any kind. Use at your own risk.

Note also that the `sandbox` config is full of my environment preferences, as those are not yet part of a generic config.

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

- **Specs** (`specs/`) - Source of truth for desired behavior; `specs/README.md` is the index
- **Implementation Plan** (`.ralph/implementation_plan.md`) - Ordered task list with status tracking
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
   vim .ralph/config
   ```

2. **Create specifications:**
   ```bash
   vim specs/my-feature.md
   ```

3. **Configure tests in AGENTS.md:**
   ```bash
   vim AGENTS.md
   ```

4. **Optionally create a convenience symlink:**
   ```bash
   ln -s .ralph/ralph ralph
   ```

5. **Commit Ralph to your project:**
   ```bash
   git add .ralph/ specs/ AGENTS.md
   git commit -m "Add Ralph iterative development system"
   ```

### Usage

```bash
# Generate implementation plan (gap-driven, from target-state specs)
.ralph/ralph plan

# Generate implementation plan (process, from phased process specs)
# Large spec volumes are handled automatically via incremental decomposition
.ralph/ralph plan --process

# Run build iterations (default max: 10)
.ralph/ralph build

# Run up to a max specific number of iterations
.ralph/ralph build 20

# Run custom prompt
.ralph/ralph prompt path/to/custom-prompt.md

# Update ralph to the latest upstream version
.ralph/ralph update

# Sandbox — isolated Docker container for agent execution
.ralph/ralph sandbox setup            # Generate sandbox files (agent-assisted)
.ralph/ralph sandbox up               # Start the sandbox container
.ralph/ralph sandbox down             # Stop the sandbox container
.ralph/ralph sandbox reset [--all]    # Re-clone codebase (--all: delete all volumes)
.ralph/ralph sandbox shell            # Open a bash shell inside the container
.ralph/ralph sandbox status           # Show sandbox container status

# Built-in help
.ralph/ralph help                     # Show available help topics
.ralph/ralph help plan                # Planning guidance (gap-driven and process)
.ralph/ralph help specs               # How to write and maintain specs
.ralph/ralph help build               # Build iteration guidance
.ralph/ralph help sandbox             # Sandbox setup and usage
```

> **Tip:** Create a convenience symlink so you can run `./ralph` from the project root:
> ```bash
> ln -s .ralph/ralph ralph
> ```

### Workflow Example

```bash
# 1. Human creates/updates specs
vim specs/authentication.md

# 2. Run plan mode to analyze and create implementation plan
.ralph/ralph plan

# 3. Run build iterations to implement tasks
.ralph/ralph build 10

# 4. Review progress
git log
cat .ralph/logs/session-*.log
cat .ralph/implementation_plan.md
```

## Design Principles

1. **Agent Autonomy** - Agents run in YOLO mode with full autonomy to implement
2. **Human Orchestration** - Humans control when and how the loop runs
3. **Incremental Progress** - One task per build iteration
4. **Durable Memory** - All state persists in files between iterations
5. **Cost Consciousness** - Minimize token usage through focused iterations
6. **Extensibility** - Support multiple agent types (amp, claude, cline, codex)

## Project Structure

```
project-root/
├── .ralph/                         # Ralph installation (hidden directory)
│   ├── ralph                       # Main executable
│   ├── config                      # Ralph configuration
│   ├── implementation_plan.md      # Current implementation plan
│   ├── .version                    # Installed upstream commit hash
│   ├── .manifest                   # SHA256 checksums of installed files
│   ├── prompts/                    # Agent prompt templates
│   │   ├── plan.md
│   │   ├── plan-process.md
│   │   ├── build.md
│   │   └── sandbox-setup.md
│   ├── sandbox/                    # Sandbox files (generated by `ralph sandbox setup`)
│   │   ├── docker-compose.yml
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── .env.example
│   │   └── .env                    # Gitignored — contains tokens
│   ├── logs/                       # Session logs
│   └── .gitignore                  # Excludes logs/ from git
├── specs/                          # Your project specifications
│   ├── README.md                   # Specs index
│   └── feature.md
├── AGENTS.md                       # Agent configuration (project-specific)
└── .git/                           # Git repository
```

## Documentation

Comprehensive specifications are available in the **[specs/](specs/README.md)** directory:

- **[overview.md](specs/overview.md)** - System overview and design principles
- **[project-structure.md](specs/project-structure.md)** - Directory layout and configuration
- **[loop-behavior.md](specs/loop-behavior.md)** - Loop execution and CLI interface
- **[plan-mode.md](specs/plan-mode.md)** - Plan mode behavior and responsibilities
- **[build-mode.md](specs/build-mode.md)** - Build mode behavior and responsibilities
- **[spec-lifecycle.md](specs/spec-lifecycle.md)** - How to write and maintain specs
- **[installer.md](specs/installer.md)** - Installation process and templates
- **[updater.md](specs/updater.md)** - Update mechanism and manifest tracking
- **[sandbox-cli.md](specs/sandbox-cli.md)** - Sandbox lifecycle commands
- **[sandbox-setup-prompt.md](specs/sandbox-setup-prompt.md)** - Sandbox setup prompt template
- **[agent-scripts.md](specs/agent-scripts.md)** - Agent script contract and extensibility
- **[process-planning.md](specs/process-planning.md)** - Process planning mode
- **[incremental-planning.md](specs/incremental-planning.md)** - Incremental process planning for large spec volumes
- **[help-system.md](specs/help-system.md)** - CLI help system
- **[AGENTS.md](AGENTS.md)** - Agent configuration for this project

## Prerequisites

- Git repository initialized (`git init`)
- Bash shell
- Agent CLI installed and available in PATH (e.g., amp, cline)
- At least one specification document in `specs/`

## Exit Codes

Ralph uses specific exit codes to indicate different outcomes:

- `0` - Success (task complete or max iterations reached)
- `1` - General error
- `2` - Implementation plan not found (build mode)
- `4` - Agent failures exceeded retries
- `5` - Git operation failure

## Future Enhancements

- **Enhanced statistics** - Better cost and performance tracking. I have no idea how much of the context window is used in a given iteration. That is a crucial missing bit for tuning prompts. This is an inherent limitation of the shell based pipe into a coding agent approach.

## Coding Agents

I generally favor open source and have used Cline in VSCode for several months,
however, after discovering [amp](https://ampcode.com), there is no looking back!
It is far more expensive because I cannot control the models I use, but these
guys have invested in the research to figure out which models work best for each
type of work, and oh my does it pay off!

Having said that, here are some alternatives I may investigate:

**Free/OSS:**

- [Cline](https://docs.cline.bot/introduction/welcome)
- [Roo](https://github.com/RooCodeInc/Roo-Code?ref=ghuntley.com) - a fork of Cline
- [Crush](https://github.com/charmbracelet/crush)
- [Qwen Code](https://github.com/QwenLM/qwen-code)

**Paid:**
- [Claude Code](https://claude.com/product/claude-code)
- [amp](https://ampcode.com/)

## References

- [Original Ralph post](https://ghuntley.com/ralph/)
- [Geoffrey Huntley's Loom project](https://github.com/ghuntley/loom/)
- [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook)
- [Accountability project](https://github.com/mikearnaldi/accountability)
- [The Real Ralph Wiggum Loop](https://thetrav.substack.com/p/the-real-ralph-wiggum-loop-what-everyone)

## License

See LICENSE file for details.
