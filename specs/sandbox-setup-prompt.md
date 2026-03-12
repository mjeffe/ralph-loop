# Sandbox Setup Prompt — Agent Instructions for Generating Sandbox Files

## Implementation Order

This spec **must be implemented after** `sandbox-cli.md`. It creates a new file
(`prompts/sandbox-setup.md`) and does not modify the `ralph` script. The CLI
plumbing that invokes this prompt already exists after `sandbox-cli.md` is
implemented — this spec only provides the content the agent receives.

The split exists because `sandbox-cli.md` modifies the `ralph` script, which is
the script ralph-loop uses to run itself. Those changes must land and stabilize
before this session adds new content. This spec is safe to implement in a
subsequent session because it only creates a new prompt file with zero risk to
the running ralph script.

## Overview

The `prompts/sandbox-setup.md` file is a managed upstream prompt template invoked
by `ralph sandbox setup`. It instructs the configured agent to analyze the target
project and generate four sandbox files: `Dockerfile`, `entrypoint.sh`,
`docker-compose.yml`, and `.env.example`.

This is a managed file (tracked in `.manifest`, updated by `ralph update`).

## What the Setup Agent Analyzes

The prompt instructs the agent to examine:

- **Package manifests:** `composer.json`, `package.json`, `Gemfile`, `go.mod`,
  `requirements.txt`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, etc.
- **Existing containerization:** `Dockerfile`, `docker-compose.yml`,
  `.devcontainer/`, `docker/`, or similar directories.
- **Environment configuration:** `.env.example`, `config/database.yml`, or
  equivalent files that reveal database engine, cache driver, mail service, etc.
- **CI configuration:** `.github/workflows/`, `.gitlab-ci.yml` — often reveals
  the full service stack.
- **Agent instructions:** `AGENTS.md` — documents how to run the project.
- **Test configuration:** `phpunit.xml`, `jest.config.*`, `pytest.ini`, etc. —
  reveals test database requirements.

## What the Setup Agent Generates

The agent creates four files in `.ralph/sandbox/`:

### 1. `Dockerfile`

An all-in-one container image. Key requirements the prompt enforces:

- **Base image:** Use `ubuntu:24.04` (or the latest LTS) for consistency.
- **All services in one container.** Database server, mail catcher, application
   runtime, package managers — everything the project needs to run and test.
- **Include `tini`.** Install `tini` as a proper PID 1 init process. Set it as
   `ENTRYPOINT` with `entrypoint.sh` as its argument (see below).
- **Include `supervisord`.** Install `supervisor` to manage long-running services
   (database, mail catcher, etc.). The entrypoint handles one-time setup, then
   hands off to `supervisord` which starts and restarts services as needed.
- **Include the agent CLI.** Install `@sourcegraph/amp` via npm (or whichever agent
   the project uses). The agent must be runnable inside the container.
- **Include `gh` CLI.** Required for git authentication via `gh auth setup-git`.
- **Create a non-root user.** Use `ralph` with passwordless sudo.
- **Copy `entrypoint.sh`** into the image.

### 2. `entrypoint.sh`

The container entrypoint script. Key requirements:

- **Git credential setup:** Configure git authentication using `GITHUB_TOKEN` by
  writing it to a file and piping to `gh auth login`, then running `gh auth setup-git`.
  Do not pass the token on the command line (it would be visible in process listings).
- **Clone on first run:** If the codebase directory is empty (fresh volume), clone
  `GITHUB_REPO`. Skip on subsequent starts.
- **Generate `.env` on first run:** Copy the project's `.env.example` and apply
  sandbox-specific overrides (e.g., `DB_HOST=127.0.0.1`, `MAIL_HOST=127.0.0.1`,
  `QUEUE_CONNECTION=sync`).
- **Install dependencies on first run:** Run the project's package manager install
  commands (e.g., `composer install`, `npm install`).
- **Start services via supervisord:** After one-time setup completes, hand off to
  `supervisord` by ending with `exec supervisord -n -c /etc/supervisor/supervisord.conf`.
  Supervisord manages all long-running services (database, mail catcher, etc.) and
  restarts them if they crash. `tini` (PID 1) handles signal forwarding and zombie
  reaping above supervisord.
- **Run migrations:** Apply database migrations on first run.
- **Generate supervisord config:** Create a `/etc/supervisor/conf.d/*.conf` file
  for each service. Each program block should set `autorestart=true`,
  `startsecs=5`, and appropriate `stdout_logfile`/`stderr_logfile` paths.
- **Sentinel files for idempotency:** Multi-step operations (dependency install,
  migrations) must use a sentinel file to track completion. For example, touch
  `/var/www/html/.sandbox-deps-installed` after a successful `composer install`.
  Check for the sentinel — not the output directory — so that a partial run
  (interrupted `composer install` that created `vendor/` but didn't finish) gets
  retried on next start. Simple existence checks (e.g., `.git/HEAD` for clone,
  `.env` for env generation) are fine for single-command steps.

### 3. `docker-compose.yml`

Compose configuration. Key requirements:

- **Project name:** Use `{project-name}-sandbox` (derived from the git repo name or
  directory name) to avoid collisions with the project's own compose setup.
- **Container name:** Use `{project-name}-sandbox` for predictable `docker exec`.
- **Environment variables:** Pass through `GITHUB_TOKEN`, `AMP_API_KEY`, and
  `GITHUB_REPO` from `.env`. Set `SANDBOX=1`.
- **Git SSH-to-HTTPS rewrite:** Include `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0`, and
  `GIT_CONFIG_VALUE_0` to rewrite `git@github.com:` to `https://github.com/` so the
  PAT works for git operations.
- **Volumes:** Named volumes for the codebase and database data (not bind mounts).
- **Ports:** Expose application port, database port, mail UI port, etc. Source
  host-side ports from `.env` variables (e.g., `${SANDBOX_HTTP_PORT:-80}:80`) so
  users can remap them to avoid collisions with host services.
- **Healthcheck:** Include a `healthcheck` that verifies all supervisord-managed
  services are in RUNNING state. Use a generous `start_period` (60s+) to allow
  for first-run setup.
- **`tty: true` and `stdin_open: true`** to keep the container running.
- **Resource limits:** Include `deploy.resources.limits` with memory and CPU
  limits sourced from `.env` (e.g., `SANDBOX_MEMORY_LIMIT`, `SANDBOX_CPU_LIMIT`)
  with sensible defaults (4g memory, 2 CPUs). This prevents runaway agent
  processes from consuming all host resources.
- **Build context:** Point to `.ralph/sandbox/` (i.e., `context: .`).
- **env_file:** Reference `.env` (the gitignored secrets file).

### 4. `.env.example`

Template for the secrets file. Always includes:

```env
# GitHub Personal Access Token (fine-grained, scoped to this repo)
GITHUB_TOKEN=

# Amp API key (https://ampcode.com)
AMP_API_KEY=

# Repository to clone (HTTPS URL)
GITHUB_REPO=https://github.com/{owner}/{repo}.git

# Resource limits (optional — defaults shown)
SANDBOX_MEMORY_LIMIT=4g
SANDBOX_CPU_LIMIT=2

# Port mappings (optional — change to avoid collisions with host services)
SANDBOX_HTTP_PORT=80
SANDBOX_VITE_PORT=5173
SANDBOX_DB_PORT=5432
SANDBOX_SMTP_PORT=1025
SANDBOX_MAIL_UI_PORT=8025
```

The agent pre-fills `GITHUB_REPO` based on the project's git remote.

## Prompt Template Content

The `prompts/sandbox-setup.md` file uses `envsubst` variables like other ralph
prompts.

```markdown
You are an expert DevOps engineer. Your task is to generate an isolated,
all-in-one Docker sandbox for this project so that AI coding agents can work
in a safe, disposable environment.

## Context

- **Ralph home:** ${RALPH_HOME}
- **Sandbox directory:** ${RALPH_HOME}/sandbox

## What to analyze

Scan the project to determine the full runtime stack:

1. Read package manifests (composer.json, package.json, Gemfile, go.mod,
   requirements.txt, Cargo.toml, pyproject.toml, etc.)
2. Read existing Docker/container files (Dockerfile, docker-compose.yml,
   .devcontainer/, docker/, etc.) for reference — do not reuse them directly,
   build the sandbox independently
3. Read .env.example or equivalent for database engine, cache, mail, queue config
4. Read AGENTS.md for project-specific run instructions
5. Read CI config (.github/workflows/, .gitlab-ci.yml) for service dependencies
6. Read test config (phpunit.xml, jest.config.*, pytest.ini) for test database needs
7. Identify the git remote URL for GITHUB_REPO default

## What to generate

Create these four files in ${RALPH_HOME}/sandbox/:

### 1. Dockerfile

Build an all-in-one container based on ubuntu:24.04 that includes:
- The project's language runtime and version (e.g., PHP 8.4, Node 22, Python 3.12)
- All required extensions and system packages
- Database server (PostgreSQL, MySQL, SQLite — whatever the project uses)
- Mail catcher (Mailpit) for local SMTP
- Package managers (composer, npm/yarn/pnpm, pip, etc.)
- GitHub CLI (gh) for git authentication
- Amp CLI: npm install -g @sourcegraph/amp
- tini (apt-get install -y tini) as PID 1 init process
- supervisord (apt-get install -y supervisor) to manage long-running services
- A non-root user named "ralph" with passwordless sudo
- Copy entrypoint.sh into the image
- ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]
- Expose relevant ports (app, database, mail UI, Vite/HMR if applicable)
- WORKDIR set to /var/www/html for PHP projects, /app for others

### 2. entrypoint.sh

Write an idempotent entrypoint that:
- Configures git credentials securely — write GITHUB_TOKEN to a temporary file,
  pipe it to `gh auth login --with-token`, then run `gh auth setup-git`, then
  delete the temporary file. Never pass the token on the command line.
- Clones GITHUB_REPO into the workdir if .git/HEAD is missing (fresh volume)
- Copies .env.example to .env if missing, with sandbox overrides (DB_HOST=127.0.0.1,
  MAIL_HOST=127.0.0.1, QUEUE_CONNECTION=sync, CACHE_STORE=file)
- Generates app secret/key if the framework requires it
- Installs dependencies and tracks completion with a sentinel file (e.g., touch
  .sandbox-deps-installed after successful install). Check the sentinel, not the
  output directory, so partial installs get retried.
- Initializes the database cluster/data directory if needed
- Creates database user and databases
- Starts the database temporarily, runs migrations (tracked with sentinel file),
  then stops it — supervisord will manage the database process going forward
- Ends with: exec supervisord -n -c /etc/supervisor/supervisord.conf
  (tini handles signal forwarding as PID 1 above supervisord)
- Generates supervisord config files in /etc/supervisor/conf.d/ for each service
  (database, mail catcher, etc.) with autorestart=true and startsecs=5

Simple existence checks (.git/HEAD, .env) are fine for single-command steps.
Multi-step operations must use sentinel files for reliable idempotency.

### 3. docker-compose.yml

- name: {project-name}-sandbox (derive from git remote or directory name)
- container_name: {project-name}-sandbox
- Build context: . (the sandbox directory)
- Environment: SANDBOX=1, GITHUB_TOKEN, AMP_API_KEY, GITHUB_REPO,
  plus GIT_CONFIG vars to rewrite SSH URLs to HTTPS
- Named volumes: sandbox-codebase (for workdir), sandbox-db (for database data)
- Ports: map standard ports using env vars with defaults
  (e.g., ${SANDBOX_HTTP_PORT:-80}:80) so users can remap to avoid collisions
- healthcheck using supervisorctl status to verify all services are RUNNING
  (start_period: 60s to allow for first-run setup)
- tty: true, stdin_open: true
- deploy.resources.limits: memory ${SANDBOX_MEMORY_LIMIT:-4g}, cpus ${SANDBOX_CPU_LIMIT:-2}
- env_file: .env

### 4. .env.example

Template with:
- GITHUB_TOKEN= (with comment: fine-grained PAT scoped to this repo)
- AMP_API_KEY= (with comment: https://ampcode.com)
- GITHUB_REPO= (pre-filled from git remote)
- SANDBOX_MEMORY_LIMIT=4g (with comment: optional resource limits)
- SANDBOX_CPU_LIMIT=2
- SANDBOX_HTTP_PORT=80 (with comment: optional port mappings)
- SANDBOX_VITE_PORT=5173
- SANDBOX_DB_PORT=5432
- SANDBOX_SMTP_PORT=1025
- SANDBOX_MAIL_UI_PORT=8025

## Rules

- Do NOT reuse the project's existing Dockerfile or docker-compose.yml. Build
  from scratch for the sandbox — existing files are reference only.
- The container must be fully self-contained. No Docker-in-Docker, no sidecar
  containers, no host mounts for the codebase.
- Use named Docker volumes, not bind mounts, for the codebase and database.
- Install services natively in the container (apt-get), not as separate containers.
- The sandbox must support running the project's full test suite.
- Add comments in generated files explaining non-obvious choices.
- Commit all generated files with message: "chore: generate sandbox environment"

When complete, output: <promise>COMPLETE</promise>
```

## Example: Generated Output for a Laravel Project

For a Laravel project using PHP 8.4, PostgreSQL 17, Node 22, these files would be
generated by the setup agent:

### `Dockerfile` (example)

```dockerfile
FROM ubuntu:24.04

LABEL description="All-in-one development sandbox for AI coding agents"

ARG NODE_VERSION=22
ARG POSTGRES_VERSION=17

WORKDIR /var/www/html

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# System packages
RUN apt-get update && apt-get upgrade -y \
    && mkdir -p /etc/apt/keyrings \
    && apt-get install -y \
       gnupg gosu curl ca-certificates zip unzip git tini sqlite3 \
       libcap2-bin libpng-dev python3 dnsutils librsvg2-bin nano \
       sudo lsb-release wget supervisor

# PHP 8.4
RUN curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xb8dc7e53946656efbce4c1dd71daeaab4ad4cab6' \
        | gpg --dearmor | tee /etc/apt/keyrings/ppa_ondrej_php.gpg > /dev/null \
    && echo "deb [signed-by=/etc/apt/keyrings/ppa_ondrej_php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main" \
        > /etc/apt/sources.list.d/ppa_ondrej_php.list \
    && apt-get update \
    && apt-get install -y php8.4-cli php8.4-dev \
       php8.4-pgsql php8.4-sqlite3 php8.4-gd php8.4-curl \
       php8.4-mbstring php8.4-xml php8.4-zip php8.4-bcmath \
       php8.4-intl php8.4-readline php8.4-redis php8.4-pcov

# Composer
RUN curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer

# Node.js
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    && npm install -g npm

# PostgreSQL
RUN curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor | tee /etc/apt/keyrings/pgdg.gpg >/dev/null \
    && echo "deb [signed-by=/etc/apt/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y postgresql-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION

# Mailpit
RUN curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | bash

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh

# Amp CLI
RUN npm install -g @sourcegraph/amp

# Cleanup
RUN apt-get -y autoremove && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Non-root user
RUN useradd -ms /bin/bash ralph \
    && echo "ralph ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ralph

# PostgreSQL log directory
RUN mkdir -p /var/log/postgresql && chown postgres:postgres /var/log/postgresql

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 5173 5432 1025 8025

ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]
```

### `entrypoint.sh` (example)

```bash
#!/usr/bin/env bash
set -e

# Git credentials (use file to avoid token in process listing)
if [ -n "$GITHUB_TOKEN" ]; then
    TOKEN_FILE=$(mktemp)
    echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chown ralph:ralph "$TOKEN_FILE"
    su - ralph -c "gh auth login --with-token < '$TOKEN_FILE' && gh auth setup-git" 2>/dev/null || true
    rm -f "$TOKEN_FILE"
fi

# Clone on fresh volume
if [ ! -f /var/www/html/.git/HEAD ]; then
    echo "[sandbox] Cloning $GITHUB_REPO..."
    su - ralph -c "git clone $GITHUB_REPO /var/www/html"
else
    echo "[sandbox] Codebase present, skipping clone."
fi

# Generate .env
if [ ! -f /var/www/html/.env ]; then
    echo "[sandbox] Generating .env..."
    cp /var/www/html/.env.example /var/www/html/.env
    sed -i 's|^DB_HOST=.*|DB_HOST=127.0.0.1|' /var/www/html/.env
    sed -i 's|^MAIL_HOST=.*|MAIL_HOST=127.0.0.1|' /var/www/html/.env
    sed -i 's|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=sync|' /var/www/html/.env
    sed -i 's|^CACHE_STORE=.*|CACHE_STORE=file|' /var/www/html/.env
    chown ralph:ralph /var/www/html/.env
    su - ralph -c "cd /var/www/html && php artisan key:generate"
fi

# Dependencies (sentinel file ensures partial installs get retried)
if [ ! -f /var/www/html/.sandbox-deps-installed ]; then
    su - ralph -c "cd /var/www/html && composer install --no-interaction"
    su - ralph -c "cd /var/www/html && npm install"
    su - ralph -c "touch /var/www/html/.sandbox-deps-installed"
fi

# PostgreSQL — initialize cluster and create role/database
PG_DATA="/var/lib/postgresql/17/main"
if [ ! -d "$PG_DATA" ] || [ ! -f "$PG_DATA/PG_VERSION" ]; then
    pg_createcluster 17 main
fi
PG_HBA="$PG_DATA/pg_hba.conf"
if ! grep -q "host all all 127.0.0.1/32" "$PG_HBA" 2>/dev/null; then
    echo "host all all 127.0.0.1/32 scram-sha-256" >> "$PG_HBA"
fi

# Start PostgreSQL temporarily for migrations and role setup
pg_ctlcluster 17 main start || true
until su - postgres -c "pg_isready" > /dev/null 2>&1; do sleep 0.5; done

su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='ralph'\" | grep -q 1" 2>/dev/null \
    || su - postgres -c "psql -c \"CREATE ROLE ralph WITH LOGIN PASSWORD 'password' CREATEDB;\""
su - postgres -c "psql -lqt | cut -d '|' -f 1 | grep -qw laravel" 2>/dev/null \
    || su - postgres -c "createdb -O ralph laravel"

# Migrations (sentinel ensures partial migrations get retried)
if [ ! -f /var/www/html/.sandbox-migrated ]; then
    su - ralph -c "cd /var/www/html && php artisan migrate --force" || true
    su - ralph -c "touch /var/www/html/.sandbox-migrated"
fi

# Stop PostgreSQL — supervisord will manage it from here
pg_ctlcluster 17 main stop || true

echo "[sandbox] Setup complete. Starting services via supervisord..."
exec supervisord -n -c /etc/supervisor/supervisord.conf
```

### `docker-compose.yml` (example)

```yaml
name: myapp-sandbox

services:
  sandbox:
    build:
      context: .
      dockerfile: Dockerfile
    image: myapp-sandbox:latest
    container_name: myapp-sandbox
    env_file: .env
    environment:
      SANDBOX: 1
      GITHUB_TOKEN: '${GITHUB_TOKEN}'
      AMP_API_KEY: '${AMP_API_KEY}'
      GITHUB_REPO: '${GITHUB_REPO:-https://github.com/owner/myapp.git}'
      GIT_CONFIG_COUNT: 1
      GIT_CONFIG_KEY_0: url.https://github.com/.insteadOf
      GIT_CONFIG_VALUE_0: 'git@github.com:'
    volumes:
      - sandbox-codebase:/var/www/html
      - sandbox-pgsql:/var/lib/postgresql
    ports:
      - '${SANDBOX_HTTP_PORT:-80}:80'
      - '${SANDBOX_VITE_PORT:-5173}:5173'
      - '${SANDBOX_DB_PORT:-5432}:5432'
      - '${SANDBOX_SMTP_PORT:-1025}:1025'
      - '${SANDBOX_MAIL_UI_PORT:-8025}:8025'
    healthcheck:
      test: ['CMD-SHELL', 'supervisorctl status | grep -v RUNNING && exit 1 || exit 0']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          memory: '${SANDBOX_MEMORY_LIMIT:-4g}'
          cpus: '${SANDBOX_CPU_LIMIT:-2}'
    tty: true
    stdin_open: true

volumes:
  sandbox-codebase:
    driver: local
  sandbox-pgsql:
    driver: local
```

### `.env.example` (example)

```env
# GitHub Personal Access Token (fine-grained, scoped to this repo)
GITHUB_TOKEN=

# Amp API key (https://ampcode.com)
AMP_API_KEY=

# Repository to clone (HTTPS URL)
GITHUB_REPO=https://github.com/owner/myapp.git

# Resource limits (optional — defaults shown)
SANDBOX_MEMORY_LIMIT=4g
SANDBOX_CPU_LIMIT=2

# Port mappings (optional — change to avoid collisions with host services)
SANDBOX_HTTP_PORT=80
SANDBOX_VITE_PORT=5173
SANDBOX_DB_PORT=5432
SANDBOX_SMTP_PORT=1025
SANDBOX_MAIL_UI_PORT=8025
```

## Example: Generated Output for a Node.js/Express Project

For a Node.js project using MongoDB, the setup agent would generate a container
with Node, MongoDB server, and Mailpit — no PHP, no PostgreSQL. The Dockerfile
and entrypoint follow the same structural pattern but with different packages:

```dockerfile
# Key differences from the Laravel example:
# - No PHP, no Composer
# - MongoDB server instead of PostgreSQL
# - WORKDIR /app instead of /var/www/html
# - entrypoint runs: mongod --fork, npm install, npm run migrate (or equivalent)
```

## Example: Generated Output for a Python/Django Project

```dockerfile
# Key differences:
# - Python 3.12, pip, virtualenv
# - PostgreSQL or MySQL depending on settings.py
# - WORKDIR /app
# - entrypoint runs: pip install -r requirements.txt, python manage.py migrate
```

The point is that `prompts/sandbox-setup.md` provides the structural requirements
while the agent adapts the specifics to whatever stack it discovers.

## Edge Cases

### No existing containerization to reference

If the project has no Dockerfile, docker-compose.yml, or .devcontainer, the agent
must infer the stack entirely from package manifests and config files. The prompt
handles this — containerization files are "reference only" and not required.

### Multiple database engines

Some projects use PostgreSQL for the app and Redis for caching. The agent should
install both in the container and start both in the entrypoint.

### Tests use SQLite in-memory

Many projects use SQLite for tests regardless of production database. The agent
should still install the production database (for manual testing and development)
but note in entrypoint comments that the test suite may not require it.

### First build is slow

The generated Dockerfile will produce large images (1-3GB). `ralph sandbox up`
should print a message: "First build may take several minutes." Subsequent starts
reuse the cached image and are fast.
