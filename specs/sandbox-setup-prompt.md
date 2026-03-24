# Sandbox Setup Prompt — Agent Instructions for Generating Sandbox Files

## Implementation Order

This spec **must be implemented after** `sandbox-cli.md`. It creates/modifies
files in `prompts/` and adds stack detection logic to `sandbox_setup()` in the
`ralph` script. The CLI plumbing that invokes this prompt already exists after
`sandbox-cli.md` is implemented.

## Overview

The `prompts/sandbox-setup.md` file is a managed upstream prompt template invoked
by `ralph sandbox setup`. It instructs the configured agent to analyze the target
project and generate four sandbox files: `Dockerfile`, `entrypoint.sh`,
`docker-compose.yml`, and `.env.example`.

This is a managed file (tracked in `.manifest`, updated by `ralph update`).

## Prompt Structure

The prompt is organized around outcomes and decision rules rather than
prescriptive shell commands. This structure gives the agent enough guidance to
succeed without micromanaging implementation details.

### Sections (in order)

1. **Definition of Done** — concrete success criteria the agent must satisfy
   before declaring completion. This is the most important section.
2. **Priority Order** — explicit trade-off hierarchy so the agent knows what
   matters most when it can't do everything perfectly:
   1. Container boots reliably
   2. Repo clones and credentials work
   3. Dependencies install
   4. Required services run
   5. Migrations and bootstrap
   6. Developer ergonomics
3. **Project Analysis** — what to read, what conclusions to extract, and
   decision rules for ambiguous cases.
4. **Hard Constraints** — non-negotiable architectural rules (single container,
   named volumes, non-root user, etc.).
5. **Generated Files** — responsibility-based descriptions of each file the
   agent must create. Lists what each file must accomplish, not exact commands.
6. **Self-Validation Checklist** — cross-checks the agent must perform before
   finishing (ports match services, env vars are documented, etc.).
7. **Appendices** — battle-tested shell snippets and known gotchas for specific
   failure modes (git credential handling, YAML syntax pitfalls, idempotency
   patterns). Separated from the main body so they inform without dominating.

### Design Rationale

Previous iterations of this prompt mixed goal definition, discovery logic,
architectural constraints, and bug-workaround snippets at the same priority
level. Agents would optimize for local compliance (reproducing exact snippets)
instead of building a coherent sandbox. The restructured prompt puts outcomes
first, keeps hard requirements short, and moves implementation-level details to
appendices where agents can reference them without fixating on them.

## What the Setup Agent Analyzes

The prompt instructs the agent to build a **project profile** by examining:

- **Package manifests:** `composer.json`, `package.json`, `Gemfile`, `go.mod`,
  `requirements.txt`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, etc.
- **Existing containerization:** `Dockerfile`, `docker-compose.yml`,
  `.devcontainer/`, `docker/`, or similar directories — for reference only.
  Do not copy them, but reuse authoritative details like runtime versions,
  package names, and startup commands.
- **Environment configuration:** `.env.example`, `config/database.yml`, or
  equivalent files that reveal database engine, cache driver, mail service, etc.
- **CI configuration:** `.github/workflows/`, `.gitlab-ci.yml` — often reveals
  the full service stack.
- **Agent instructions:** `AGENTS.md` — documents how to run the project.
- **Test configuration:** `phpunit.xml`, `jest.config.*`, `pytest.ini`, etc. —
  reveals test database requirements.
- **Test environment files:** `.env.testing`, `.env.test`, or equivalent — these
  often contain empty secrets that must be generated for tests to pass. Their
  presence also signals a potential env var conflict in an all-in-one container
  (see entrypoint step 5a).
- **Ralph dependencies:** The `dependencies` file in ralph's home directory lists
  system packages (apt) that ralph itself requires at runtime. All listed packages
  must be installed in the Dockerfile.
- **Sandbox preferences:** `sandbox-preferences.md` in ralph's home directory
  contains user-defined sandbox environment preferences (e.g., preferred editor,
  additional packages, configuration choices). The agent incorporates these into
  the generated files. This is a managed file (installed/updated like `config`).

The agent must extract these conclusions from the sources above:

- Primary runtime(s) and version(s)
- Package manager(s) — prefer lockfiles over manifests for tool choice
- Required services for tests and dev (DB, cache, search, mail, etc.)
- Long-running processes the project needs (web server, queue worker,
  Vite/HMR dev server, scheduler, etc.)
- Primary workdir path
- Bootstrap/install command(s)
- Likely test command
- Git hosting provider (GitHub vs other)

### Decision Rules

- Always provision the project's primary database engine — agents need to run
  the full app, not just tests. Use .env.example, config files, and
  docker-compose.yml to determine the primary engine.
- If tests use a different DB (e.g., SQLite for speed), configure that as the
  test database, but still provision the primary server DB.
- Include only *additional* services (cache, search, queue) that AGENTS.md, CI,
  test config, or env/config actually require.
- Include Mailpit only when mail is used by the project or implied by framework.
- For ambiguous cases (monorepos, multiple runtimes), optimize for the primary
  app; note limitations in comments.

## Stack Playbooks

### Problem

Different project stacks require different setup decisions: package manager
commands, runtime installation, framework-specific bootstrap steps (key
generation, migrations, asset compilation), service configuration, and workdir
conventions. A single universal prompt cannot encode all of these without
becoming unwieldy, and leaving them to agent inference leads to inconsistent
results.

### Solution

Stack playbooks are short, supplementary prompt files that provide stack-specific
guidance. They live in `prompts/playbooks/` and are injected into the setup
prompt by ralph's `sandbox_setup()` function based on deterministic stack
detection.

### Directory Structure

```
prompts/
├── sandbox-setup.md           # Core prompt (stack-agnostic)
└── playbooks/
    ├── php-laravel.md         # PHP/Laravel-specific guidance
    ├── php.md                 # Generic PHP
    ├── node.md                # Node.js
    ├── python-django.md       # Python/Django
    ├── python.md              # Generic Python
    ├── rails.md               # Ruby on Rails
    └── ...                    # Added as needed
```

Playbooks are managed upstream files (tracked in `.manifest`, updated by
`ralph update`). Not every stack needs a playbook — the core prompt handles
unknown stacks on its own.

### Stack Detection

The `sandbox_setup()` function detects the project's primary stack before
invoking the agent. Detection is deterministic (bash, not LLM) to avoid
adding a failure point where the agent misidentifies or skips the playbook.

```bash
detect_stack() {
    # Framework-specific indicators first (most distinctive wins)

    # PHP/Laravel — artisan file is the strongest Laravel signal
    if [[ -f "artisan" ]] \
        || { [[ -f "composer.json" ]] && grep -q '"laravel/framework"' composer.json 2>/dev/null; }; then
        echo "php-laravel"
        return
    fi

    # PHP (generic)
    if [[ -f "composer.json" ]]; then
        echo "php"
        return
    fi

    # Ruby/Rails
    if [[ -f "bin/rails" ]] \
        || { [[ -f "Gemfile" ]] && grep -q "rails" Gemfile 2>/dev/null; }; then
        echo "rails"
        return
    fi

    # Ruby (generic)
    if [[ -f "Gemfile" ]]; then
        echo "ruby"
        return
    fi

    # Python/Django
    if [[ -f "manage.py" ]] && grep -q "django" manage.py 2>/dev/null; then
        echo "python-django"
        return
    fi

    # Python (generic)
    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]] \
        || [[ -f "Pipfile" ]] || [[ -f "setup.py" ]]; then
        echo "python"
        return
    fi

    # Go
    if [[ -f "go.mod" ]]; then
        echo "go"
        return
    fi

    # Rust
    if [[ -f "Cargo.toml" ]]; then
        echo "rust"
        return
    fi

    # Node.js — checked LAST because many non-Node projects have
    # package.json for frontend tooling (Laravel, Rails, Django, etc.)
    if [[ -f "package.json" ]]; then
        echo "node"
        return
    fi

    echo ""
}
```

**Key design decisions:**

- **`package.json` is checked last.** Almost every web project has one for
  frontend assets — its presence alone does not indicate a Node project.
- **Framework before runtime.** `php-laravel` before `php`, `rails` before
  `ruby`, `python-django` before `python`. Framework-specific playbooks carry
  more targeted guidance than generic runtime playbooks.
- **Grep for framework markers.** Checking `composer.json` for
  `laravel/framework`, `Gemfile` for `rails`, `manage.py` for `django` — these
  are strong, reliable signals.
- **Graceful fallback.** If nothing matches, no playbook is injected. The core
  prompt handles it alone.

### Injection into the Prompt

The `sandbox_setup()` function detects the stack, resolves the playbook path,
and exports it as a template variable for `envsubst`:

```bash
STACK=$(detect_stack)
PLAYBOOK_FILE="$RALPH_DIR/prompts/playbooks/${STACK}.md"
if [[ -n "$STACK" && -f "$PLAYBOOK_FILE" ]]; then
    export STACK_PLAYBOOK="$PLAYBOOK_FILE"
else
    export STACK_PLAYBOOK=""
fi
```

The core prompt (`sandbox-setup.md`) references the playbook via a conditional
instruction:

```markdown
If a stack playbook is provided, read and follow it: ${STACK_PLAYBOOK}
```

When `STACK_PLAYBOOK` is empty, the line resolves to inert text and the agent
proceeds with the core prompt alone.

### Playbook Content Guidelines

Each playbook should be short (under 50 lines) and cover only stack-specific
decisions that the core prompt cannot make generically:

- **Runtime installation:** specific apt packages, PPA/repository setup, version
  pinning (e.g., `ondrej/php` PPA for PHP 8.x, `nodesource` for Node LTS)
- **Package manager:** which tool to use and install commands
  (e.g., `composer install --no-interaction`, `npm ci`, `poetry install`)
- **Framework bootstrap:** key generation, asset compilation, etc.
  (e.g., `php artisan key:generate`, `npm run build`)
- **Migrations:** framework-specific migration command
  (e.g., `php artisan migrate --force`, `python manage.py migrate`)
- **Common extensions/packages:** frequently needed system packages or runtime
  extensions (e.g., PHP extensions `pdo_pgsql`, `redis`, `gd`)
- **Workdir convention:** `/var/www/html` for PHP, `/app` for others
- **Sandbox env overrides:** framework-specific `.env` adjustments
  (e.g., `QUEUE_CONNECTION=sync`, `CACHE_STORE=file` for Laravel)
- **Long-running processes:** which services to run under supervisord
  (e.g., `php artisan serve` or php-fpm for Laravel web, `npm run dev` for Vite)

Playbooks should **not** repeat information from the core prompt (hard
constraints, credential handling, idempotency patterns, etc.).

### Adding New Playbooks

1. Create `prompts/playbooks/{stack-name}.md` following the content guidelines.
2. Add the stack detection case to `detect_stack()` in the `ralph` script.
3. Add the playbook to the `MANAGED_FILES` array in `update.sh`.
4. Update `specs/project-structure.md` to include the new file.

Playbooks can be added incrementally — start with the stacks you use most.

## What the Setup Agent Generates

The agent creates four files in `.ralph/sandbox/`:

### 1. `Dockerfile`

Responsibilities:
- Install the project's language runtime and version
- Install all required extensions and system packages
- Install service packages natively (database server, etc.) — only those
  identified as required during project analysis
- Install package managers (composer, npm/yarn/pnpm, pip, etc.)
- Install GitHub CLI (gh) — only for GitHub-hosted projects
- Install Amp CLI (`npm install -g @sourcegraph/amp`), tini, supervisord,
  and ralph dependencies
- Handle UID 1000 conflicts: the base image may have a user with UID 1000
  (e.g., "ubuntu") — delete it with `userdel --remove` before creating "ralph"
- Create a non-root user named "ralph" (UID 1000, GID 1000) with passwordless
  sudo
- Copy entrypoint.sh to a location in PATH (e.g., `/usr/local/bin/`)
- ENTRYPOINT `["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]`
- WORKDIR: `/var/www/html` for PHP projects, `/app` for others
- EXPOSE only ports for services that are actually provisioned

### 2. `entrypoint.sh`

An idempotent entrypoint that must begin with:

```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[sandbox] ERROR: entrypoint failed at line $LINENO (exit code $?)" >&2' ERR
```

Responsibilities (in order):
1. Configure git credentials (GitHub path via `gh auth`, or generic path via
   git credential store — see Appendix A in the prompt)
2. Clone GIT_REPO into workdir if `.git/HEAD` is missing (fresh volume).
   Docker named volumes are created with root ownership — chown the workdir
   to ralph **before** cloning so `git clone` (running as ralph) can write
   to it.
3. Create sentinel directory at `${RALPH_HOME}/.sandbox/` (after clone —
   workdir must be empty for clone). This keeps sentinel files inside ralph's
   own directory where they are covered by `.ralph/.gitignore`, avoiding any
   changes to the parent project's `.gitignore`.
4. Copy `.env.example` → `.env` if missing, with sandbox-appropriate overrides
   (e.g., `DB_HOST=127.0.0.1`, `MAIL_HOST=127.0.0.1`, `QUEUE_CONNECTION=sync`,
   `CACHE_STORE=file` — adjusted based on provisioned services).
5. Apply project-level secrets from container environment into `.env`:
   for each key in `.env`, if a matching env var is set in the container
   environment and non-empty, overwrite that key's value. This runs on
   **every boot** (not just first creation) so users can add or update
   secrets in the sandbox `.env` and restart the container.
   The sandbox `.env` contains real secrets and must never be committed.
5a. Bootstrap test environment files if the project has them (e.g.,
   `.env.testing`, `.env.test`). Two responsibilities:
   - **Generate missing secrets:** Copy the test env template if the
     framework doesn't auto-create it, then populate any empty secret
     keys (e.g., `APP_KEY`, `JWT_SECRET`) with generated values — the
     same way the primary `.env` secrets are handled.
   - **Mitigate container env var conflicts:** In an all-in-one container,
     the entrypoint exports environment variables (e.g., `DB_DATABASE`)
     that are visible to all processes. Many frameworks use an immutable
     dotenv loader that refuses to overwrite values already present in the
     process environment, so test env file overrides (like a separate test
     database name) are silently ignored. The agent must detect this risk
     and generate a mitigation — typically a test bootstrap snippet that
     clears conflicting env vars before the framework loads its dotenv
     file. The specific mechanism is framework-dependent; stack playbooks
     should provide the concrete pattern.
6. Install dependencies idempotently (sentinel file pattern — sentinels go
   in `${RALPH_HOME}/.sandbox/`)
7. Generate app secret/key if framework requires it (after deps install)
8. Initialize and bootstrap database if applicable:
   a. Init data directory if needed, start DB temporarily, create user/databases.
   b. **Pre-migration prerequisites:** Scan migration files, SQL directories,
      documentation, and AGENTS.md for database prerequisites that must exist
      before migrations can run — e.g., PostgreSQL extensions (`CREATE EXTENSION
      pgcrypto`, `postgis`, `uuid-ossp`), custom SQL functions or triggers,
      or schema setup scripts. Install/run any prerequisites found. This step
      is critical: without it, migrations that depend on extensions or functions
      will fail on first boot.
   c. Run migrations (with sentinel).
   d. **Run seeders** if the project has them (with sentinel). Scan for
      seeder classes, seed scripts, or fixture-loading commands in the
      project source, documentation, or AGENTS.md. Reference data seeders
      (lookup tables, roles, permissions) are especially important — the
      app may be non-functional without them. Stack playbooks provide the
      specific seeding command. If a separate test database was created
      (step 5a), run seeders against it too.
   e. Stop DB — supervisord manages it going forward.
9. Generate supervisord config files for each required long-running process
   (database server, web server, queue worker, Vite dev server, mail catcher,
   etc. — only processes the project actually uses)
10. End with: `exec supervisord -n -c /etc/supervisor/supervisord.conf`

Multi-step operations must use **sentinel files** in `${RALPH_HOME}/.sandbox/`
for idempotency (e.g., `touch ${RALPH_HOME}/.sandbox/deps-installed`). Check
the sentinel, not the output directory, so partial installs get retried. Simple
existence checks (`.git/HEAD`, `.env`) are fine for single-command steps.
The sentinel directory must be created after the clone step — the workdir must
be empty for `git clone` to succeed into it.

### 3. `docker-compose.yml`

- **Project name:** `${SANDBOX_NAME:-{project-name}-sandbox}` — uses the
  `SANDBOX_NAME` env var (auto-derived by ralph from the checkout path, see
  `sandbox-cli.md`). This ensures unique project names when the same project
  is checked out in multiple locations.
- **No `container_name:`** — omit `container_name` so Compose auto-derives it
  from the project name. The existing `sandbox_container_name()` fallback
  already handles this (derives `{project-name}-sandbox-1` from the compose
  project name).
- **Build context:** `.` (the sandbox directory)
- **Environment:** Use list syntax (`- KEY=value`), never map syntax. Quote any
  entry whose value contains a colon. Required vars: `SANDBOX=1`, `GIT_REPO`,
  `AMP_API_KEY`, credential vars, `GIT_CONFIG` vars to rewrite SSH URLs to HTTPS
  (derive host from `GIT_REPO`, do not hardcode)
- **Volumes:** Named volumes for codebase and database data (not bind mounts)
- **Ports:** Use env vars with defaults (e.g., `${SANDBOX_HTTP_PORT:-80}:80`)
  so users can remap; only map ports for provisioned services
- **Healthcheck:** `supervisorctl status` to verify all services are RUNNING
  (start_period: 60s to allow for first-run setup)
- **tty: true, stdin_open: true**
- **Resource limits:** `deploy.resources.limits` with memory and CPU from env
  vars (defaults: 4g memory, 2 CPUs)
- **env_file:** `.env`

### 4. `.env.example`

Template with:
- `GIT_REPO=` (pre-filled from git remote)
- Credential vars: `GITHUB_TOKEN` uncommented for GitHub repos, or
  `GIT_CRED_USER` + `GIT_CRED_PASS` uncommented for non-GitHub repos
- `AMP_API_KEY=`
- `SANDBOX_MEMORY_LIMIT=4g`
- `SANDBOX_CPU_LIMIT=2`
- Port mappings with defaults matching provisioned services (e.g.,
  `SANDBOX_HTTP_PORT=80`, `SANDBOX_DB_PORT=5432` or `3306`,
  `SANDBOX_SMTP_PORT=1025`, `SANDBOX_MAIL_UI_PORT=8025`,
  `SANDBOX_VITE_PORT=5173` if applicable)
- `SANDBOX_NAME` — commented out, with a note that it is auto-derived from the
  checkout path and can be overridden when the auto-generated name is not suitable
- Every env var used in `docker-compose.yml` or `entrypoint.sh` must be
  documented here
- **Project-level secrets:** Scan the project's `.env.example` (or equivalent)
  for third-party API keys and secrets that are not covered by the sandbox
  infrastructure vars above (e.g., `STRIPE_SECRET`, `AWS_ACCESS_KEY_ID`,
  `SENDGRID_API_KEY`). Include each as a commented-out entry with a note
  that the user must fill it in if the project requires it. Prefix the
  section with a comment: `# Project secrets (fill in if needed by your app)`

## Prompt Appendices

The prompt includes appendices with battle-tested solutions for known failure
modes. These are separated from the main body so the agent can reference them
without fixating on them at the expense of higher-priority concerns.

- **Appendix A: Git Credential Configuration** — exact shell snippets for
  GitHub (`gh auth login` with `env -u` workaround) and generic credential
  store (URL-encoded credentials for providers like AWS CodeCommit).
- **Appendix B: YAML Environment Variable Syntax** — examples of correct list
  syntax and the colon-quoting pitfall in docker-compose.yml.
- **Appendix C: Idempotency Patterns** — sentinel file pattern using
  `${RALPH_HOME}/.sandbox/`, empty workdir requirement before clone, and
  when simple existence checks suffice.

## Template Variables

The prompt uses `envsubst` variables like other ralph prompts:

| Variable | Source | Description |
|----------|--------|-------------|
| `${RALPH_HOME}` | runtime | Relative path from project root to Ralph's directory |
| `${STACK_PLAYBOOK}` | `sandbox_setup()` | Path to stack-specific playbook file, or empty |

## Edge Cases

### No existing containerization to reference

If the project has no Dockerfile, docker-compose.yml, or .devcontainer, the agent
must infer the stack entirely from package manifests and config files. The prompt
handles this — containerization files are reference material, not required.

### Multiple database engines

Some projects use PostgreSQL for the app and Redis for caching. The agent should
install both in the container and manage both under supervisord.

### Tests use SQLite in-memory

Many projects use SQLite for tests regardless of production database. The agent
should still provision the production database (for development and manual
testing) but may note in comments that the test suite uses SQLite.

### No playbook for detected stack

If `detect_stack()` identifies a stack but no playbook file exists for it, the
agent proceeds with the core prompt alone. The core prompt is designed to be
sufficient — playbooks are an enhancement, not a requirement.

### First build is slow

The generated Dockerfile will produce large images (1-3GB). `ralph sandbox up`
should print a message: "First build may take several minutes." Subsequent starts
reuse the cached image and are fast.

## Changes to `ralph` Script

Add `detect_stack()` function and update `sandbox_setup()` to call it:

```bash
detect_stack() {
    if [[ -f "artisan" ]] \
        || { [[ -f "composer.json" ]] && grep -q '"laravel/framework"' composer.json 2>/dev/null; }; then
        echo "php-laravel"; return
    fi
    if [[ -f "composer.json" ]]; then echo "php"; return; fi
    if [[ -f "bin/rails" ]] \
        || { [[ -f "Gemfile" ]] && grep -q "rails" Gemfile 2>/dev/null; }; then
        echo "rails"; return
    fi
    if [[ -f "Gemfile" ]]; then echo "ruby"; return; fi
    if [[ -f "manage.py" ]] && grep -q "django" manage.py 2>/dev/null; then
        echo "python-django"; return
    fi
    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]] \
        || [[ -f "Pipfile" ]] || [[ -f "setup.py" ]]; then
        echo "python"; return
    fi
    if [[ -f "go.mod" ]]; then echo "go"; return; fi
    if [[ -f "Cargo.toml" ]]; then echo "rust"; return; fi
    if [[ -f "package.json" ]]; then echo "node"; return; fi
    echo ""
}
```

In `sandbox_setup()`, before `prepare_prompt`:

```bash
STACK=$(detect_stack)
PLAYBOOK_FILE="$RALPH_DIR/prompts/playbooks/${STACK}.md"
if [[ -n "$STACK" && -f "$PLAYBOOK_FILE" ]]; then
    export STACK_PLAYBOOK="$PLAYBOOK_FILE"
else
    export STACK_PLAYBOOK=""
fi
```

## Changes to Installer and Updater

- Add `prompts/playbooks/` directory to installer
- Add each playbook file to `MANAGED_FILES` in `update.sh`
- Add `prompts/sandbox-setup.md` to `MANAGED_FILES` (already specified)

## Changes to Project Structure

Add `prompts/playbooks/` to the directory layouts in `specs/project-structure.md`:

```
prompts/
├── plan.md
├── build.md
├── sandbox-setup.md
└── playbooks/
    ├── php-laravel.md
    └── ...
```
