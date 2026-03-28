# Sandbox Setup Prompt — Multi-Container, Multi-Pass Architecture

## Implementation Order

This spec **must be implemented after** `sandbox-cli.md`. It creates/modifies
files in `prompts/` and adds stack detection logic and the multi-pass pipeline
to `sandbox_setup()` in the `ralph` script. The CLI plumbing that invokes
this pipeline already exists after `sandbox-cli.md` is implemented.

## Overview

The sandbox setup system uses a multi-container architecture with a multi-pass
prompt pipeline to generate project-specific sandbox files. Services (database,
cache, mail) run in their own containers using official Docker images, while the
agent works exclusively in an app container. A managed base image provides the
invariant layer (OS, tools, agent CLI), and LLM-generated files handle only
project-specific concerns.

Three separate prompts handle analysis, generation, and repair:

- `prompts/sandbox-analyze.md` — Pass 1: analyze the project, produce a
  structured profile
- `prompts/sandbox-render.md` — Pass 2: generate sandbox files from the profile
- `prompts/sandbox-repair.md` — Pass 3: fix validation failures (runs automatically when validation finds issues)

A machine validator checks generated files for structural correctness before
the user ever runs `docker compose up`.

## Design Principles

1. **Services run in their own containers.** Database, cache, mail, and search
   services use official Docker images. The app container contains only the
   project runtime, dependencies, tooling, and app-level processes.
   `depends_on` with healthchecks ensures service readiness.
2. **The base image is invariant.** It changes only when ralph's own
   requirements change (new system dependency, new tool). It is a managed file
   updated by `ralph update`. The base image is auto-refreshed on every
   `ralph sandbox up` so updates take effect without manual rebuilds.
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
7. **User preferences are deterministic.** Sandbox-preferences is a
   user-maintained bash script (`sandbox-preferences.sh`) that runs during
   `docker build`. Ralph COPY's and executes it without LLM interpretation —
   the content is applied byte-for-byte, not parsed or translated by an agent.

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

This produces a much simpler supervisord configuration than managing
infrastructure alongside app processes: 1–3 well-known program blocks instead
of 5–8 that include database servers, cache engines, and mail catchers. The
LLM's task is to generate a few predictable supervisord programs from the
project profile, not to configure infrastructure services from scratch.

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
- User preferences from `sandbox-preferences.sh`
- GitHub CLI (only needed for GitHub-hosted projects)

These are added by the generated project Dockerfile which uses the base image
as its `FROM` layer.

### Build Sequence

The base image is built during `ralph sandbox setup` (before the agent runs)
and auto-refreshed on every `ralph sandbox up`:

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

Auto-refreshing on every `ralph sandbox up` ensures that `ralph update`
changes to the base image take effect without manual intervention. Docker
layer cache makes the rebuild instant when the Dockerfile is unchanged.

The generated project Dockerfile references it:

```dockerfile
FROM ralph-sandbox-base

USER root

# Project-specific runtime, extensions, packages (LLM-generated)
RUN apt-get update && apt-get install -y php8.3-cli php8.3-fpm ...

# User preferences (deterministic — no LLM involvement)
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh && rm -f /tmp/sandbox-preferences.sh

RUN chown -R ralph:ralph /home/ralph
USER ralph

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
EXPOSE 80
```

**User preferences are applied via `sandbox-preferences.sh`** — a user-maintained
bash script that ralph COPY's into the build context and executes during
`docker build`. The script runs non-interactively (no TTY), so users must ensure
their commands are Docker-build-compatible. The LLM does not read, interpret, or
translate this file — it emits the fixed COPY/RUN block above. See the "Sandbox
Preferences" section for details.

## Multi-Pass Prompt Pipeline

### Pass 1: Analyze → Project Profile

**Prompt:** `prompts/sandbox-analyze.md`

The agent reads the project sources (manifests, env files, CI config, AGENTS.md,
existing Docker files, test config) and outputs a structured project profile in
JSON. The prompt is focused exclusively on discovery and decision-making — the
agent does not generate any Docker files.

The prompt includes the same "Sources to read" and "Decision rules" sections
from the "What the Setup Agent Analyzes" section below, plus the stack playbook
if available. It instructs the agent to output **only** a JSON profile to a
designated file.

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

### Profile Schema

The profile is the contract between Pass 1 (analysis) and Pass 2 (generation).
Required fields must always be present — use empty arrays/objects (`[]`, `{}`)
when a section does not apply. Optional fields may be omitted entirely.

Separating analysis from generation improves consistency: the same profile
always produces the same (or very similar) output, and the profile serves as
a debuggable intermediate artifact that users can inspect and edit.

**Required top-level fields:**

| Field | Type | Description |
|---|---|---|
| `schema_version` | integer | Always `1`. Reserved for future schema changes. |
| `stack` | string | Detected stack identifier (e.g., `"php-laravel"`, `"node"`, `"python-django"`). Empty string if unknown. |
| `runtimes` | array of objects | Language runtimes. Each: `name` (required), `version` (required), `evidence` (required, array of strings). |
| `package_managers` | array of objects | Each: `name` (required), `install_command` (required). |
| `services` | array of objects | External services (DB, cache, mail). Each: `name` (required), `image` (required), `port` or `ports` (required), `reason` (required). Empty array if no services needed. |
| `system_packages` | array of strings | APT packages needed for the runtime (e.g., dev libraries). |
| `git_provider` | string | `"github"` or `"other"`. Determines credential setup and whether GitHub CLI is installed. |
| `git_remote` | string | Git clone URL for the project. |
| `workdir` | string | Container working directory (e.g., `"/var/www/html"`, `"/app"`). |
| `env_overrides` | object | Key-value pairs written to the project's `.env` on first boot. Service hostnames use compose service names (e.g., `"DB_HOST": "db"`). |
| `bootstrap` | object | See below. |
| `supervisor_programs` | array of objects | Each: `name` (required), `command` (required). Must contain at least one entry. For projects with no long-running app processes, use `{"name": "keepalive", "command": "sleep infinity"}`. |
| `compose_ports` | object | Port mappings for `.env.example` and docker-compose.yml. Keys are descriptive names (e.g., `"http"`, `"db"`), values are port numbers. |
| `assumptions` | array of strings | Decisions made without strong evidence. |
| `notes` | array of strings | Observations, warnings, or context for the user. |

**Required fields in `bootstrap`:**

| Field | Type | Description |
|---|---|---|
| `secret_generation` | string or null | Command to generate app secrets (e.g., `"php artisan key:generate --force"`). Null if not needed. |
| `migration` | string or null | Migration command. Null if no database. |
| `seeder` | string or null | Seeder command. Null if no seeders. |
| `post_install` | array of strings | Post-install commands (e.g., `["php artisan storage:link", "npm run build"]`). Empty array if none. |

**Optional top-level fields:**

| Field | Type | Description |
|---|---|---|
| `php_extensions` | array of strings | PHP extensions to install. Only present for PHP stacks. |
| `test_env` | object or null | Test environment config: `file` (string), `test_db` (string or null), `secrets` (array of strings). |
| `pre_migration_sql` | array of strings | SQL statements to run before migrations (e.g., `CREATE EXTENSION`). |

**Key rules for the analysis prompt:**
- Output only the JSON profile — no Docker files, no bash scripts.
- Every decision must cite evidence (the `evidence`, `reason` fields).
- Ambiguous or uncertain items go in `assumptions` or `notes`.
- The profile schema is defined in the spec (above) and replicated in the
  prompt so the agent knows the expected structure.
- Required fields must always be present, even when empty.

### Pass 2: Generate Files from Profile

**Prompt:** `prompts/sandbox-render.md`

The agent reads the project profile and generates the four sandbox files. The
prompt provides:
- The locked project profile (read from `.ralph/sandbox/project-profile.json`)
- Hard constraints (named volumes, non-root user, tini, git-mediated code flow)
- File responsibilities (what each file must accomplish)
- Git credential snippets (Appendix A — these handle known failure modes with
  `gh auth login` and URL-encoded credentials)
- The stack playbook (if available) for stack-specific code patterns
- The `sandbox-preferences.sh` script is COPY'd into the build context by
  ralph before the agent runs — the render prompt does not read or interpret it

**Key rules for the render prompt:**
- Do not re-analyze the project. Use only information from the profile.
- Do not add services, packages, or steps not represented in the profile.
- Follow the profile's decisions exactly (runtime versions, package managers,
  env overrides, bootstrap commands).
- Emit the fixed COPY/RUN block for `sandbox-preferences.sh` — do not read
  or interpret the script's contents.
- For each entry in `profile.runtimes`, the Dockerfile must explicitly
  provision that runtime version and make it the default on PATH. Never rely
  on a runtime that happens to exist in `ralph-sandbox-base`.
- Make runtime selection a Dockerfile concern, not an entrypoint concern.
  Prefer stable install locations plus `ENV PATH=...`. Do not source shell
  init scripts in the entrypoint (e.g., `nvm.sh`, `pyenv init`, `rbenv init`). If a version
  manager is used, it must be fully installed and initialized in the Dockerfile
  so the selected runtime is already on PATH before the entrypoint runs.

This separation means the render agent has a much simpler job: translate a
structured specification into Docker files. The decisions are already made.

### Pass 3: Repair (Conditional)

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

`ralph sandbox setup` runs the full pipeline by default. Two flags modify
behavior:

- `--force` — overwrites existing generated files (preserves `.env`).
- `--render-only` — skips Pass 1 (analysis), uses the existing
  `project-profile.json` to run Pass 2 (generation) → validation → repair.
  This is the advanced correction path: the user edits `project-profile.json`
  to fix a wrong runtime version, add a missing service, or adjust env
  overrides, then re-renders without paying for re-analysis.

The flags are orthogonal:

| Scenario | Behavior |
|---|---|
| No sandbox files exist | Pass 1 → Pass 2 → validate |
| Files exist, no flags | Error: "use --force to regenerate" |
| `--force` | Delete sandbox dir (preserve .env) → Pass 1 → Pass 2 → validate |
| `--render-only` | Require existing profile → Pass 2 → validate |
| `--render-only --force` | Require existing profile, delete generated files (preserve .env, preserve profile) → Pass 2 → validate |

**`--render-only` guard rails:**
- If `project-profile.json` does not exist, exit with error:
  `"No project profile found. Run 'ralph sandbox setup' first (without --render-only)."`
- Profile schema is validated before Pass 2 starts — missing required fields
  produce a clear error listing the missing fields.
- `--render-only` never modifies `project-profile.json`.
- When combined with `--force`, only generated files (Dockerfile, entrypoint.sh,
  docker-compose.yml, .env.example) are deleted. The profile and `.env` are
  preserved.

The `--render-only` flag exists so users can fix wrong detections without
re-paying for analysis. If Pass 1 detected the wrong PHP version or missed a
service, the user edits the profile JSON directly and re-renders.

## Machine Validator

A bash function (`sandbox_validate()` in the ralph script) that checks
generated files for structural correctness. Run automatically after Pass 2
(and after Pass 3 if invoked).

### Checks

**Syntax:**
- `bash -n entrypoint.sh` — entrypoint parses without errors
- `docker compose -f docker-compose.yml config` — compose file is valid
- `bash -n sandbox-preferences.sh` — preferences script parses without errors

**Structural (Dockerfile):**
- `FROM ralph-sandbox-base` is present
- `ENTRYPOINT` uses tini
- `entrypoint.sh` is copied into the image
- WORKDIR is set
- `sandbox-preferences.sh` is COPY'd and executed

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
  (commented-out entries count as documented — optional vars like
  `SANDBOX_NAME` are intentionally commented)
- Service ports in compose healthchecks match the service images' default ports
- If entrypoint.sh references a runtime manager init script or command
  (`nvm.sh`, `pyenv init`, `rbenv init`, `.asdf/asdf.sh`, `sdkman-init.sh`,
  `volta`), the Dockerfile must also reference it (i.e., install and configure
  it). Catches entrypoints that source tools the Dockerfile never installed.

**Profile consistency:**
- Services in compose match `services` array in project profile
- Runtime/version in Dockerfile matches profile
- Env overrides in entrypoint match profile

**Profile schema (run before Pass 2):**
- All required top-level fields are present
- `schema_version` equals `1`
- `supervisor_programs` has at least one entry
- `runtimes` has at least one entry
- All `services` entries have required fields (`name`, `image`, `port`/`ports`, `reason`)

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

## Generated Files

### 1. Dockerfile (project-specific)

With the base image handling invariants, the generated Dockerfile is short.
User preferences are applied deterministically via `sandbox-preferences.sh`.

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

# User preferences (deterministic — no LLM involvement)
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh && rm -f /tmp/sandbox-preferences.sh

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

The entrypoint follows five phases. Individual steps within each phase
maintain their own idempotency boundaries (sentinel files) but the phases
give the LLM a smaller mental model for generation. Phases are conceptual
groupings that reduce LLM cognitive load — they are not merged retry
boundaries. Each substep keeps its own sentinel so that failures can be
retried independently.

```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[sandbox] ERROR: entrypoint failed at line $LINENO (exit $?)" >&2' ERR

RALPH_HOME="${RALPH_HOME:-.ralph}"

# =============================================
# Phase 1: Repo Access
# =============================================

# --- 1a. Git credentials ---
# Use exact snippets from Appendix A of the render prompt (unchanged from
# current — these handle known failure modes with gh auth and URL-encoded
# credentials). GitHub path when GITHUB_TOKEN is set; generic credential
# store path when GIT_CRED_USER/GIT_CRED_PASS are set.

# --- 1b. Clone repo ---
if [ ! -f .git/HEAD ]; then
    sudo chown ralph:ralph "$(pwd)"
    git clone "$GIT_REPO" .
fi

# =============================================
# Phase 2: Ralph State Init
# =============================================

# --- 2a. Sentinel directory ---
mkdir -p "${RALPH_HOME}/.sandbox"

# =============================================
# Phase 3: Env Bootstrap
# =============================================

# --- 3a. App .env setup (first boot only) ---
# Copy project's .env.example → .env, then apply env_overrides from profile
# using sed commands. Service hostnames (db, mail, redis) instead of 127.0.0.1.
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    sed -i 's|^DB_HOST=.*|DB_HOST=db|' .env
    # ... remaining overrides from profile.env_overrides
fi

# --- 3b. Test env setup ---
# Copy test env template if it exists, populate empty secrets.

# =============================================
# Phase 4: Project Bootstrap
# =============================================

# --- 4a. Install dependencies (sentinel-guarded) ---
if [ ! -f "${RALPH_HOME}/.sandbox/deps-installed" ]; then
    <install-commands-from-profile>
    touch "${RALPH_HOME}/.sandbox/deps-installed"
fi

# --- 4b. App secret generation (if framework requires it) ---
<secret-generation-command-from-profile>

# --- 4c. Database bootstrap ---
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

# --- 4d. Post-install steps from profile.bootstrap.post_install ---

# =============================================
# Phase 5: Supervisord Handoff
# =============================================

# --- 5a. Supervisord programs (app-level processes only) ---
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

# --- 5b. Start supervisord (foreground) ---
exec supervisord -n -c /etc/supervisor/supervisord.conf
```

**Key characteristics:**
- **5 phases** (repo access, state init, env bootstrap, project bootstrap,
  supervisord handoff) instead of many flat steps
- No `initdb`, `pg_ctl`, `pg_createcluster`, stale PID handling
- No supervisord config for infrastructure services (DB, redis, mail)
- Supervisord manages only 1–3 app-level processes
- DB is already running and healthy when this script starts
- Service hostnames (`db`, `mail`) instead of `127.0.0.1`
- Each substep maintains its own idempotency boundary (sentinel files)

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

**Key characteristics:**
- Multiple services instead of one monolithic container
- Official images for services — no native installation
- `depends_on` with healthchecks — no wait-for-it scripts
- DB initialization handled entirely by the official postgres image
  (user, password, database created via environment variables)
- **Environment uses list syntax** (`- KEY=value`), never map syntax. Quote any
  entry whose value contains a colon.
- **Only infrastructure vars** — do NOT include app-config vars (`DB_*`,
  `MAIL_*`, `CACHE_STORE`, etc.) which would shadow the framework's dotenv
  loader.
- Named volumes for codebase and service data (not bind mounts)
- `env_file` with `required: false`
- `tty: true` and `stdin_open: true`
- Resource limits via env vars

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
user can remap ports per checkout.

### 4. .env.example

**Formatting rule:** Use plain ASCII section headers — `# --- Section Name ---`.
Do NOT use Unicode box-drawing characters or padded decorative lines.

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

Every env var used in `docker-compose.yml` must be documented here. **No
app-config vars.** Do not include `DB_*`, `MAIL_*`, `CACHE_STORE`, `APP_KEY`,
`JWT_SECRET`, or other application-level config — these are hardcoded in
`entrypoint.sh` and written to the project's `.env` on first boot.

## Sandbox Preferences

User preferences for the sandbox environment are defined in
`sandbox-preferences.sh` — a user-maintained bash script that runs as root
during `docker build`, after the project runtime is installed and before the
final `USER ralph` / `ENTRYPOINT` layers.

### How It Works

1. Ralph ships a starter `sandbox-preferences.sh` with commented-out examples.
2. The user uncomments and customizes the script for their needs.
3. During `ralph sandbox setup` (and `ralph sandbox up`), ralph copies the
   script into the sandbox build context.
4. The generated Dockerfile contains a fixed COPY/RUN block:
   ```dockerfile
   COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
   RUN bash /tmp/sandbox-preferences.sh && rm -f /tmp/sandbox-preferences.sh
   ```
5. The LLM never reads, interprets, or translates this file. Content is
   applied byte-for-byte.

### Starter File

The installer creates `sandbox-preferences.sh` with commented-out examples
of common tasks:

```bash
#!/usr/bin/env bash
# Sandbox Preferences
#
# User-defined preferences for the sandbox environment. This script runs as
# root during `docker build` to install packages, configure dotfiles, set up
# editors, and apply any other customizations you want in your container.
#
# How it works:
# - Runs during image build, not on every container start. Changes are baked
#   into the Docker image layer.
# - Every `ralph sandbox up` copies this file into the build context and
#   rebuilds with --build. Docker's layer cache skips re-execution if the
#   file hasn't changed. Edit this file and run `sandbox up` to apply changes.
# - Runs as root, so apt-get install, writing to /home/ralph, etc. all work.
#   Ownership of /home/ralph is fixed after this script runs.
#
# IMPORTANT: This script runs non-interactively — there is no TTY during
# `docker build`. Commands that read from /dev/tty will fail. This includes
# commands in scripts fetched via curl. Common patterns and workarounds:
#
#   Problem:  vim +PlugInstall +qall </dev/tty
#   Fix:      vim -es -u ~/.vimrc +PlugInstall +qall
#
#   Problem:  curl -fsSL https://example.com/setup.sh | bash  # script uses /dev/tty internally
#   Fix:      curl -fsSL https://example.com/setup.sh | sed 's|</dev/tty||g' | bash
#
#   Problem:  read -p "Continue? " answer </dev/tty
#   Fix:      Remove interactive prompts, or default to "yes" in Docker builds
#
# This file is user-owned — `ralph update` will never overwrite it.
#
# Common examples (uncomment and modify):
#
# --- Install packages ---
# apt-get update && apt-get install -y --no-install-recommends \
#     vim bash-completion ripgrep \
#     && rm -rf /var/lib/apt/lists/*
#
# --- Append to .bashrc ---
# cat >> /home/ralph/.bashrc <<'BASHRC'
# alias ll="ls -lF"
# export EDITOR=vim
# BASHRC
#
# --- Write .gitconfig ---
# cat > /home/ralph/.gitconfig <<'GITCONFIG'
# [push]
#     default = simple
# [pull]
#     rebase = true
# GITCONFIG
#
# --- Install editor plugins ---
# curl -fsSL https://example.com/vim-setup.sh | bash -s min
```

### Design Rationale

Previous iterations used `sandbox-preferences.md` — a markdown file that the
LLM read during setup and translated into Dockerfile instructions (heredocs,
apt-get commands, etc.). This was fragile because:

- User content is arbitrary — `.bashrc` with backticks, `$()` subshells,
  ANSI escapes in PS1; `.gitconfig` with complex format strings.
- The LLM is an unreliable intermediary for faithfully reproducing
  shell-heavy text. One escaping mistake breaks the Docker build silently.
- Different runs could translate the same preferences differently.

The bash script approach eliminates the LLM from the content-copying path
entirely. The user writes bash (they know their content), ralph COPY's and
runs it. Deterministic, debuggable, works for any content.

### File Ownership

`sandbox-preferences.sh` is user-owned. The installer creates the starter
file. `ralph update` treats it as a customizable file — it will not overwrite
user modifications (same as `config`). The file lives at
`$RALPH_DIR/sandbox-preferences.sh` and is copied into the sandbox build
context (`$RALPH_DIR/sandbox/sandbox-preferences.sh`) during setup and up.

## What the Setup Agent Analyzes

The analysis prompt instructs the agent to build a **project profile** by
examining:

- **Package manifests:** `composer.json`, `package.json`, `Gemfile`, `go.mod`,
  `requirements.txt`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, etc.
- **Existing containerization:** `Dockerfile`, `docker-compose.yml`,
  `.devcontainer/`, `docker/`, or similar directories — for reference only.
  Do not copy them, but reuse authoritative details like runtime versions,
  package names, and startup commands.
- **Environment configuration:** The project's `.env.example`, `config/database.yml`,
  or equivalent files that reveal database engine, cache driver, mail service,
  etc. (This is the **application** env file, distinct from the sandbox
  `.env.example` that the agent generates.)
- **CI configuration:** `.github/workflows/`, `.gitlab-ci.yml` — often reveals
  the full service stack.
- **Agent instructions:** `AGENTS.md` — documents how to run the project.
- **Test configuration:** `phpunit.xml`, `jest.config.*`, `pytest.ini`, etc. —
  reveals test database requirements.
- **Test environment files:** `.env.testing`, `.env.test`, or equivalent — these
   often contain empty secrets that must be generated for tests to pass.
- **Ralph dependencies:** The `dependencies` file in ralph's home directory lists
  system packages (apt) that ralph itself requires at runtime. All listed packages
  must be installed in the base image (they are already covered by the managed
  `Dockerfile.base`).

The agent must extract these conclusions from the sources above:

- All runtimes required by the project's install, build, run, or test
  commands — not just the primary framework runtime. Include secondary
  runtimes used only for asset builds or tooling (e.g., Laravel + Vue,
  Rails + webpack).
- Package manager(s) — prefer lockfiles over manifests for tool choice
- Required services as compose services (DB, cache, search, mail, etc.) —
  each becomes a separate container using official Docker images
- Long-running app processes the project needs (web server, queue worker,
  Vite/HMR dev server, scheduler, etc.) — these are the only processes
  managed by supervisord
- Primary workdir path
- Bootstrap/install command(s)
- Likely test command
- Git hosting provider (GitHub vs other)

### Decision Rules

- Always provision the project's primary database engine as a compose service.
  Agents need to run the full app, not just tests. Use .env.example, config
  files, and docker-compose.yml to determine the primary engine.
- If tests use a different DB (e.g., SQLite for speed), configure that as the
  test database, but still provision the primary server DB as a compose service.
- Include only *additional* services (cache, search, queue) that AGENTS.md, CI,
  test config, or env/config actually require. Each becomes its own compose
  service with an official Docker image.
- Include Mailpit only when mail is used by the project or implied by framework.
- For ambiguous cases (monorepos, multiple runtimes), optimize for the primary
  app; note limitations in `assumptions` or `notes`.
- For each runtime, prefer explicit version pins from project files (`.nvmrc`,
  `.node-version`, `.python-version`, `.ruby-version`, `.tool-versions`, manifest
  engine fields). Use CI config or existing Dockerfiles only as fallback. Record
  pinned old/EOL versions exactly; do not upgrade them.

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
guidance. They live in `prompts/playbooks/` and are injected into the analysis
prompt (`prompts/sandbox-analyze.md`) by ralph's `sandbox_setup()` function
based on deterministic stack detection.

### Directory Structure

```
prompts/
├── sandbox-analyze.md         # Pass 1: project analysis prompt (stack-agnostic)
├── sandbox-render.md          # Pass 2: file generation prompt
├── sandbox-repair.md          # Pass 3: targeted repair prompt
├── templates/
│   └── Dockerfile.base        # Base image (managed, invariant)
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
`ralph update`). Not every stack needs a playbook — the analysis prompt handles
unknown stacks on its own.

### Stack Detection

The `sandbox_setup()` function detects the project's primary stack before
invoking the agent. Detection is deterministic (bash, not LLM) to avoid
adding a failure point where the agent misidentifies or skips the playbook.

See the `detect_stack()` function in "Changes to `ralph` Script" below for
the full implementation.

**Key design decisions:**

- **`package.json` is checked last.** Almost every web project has one for
  frontend assets — its presence alone does not indicate a Node project.
- **Framework before runtime.** `php-laravel` before `php`, `rails` before
  `ruby`, `python-django` before `python`. Framework-specific playbooks carry
  more targeted guidance than generic runtime playbooks.
- **Grep for framework markers.** Checking `composer.json` for
  `laravel/framework`, `Gemfile` for `rails`, `manage.py` for `django` — these
  are strong, reliable signals.
- **Graceful fallback.** If nothing matches, no playbook is injected. The
  analysis prompt handles it alone.

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

The analysis prompt (`prompts/sandbox-analyze.md`) references the playbook as
the **first bullet** under "Sources to read", bolded, with directive language:

> **If `${STACK_PLAYBOOK}` is non-empty, read the playbook first. Follow its
> guidance for runtime installation, package manager commands, bootstrap steps,
> and app-level supervisord programs.**

### Playbook Content Guidelines

Playbooks focus on:
- Runtime installation (apt packages, PPAs, extensions)
- Package manager commands
- Framework bootstrap sequence (key generation, migrations, seeders)
- Env override defaults for the framework
- App-level supervisord programs (web server command, queue worker command)
- Workdir convention

Playbooks do **not** cover:
- Native database installation or initialization (services run in their own
  containers)
- Supervisord configuration for infrastructure services (not applicable)
- Service health management (handled by compose healthchecks)

### Adding New Playbooks

1. Create `prompts/playbooks/{stack}.md` with stack-specific guidance.
2. Add a detection rule to `detect_stack()` if the stack doesn't already have
   one.
3. Add the playbook to `MANAGED_FILES` in `update.sh`.

## Template Variables

The prompts use `envsubst` variables like other ralph prompts:

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
add each as a separate compose service with its own official Docker image and
named volume.

### Tests use SQLite in-memory

Many projects use SQLite for tests regardless of production database. The agent
should still provision the production database as a compose service (for
development and manual testing) but may note in the profile that the test suite
uses SQLite.

### No playbook for detected stack

If `detect_stack()` identifies a stack but no playbook file exists for it, the
agent proceeds with the analysis prompt alone. The analysis prompt is designed to
be sufficient — playbooks are an enhancement, not a requirement.

### First build is slow

The generated Dockerfile will produce large images (1-3GB). `ralph sandbox up`
should print a message: "First build may take several minutes." Subsequent starts
reuse the cached image and are fast.

## Changes to `ralph` Script

### `sandbox_setup()` Function

The function orchestrates the multi-pass pipeline:

```bash
sandbox_setup() {
    local sandbox_dir="$RALPH_DIR/sandbox"
    local force=0
    local render_only=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=1; shift ;;
            --render-only) render_only=1; shift ;;
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

    # --render-only requires an existing profile
    if [[ "$render_only" -eq 1 && ! -f "$sandbox_dir/project-profile.json" ]]; then
        echo "Error: no project profile found at $sandbox_dir/project-profile.json" >&2
        echo "Run 'ralph sandbox setup' first (without --render-only)." >&2
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
        if [[ "$render_only" -eq 1 ]]; then
            # Preserve profile — only delete generated files
            local saved_profile
            saved_profile=$(mktemp)
            cp "$sandbox_dir/project-profile.json" "$saved_profile"
            rm -rf "$sandbox_dir"
            mkdir -p "$sandbox_dir"
            cp "$saved_profile" "$sandbox_dir/project-profile.json"
            rm -f "$saved_profile"
        else
            rm -rf "$sandbox_dir"
        fi
    fi

    mkdir -p "$sandbox_dir"

    # Copy base Dockerfile and sandbox-preferences into build context
    cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$sandbox_dir/Dockerfile.base"
    cp "$RALPH_DIR/sandbox-preferences.sh" "$sandbox_dir/sandbox-preferences.sh"

    # Build base image (deterministic, no LLM involved)
    echo "Building sandbox base image..."
    docker build -t ralph-sandbox-base \
        -f "$sandbox_dir/Dockerfile.base" \
        "$sandbox_dir/"

    if [[ "$render_only" -eq 0 ]]; then
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
    else
        echo "Using existing project profile (--render-only)."
    fi

    # Validate profile schema before Pass 2
    local profile_errors
    profile_errors=$(sandbox_validate_profile "$sandbox_dir/project-profile.json")
    if [[ -n "$profile_errors" ]]; then
        echo "Error: project profile has schema errors:" >&2
        echo "$profile_errors" >&2
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

### `detect_stack()` Function

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

## Changes to Installer and Updater

### New managed files

- `prompts/sandbox-analyze.md` — Pass 1 analysis prompt
- `prompts/sandbox-render.md` — Pass 2 generation prompt
- `prompts/sandbox-repair.md` — Pass 3 repair prompt
- `prompts/templates/Dockerfile.base` — base image template
- `sandbox-preferences.sh` — user-customizable starter script

### Removed managed files

- `prompts/sandbox-setup.md` — replaced by the three focused prompts above

### Playbooks

- `prompts/playbooks/` directory and all playbook files are managed upstream

## Migration from Single-Container Sandbox

Existing users who generated sandbox files with the previous single-container
approach upgrade by running `ralph update` (delivers new prompts and base image
template), then `ralph sandbox setup --force` to regenerate. The `.env` file is
preserved across `--force` regeneration. Old single-container sandbox files are
replaced with multi-container ones. No backward compatibility is needed —
sandbox files are regenerated from scratch.

## Changes to Project Structure

The directory layouts in `specs/project-structure.md` are updated to reflect
the new prompt files, templates directory, and `sandbox-preferences.sh`. See
that spec for the current layouts.
