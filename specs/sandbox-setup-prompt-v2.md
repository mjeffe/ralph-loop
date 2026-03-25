# Sandbox Setup v2 — Multi-Container, Multi-Pass Architecture

**Status:** DRAFT — proposed replacement for `sandbox-setup-prompt.md`

## Problem Statement

The current sandbox setup asks a single LLM prompt to simultaneously analyze a
project, make architectural decisions, and generate four complex files
(Dockerfile, entrypoint.sh, docker-compose.yml, .env.example). This produces:

- **Low first-run success rate** — agents rarely produce a fully functional
  sandbox. Users debug and modify generated Docker config and entrypoint scripts.
- **Non-deterministic output** — rerunning `ralph sandbox setup` produces
  different results: missing services, different entrypoint steps, inconsistent
  choices.
- **Service detection failures** — agents fail to detect required services even
  when the project has a `docker-compose.yml` that explicitly defines them.
- **Complex DB bootstrapping** — native database installation inside the
  container (pg_createcluster/pg_dropcluster, initdb, stale PID files,
  supervisord management) is fragile and error-prone.

## Solution Overview

Replace the monolithic single-container, single-prompt approach with:

1. **Multi-container architecture** — official Docker images for services
   (postgres, redis, mailpit), eliminating native service installation. The
   agent works exclusively in an app container. A minimal supervisord in the
   app container manages app-level processes only (web server, queue worker,
   etc.).
2. **Base image** — a managed Dockerfile that provides the invariant layer
   (ubuntu, tini, supervisord, git, Amp CLI, user ralph). Built locally during
   setup, never published to a registry.
3. **Multi-pass prompt pipeline** — separate analysis from generation.
   Pass 1 produces a structured project profile; Pass 2 generates files from
   that profile. An optional Pass 3 repairs validation failures.
4. **Machine validation** — a deterministic bash validator checks generated
   files for structural correctness before the user runs `docker compose up`.

## Design Principles

1. **Services run in their own containers.** Database, cache, mail, and search
   services use official Docker images. The app container contains only the
   project runtime, dependencies, tooling, and app-level processes.
   `depends_on` with healthchecks ensures service readiness.
2. **The base image is invariant.** It changes only when ralph's own
   requirements change (new system dependency, new tool). It is a managed file
   updated by `ralph update`.
3. **Analysis and generation are separate concerns.** The LLM analyzes the
   project once and produces a locked profile. File generation references only
   the profile, not the raw project sources. This improves consistency because
   the same profile always produces the same (or very similar) output.
4. **Machine validation before human debugging.** Structural checks catch
   cross-file inconsistencies (port mismatches, missing env vars, syntax errors)
   before the user ever runs `docker compose up`.
5. **Ralph remains project-agnostic.** Stack-specific knowledge lives in
   playbooks and the LLM's analysis, not in ralph's bash code (beyond
   `detect_stack()`).
6. **Minimal supervisord for app processes.** Supervisord remains in the app
   container but manages only app-level processes (web server, queue worker,
   Vite dev server). Infrastructure services (database, cache, mail) run in
   their own containers and are not managed by supervisord.

## Architecture

### Multi-Container Model

```
docker-compose.yml (generated)
├── app         — built from base image + project Dockerfile
│                 ralph works here exclusively
│                 ralph sandbox shell → exec into this container
│                 supervisord manages app processes (web, queue, vite)
├── db          — postgres:XX or mysql:XX (official image, if needed)
├── redis       — redis:7 (official image, if needed)
├── mail        — mailpit (official image, if needed)
└── ...         — additional services as detected
```

The app container is the only container with custom build logic. All service
containers use official images with configuration via environment variables
and named volumes.

**Networking:** Services are accessible from the app container by service name
(e.g., `db:5432`, `redis:6379`, `mail:1025`). Application env overrides use
service hostnames instead of `127.0.0.1`.

**Service readiness:** The app container uses `depends_on` with
`condition: service_healthy` for each service. By the time the app entrypoint
runs, all services are accepting connections. No `wait-for-it.sh` or retry
loops needed.

### Supervisord Scope

Supervisord in the app container manages **only app-level processes** — things
the project itself needs running:

- Web server (`php artisan serve`, php-fpm, etc.)
- Queue worker (`php artisan queue:work`, celery, etc.)
- Vite/HMR dev server (`npm run dev`)
- Scheduler (`php artisan schedule:work`)

Supervisord does **not** manage infrastructure services. Those run in their
own containers with their own restart policies and healthchecks.

This is a much simpler supervisord configuration than the current approach:
1–3 well-known program blocks instead of 5–8 that include database servers,
cache engines, and mail catchers. The LLM's task is to generate a few
predictable supervisord programs from the project profile, not to configure
infrastructure services from scratch.

The entrypoint ends with `exec supervisord -n -c /etc/supervisor/supervisord.conf`
as it does today, but supervisord manages far fewer processes. For projects
with no long-running app processes (e.g., static HTML/CSS), the entrypoint
generates a single supervisord program that runs `sleep infinity` as a
keepalive so `ralph sandbox shell` works.

### Base Image

The base image Dockerfile is a managed file shipped with ralph at
`prompts/templates/Dockerfile.base`. It provides the invariant layer that
every sandbox needs:

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System essentials
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq gettext-base sudo \
    tini supervisor \
    && rm -rf /var/lib/apt/lists/*

# Node.js (for Amp CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Amp CLI
# TODO: Make agent-configurable. Consider adding agent_install() to the
# agents/*.sh script interface so each agent defines its own install command.
RUN npm install -g @sourcegraph/amp

# Ralph dependencies from dependencies file are covered above (git, curl,
# jq, gettext-base). If dependencies file grows, this section must be
# updated to match.

# Handle UID 1000 conflict (ubuntu user in base image)
RUN userdel --remove ubuntu 2>/dev/null || true

# Non-root user
RUN groupadd -g 1000 ralph \
    && useradd -m -u 1000 -g 1000 -s /bin/bash ralph \
    && echo 'ralph ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ralph

USER ralph
WORKDIR /home/ralph
```

**What the base image does NOT include:**
- Language runtimes (PHP, Python, Ruby, etc.)
- Package managers (composer, pip, etc.)
- Database clients or servers
- Project-specific extensions or packages
- User preferences from `sandbox-preferences.md`
- GitHub CLI (only needed for GitHub-hosted projects)

These are added by the generated project Dockerfile which uses the base image
as its `FROM` layer.

### Build Sequence

During `ralph sandbox setup`, the base image is built before the agent runs:

```bash
cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$sandbox_dir/Dockerfile.base"

docker build -t ralph-sandbox-base \
    -f "$sandbox_dir/Dockerfile.base" \
    "$sandbox_dir/"
```

The `Dockerfile.base` is copied into the sandbox directory so both the base
image build and the project Dockerfile build share the same build context
(`.ralph/sandbox/`). This keeps the Docker build context entirely within
ralph's directory and separate from any parent project Docker context.

The generated project Dockerfile references it:

```dockerfile
FROM ralph-sandbox-base

USER root

# Project-specific runtime, extensions, packages (LLM-generated)
RUN apt-get update && apt-get install -y php8.3-cli php8.3-fpm ...

# User preferences from sandbox-preferences.md (LLM-generated, heredocs)
RUN cat >> /home/ralph/.bashrc <<'BASHRC'
# ... contents from sandbox-preferences.md ...
BASHRC

RUN cat > /home/ralph/.gitconfig <<'GITCONFIG'
# ... contents from sandbox-preferences.md ...
GITCONFIG

# Vim config (from sandbox-preferences.md — strip /dev/tty for non-interactive)
RUN curl -fsSL https://raw.githubusercontent.com/.../install.sh \
    | sed 's|</dev/tty||g' | bash -s min

RUN chown -R ralph:ralph /home/ralph
USER ralph

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
EXPOSE 80
```

**Sandbox-preferences content is inlined via heredocs** in the Dockerfile
rather than COPY'd from separate support files. This keeps the Dockerfile
self-contained and avoids a support files subdirectory in the build context.
The LLM reads `sandbox-preferences.md` and translates each preference into
the appropriate Dockerfile instruction.

## Multi-Pass Prompt Pipeline

### Pass 1: Analyze → Project Profile

**Prompt:** `prompts/sandbox-analyze.md`

The agent reads the project sources (manifests, env files, CI config, AGENTS.md,
existing Docker files, test config) and outputs a structured project profile in
JSON. The prompt is focused exclusively on discovery and decision-making — the
agent does not generate any Docker files.

The prompt includes the same "Sources to read" and "Decision rules" sections
from the current prompt, plus the stack playbook if available. It instructs the
agent to output **only** a JSON profile to a designated file.

**Output:** `.ralph/sandbox/project-profile.json`

```json
{
    "schema_version": 1,
    "stack": "php-laravel",
    "runtimes": [
        {"name": "php", "version": "8.3", "evidence": ["composer.json"]},
        {"name": "node", "version": "20", "evidence": ["package.json"]}
    ],
    "package_managers": [
        {"name": "composer", "install_command": "composer install --no-interaction --no-progress --optimize-autoloader"},
        {"name": "npm", "install_command": "npm ci"}
    ],
    "services": [
        {"name": "postgres", "image": "postgres:16", "port": 5432, "reason": ".env.example DB_CONNECTION=pgsql"},
        {"name": "mailpit", "image": "axllent/mailpit", "ports": [1025, 8025], "reason": "MAIL_MAILER=smtp in .env.example"}
    ],
    "php_extensions": ["pdo_pgsql", "pgsql", "mbstring", "xml", "curl", "zip", "bcmath", "intl", "gd", "redis"],
    "system_packages": ["libpq-dev", "libzip-dev", "libpng-dev"],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/var/www/html",
    "env_overrides": {
        "DB_CONNECTION": "pgsql",
        "DB_HOST": "db",
        "DB_PORT": "5432",
        "DB_DATABASE": "app",
        "DB_USERNAME": "ralph",
        "DB_PASSWORD": "ralph",
        "MAIL_MAILER": "smtp",
        "MAIL_HOST": "mail",
        "MAIL_PORT": "1025",
        "QUEUE_CONNECTION": "sync",
        "CACHE_STORE": "file",
        "SESSION_DRIVER": "file"
    },
    "bootstrap": {
        "secret_generation": "php artisan key:generate --force",
        "migration": "php artisan migrate --force",
        "seeder": "php artisan db:seed --force",
        "post_install": ["php artisan storage:link", "npm run build"]
    },
    "test_env": {
        "file": ".env.testing",
        "test_db": "app_testing",
        "secrets": ["APP_KEY"]
    },
    "supervisor_programs": [
        {"name": "web", "command": "php artisan serve --host=0.0.0.0 --port=80"},
        {"name": "queue", "command": "php artisan queue:work --sleep=3 --tries=3"}
    ],
    "compose_ports": {
        "http": 80,
        "db": 5432,
        "mail_smtp": 1025,
        "mail_ui": 8025
    },
    "pre_migration_sql": [
        "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    ],
    "assumptions": [],
    "notes": []
}
```

**Key rules for the analysis prompt:**
- Output only the JSON profile — no Docker files, no bash scripts.
- Every decision must cite evidence (the `evidence`, `reason` fields).
- Ambiguous or uncertain items go in `assumptions` or `notes`.
- The profile schema is defined in the prompt so the agent knows the
  expected structure.
- `supervisor_programs` must include at least one entry. For projects with
  no long-running app processes, use `{"name": "keepalive", "command": "sleep infinity"}`.

### Pass 2: Generate Files from Profile

**Prompt:** `prompts/sandbox-render.md`

The agent reads the project profile and generates the four sandbox files. The
prompt provides:
- The locked project profile (read from `.ralph/sandbox/project-profile.json`)
- Hard constraints (same as current: named volumes, non-root user, tini,
  git-mediated code flow)
- File responsibilities (what each file must accomplish)
- Git credential snippets (Appendix A from current prompt — these work well)
- The stack playbook (if available) for stack-specific code patterns
- User preferences from `sandbox-preferences.md`

**Key rules for the render prompt:**
- Do not re-analyze the project. Use only information from the profile.
- Do not add services, packages, or steps not represented in the profile.
- Follow the profile's decisions exactly (runtime versions, package managers,
  env overrides, bootstrap commands).
- Inline sandbox-preferences content via heredocs in the Dockerfile — do not
  create separate support files.

This separation means the render agent has a much simpler job: translate a
structured specification into Docker files. The decisions are already made.

### Pass 3 (Optional): Repair

**Prompt:** `prompts/sandbox-repair.md`

Invoked only when the machine validator (see below) finds failures. The repair
prompt receives:
- The current generated files
- The project profile
- The exact validator failure messages

The agent makes targeted fixes to address specific failures. This is a single
repair attempt — if validation fails again, the user is shown the remaining
issues to fix manually.

### Setup Invocation Model

`ralph sandbox setup` always runs the full pipeline. If sandbox files already
exist, the user must pass `--force` to regenerate (which preserves `.env`).
There is no partial rerun — re-rendering from an existing profile without
re-analyzing produces identical output, so there is no value in supporting it
as a separate mode.

| Scenario | Behavior |
|---|---|
| No sandbox files exist | Pass 1 → Pass 2 → validate |
| Files exist, no `--force` | Error: "use --force to regenerate" |
| `--force` | Delete sandbox dir (preserve .env) → Pass 1 → Pass 2 → validate |

## Machine Validator

A bash function (`sandbox_validate()` in the ralph script) that checks
generated files for structural correctness. Run automatically after Pass 2
(and after Pass 3 if invoked).

### Checks

**Syntax:**
- `bash -n entrypoint.sh` — entrypoint parses without errors
- `docker compose -f docker-compose.yml config` — compose file is valid

**Structural (Dockerfile):**
- `FROM ralph-sandbox-base` is present
- `ENTRYPOINT` uses tini
- `entrypoint.sh` is copied into the image
- WORKDIR is set

**Structural (entrypoint.sh):**
- Starts with `#!/usr/bin/env bash` and `set -euo pipefail`
- Contains git credential configuration
- Contains clone logic (`.git/HEAD` check)
- Ends with `exec supervisord`

**Structural (docker-compose.yml):**
- Defines an `app` service with build context
- Uses list syntax for environment variables (not map syntax)
- No app-config vars (DB_*, MAIL_*, etc.) in compose environment
- Named volumes only (no bind mounts)
- `depends_on` with `condition: service_healthy` for each service that
  supports healthchecks
- `env_file` with `required: false`
- `tty: true` and `stdin_open: true`

**Cross-file consistency:**
- Every port exposed in Dockerfile has a corresponding port mapping in compose
- Every service in compose has a corresponding env override in entrypoint
  (e.g., postgres service → DB_HOST=db)
- Every env var referenced in compose is documented in `.env.example`
- Service ports in compose healthchecks match the service images' default ports

**Profile consistency:**
- Services in compose match `services` array in project profile
- Runtime/version in Dockerfile matches profile
- Env overrides in entrypoint match profile

### Validator Output

```
[PASS] entrypoint.sh syntax valid
[PASS] docker-compose.yml syntax valid
[PASS] Dockerfile uses ralph-sandbox-base
[PASS] entrypoint.sh starts with required header
[FAIL] compose env var SANDBOX_VITE_PORT not documented in .env.example
[FAIL] postgres service missing healthcheck
```

Failures are machine-readable so they can be fed to the repair prompt.

## Generated Files — Simplified

### 1. Dockerfile (project-specific)

With the base image handling invariants, the generated Dockerfile is short.
User preferences from `sandbox-preferences.md` are inlined via heredocs.

```dockerfile
FROM ralph-sandbox-base

USER root

# Runtime — language, version, and extensions from profile
# (example: PHP with extensions; actual content varies by stack)
RUN apt-get update && apt-get install -y --no-install-recommends \
    <runtime-packages-from-profile> \
    && rm -rf /var/lib/apt/lists/*

# Package managers from profile (composer, pip, etc.)
RUN <package-manager-install-commands>

# GitHub CLI — only for GitHub-hosted projects (from profile.git_provider)
RUN <gh-install-commands>

# User preferences from sandbox-preferences.md — inlined via heredocs.
# The agent reads sandbox-preferences.md and translates each preference
# into Dockerfile instructions. Packages are installed via apt-get,
# dotfile content is appended/created via heredocs.
RUN apt-get update && apt-get install -y <preference-packages> \
    && rm -rf /var/lib/apt/lists/*

RUN cat >> /home/ralph/.bashrc <<'BASHRC'
# ... contents from sandbox-preferences.md Packages/User Environment sections
BASHRC

RUN cat > /home/ralph/.gitconfig <<'GITCONFIG'
# ... contents from sandbox-preferences.md if it specifies git config
GITCONFIG

# Scripts from sandbox-preferences.md (strip /dev/tty for Docker build)
RUN curl -fsSL https://example.com/install.sh \
    | sed 's|</dev/tty||g' | bash

RUN chown -R ralph:ralph /home/ralph
USER ralph

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR <workdir-from-profile>
EXPOSE <ports-from-profile>
```

### 2. entrypoint.sh

With services running in separate containers, the entrypoint no longer handles
database server installation, initialization, or supervisord configuration for
infrastructure services. It generates a small number of supervisord program
configs for app-level processes, then hands off to supervisord.

The entrypoint follows a fixed sequence. Steps are shown with generic
placeholders — the LLM fills in stack-specific commands from the profile.

```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[sandbox] ERROR: entrypoint failed at line $LINENO (exit $?)" >&2' ERR

RALPH_HOME="${RALPH_HOME:-.ralph}"

# --- 1. Git credentials ---
# Use exact snippets from Appendix A of the render prompt (unchanged from
# current — these handle known failure modes with gh auth and URL-encoded
# credentials). GitHub path when GITHUB_TOKEN is set; generic credential
# store path when GIT_CRED_USER/GIT_CRED_PASS are set.

# --- 2. Clone repo ---
if [ ! -f .git/HEAD ]; then
    sudo chown ralph:ralph "$(pwd)"
    git clone "$GIT_REPO" .
fi

# --- 3. Sentinel directory ---
mkdir -p "${RALPH_HOME}/.sandbox"

# --- 4. App .env setup (first boot only) ---
# Copy project's .env.example → .env, then apply env_overrides from profile
# using sed commands. Key difference from current: service hostnames (db,
# mail, redis) instead of 127.0.0.1.
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    sed -i 's|^DB_HOST=.*|DB_HOST=db|' .env
    # ... remaining overrides from profile.env_overrides
fi

# --- 5. Test env setup ---
# Copy test env template if it exists, populate empty secrets.

# --- 6. Install dependencies (sentinel-guarded) ---
if [ ! -f "${RALPH_HOME}/.sandbox/deps-installed" ]; then
    <install-commands-from-profile>
    touch "${RALPH_HOME}/.sandbox/deps-installed"
fi

# --- 7. App secret generation (if framework requires it) ---
<secret-generation-command-from-profile>

# --- 8. Database bootstrap ---
# DB server runs in its own container and is healthy before this entrypoint
# starts (depends_on with healthcheck). No server init needed.
if [ ! -f "${RALPH_HOME}/.sandbox/db-migrated" ]; then
    # Pre-migration prerequisites from profile.pre_migration_sql
    <migration-command-from-profile>
    touch "${RALPH_HOME}/.sandbox/db-migrated"
fi
if [ ! -f "${RALPH_HOME}/.sandbox/db-seeded" ]; then
    <seeder-command-from-profile>
    touch "${RALPH_HOME}/.sandbox/db-seeded"
fi

# --- 9. Post-install steps from profile.bootstrap.post_install ---

# --- 10. Supervisord programs (app-level processes only) ---
# Generate one conf file per entry in profile.supervisor_programs.
# Each uses autorestart=true, startsecs=5, stdout/stderr to /dev/stdout.
sudo tee /etc/supervisor/conf.d/<name>.conf > /dev/null <<'EOF'
[program:<name>]
command=<command-from-profile>
directory=<workdir-from-profile>
user=ralph
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# --- 11. Start supervisord (foreground) ---
exec supervisord -n -c /etc/supervisor/supervisord.conf
```

**Key differences from current:**
- No `initdb`, `pg_ctl`, `pg_createcluster`, stale PID handling
- No supervisord config for infrastructure services (DB, redis, mail)
- Supervisord manages only 1–3 app-level processes
- DB is already running and healthy when this script starts
- Service hostnames (`db`, `mail`) instead of `127.0.0.1`

### 3. docker-compose.yml

```yaml
name: ${SANDBOX_NAME:-project-sandbox}

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    depends_on:
      db:
        condition: service_healthy
      mail:
        condition: service_started
    env_file:
      - path: .env
        required: false
    environment:
      - SANDBOX=1
      - "GIT_REPO=${GIT_REPO}"
      - "AMP_API_KEY=${AMP_API_KEY}"
      - "GITHUB_TOKEN=${GITHUB_TOKEN}"
      - "GIT_CONFIG_COUNT=1"
      - "GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf"
      - "GIT_CONFIG_VALUE_0=git@github.com:"
    volumes:
      - sandbox-codebase:/var/www/html
    ports:
      - "${SANDBOX_HTTP_PORT:-80}:80"
    tty: true
    stdin_open: true
    deploy:
      resources:
        limits:
          memory: ${SANDBOX_MEMORY_LIMIT:-4g}
          cpus: "${SANDBOX_CPU_LIMIT:-2}"

  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=ralph
      - POSTGRES_PASSWORD=ralph
      - POSTGRES_DB=app
    volumes:
      - sandbox-db:/var/lib/postgresql/data
    ports:
      - "${SANDBOX_DB_PORT:-5432}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ralph"]
      interval: 5s
      timeout: 3s
      retries: 5

  mail:
    image: axllent/mailpit
    ports:
      - "${SANDBOX_SMTP_PORT:-1025}:1025"
      - "${SANDBOX_MAIL_UI_PORT:-8025}:8025"

volumes:
  sandbox-codebase:
  sandbox-db:
```

**Key differences from current:**
- Multiple services instead of one monolithic container
- Official images for services — no native installation
- `depends_on` with healthchecks — no wait-for-it scripts
- DB initialization handled entirely by the official postgres image
  (user, password, database created via environment variables)
- No healthcheck on app service referencing `supervisorctl status` for
  infrastructure services

### Multi-Sandbox Isolation

The compose `name:` field uses `${SANDBOX_NAME}`, which ralph auto-derives
from the checkout path via `sandbox_ensure_name()` (see `sandbox-cli.md`).
Docker Compose uses the project name to namespace **all** resources:

| Resource | Naming pattern | Example (checkout `~/src/foo`) | Example (checkout `~/src/foo-2`) |
|---|---|---|---|
| Project name | `${SANDBOX_NAME}` | `foo-sandbox-a1b2c3d4` | `foo-sandbox-e5f67890` |
| Containers | `{project}-{service}-1` | `foo-sandbox-a1b2c3d4-app-1` | `foo-sandbox-e5f67890-app-1` |
| Volumes | `{project}_{volume}` | `foo-sandbox-a1b2c3d4_sandbox-codebase` | `foo-sandbox-e5f67890_sandbox-codebase` |
| Networks | `{project}_default` | `foo-sandbox-a1b2c3d4_default` | `foo-sandbox-e5f67890_default` |

Service names (`app`, `db`, `mail`) are internal to each compose project —
they do not collide across sandboxes. Each sandbox gets its own isolated
network, so `db:5432` in one sandbox refers to that sandbox's database, not
another's.

**Port collisions** are the one resource not namespaced by Compose. Two
sandboxes cannot bind the same host port. The `.env` file provides port
override variables (`SANDBOX_HTTP_PORT`, `SANDBOX_DB_PORT`, etc.) so the
user can remap ports per checkout. For example:

```bash
# ~/src/foo/.ralph/sandbox/.env
SANDBOX_HTTP_PORT=8080
SANDBOX_DB_PORT=54321

# ~/src/foo-2/.ralph/sandbox/.env
SANDBOX_HTTP_PORT=8081
SANDBOX_DB_PORT=54322
```

The `ralph sandbox setup` post-setup message and `ralph sandbox help`
should document this — when running multiple sandboxes on the same host,
remap ports in each `.env` to avoid bind conflicts.

### 4. .env.example

```bash
# --- Git Repository ---
GIT_REPO=https://github.com/example/project.git

# --- Credentials ---
# GitHub token (for GitHub-hosted repos)
GITHUB_TOKEN=
# Generic git credentials (for non-GitHub repos — uncomment if needed)
# GIT_CRED_USER=
# GIT_CRED_PASS=

# Amp API key (https://ampcode.com)
AMP_API_KEY=

# --- Resource Limits ---
SANDBOX_MEMORY_LIMIT=4g
SANDBOX_CPU_LIMIT=2

# --- Port Mappings ---
# Remap ports to avoid collisions with host services
SANDBOX_HTTP_PORT=80
SANDBOX_DB_PORT=5432
SANDBOX_SMTP_PORT=1025
SANDBOX_MAIL_UI_PORT=8025

# --- Sandbox Name ---
# Auto-derived from checkout path. Uncomment to override.
# SANDBOX_NAME=my-project-sandbox
```

## Changes to `sandbox_setup()` in ralph Script

The function orchestrates the multi-pass pipeline:

```bash
sandbox_setup() {
    local sandbox_dir="$RALPH_DIR/sandbox"
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=1; shift ;;
            *) echo "Error: unknown option for sandbox setup: $1" >&2; exit 1 ;;
        esac
    done

    # Load agent script (needed for agent_invoke)
    AGENT_SCRIPT="$RALPH_DIR/agents/${AGENT}.sh"
    if [[ ! -f "$AGENT_SCRIPT" ]]; then
        echo "Error: agent script not found: $AGENT_SCRIPT" >&2
        exit 1
    fi
    source "$AGENT_SCRIPT"

    if ! command -v "$AGENT_CLI" &>/dev/null; then
        echo "Error: agent CLI not found in PATH: $AGENT_CLI" >&2
        exit 1
    fi

    # Handle existing sandbox files
    if [[ -f "$sandbox_dir/Dockerfile" ]]; then
        if [[ "$force" -eq 0 ]]; then
            echo "Sandbox files already exist in $sandbox_dir/"
            echo "Use --force to regenerate."
            exit 1
        fi
        # Preserve .env across regeneration (contains user secrets/tokens)
        local saved_env=""
        if [[ -f "$sandbox_dir/.env" ]]; then
            saved_env=$(mktemp)
            cp "$sandbox_dir/.env" "$saved_env"
        fi
        rm -rf "$sandbox_dir"
    fi

    mkdir -p "$sandbox_dir"

    # Copy base Dockerfile into sandbox build context
    cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$sandbox_dir/Dockerfile.base"

    # Build base image (deterministic, no LLM involved)
    echo "Building sandbox base image..."
    docker build -t ralph-sandbox-base \
        -f "$sandbox_dir/Dockerfile.base" \
        "$sandbox_dir/"

    # Detect stack and resolve playbook
    local STACK
    STACK=$(detect_stack)
    local PLAYBOOK_FILE="$RALPH_DIR/prompts/playbooks/${STACK}.md"
    if [[ -n "$STACK" && -f "$PLAYBOOK_FILE" ]]; then
        export STACK_PLAYBOOK="$PLAYBOOK_FILE"
    else
        export STACK_PLAYBOOK=""
    fi

    # Pass 1: Analyze project → project profile
    echo "Analyzing project..."
    local analyze_prompt
    analyze_prompt=$(mktemp)
    prepare_prompt "$RALPH_DIR/prompts/sandbox-analyze.md" "$analyze_prompt"
    agent_invoke "$analyze_prompt" | agent_format_display
    rm -f "$analyze_prompt"

    if [[ ! -f "$sandbox_dir/project-profile.json" ]]; then
        echo "Error: analysis did not produce project-profile.json" >&2
        exit 1
    fi

    # Pass 2: Generate files from profile
    echo "Generating sandbox files..."
    local render_prompt
    render_prompt=$(mktemp)
    prepare_prompt "$RALPH_DIR/prompts/sandbox-render.md" "$render_prompt"
    agent_invoke "$render_prompt" | agent_format_display
    rm -f "$render_prompt"

    # Validate generated files
    local validation_failures
    validation_failures=$(sandbox_validate "$sandbox_dir")
    if [[ -n "$validation_failures" ]]; then
        echo ""
        echo "Validation found issues:"
        echo "$validation_failures"

        # Pass 3: Repair
        echo ""
        echo "Attempting automated repair..."
        export VALIDATION_FAILURES="$validation_failures"
        local repair_prompt
        repair_prompt=$(mktemp)
        prepare_prompt "$RALPH_DIR/prompts/sandbox-repair.md" "$repair_prompt"
        agent_invoke "$repair_prompt" | agent_format_display
        rm -f "$repair_prompt"

        # Re-validate
        validation_failures=$(sandbox_validate "$sandbox_dir")
        if [[ -n "$validation_failures" ]]; then
            echo ""
            echo "Remaining issues after repair:"
            echo "$validation_failures"
            echo ""
            echo "Please fix these manually before running 'ralph sandbox up'."
        fi
    fi

    # Restore .env if preserved from --force
    if [[ -n "${saved_env:-}" && -f "$saved_env" ]]; then
        cp "$saved_env" "$sandbox_dir/.env"
        rm -f "$saved_env"
        echo ""
        echo "Restored existing .env (your tokens are preserved)."
        echo ""
        echo "Next steps:"
        echo "  1. Review $sandbox_dir/.env against .env.example for any new variables"
        echo "  2. Run 'ralph sandbox up' to start the sandbox"
    else
        echo ""
        echo "Next steps:"
        echo "  1. cp $sandbox_dir/.env.example $sandbox_dir/.env"
        echo "  2. Edit $sandbox_dir/.env and set GITHUB_TOKEN and AMP_API_KEY"
        echo "  3. Run 'ralph sandbox up' to start the sandbox"
    fi
}
```

## Changes to Directory Structure

### ralph-loop repo (self-hosting)

```
prompts/
├── sandbox-analyze.md         # Pass 1: project analysis prompt
├── sandbox-render.md          # Pass 2: file generation prompt
├── sandbox-repair.md          # Pass 3: targeted repair prompt
├── templates/
│   └── Dockerfile.base        # Base image (managed, invariant)
└── playbooks/
    ├── php-laravel.md         # Stack-specific guidance
    └── ...
```

### Parent project (after installation)

```
.ralph/
├── sandbox/
│   ├── Dockerfile.base        # Copied from templates/ during setup
│   ├── Dockerfile             # Generated by Pass 2 (project-specific)
│   ├── docker-compose.yml     # Generated by Pass 2
│   ├── entrypoint.sh          # Generated by Pass 2
│   ├── .env.example           # Generated by Pass 2
│   ├── .env                   # User-created from .env.example (gitignored)
│   └── project-profile.json   # Generated by Pass 1 (committed)
├── prompts/
│   ├── sandbox-analyze.md     # Managed
│   ├── sandbox-render.md      # Managed
│   ├── sandbox-repair.md      # Managed
│   ├── templates/
│   │   └── Dockerfile.base    # Managed
│   └── playbooks/
│       └── php-laravel.md     # Managed
└── ...
```

### Docker Build Context

The build context for the app container is `.ralph/sandbox/`. This is entirely
within ralph's directory and does not overlap with the parent project's own
Docker context (if any). The parent project may have its own `Dockerfile` and
`docker-compose.yml` at the project root for production/development — these
are completely separate from the sandbox.

The base image build also uses `.ralph/sandbox/` as its context.
`Dockerfile.base` is copied into the sandbox directory during setup so
both builds share the same context directory.

## File Ownership

| File | Owner | Updated by `ralph update`? |
|---|---|---|
| `prompts/sandbox-analyze.md` | upstream | Yes |
| `prompts/sandbox-render.md` | upstream | Yes |
| `prompts/sandbox-repair.md` | upstream | Yes |
| `prompts/templates/Dockerfile.base` | upstream | Yes |
| `prompts/playbooks/*.md` | upstream | Yes |
| `sandbox/Dockerfile` | project | No — generated by setup |
| `sandbox/docker-compose.yml` | project | No — generated by setup |
| `sandbox/entrypoint.sh` | project | No — generated by setup |
| `sandbox/.env.example` | project | No — generated by setup |
| `sandbox/project-profile.json` | project | No — generated by setup |
| `sandbox/.env` | user | No — gitignored |
| `sandbox/Dockerfile.base` | upstream (copy) | Indirectly — copied from templates/ during setup |

## Changes to Existing Specs

### sandbox-cli.md

- `sandbox_container_name()` should look for the `app` service specifically
  (instead of the first/only service).
- `sandbox_shell` execs into the `app` container.
- `sandbox_reset` volume handling changes — codebase volume is on the `app`
  service, DB volume is on the `db` service. `--all` removes both.
- `sandbox_status` should show status of all service containers.

### sandbox-setup-prompt.md

Replaced entirely by this spec. The single `prompts/sandbox-setup.md` is
replaced by three focused prompts (`sandbox-analyze.md`, `sandbox-render.md`,
`sandbox-repair.md`) plus the base image template.

### project-structure.md

Update directory layouts to reflect new prompt files and templates directory.

### installer.md / updater.md

Add new managed files:
- `prompts/sandbox-analyze.md`
- `prompts/sandbox-render.md`
- `prompts/sandbox-repair.md`
- `prompts/templates/Dockerfile.base`

Remove: `prompts/sandbox-setup.md` (replaced)

## Impact on Playbooks

Stack playbooks remain useful but their scope narrows significantly. They no
longer need guidance on:
- Native database installation or initialization
- Supervisord configuration for infrastructure services
- Service health management

They focus on:
- Runtime installation (apt packages, PPAs, extensions)
- Package manager commands
- Framework bootstrap sequence (key generation, migrations, seeders)
- Env override defaults for the framework
- App-level supervisord programs (web server command, queue worker command)
- Workdir convention

The existing `php-laravel.md` playbook would shrink as the DB-related and
infrastructure supervisord sections are removed.

## Migration Path

For existing users who have already generated sandbox files with the current
single-container approach:

1. `ralph update` delivers the new prompts and base image template.
2. User runs `ralph sandbox setup --force` to regenerate.
3. `.env` is preserved across regeneration (existing behavior).
4. Old single-container sandbox files are replaced with multi-container ones.

No backward compatibility is needed — sandbox files are regenerated from
scratch with `--force`.

## Comparison: Current vs v2

| Aspect | Current (single container) | v2 (multi-container, multi-pass) |
|---|---|---|
| Prompt count | 1 (~365 lines) | 2–3 (~150 lines each, focused) |
| Container count | 1 (all-in-one) | 2–5 (app + services) |
| DB bootstrapping | Native install, initdb, PID files, temp start/stop | Official image, env vars, done |
| Supervisord scope | 5–8 programs (DB, web, queue, mail, redis, ...) | 1–3 programs (web, queue, vite) |
| Service detection | Must decide what to install natively (error-prone) | Must decide which compose services to add (simpler) |
| Entrypoint steps | 10 (including DB init, supervisord config gen) | 11 (but steps 8–10 are much simpler) |
| Consistency across runs | Low (entire generation is non-deterministic) | Higher (locked profile, separate passes) |
| Validation | Self-check in prompt (weak) | Machine validator + optional repair pass |
| Base image | None (everything generated each time) | Managed, invariant, built locally |
| Sandbox-preferences | Applied via COPY + separate files | Applied via heredocs (self-contained) |
