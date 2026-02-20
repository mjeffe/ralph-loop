# Ralph Installer

## Overview

The Ralph installer is a bash script that copies Ralph files into a host project, making it easy to add Ralph to any project.

## Installation Method

```bash
curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh | bash
```

## Installer Behavior

### Pre-installation Checks

1. **Check for existing installation**
   - If `ralph/` directory exists, refuse to install
   - Exit with code 1 and message: "Ralph is already installed. Remove ralph/ directory to reinstall."

2. **Verify prerequisites**
   - Git repository exists (`.git/` directory)
   - Bash is available
   - Basic Unix tools available (mkdir, cp, etc.)

### Installation Steps

1. **Create directory structure**
   ```
   ralph/
   ├── README.md
   ├── config
   ├── implementation_plan.md (empty template)
   ├── prompts/
   │   ├── plan.md
   │   └── build.md
   ├── logs/
   └── bin/
       └── ralph
   ```

2. **Copy files**
   - Copy README.md from this project to `ralph/README.md`
   - Copy default config template
   - Copy prompt templates
   - Copy ralph CLI script
   - Create empty implementation_plan.md template

3. **Set permissions**
   - Make `ralph/bin/ralph` executable

4. **Create specs directory** (if it doesn't exist)
   - Create `specs/` directory
   - Add `.gitkeep` file

5. **Display success message**
   ```
   Ralph installed successfully!
   
   Next steps:
   1. Review and customize ralph/config
   2. Review and customize ralph/prompts/*.md
   3. Create specs in specs/ directory
   4. Commit Ralph files: git add ralph/ specs/ && git commit -m "Add Ralph"
   5. Run: ralph/bin/ralph plan
   ```

## File Templates

### ralph/config

```bash
#!/bin/bash
# Ralph configuration

# Project directories
PROJECT_ROOT="."
SRC_DIR="src"
SPECS_DIR="specs"
RALPH_DIR="ralph"

# Ralph paths
PLAN_PATH="${RALPH_DIR}/implementation_plan.md"
LOG_DIR="${RALPH_DIR}/logs"
PROMPT_DIR="${RALPH_DIR}/prompts"

# Agent configuration
AGENT_CLI="cline"  # or path to agent CLI
AGENT_ARGS=""      # additional args for agent

# Loop configuration
DEFAULT_MAX_ITERATIONS=10
MAX_RETRIES=3

# Test configuration (see AGENTS.md for details)
TEST_COMMAND=""    # e.g., "npm test" or "pytest"
```

### ralph/implementation_plan.md (template)

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

### ralph/prompts/plan.md

```markdown
You are an expert software architect and planner working in Ralph plan mode.

## Your Mission

Analyze the project specifications and source code to create a comprehensive implementation plan.

## Context

- **Project Root:** ${PROJECT_ROOT}
- **Source Code:** ${SRC_DIR}
- **Specifications:** ${SPECS_DIR}
- **Implementation Plan:** ${PLAN_PATH}

## Planning Phases

You should work through these phases systematically:

1. **Inventory** - Survey the codebase and identify key modules/components
2. **Spec Alignment** - For each spec, identify gaps between desired and current behavior
3. **Task Decomposition** - Break gaps into discrete, ordered tasks with clear steps
4. **Dependency Ordering** - Order tasks based on dependencies and logical sequence

For small projects, you may complete all phases in one iteration.
For large projects, complete what you can and update the plan status to indicate progress.

## Your Responsibilities

1. Read all specifications in ${SPECS_DIR}
2. Analyze source code in ${SRC_DIR}
3. Identify gaps between specs and code
4. Create ordered tasks in ${PLAN_PATH}
5. Document dependencies between tasks
6. Update plan status to track your progress
7. When planning is complete, output: <promise>COMPLETE</promise>

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

### ralph/prompts/build.md

```markdown
You are an expert software developer working in Ralph build mode.

## Your Mission

Implement ONE task from the implementation plan, ensure all tests pass, and commit your work.

## Context

- **Project Root:** ${PROJECT_ROOT}
- **Source Code:** ${SRC_DIR}
- **Specifications:** ${SPECS_DIR}
- **Implementation Plan:** ${PLAN_PATH}
- **Iteration:** ${ITERATION}

## Your Responsibilities

1. Read ${PLAN_PATH}
2. Select ONE task to implement (prefer tasks with status "planned" and no blockers)
3. Update task status to "in-progress"
4. Implement the task following its steps
5. Run all tests (see AGENTS.md for test command)
6. Fix any broken tests (even unrelated ones)
7. Update task status to "complete"
8. Add any new tasks discovered during implementation
9. If no tasks remain, output: <promise>COMPLETE</promise>

## Critical Rules

- **ONE TASK ONLY** per iteration
- **ALL TESTS MUST PASS** before you finish
- **DO NOT COMMIT BROKEN CODE**
- If you discover new work, add it to the plan but don't do it now
- If a task is blocked, mark it "blocked" and end iteration

## Discovering New Work

If you find bugs or missing features:
- Add them as new tasks in the plan
- Create specs if needed for complex features
- Continue with your current task

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

After installation, the user should:

1. **Review configuration**
   ```bash
   vim ralph/config
   ```

2. **Customize prompts** (optional)
   ```bash
   vim ralph/prompts/plan.md
   vim ralph/prompts/build.md
   ```

3. **Create AGENTS.md** (see AGENTS.md spec)
   ```bash
   vim AGENTS.md
   ```

4. **Create initial specs**
   ```bash
   vim specs/feature-1.md
   ```

5. **Commit Ralph to project**
   ```bash
   git add ralph/ specs/ AGENTS.md
   git commit -m "Add Ralph iterative development system"
   ```

6. **Run plan mode**
   ```bash
   ralph/bin/ralph plan
   ```

## Upgrade Path (Future)

Currently, upgrading Ralph requires:
1. Manual backup of customizations (config, prompts)
2. Remove `ralph/` directory
3. Re-run installer
4. Restore customizations

A future version may support in-place upgrades.

## Uninstallation

To remove Ralph:
```bash
rm -rf ralph/
git add ralph/
git commit -m "Remove Ralph"
```

Specs remain in `specs/` and can be kept or removed separately.

## Installer Script Location

The installer script should live at:
```
scripts/install.sh
```

And be accessible via GitHub raw URL:
```
https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh
```

## Error Handling

The installer should handle:
- Missing git repository (exit with helpful message)
- Existing ralph/ directory (refuse to overwrite)
- Permission errors (exit with helpful message)
- Missing dependencies (check and report)

All errors should exit with non-zero code and clear error message.
