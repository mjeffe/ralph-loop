# Ralph Wiggum Loop

> [!CAUTION]
> **This is my sandbox for developing and experimenting with loop-based, LLM
> coding agent workflows (based on Geoffrey Huntley's [Ralph Wiggum post](https://ghuntley.com/ralph/)).
> I am actively using it in several projects, but it is essentially _a research project_.
> USE AT YOUR OWN RISK.**
>
> This software is experimental, unstable, and under active development. There is no support, no documentation guarantees, and no warranty of any kind. Use at your own risk.

## What Is Ralph?

Ralph is a bash script that runs an LLM coding agent in a loop. Each iteration, it feeds the agent a prompt, the agent does work and commits, then the loop starts a fresh iteration with clean context. Files on disk — specs, an implementation plan, and the codebase itself — are the agent's memory between iterations.

This solves the core problem with using LLM agents on large projects: context windows are finite. Rather than trying to hold an entire project in context, Ralph breaks work into discrete chunks where each iteration makes one focused piece of progress and writes everything important to disk before the next iteration starts fresh.

## How It Works

Ralph operates in two primary modes:

1. **Plan** — The agent reads your specs and surveys the codebase to produce an ordered implementation plan (a markdown file with tasks, statuses, and dependencies).

2. **Build** — The agent picks one task from the plan, implements it, runs tests, updates the plan, and commits. Repeat.

```
Human writes specs
       |
       v
  ralph plan  --->  implementation_plan.md
                         |
                         v
                    ralph build (loop)
                    .-------------------.
                    | 1. Read plan       |<--.
                    | 2. Pick next task  |   |
                    | 3. Implement+test  |   |
                    | 4. Mark complete   |   |
                    | 5. git commit      |---'
                    '-------------------'
                         |
                    Exit: all done, max
                    iterations, or REPLAN
```

### Why Separate Plan and Build?

Planning requires reading all specs and surveying the entire codebase. If every build iteration also re-analyzed everything, it would burn enormous context on repeated work. The implementation plan is the compressed, durable memory that survives across fresh-context iterations — build agents produce better work when they have a single, well-defined task rather than simultaneously analyzing the whole project and deciding what to build.

### Planning Modes

Ralph supports two planning strategies:

- **Gap-driven** (`ralph plan`) — You write target-state specs describing what the system should be. The planner compares specs to code and generates tasks to close the gaps. Use this when you know the destination but not the exact steps.

- **Sequence-constrained** (`ralph plan --process`) — You write process specs with explicit phases and ordering (migrations, staged rollouts, phased refactors). The planner decomposes your phases into tasks while preserving your sequencing. Use this when the order of work matters.

Run `ralph help plan` and `ralph help specs` for detailed guidance on choosing between them.

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
   Set `AGENT` to your coding agent (`amp`, `claude`, `cline`, `codex`).

2. **Write specifications:**
   ```bash
   vim specs/my-feature.md
   ```
   Describe what the system should do. One feature per spec, be specific, include test criteria.

3. **Configure your project in AGENTS.md:**
   ```bash
   vim AGENTS.md
   ```
   Tell agents how to build, test, and lint your project. This file is read every iteration.

4. **Commit Ralph to your project:**
   ```bash
   git add .ralph/ specs/ AGENTS.md
   git commit -m "Add Ralph iterative development system"
   ```

5. **Run it:**
   ```bash
   .ralph/ralph plan          # Generate implementation plan
   .ralph/ralph build 10      # Run up to 10 build iterations
   ```

6. **Review progress:**
   ```bash
   git log --oneline                       # What was committed
   cat .ralph/implementation_plan.md       # Task statuses
   cat .ralph/logs/session-*.log           # Detailed session logs
   ```
   See `ralph help retro` for deeper guidance on reviewing build cycles.

> **Tip:** Create a convenience symlink so you can run `./ralph` from the project root:
> ```bash
> ln -s .ralph/ralph ralph
> ```

## Usage

```bash
ralph plan                        # Gap-driven planning from target-state specs
ralph plan --process              # Sequence-constrained planning from process specs
ralph build [max_iterations]      # Build tasks from the implementation plan
ralph prompt <file>               # Run a custom prompt in the loop
ralph align-specs                 # Update target-state specs after a process migration
ralph update                      # Update ralph to the latest upstream version
ralph sandbox setup               # Generate a Docker sandbox for isolated agent execution
ralph help                        # List available help topics
ralph help <topic>                # Detailed guidance (specs, plan, build, prompt, sandbox, ...)
```

Ralph also provides an optional Docker-based sandbox for running agents in an isolated container. Run `ralph help sandbox` for setup and usage details.

Run `ralph` with no arguments for CLI usage, or `ralph help` to explore help topics.

## Design Principles

1. **Agent Autonomy** — Agents run with full autonomy to implement tasks. Specs define *what* to build; the agent decides *how*.
2. **Human Orchestration** — Humans write specs, control when the loop runs, and review results.
3. **Incremental Progress** — One task per build iteration. Small, focused, committable units of work.
4. **Durable Memory** — All state persists in files. The agent starts fresh each iteration and reads everything it needs from disk.
5. **Cost Consciousness** — Focused iterations minimize token usage. No wasted context on re-analysis.
6. **Extensibility** — Pluggable agent scripts (`.ralph/agents/`) make it easy to add new coding agents.

## Project Structure (Installed)

After installation, Ralph lives in `.ralph/` inside your project:

```
your-project/
├── .ralph/                         # Ralph installation
│   ├── ralph                       # Main executable
│   ├── config                      # Configuration (agent, iterations, specs path)
│   ├── implementation_plan.md      # Current plan (generated by ralph plan)
│   ├── agents/                     # Agent scripts (amp.sh, claude.sh, cline.sh, codex.sh)
│   ├── prompts/                    # Prompt templates (customizable per project)
│   │   ├── plan.md
│   │   ├── build.md
│   │   └── ...
│   ├── sandbox/                    # Sandbox files (generated by ralph sandbox setup)
│   └── logs/                       # Session logs (gitignored)
├── specs/                          # Your specifications (source of truth)
│   ├── README.md                   # Specs index
│   └── *.md                        # One spec per feature
├── AGENTS.md                       # Project-specific agent instructions
└── .git/
```

## References

- [Original Ralph post](https://ghuntley.com/ralph/) — Geoffrey Huntley's concept
- [Geoffrey Huntley's Loom project](https://github.com/ghuntley/loom/)
- [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook)
- [Accountability project](https://github.com/mikearnaldi/accountability)
- [The Real Ralph Wiggum Loop](https://thetrav.substack.com/p/the-real-ralph-wiggum-loop-what-everyone)

## License

See LICENSE file for details.
