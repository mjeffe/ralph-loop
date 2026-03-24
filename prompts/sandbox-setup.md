You are an expert DevOps engineer. Your task is to generate an isolated,
all-in-one Docker sandbox for this project so that AI coding agents can work
in a safe, disposable environment.

## Context

- **Ralph home:** ${RALPH_HOME}
- **Sandbox directory:** ${RALPH_HOME}/sandbox

## Definition of Done

The sandbox is complete when ALL of these are true:

1. `docker compose up --build` succeeds without errors
2. The repo is cloned into the code volume
3. Dependencies install successfully
4. Every service required by the project's tests is running
5. The project's primary test command can be run as user `ralph`
6. All env vars referenced in compose/entrypoint are documented in `.env.example`
7. All four generated files are internally consistent (ports ↔ services,
   workdir ↔ compose volumes, DB type ↔ init logic)
8. If the project has test environment files, secrets are populated and
   container env var conflicts are mitigated
9. If the project has database seeders, they run after migrations
10. If migrations depend on DB extensions or functions, prerequisites are
    installed before migrations run

## Priority Order

When making trade-offs, follow this priority:

1. **Container boots reliably** — entrypoint completes, supervisord starts
2. **Repo clones and credentials work** — git auth, clone into volume
3. **Dependencies install** — correct package manager, idempotent with sentinels
4. **Required services run** — only services the project actually needs
5. **Migrations and bootstrap** — only if the project has them
6. **Developer ergonomics** — editor config, aliases, preferences

## Project Analysis

Scan the project to build a **project profile**. Read these sources and extract
the conclusions listed below. Existing Docker/devcontainer files are reference
material — do not copy them, but do reuse authoritative details like runtime
versions, package names, and startup commands.

**Sources to read:**
- **Stack playbook (read first if provided):** ${STACK_PLAYBOOK}
  This file contains stack-specific commands, bootstrap sequences, and
  mitigation patterns. Follow its guidance for all stack-specific decisions.
- Package manifests (composer.json, package.json, Gemfile, go.mod,
  requirements.txt, Cargo.toml, pyproject.toml, etc.)
- Existing Docker/container files (Dockerfile, docker-compose.yml,
  .devcontainer/, docker/) — for reference only
- The project's .env.example (or equivalent) — this is the **application** env
  file, distinct from the sandbox .env.example you will generate
- AGENTS.md for project-specific run/test instructions
- CI config (.github/workflows/, .gitlab-ci.yml) for service dependencies
- Test config (phpunit.xml, jest.config.*, pytest.ini) for test database needs
- Test environment files (.env.testing, .env.test, or equivalent) — check for
  empty secrets and note potential container env var conflicts
- Git remote URL (for GIT_REPO default)
- ${RALPH_HOME}/dependencies for ralph's own system package requirements
- ${RALPH_HOME}/sandbox-preferences.md for user-defined environment preferences

**Conclusions to extract:**
- Primary runtime(s) and version(s)
- Package manager(s) — prefer lockfiles over manifests for tool choice
- Required services for tests and dev (DB, cache, search, mail, etc.)
- Long-running processes the project needs (web server, queue worker,
  Vite/HMR dev server, scheduler, etc.)
- Primary workdir path
- Bootstrap/install command(s)
- Likely test command
- Git hosting provider (GitHub vs other)

**Decision rules:**
- Always provision the project's primary database engine — agents need to
  run the full app, not just tests. Use .env.example, config files, and
  docker-compose.yml to determine the primary engine.
- If tests use a different DB (e.g., SQLite for speed), configure that as
  the test database, but still provision the primary server DB
- Include only *additional* services (cache, search, queue) that AGENTS.md,
  CI, test config, or env/config actually require
- Include Mailpit only when mail is used by the project or implied by framework
- For ambiguous cases (monorepos, multiple runtimes), optimize for the
  primary app; note limitations in comments

## Hard Constraints

These are non-negotiable:

- **Single container** — all-in-one, no Docker-in-Docker, no sidecars
- **Named volumes** — for codebase and database data, never bind mounts
- **Non-root user** named "ralph" (UID 1000, GID 1000) with passwordless sudo
- **tini** as PID 1 init process
- **supervisord** to manage long-running services
- **Ralph dependencies** — every package in ${RALPH_HOME}/dependencies must
  be installed in the Dockerfile
- **Amp CLI** — `npm install -g @sourcegraph/amp`
- **Idempotent entrypoint** — safe to re-run on existing volumes
- **Base image:** ubuntu:24.04

## Generated Files

Create these four files in ${RALPH_HOME}/sandbox/:

### 1. Dockerfile

Responsibilities:
- Install the project's language runtime and version
- Install all required extensions and system packages
- Install service packages natively (database server, etc.) — only those
  identified as required during project analysis
- Install package managers (composer, npm/yarn/pnpm, pip, etc.)
- Install GitHub CLI (gh) — only for GitHub-hosted projects
- Install Amp CLI, tini, supervisord, and ralph dependencies
- Handle UID 1000 conflicts: the base image may have a user with UID 1000
  (e.g., "ubuntu") — delete it with `userdel --remove` before creating "ralph"
- Copy entrypoint.sh and make it executable
- ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
- WORKDIR: /var/www/html for PHP projects, /app for others
- EXPOSE only ports for services that are actually provisioned

### 2. entrypoint.sh

Must begin with:
```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[sandbox] ERROR: entrypoint failed at line $LINENO (exit code $?)" >&2' ERR
```

Responsibilities (in order):
1. Configure git credentials — **use the exact snippets from Appendix A**
   (they contain critical workarounds for known failure modes)
2. Clone GIT_REPO into workdir if `.git/HEAD` is missing (fresh volume).
   Docker named volumes are created with root ownership — chown the workdir
   to ralph **before** cloning so `git clone` (running as ralph) can write
   to it.
3. Create sentinel directory at `${RALPH_HOME}/.sandbox/` (after clone —
   workdir must be empty for clone). Sentinel files live here so they are
   covered by `.ralph/.gitignore` and do not pollute the project's git status.
4. Copy the **project's** .env.example → .env if missing, with
   sandbox-appropriate overrides. Common overrides: DB_HOST=127.0.0.1,
   MAIL_HOST=127.0.0.1, QUEUE_CONNECTION=sync, CACHE_STORE=file. Adjust
   based on what services are actually provisioned in the container.
   (This is the application's runtime .env inside the repo workdir, not
   the sandbox's compose .env in ${RALPH_HOME}/sandbox/.)
5. Apply project-level secrets from container environment into the
   project's .env:
   for each key in .env, if a matching env var is set in the container
   environment and non-empty, overwrite that key's value. This runs on
   **every boot** (not just first creation) so users can add or update
   secrets in the sandbox .env and restart the container.
   The sandbox .env contains real secrets and must never be committed.
6. Bootstrap test environment files if the project has them (e.g.,
   .env.testing, .env.test):
   - **Generate missing secrets:** Copy the test env template if the
     framework doesn't auto-create it, then populate any empty secret
     keys (APP_KEY, JWT_SECRET, etc.) with generated values — same
     approach as the primary .env.
   - **Mitigate container env var conflicts:** In an all-in-one container,
     entrypoint-exported env vars (e.g., DB_DATABASE) are visible to all
     processes. Frameworks with immutable dotenv loaders will ignore test
     env file overrides, causing tests to silently run against the main
     database. Detect this risk and generate a framework-appropriate
     mitigation — typically a test bootstrap snippet that clears
     conflicting env vars before the framework loads its dotenv file.
     Refer to the stack playbook for the concrete pattern.
7. Install dependencies idempotently (sentinel file in `${RALPH_HOME}/.sandbox/`
   — check sentinel, not output directory, so partial installs get retried)
8. Generate app secret/key if framework requires it (after deps install)
9. Initialize and bootstrap database if applicable:
   a. Init data directory if needed, start DB temporarily, create user/databases.
   b. **Pre-migration prerequisites:** Scan migration files, SQL directories
      (e.g., `database/sql/`, `db/`), documentation, and AGENTS.md for
      prerequisites that must exist before migrations run — PostgreSQL
      extensions (`CREATE EXTENSION pgcrypto`, `postgis`, `uuid-ossp`),
      custom SQL functions or triggers, or schema setup scripts. Install
      or run any prerequisites found. Without this, migrations that depend
      on extensions or functions will fail on first boot.
   c. Run migrations (with sentinel).
   d. **Run seeders** if the project has them (with sentinel). Scan for
      seeder classes, seed scripts, or fixture-loading commands in project
      source, documentation, or AGENTS.md. Reference data seeders (lookup
      tables, roles, permissions) are especially important — the app may
      be non-functional without them. Refer to the stack playbook for the
      specific command. If a separate test database was created (step 6),
      run seeders against it too.
   e. Stop DB — supervisord manages it going forward.
10. Generate supervisord config files in /etc/supervisor/conf.d/ for each
    required service (autorestart=true, startsecs=5). Determine which
    long-running processes the project needs — this typically includes the
    database server and may include a web server, queue worker, Vite/HMR
    dev server, mail catcher, etc. Only include processes the project
    actually uses. Do NOT include one-shot tasks like migrations.
11. End with: `exec supervisord -n -c /etc/supervisor/supervisord.conf`

### 3. docker-compose.yml

- **Define exactly one service** — all processes run inside it via supervisord
- name: ${SANDBOX_NAME:-{project-name}-sandbox} (SANDBOX_NAME is auto-derived
  by ralph from the checkout path; the default is a fallback for manual use)
- Do NOT set container_name — let Compose auto-derive it from the project name
- Build context: `.` (the sandbox directory)
- Environment variables: **use list syntax (`- KEY=value`), never map syntax**
  (see Appendix B for YAML quoting rules)
- Required env vars: SANDBOX=1, GIT_REPO, AMP_API_KEY, plus credential vars,
  plus GIT_CONFIG vars to rewrite SSH URLs to HTTPS (derive host from GIT_REPO)
- Named volumes: sandbox-codebase (workdir), sandbox-db (database data, if applicable)
- Ports: use env vars with defaults (e.g., `${SANDBOX_HTTP_PORT:-80}:80`)
  so users can remap to avoid collisions — only map ports for provisioned services
- Healthcheck: `supervisorctl status` to verify all services are RUNNING
  (start_period: 60s)
- tty: true, stdin_open: true
- deploy.resources.limits: memory ${SANDBOX_MEMORY_LIMIT:-4g}, cpus ${SANDBOX_CPU_LIMIT:-2}
- env_file with required: false so compose does not fail when .env is
  missing (the user creates it from .env.example before first `up`):
  `env_file: [{path: .env, required: false}]`

### 4. .env.example (sandbox compose env file)

- GIT_REPO= (pre-filled from git remote)
- Credential vars: uncomment GITHUB_TOKEN for GitHub repos, or GIT_CRED_USER
  and GIT_CRED_PASS for non-GitHub repos
- AMP_API_KEY= (with comment: https://ampcode.com)
- SANDBOX_MEMORY_LIMIT=4g
- SANDBOX_CPU_LIMIT=2
- Port mappings with defaults matching the provisioned services, e.g.:
  SANDBOX_HTTP_PORT=80, SANDBOX_DB_PORT=5432 (or 3306 for MySQL),
  SANDBOX_SMTP_PORT=1025, SANDBOX_MAIL_UI_PORT=8025,
  SANDBOX_VITE_PORT=5173 (if applicable)
- SANDBOX_NAME — commented out, with a note that it is auto-derived from the
  checkout path and can be overridden when the auto-generated name is not suitable:
  `# SANDBOX_NAME=my-project-sandbox`
- Document every env var used in docker-compose.yml or entrypoint.sh
- **Project-level secrets:** Scan the project's .env.example (or equivalent)
  for third-party API keys and secrets not covered by the sandbox infrastructure
  vars above (e.g., STRIPE_SECRET, AWS_ACCESS_KEY_ID, SENDGRID_API_KEY).
  Include each as a commented-out entry with a note that the user must fill
  it in if the project requires it. Prefix the section with a comment:
  `# Project secrets (fill in if needed by your app)`

## Self-Validation Checklist

Before finishing, verify:

- [ ] Chosen workdir matches project type
- [ ] Every compose env var is documented in .env.example
- [ ] Supervisord services match exposed ports (no orphan ports or services)
- [ ] DB init/migration logic matches the detected database type
  (no server init for SQLite, no pg_* commands for MySQL, etc.)
- [ ] If migrations reference extensions, functions, or triggers, pre-migration
  prerequisites are installed before migrations run
- [ ] Install commands match the detected package manager
- [ ] entrypoint.sh is copied to a location in PATH (e.g., /usr/local/bin/)
- [ ] User ralph has correct permissions for workdir and home directory
- [ ] All packages from ${RALPH_HOME}/dependencies are installed
- [ ] User preferences from ${RALPH_HOME}/sandbox-preferences.md are applied
- [ ] If test environment files exist, secrets are populated and container
  env var conflicts are mitigated

## Rules

- Add comments in generated files explaining non-obvious choices
- Commit all generated files with message: "chore: generate sandbox environment"

When complete, output: <promise>COMPLETE</promise>

---

## Appendix A: Git Credential Configuration

The entrypoint must support two credential strategies:

**GitHub path** — when `GITHUB_TOKEN` is set:
```bash
if [ -n "${GITHUB_TOKEN:-}" ]; then
    TMPFILE=$(mktemp)
    printf '%s' "$GITHUB_TOKEN" > "$TMPFILE"
    env -u GITHUB_TOKEN gh auth login --with-token < "$TMPFILE"
    gh auth setup-git
    rm -f "$TMPFILE"
fi
```
**Why `env -u`:** gh CLI refuses `--with-token` when GITHUB_TOKEN is already
set as an env var, exiting non-zero and silently killing the entrypoint under
`set -euo pipefail`. Never pass the token on the command line.

**Generic path** — when `GIT_CRED_USER` and `GIT_CRED_PASS` are set (GitLab,
Bitbucket, AWS CodeCommit, self-hosted git, etc.):
```bash
elif [ -n "${GIT_CRED_USER:-}" ] && [ -n "${GIT_CRED_PASS:-}" ]; then
    REPO_HOST=$(echo "${GIT_REPO}" | sed -E 's|https?://([^/]+).*|\1|')
    ENCODED_USER=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "${GIT_CRED_USER}")
    ENCODED_PASS=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "${GIT_CRED_PASS}")
    printf 'https://%s:%s@%s\n' "${ENCODED_USER}" "${ENCODED_PASS}" "${REPO_HOST}" \
        > /home/ralph/.git-credentials
    chmod 600 /home/ralph/.git-credentials
    chown ralph:ralph /home/ralph/.git-credentials
    su - ralph -c "git config --global credential.helper 'store --file=/home/ralph/.git-credentials'"
fi
```
Credentials are URL-encoded because some providers (notably AWS CodeCommit)
generate passwords containing `/`, `+`, and `=` that break the credential
URL format if written raw.

## Appendix B: YAML Environment Variable Syntax

In docker-compose.yml, always use list syntax for environment variables.
Quote any entry whose value contains a colon:

- BAD:  `GIT_CONFIG_VALUE_0: git@example.com:`     ← map syntax, colon breaks YAML
- BAD:  `- GIT_CONFIG_VALUE_0=git@example.com:`    ← list syntax but unquoted colon
- GOOD: `- "GIT_CONFIG_VALUE_0=git@example.com:"`  ← list syntax, quoted

## Appendix C: Idempotency Patterns

- Simple existence checks (`.git/HEAD`, `.env`) are fine for single-command steps
- Multi-step operations (dependency install, migrations) must use **sentinel files**
  stored in `${RALPH_HOME}/.sandbox/` (e.g., `touch ${RALPH_HOME}/.sandbox/deps-installed`
  after success; check the sentinel, not the output directory, so partial installs
  get retried)
- **Create the sentinel directory after the clone step** — the workdir must be
  empty for `git clone` to succeed into it
