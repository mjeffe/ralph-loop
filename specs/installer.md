# Ralph Installer

## Overview

The Ralph installer is a bash script (`install.sh`) that copies Ralph files into a host project,
making it easy to add Ralph to any project.

## Installation Method

```bash
curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh | bash
```

The installer script lives at the root of the ralph-loop repository so the curl URL is minimal.

## Installer Behavior

### Pre-installation Checks

1. **Check for existing installation**
   - If `.ralph/` directory exists, refuse to install
   - Exit with code 1 and message: "Ralph is already installed. Remove .ralph/ directory to reinstall."

2. **Verify prerequisites**
   - Git repository exists (`.git/` directory)
   - Bash is available
   - Basic Unix tools available (mkdir, cp, envsubst, etc.)

### Installation Steps

1. **Create `.ralph/` directory structure**
   ```
   .ralph/
   ├── ralph               (executable)
   ├── config
   ├── implementation_plan.md (empty template)
   ├── prompts/
   │   ├── plan.md
   │   └── build.md
   ├── logs/
   └── .gitignore
   ```

2. **Copy files into `.ralph/`**
   - Copy `ralph` script (make executable)
   - Copy default `config` template
   - Copy prompt templates from `prompts/` (canonical source in ralph-loop repo)
   - Create empty `implementation_plan.md` template
   - Create `.ralph/.gitignore`

3. **Create `specs/` directory** (if it doesn't exist)
   - Create `specs/` directory
   - Create `specs/README.md` template (if it doesn't exist)

4. **Create `AGENTS.md`** (if it doesn't exist)

5. **Display success message** with next steps

### No-Overwrite Policy

The installer is **additive only** for everything outside `.ralph/`:

- `.ralph/` directory — all-or-nothing: if it exists, abort entirely
- `specs/` directory — create if missing, leave alone if present
- `specs/README.md` — create if missing, leave alone if present
- `AGENTS.md` — create if missing, leave alone if present

This ensures the installer never destroys existing project files.

## File Templates

### .ralph/config

```bash
#!/bin/bash
# Ralph configuration

# Project directories
SPECS_DIR="specs"

# Loop configuration
DEFAULT_MAX_ITERATIONS=10
MAX_RETRIES=3

# Agent configuration
AGENT_CLI="cline"  # or path to agent CLI
AGENT_ARGS="--yolo"  # additional args for agent
```

### .ralph/.gitignore

```
# Ralph session logs (generated, not committed)
logs/
```

### .ralph/implementation_plan.md (template)

```markdown
# Implementation Plan
```

This is intentionally minimal. Plan mode regenerates the plan from scratch, so there is no
value in pre-populating it with skeleton sections.

### specs/README.md (template)

```markdown
# Specs Index

This directory contains the specifications that define this project's desired behavior.
Specs are the source of truth. When adding or removing a spec, update this index.

| Spec | Description |
|------|-------------|
| [example.md](example.md) | Brief description of this spec |
```

### AGENTS.md (template)

```markdown
# Agent Configuration

## Project Overview

Brief description of this project and its structure.

## Build & Test

Describe how to run tests and verify the project builds correctly.
For example:
- Run `npm test` to execute the test suite
- Run `npm run lint` to check code style
- Run `npm run build` to verify the project compiles

## Project-Specific Guidelines

- Any project-specific rules agents should follow
- e.g., "Always run migrations after modifying schema files"
- e.g., "Keep docs/ in sync with API changes"
```

### .ralph/prompts/plan.md

The canonical plan prompt template is defined in `specs/plan-mode.md` under "Prompt Template".
The installer copies this template to `.ralph/prompts/plan.md` in the parent project.

### .ralph/prompts/build.md

The canonical build prompt template is defined in `specs/build-mode.md` under "Prompt Template".
The installer copies this template to `.ralph/prompts/build.md` in the parent project.

## Template Variable Substitution

Before invoking the agent, the ralph loop substitutes variables into prompt templates using `envsubst`. All variables defined in `config` are automatically available in prompts.

Default variables available in all prompts:

| Variable | Defined In | Description |
|----------|-----------|-------------|
| `${SPECS_DIR}` | config | Path to specs directory (e.g., `specs`) |
| `${MODE}` | runtime | Current mode: `plan`, `build`, or `prompt` |

Custom variables can be added to `config` and will be available in prompts automatically.

**Example:** If `config` contains `SPECS_DIR="specs"`, then `${SPECS_DIR}` in any prompt template will be replaced with `specs` before the prompt is sent to the agent.

## Post-Installation

After installation, the success message should read:

```
Ralph installed successfully!

Ralph is installed in .ralph/ (a hidden directory).

Next steps:
1. Review and customize .ralph/config
2. Review and customize .ralph/prompts/*.md  (optional)
3. Create your specs in specs/
4. Fill in AGENTS.md with project-specific configuration
5. Optionally create a convenience symlink:
   ln -s .ralph/ralph ralph
6. Commit Ralph files:
   git add .ralph/ specs/ AGENTS.md && git commit -m "Add Ralph"
7. Run Ralph:
   .ralph/ralph plan   (or: ./ralph plan  if you created the symlink)
```

## Installer Script Location

The installer script lives at the root of the ralph-loop repository:
```
install.sh
```

Accessible via GitHub raw URL:
```
https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh
```

## Error Handling

The installer should handle:
- Missing git repository (exit with helpful message)
- Existing `.ralph/` directory (refuse to overwrite, exit code 1)
- Permission errors (exit with helpful message)
- Missing dependencies (check and report)

All errors should exit with non-zero code and clear error message.

## Upgrade Path (Future)

Currently, upgrading Ralph requires:
1. Manual backup of customizations (config, prompts)
2. Remove `.ralph/` directory
3. Re-run installer
4. Restore customizations

A future version may support in-place upgrades.

## Uninstallation

To remove Ralph:
```bash
rm -rf .ralph/
git add .ralph/
git commit -m "Remove Ralph"
```

Specs remain in `specs/` and can be kept or removed separately.
`AGENTS.md` can also be kept or removed.
