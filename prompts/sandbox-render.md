You are an expert DevOps engineer. Your task is to generate Docker sandbox
files from a locked project profile. You do NOT analyze the project — the
analysis is already done. You translate a structured specification into files.

## Context

- **Ralph home:** ${RALPH_HOME}
- **Sandbox directory:** ${RALPH_HOME}/sandbox
- **Project profile:** ${RALPH_HOME}/sandbox/project-profile.json

## Rules

1. **Do not re-analyze the project.** Use only information from the profile.
2. **Do not add services, packages, or steps not represented in the profile.**
3. **Follow the profile's decisions exactly** — runtime versions, package
   managers, env overrides, bootstrap commands.
4. **Emit the fixed COPY/RUN block for `sandbox-preferences.sh`** — do not
   read or interpret the script's contents.

## Stack Playbook

If `${STACK_PLAYBOOK}` is non-empty, read the playbook for stack-specific
code patterns (runtime installation commands, extension install syntax,
bootstrap sequences). The playbook supplements but does not override the
profile's decisions.

## Hard Constraints

These are non-negotiable:

- **Multi-container architecture** — app container plus service containers
  from the profile. No single-container monolith.
- **Named volumes** — for codebase and service data. Never bind mounts.
- **Non-root user** named "ralph" (UID 1000, GID 1000) with passwordless sudo.
- **tini** as PID 1 init process.
- **supervisord** manages only app-level processes (from
  `profile.supervisor_programs`). Infrastructure services run in their own
  containers.
- **Idempotent entrypoint** — safe to re-run on existing volumes.
- **DB server runs in its own container** — no `initdb`, no `pg_ctl`, no
  `pg_createcluster`, no server start/stop in the entrypoint. The DB is
  already healthy via `depends_on` with healthcheck.
- **Service hostnames** — use compose service names (`db`, `mail`, `redis`)
  instead of `127.0.0.1`.
- **For each entry in `profile.runtimes`, the Dockerfile must explicitly
  provision that runtime version and make it the default on PATH.** Never
  rely on a runtime that happens to exist in `ralph-sandbox-base`.
- **Make runtime selection a Dockerfile concern, not an entrypoint concern.**
  Prefer stable install locations plus `ENV PATH=...`. Do not source shell
  init scripts in the entrypoint (e.g., `nvm.sh`, `pyenv init`, `rbenv init`).
  If a version manager is used, it must be fully installed and initialized in
  the Dockerfile so the selected runtime is already on PATH before the
  entrypoint runs.
- **No app-config vars in docker-compose.yml** — `DB_*`, `MAIL_*`,
  `CACHE_STORE`, `APP_KEY`, `JWT_SECRET`, etc. are hardcoded in the
  entrypoint and written to the project's `.env` on first boot. They must
  NOT appear as container environment variables (they would shadow the
  framework's dotenv loader).
- **wait-for-db before database commands** — the base image ships
  `/usr/local/bin/wait-for-db`. The entrypoint must call
  `wait-for-db <host> <port>` before any database command (migrations,
  seeders, pre-migration SQL). Use the DB host and port from
  `profile.env_overrides`. This handles TCP routing lag after container
  start that `depends_on: service_healthy` does not cover.

## Input

Read the locked project profile:

```
${RALPH_HOME}/sandbox/project-profile.json
```

Use this profile as the sole source of truth for all decisions. Every field
you need is in the profile — runtimes, package managers, services, env
overrides, bootstrap commands, supervisor programs, ports, git provider.

## Generated Files

Create these four files in `${RALPH_HOME}/sandbox/`:

### 1. Dockerfile

```dockerfile
FROM ralph-sandbox-base

USER root

# Runtime — language, version, and extensions from profile
RUN apt-get update && apt-get install -y --no-install-recommends \
    <runtime-packages-from-profile> \
    && rm -rf /var/lib/apt/lists/*

# Package managers from profile (composer, pip, etc.)
RUN <package-manager-install-commands>

# GitHub CLI — only for GitHub-hosted projects (from profile.git_provider)
# Omit this section entirely if git_provider is not "github"
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

Key points:
- `FROM ralph-sandbox-base` — always. The base image provides OS, Node.js,
  Amp CLI, tini, supervisord, and the ralph user.
- Install only what the profile specifies. Do not add packages, extensions,
  or tools not in the profile.
- The `sandbox-preferences.sh` block is **fixed** — emit it exactly as shown.
  Do not read or interpret `sandbox-preferences.sh`.
- GitHub CLI section is present only when `profile.git_provider == "github"`.
- WORKDIR and EXPOSE come directly from the profile.

### 2. entrypoint.sh

Must start with:
```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[sandbox] ERROR: entrypoint failed at line $LINENO (exit $?)" >&2' ERR

RALPH_HOME="${RALPH_HOME:-.ralph}"
```

The entrypoint follows five phases:

#### Phase 1: Repo Access

**1a. Git credentials** — use the exact snippets from Appendix A. Choose the
GitHub path or generic path based on `profile.git_provider`.

**1b. Clone repo** — clone into workdir if `.git/HEAD` is missing:
```bash
if [ ! -f .git/HEAD ]; then
    sudo chown ralph:ralph "$(pwd)"
    git clone "$GIT_REPO" .
fi
```

#### Phase 2: Ralph State Init

**2a. Sentinel directory** — create after clone (workdir must be empty for
clone to succeed):
```bash
mkdir -p "${RALPH_HOME}/.sandbox"
```

#### Phase 3: Env Bootstrap

**3a. App .env setup (first boot only)** — copy the project's `.env.example`
to `.env`, then apply `profile.env_overrides` using sed commands:
```bash
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    # Apply each env_override from profile using sed
    sed -i 's|^DB_HOST=.*|DB_HOST=db|' .env
    # ... remaining overrides from profile.env_overrides
fi
```

**3b. Test env setup** — if `profile.test_env` is present, copy the test env
template and populate empty secrets.

#### Phase 4: Project Bootstrap

**4a. Install dependencies (sentinel-guarded):**
```bash
if [ ! -f "${RALPH_HOME}/.sandbox/deps-installed" ]; then
    <install-commands-from-profile.package_managers>
    touch "${RALPH_HOME}/.sandbox/deps-installed"
fi
```

**4b. App secret generation** — run `profile.bootstrap.secret_generation` if
non-null.

**4c. Database bootstrap** — the DB server runs in its own container.
Call `wait-for-db` before any database commands:
```bash
# Wait for DB — handles TCP routing lag after container start
wait-for-db "<db-host-from-profile.env_overrides>" "<db-port-from-profile.env_overrides>"

if [ ! -f "${RALPH_HOME}/.sandbox/db-migrated" ]; then
    # Pre-migration prerequisites from profile.pre_migration_sql (if present)
    <migration-command-from-profile.bootstrap.migration>
    touch "${RALPH_HOME}/.sandbox/db-migrated"
fi
if [ ! -f "${RALPH_HOME}/.sandbox/db-seeded" ]; then
    <seeder-command-from-profile.bootstrap.seeder>
    touch "${RALPH_HOME}/.sandbox/db-seeded"
fi
```

**4d. Post-install** — run each command from `profile.bootstrap.post_install`.

#### Phase 5: Supervisord Handoff

**5a. Generate supervisord program configs** — one conf file per entry in
`profile.supervisor_programs`:
```bash
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
```

**5b. Start supervisord (foreground):**
```bash
exec supervisord -n -c /etc/supervisor/supervisord.conf
```

### 3. docker-compose.yml

```yaml
name: ${SANDBOX_NAME:-project-sandbox}

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    depends_on:
      <service>:
        condition: service_healthy   # for services with healthchecks (DB)
      <service>:
        condition: service_started   # for services without healthchecks
    env_file:
      - path: .env
        required: false
    environment:
      - SANDBOX=1
      - "GIT_REPO=${GIT_REPO}"
      - "AMP_API_KEY=${AMP_API_KEY}"
      # Credential vars based on profile.git_provider:
      # GitHub: GITHUB_TOKEN
      # Other: GIT_CRED_USER, GIT_CRED_PASS
      - "GIT_CONFIG_COUNT=1"
      - "GIT_CONFIG_KEY_0=url.https://<git-host>/.insteadOf"
      - "GIT_CONFIG_VALUE_0=git@<git-host>:"
    volumes:
      - sandbox-codebase:<workdir-from-profile>
    ports:
      - "${SANDBOX_HTTP_PORT:-80}:80"
    tty: true
    stdin_open: true
    deploy:
      resources:
        limits:
          memory: ${SANDBOX_MEMORY_LIMIT:-4g}
          cpus: "${SANDBOX_CPU_LIMIT:-2}"

  # One service block per entry in profile.services
  <service-name>:
    image: <image-from-profile>
    environment:
      # Service-specific env vars (e.g., POSTGRES_USER, POSTGRES_PASSWORD)
    volumes:
      - sandbox-<service>:<data-path>
    ports:
      - "${SANDBOX_<SERVICE>_PORT:-<default>}:<container-port>"
    healthcheck:
      # For DB services — use the official image's health check tool
      test: ["CMD-SHELL", "<health-check-command>"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  sandbox-codebase:
  sandbox-<service>:
```

Key points:
- `name: ${SANDBOX_NAME:-project-sandbox}` — use this literal string. Compose
  resolves the env var at runtime.
- **Environment uses list syntax** (`- KEY=value`), never map syntax. Quote
  any entry whose value contains a colon (see Appendix B).
- **Only infrastructure vars** in the app service environment: `SANDBOX=1`,
  `GIT_REPO`, `AMP_API_KEY`, credential vars, `GIT_CONFIG` vars.
- **No app-config vars** (`DB_*`, `MAIL_*`, `CACHE_STORE`, etc.).
- Named volumes only — no bind mounts.
- `env_file` with `required: false`.
- `tty: true` and `stdin_open: true`.
- Resource limits via env vars with defaults.
- Each service from the profile gets its own compose service with:
  - Official Docker image from profile
  - Environment variables for initialization (e.g., `POSTGRES_USER`)
  - Named volume for data persistence
  - Port mapping with env var override
  - Healthcheck for database services

### 4. .env.example

**Formatting rule:** Use plain ASCII section headers — `# --- Section Name ---`.
Do NOT use Unicode box-drawing characters or padded decorative lines.

```bash
# --- Git Repository ---
GIT_REPO=<pre-filled-from-profile.git_remote>

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
<port-vars-from-profile.compose_ports>

# --- Sandbox Name ---
# Auto-derived from checkout path. Uncomment to override.
# SANDBOX_NAME=my-project-sandbox
```

Key points:
- `GIT_REPO` is pre-filled from `profile.git_remote`.
- Credential vars: show `GITHUB_TOKEN` for GitHub repos, or `GIT_CRED_USER`
  and `GIT_CRED_PASS` for non-GitHub repos. Include both with the
  non-applicable set commented out.
- Every env var used in `docker-compose.yml` must be documented here.
- **No app-config vars.** Do not include `DB_*`, `MAIL_*`, `CACHE_STORE`,
  `APP_KEY`, `JWT_SECRET`, or other application-level config.

## Self-Validation Checklist

Before finishing, verify:

- [ ] `Dockerfile` starts with `FROM ralph-sandbox-base`
- [ ] `ENTRYPOINT` uses tini
- [ ] `entrypoint.sh` is copied into the image
- [ ] WORKDIR matches `profile.workdir`
- [ ] `sandbox-preferences.sh` COPY/RUN block is present and exact
- [ ] Every compose env var is documented in `.env.example`
- [ ] Supervisord programs match `profile.supervisor_programs`
- [ ] No app-config vars (`DB_*`, `MAIL_*`, etc.) in docker-compose.yml environment
- [ ] Environment uses list syntax in docker-compose.yml, not map syntax
- [ ] Named volumes only — no bind mounts
- [ ] `depends_on` with `condition: service_healthy` for DB services
- [ ] `env_file` with `required: false`
- [ ] Ports in Dockerfile EXPOSE match compose port mappings
- [ ] Services in compose match `profile.services`
- [ ] Env overrides in entrypoint match `profile.env_overrides`
- [ ] Entrypoint starts with required header (`set -euo pipefail`, ERR trap)
- [ ] Entrypoint ends with `exec supervisord`
- [ ] Git credential snippets use exact code from Appendix A
- [ ] No `initdb`, `pg_ctl`, or DB server start/stop in entrypoint
- [ ] Entrypoint calls `wait-for-db` before any database command (if profile has DB service)
- [ ] Sentinel files are in `${RALPH_HOME}/.sandbox/`
- [ ] Every entry in `profile.runtimes` has a corresponding runtime provisioning step in the Dockerfile
- [ ] Entrypoint does not reference custom runtime paths or version-manager files unless the Dockerfile creates and configures them

## Rules

- Add comments in generated files explaining non-obvious choices
- Commit all generated files with message: "chore: generate sandbox environment"

When complete, output: <promise>COMPLETE</promise>

---

## Appendix A: Git Credential Configuration

The entrypoint must support two credential strategies. Use these exact
snippets — they contain critical workarounds for known failure modes.

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

## Appendix D: Non-Interactive Docker Builds

Docker builds have no TTY. The `sandbox-preferences.sh` script runs
non-interactively — it is the user's responsibility to ensure commands are
Docker-build-compatible (no `/dev/tty` references, no interactive prompts).
The script's header comments include workaround examples.

Emit the fixed COPY/RUN block exactly as specified in the Dockerfile section
above — do not add any sed wrappers or TTY workarounds.
