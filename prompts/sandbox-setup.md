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
7. Identify the git remote URL for GIT_REPO default
8. Read ${RALPH_HOME}/dependencies for ralph's own system package requirements
   and ensure ALL listed packages are installed in the Dockerfile
9. Read ${RALPH_HOME}/sandbox-preferences.md for user-defined sandbox environment
   preferences and incorporate them into the generated files

## What to generate

Create these four files in ${RALPH_HOME}/sandbox/:

### 1. Dockerfile

Build an all-in-one container based on ubuntu:24.04 that includes:
- The project's language runtime and version (e.g., PHP 8.4, Node 22, Python 3.12)
- All required extensions and system packages
- Database server (PostgreSQL, MySQL, SQLite — whatever the project uses)
- Mail catcher (Mailpit) for local SMTP
- Package managers (composer, npm/yarn/pnpm, pip, etc.)
- GitHub CLI (gh) — only if the project is hosted on GitHub
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
- Configure git credentials securely. Support two strategies depending on which
  environment variables are set:

  **GitHub path** — if `GITHUB_TOKEN` is set:
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

  **Generic path** — if `GIT_CRED_USER` and `GIT_CRED_PASS` are set (for
  GitLab, Bitbucket, AWS CodeCommit, self-hosted git, etc.):
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
- Clones GIT_REPO into the workdir if .git/HEAD is missing (fresh volume)
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
**Create sentinel directories after the clone step** — the workdir must be
empty for `git clone` to succeed into it.

### 3. docker-compose.yml

- name: {project-name}-sandbox (derive from git remote or directory name)
- container_name: {project-name}-sandbox
- Build context: . (the sandbox directory)
- **Environment: use list syntax (`- KEY=value`), NEVER map syntax (`KEY: value`).**
  Quote every entry whose value contains a colon — a trailing colon makes YAML
  interpret the line as a mapping key instead of a string, e.g.:
    - BAD:  `GIT_CONFIG_VALUE_0: git@example.com:`     ← map syntax, colon breaks YAML
    - BAD:  `- GIT_CONFIG_VALUE_0=git@example.com:`    ← list syntax but unquoted colon
    - GOOD: `- "GIT_CONFIG_VALUE_0=git@example.com:"`  ← list syntax, quoted
  Required vars: SANDBOX=1, GIT_REPO, AMP_API_KEY, plus credential vars
  (GITHUB_TOKEN for GitHub, or GIT_CRED_USER + GIT_CRED_PASS for other
  providers), plus GIT_CONFIG vars to rewrite SSH URLs to HTTPS (derive the
  host from GIT_REPO, do not hardcode github.com)
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
- GIT_REPO= (pre-filled from git remote)
- GITHUB_TOKEN= (with comment: for GitHub repos — fine-grained PAT)
- GIT_CRED_USER= (with comment: for non-GitHub repos — HTTPS username or token)
- GIT_CRED_PASS= (with comment: for non-GitHub repos — HTTPS password or token)
- AMP_API_KEY= (with comment: https://ampcode.com)
- SANDBOX_MEMORY_LIMIT=4g (with comment: optional resource limits)
- SANDBOX_CPU_LIMIT=2
- SANDBOX_HTTP_PORT=80 (with comment: optional port mappings)
- SANDBOX_VITE_PORT=5173
- SANDBOX_DB_PORT=5432
- SANDBOX_SMTP_PORT=1025
- SANDBOX_MAIL_UI_PORT=8025

For GitHub remotes, uncomment GITHUB_TOKEN by default. For non-GitHub remotes,
uncomment GIT_CRED_USER and GIT_CRED_PASS instead.

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
