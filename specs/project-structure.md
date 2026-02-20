# Project Structure

## Overview

Ralph is designed to be self-contained and unobtrusive, living entirely within a single `ralph/` directory in the host project. This allows Ralph to be easily added to any project without interfering with existing structure.

## Directory Layout

```
project-root/
├── specs/                          # Specification documents (source of truth)
│   ├── feature-1.md
│   ├── feature-2.md
│   └── ...
├── ralph/                          # Ralph system directory
│   ├── README.md                   # Agent orientation guide
│   ├── implementation_plan.md      # Current implementation plan
│   ├── prompts/                    # Agent prompt templates
│   │   ├── plan.md
│   │   └── build.md
│   ├── logs/                       # Session logs
│   │   └── session-YYYYMMDD-HHMMSS.log
│   └── bin/                        # Ralph executables
│       └── ralph                   # Main CLI script
├── src/                            # Project source code (configurable)
│   └── ...
└── .git/                           # Git repository
```

## Configuration

Ralph uses a configuration file to adapt to different project structures.

### ralph/config

```bash
# Project-specific configuration
SRC_DIR="src"                       # Source code directory
SPECS_DIR="specs"                   # Specifications directory
PROJECT_ROOT="."                    # Project root (usually current directory)
RALPH_DIR="ralph"                   # Ralph installation directory
PLAN_PATH="${RALPH_DIR}/implementation_plan.md"
```

## Key Directories

### specs/

Contains all specification documents that define desired project behavior. These are the source of truth that plan mode uses to generate implementation tasks.

- One spec per feature/component
- Written in Markdown
- Human-editable
- Version controlled with the project

### ralph/

Self-contained Ralph installation directory. All Ralph-specific files live here.

**Key files:**
- `README.md` - Orientation guide for agents
- `implementation_plan.md` - Current plan with ordered tasks
- `config` - Project-specific configuration
- `prompts/` - Agent prompt templates (editable per project)
- `logs/` - Session logs
- `bin/ralph` - Main CLI executable

### Source Code

Location is configurable via `SRC_DIR` in config. Ralph makes no assumptions about source code organization beyond what's specified in the config.

## Installation

Ralph is installed via a curl-based installer that copies files into the project:

```bash
curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh | bash
```

The installer:
1. Checks if `ralph/` already exists (refuses to overwrite)
2. Creates `ralph/` directory structure
3. Copies Ralph files into the project
4. Creates default config
5. Initializes empty implementation plan

After installation, the user commits Ralph files to their project repository, allowing customization of prompts and configuration.

## Template Variables

Ralph supports template variables in prompts and configuration that are substituted at runtime:

- `${PROJECT_ROOT}` - Project root directory
- `${SRC_DIR}` - Source code directory
- `${SPECS_DIR}` - Specifications directory
- `${RALPH_DIR}` - Ralph installation directory
- `${PLAN_PATH}` - Path to implementation_plan.md
- `${ITERATION}` - Current iteration number
- `${MODE}` - Current mode (plan/build/prompt)

## Portability

Ralph is designed to be portable and avoid host-specific assumptions:

- Uses standard Bash (no exotic shell features)
- Requires only: Bash, Git, and the agent CLI
- No absolute paths (all paths relative to project root)
- No OS-specific commands beyond POSIX standard tools
- Designed to work in containers/VMs (future feature)
