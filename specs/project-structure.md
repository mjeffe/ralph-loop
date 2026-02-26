# Project Structure

## Overview

Ralph exists in two forms:

1. **The Ralph project** (`ralph-loop` repo) — where Ralph is developed. Ralph lives at the project root and operates on itself.
2. **Installed into a parent project** — Ralph is installed into a hidden `.ralph/` directory at the parent project's root.

In both cases, Ralph is **self-relative**: all internal paths (`prompts/`, `logs/`, `config`, `implementation_plan.md`) resolve relative to the directory containing the `ralph` script. Configuration parameters (`SPECS_DIR`, etc.) are the escape hatches that point outward to the host project's structure.

## Ralph Project Layout (ralph-loop repo)

```
ralph-loop/                         # Project root = Ralph's home
├── ralph                           # Main executable
├── install.sh                      # Installer script (for parent projects)
├── config                          # Ralph configuration
├── implementation_plan.md          # Current implementation plan
├── prompts/                        # Agent prompt templates (source of truth)
│   ├── plan.md
│   └── build.md
├── logs/                           # Session logs
│   └── session-YYYYMMDD-HHMMSS.log
├── specs/                          # Ralph's own specifications
│   ├── README.md                   # Specs index
│   └── *.md
├── AGENTS.md                       # Agent configuration for this project
├── README.md                       # Project readme
└── .git/
```

## Parent Project Layout (after installation)

```
parent-project/
├── .ralph/                         # Ralph installation (hidden directory)
│   ├── ralph                       # Main executable
│   ├── config                      # Ralph configuration
│   ├── README.md                   # Overview of how Ralph works
│   ├── implementation_plan.md      # Current implementation plan
│   ├── prompts/                    # Agent prompt templates (customizable)
│   │   ├── plan.md
│   │   └── build.md
│   ├── logs/                       # Session logs
│   │   └── session-YYYYMMDD-HHMMSS.log
│   └── .gitignore                  # Excludes logs/ from parent project's git
├── specs/                          # Parent project's specifications
│   ├── README.md                   # Specs index
│   └── *.md
├── AGENTS.md                       # Agent configuration for parent project
├── src/                            # Parent project source code (varies)
└── .git/
```

### Invocation in a Parent Project

```bash
# Direct invocation
.ralph/ralph plan

# Or create a convenience symlink at the project root
ln -s .ralph/ralph ralph
./ralph plan
```

The symlink is named `ralph` (not `.ralph`) so it's visible and easy to use. It does not conflict with the `.ralph/` directory.

## Self-Relative Path Resolution

The `ralph` script always resolves its own location at runtime:

```bash
RALPH_DIR="$(dirname "$(readlink -f "$0")")"
```

This means:
- `$RALPH_DIR/prompts/` — prompt templates
- `$RALPH_DIR/logs/` — session logs
- `$RALPH_DIR/config` — configuration file
- `$RALPH_DIR/implementation_plan.md` — current plan

This works correctly whether ralph is invoked as `.ralph/ralph`, `./ralph` (via symlink), or from any working directory.

## Configuration

Ralph uses a configuration file (`config`) located in the same directory as the `ralph` script.

### config

```bash
# Project-specific configuration
SPECS_DIR="specs"                   # Specifications directory (relative to project root)

# Loop configuration
DEFAULT_MAX_ITERATIONS=10
MAX_RETRIES=3

# Agent configuration
AGENT_TYPE="amp"                    # Built-in presets: amp, claude, cline, codex
```

`AGENT_TYPE` selects built-in presets for the agent CLI command, arguments, response parsing, and terminal display filter. Supported types: `amp`, `claude`, `cline`, `codex`.

Each type sets defaults for: `AGENT_CLI`, `AGENT_ARGS`, `AGENT_RESPONSE_FILTER`, and `AGENT_DISPLAY_FILTER`. Any of these can be overridden individually in the config file — explicit values take precedence over built-in defaults.

Example configurations:

```bash
# Minimal: just pick an agent type
AGENT_TYPE="amp"

# Override specific settings while keeping other defaults
AGENT_TYPE="amp"
AGENT_ARGS="-x --dangerously-allow-all --stream-json-thinking"
```

Note: There is no `SRC_DIR` — agents explore the project root directly. If a project has unusual structure, document it in `AGENTS.md`.

### Template Variable Substitution

Before invoking the agent, the ralph loop substitutes variables into prompt templates using `envsubst`. All variables defined in `config` are automatically available in prompts, along with runtime variables set by the loop.

Default variables available in all prompts:

| Variable | Source | Description |
|----------|--------|-------------|
| `${SPECS_DIR}` | config | Path to specs directory (e.g., `specs`) |
| `${MODE}` | runtime | Current mode: `plan`, `build`, or `prompt` |

Custom variables can be added to `config` and will be available in prompts automatically. This is the mechanism for orienting the agent to project-specific paths or settings.

Test instructions are **not** a config variable — they are described in prose in `AGENTS.md`, which the agent reads and interprets directly.

## Key Directories

### specs/

Contains all specification documents that define desired project behavior. These are the source of truth that plan mode uses to generate implementation tasks.

- `specs/README.md` — index of all specs with one-line descriptions; keep this current
- One spec per feature/component
- Written in Markdown
- Human-editable
- Version controlled with the project
- **Never copied by the installer** — specs are always project-specific

### prompts/

Agent prompt templates. In the ralph-loop repo these are the canonical source. When installed into a parent project, they are copied to `.ralph/prompts/` and can be customized per project.

### logs/

Session logs written by the ralph loop. Excluded from git via `.ralph/.gitignore` (parent projects) or the ralph-loop repo's own `.gitignore`.

## Installation

Ralph is installed via a curl-based installer:

```bash
curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh | bash
```

The installer:
1. Checks if `.ralph/` already exists (refuses to overwrite)
2. Creates `.ralph/` directory structure
3. Copies Ralph files into `.ralph/`
4. Creates `specs/` directory if it doesn't exist
5. Creates `specs/README.md` if it doesn't exist
6. Creates `AGENTS.md` if it doesn't exist
7. Never overwrites existing files outside `.ralph/`

See `specs/installer.md` for full details.

## Portability

Ralph is designed to be portable:

- Uses standard Bash (no exotic shell features)
- Requires only: Bash, Git, and the agent CLI
- All internal paths relative to the ralph script's own directory
- External paths (specs, project root) relative to working directory
- No OS-specific commands beyond POSIX standard tools
