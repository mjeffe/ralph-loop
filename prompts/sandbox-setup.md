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
- A non-root user named "ralph" (UID 1000, GID 1000) with passwordless sudo.
  The base image may already have a user with UID 1000 (e.g., "ubuntu"). If so,
  delete that user first with `userdel --remove` before creating "ralph".
- Copy entrypoint.sh into the image
- ENTRYPOINT ["/usr/bin/tini", "--", "entrypoint.sh"]
- Expose relevant ports (app, database, mail UI, Vite/HMR if applicable)
- WORKDIR set to /var/www/html for PHP projects, /app for others

### 2. entrypoint.sh

Write an idempotent entrypoint. It MUST begin with these exact lines:

```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[sandbox] ERROR: entrypoint failed at line $LINENO (exit code $?)" >&2' ERR
```

The ERR trap ensures failures are diagnosable in container logs.

The entrypoint must:
- Configure git credentials securely using this exact pattern:
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
- Clones GITHUB_REPO into the workdir if .git/HEAD is missing (fresh volume)
- Copies .env.example to .env if missing, with sandbox overrides (DB_HOST=127.0.0.1,
  MAIL_HOST=127.0.0.1, QUEUE_CONNECTION=sync, CACHE_STORE=file)
- Installs dependencies and tracks completion with a sentinel file (e.g., touch
  .sandbox-deps-installed after successful install). Check the sentinel, not the
  output directory, so partial installs get retried.
- Generates app secret/key if the framework requires it (must come after
  dependency installation, since key-generation CLIs need the framework loaded)
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
- **Environment: use list syntax (`- KEY=value`), NEVER map syntax (`KEY: value`).**
  Quote every entry whose value contains a colon — a trailing colon makes YAML
  interpret the line as a mapping key instead of a string, e.g.:
    - BAD:  `GIT_CONFIG_VALUE_0: git@github.com:`     ← map syntax, colon breaks YAML
    - BAD:  `- GIT_CONFIG_VALUE_0=git@github.com:`    ← list syntax but unquoted colon
    - GOOD: `- "GIT_CONFIG_VALUE_0=git@github.com:"`  ← list syntax, quoted
  Required vars: SANDBOX=1, GITHUB_TOKEN,
  AMP_API_KEY, GITHUB_REPO, plus GIT_CONFIG vars to rewrite SSH URLs to HTTPS
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
- Use list syntax (`- KEY=value`) for all environment variables in docker-compose.yml, never map syntax (`KEY: value`).
- Add comments in generated files explaining non-obvious choices.
- Commit all generated files with message: "chore: generate sandbox environment"

When complete, output: <promise>COMPLETE</promise>
