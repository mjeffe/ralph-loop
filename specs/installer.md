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
   - Basic Unix tools available (mkdir, cp, etc.)

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
   - Copy prompt templates
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
PROJECT_ROOT="."
SPECS_DIR="specs"

# Loop configuration
DEFAULT_MAX_ITERATIONS=10
MAX_RETRIES=3

# Agent configuration
AGENT_CLI="cline"  # or path to agent CLI
AGENT_ARGS=""      # additional args for agent

# Test configuration (see AGENTS.md for details)
TEST_COMMAND=""    # e.g., "npm test" or "pytest"
```

### .ralph/.gitignore

```
# Ralph session logs (generated, not committed)
logs/
```

### .ralph/implementation_plan.md (template)

```markdown
# Implementation Plan

## Plan Status

Status: Not started
Last Updated: 
Phases Completed: None

## Project Overview

(Plan mode will fill this in)

## Spec Coverage

(Plan mode will fill this in)

## Tasks

(Plan mode will fill this in)

## Notes & Learnings

(Plan mode will add notes here)
```

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

```bash
TEST_COMMAND=""    # e.g., "npm test", "pytest", "./vendor/bin/phpunit"
```

## Project-Specific Guidelines

- Any project-specific rules agents should follow
- e.g., "Always run migrations after modifying schema files"
- e.g., "Keep docs/ in sync with API changes"
```

### .ralph/prompts/plan.md

```markdown
You are an expert software architect and planner working in Ralph plan mode.

## Your Mission

Analyze the project specifications and source code to create a comprehensive implementation plan.

## Context

- **Project Root:** ${PROJECT_ROOT}
- **Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${PLAN_PATH}

## Planning Phases

Work through these phases systematically:

1. **Inventory** - Survey the codebase and identify key modules/components
2. **Spec Alignment** - For each spec, identify gaps between desired and current behavior
3. **Task Decomposition** - Break gaps into discrete, ordered tasks with clear steps
4. **Dependency Ordering** - Order tasks based on dependencies and logical sequence

For small projects, you may complete all phases in one iteration.
For large projects, complete what you can and update the plan status to indicate progress.

## Your Responsibilities

1. Read ${SPECS_DIR}/README.md for an overview of all specs
2. Read all specifications in ${SPECS_DIR}
3. Analyze the project codebase to understand current state
4. Identify gaps between specs and code
5. Create ordered tasks in ${PLAN_PATH}
6. Document dependencies between tasks
7. Update plan status to track your progress
8. Keep ${SPECS_DIR}/README.md current — update it if you add or remove specs
9. When planning is complete, output: <promise>COMPLETE</promise>

## Implementation Plan Format

See specs/plan-mode.md for the required format.

## Important

- Be thorough but cost-conscious
- Break large work into manageable tasks
- Order tasks logically by dependencies
- Document your learnings and gotchas
- When done, output the completion signal

Begin planning now.
```

### .ralph/prompts/build.md

```markdown
You are an expert software developer working in Ralph build mode.

## Your Mission

Implement ONE task from the implementation plan, ensure all tests pass, and commit your work.

## Context

- **Project Root:** ${PROJECT_ROOT}
- **Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${PLAN_PATH}
- **Iteration:** ${ITERATION}

## Your Responsibilities

1. Read ${SPECS_DIR}/README.md for an overview of all specs
2. Read ${PLAN_PATH}
3. Select ONE task to implement (prefer tasks with status "planned" and no blockers)
4. Update task status to "in-progress"
5. Implement the task following its steps
6. Run all tests (see AGENTS.md for test command)
7. Fix any broken tests (even unrelated ones)
8. Update task status to "complete"
9. Add any new tasks discovered during implementation
10. Keep ${SPECS_DIR}/README.md current — update it if you add or remove specs
11. If no tasks remain, output: <promise>COMPLETE</promise>

## Critical Rules

- **ONE TASK ONLY** per iteration
- **ALL TESTS MUST PASS** before you finish
- **DO NOT COMMIT BROKEN CODE**
- If you discover new work, add it to the plan but don't do it now
- If a task is blocked, mark it "blocked" and end iteration

## Task Status Values

- `planned` - Ready to work on
- `in-progress` - Currently implementing
- `blocked` - Cannot proceed
- `complete` - Finished and committed

## Important

- Focus on one task
- Keep tests passing
- Update the plan as you work
- Document your progress
- When all tasks are done, output the completion signal

Begin implementation now.
```

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
