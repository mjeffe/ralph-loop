You are an expert DevOps engineer. Your task is to analyze this project and
produce a structured JSON profile that describes everything needed to build a
multi-container Docker sandbox. You do NOT generate Docker files, entrypoint
scripts, or compose files — only the JSON profile.

## Context

- **Ralph home:** ${RALPH_HOME}
- **Sandbox directory:** ${RALPH_HOME}/sandbox
- **Profile output:** ${RALPH_HOME}/sandbox/project-profile.json

## Sources to Read

Read these sources and extract the conclusions listed below. Existing
Docker/container files are reference material — do not copy them, but do reuse
authoritative details like runtime versions, package names, and startup
commands.

- **Stack playbook (read first if provided):** ${STACK_PLAYBOOK}
  This file contains stack-specific commands, bootstrap sequences, and
  mitigation patterns. Follow its guidance for all stack-specific decisions.
  If this path is empty, skip this source.
- Package manifests (composer.json, package.json, Gemfile, go.mod,
  requirements.txt, Cargo.toml, pyproject.toml, pom.xml, etc.)
- Existing Docker/container files (Dockerfile, docker-compose.yml,
  .devcontainer/, docker/) — for reference only
- The project's .env.example (or equivalent) — this is the **application** env
  file, distinct from the sandbox .env.example generated in Pass 2
- AGENTS.md for project-specific run/test instructions
- CI config (.github/workflows/, .gitlab-ci.yml) for service dependencies
- Test config (phpunit.xml, jest.config.*, pytest.ini) for test database needs
- Test environment files (.env.testing, .env.test, or equivalent) — check for
  empty secrets that must be generated for tests to pass
- Git remote URL (for git_remote)
- ${RALPH_HOME}/dependencies for ralph's own system package requirements

## Conclusions to Extract

- All runtimes required by the project's install, build, run, or test commands —
  not just the primary framework runtime. Include secondary runtimes used only
  for asset builds or tooling (e.g., Laravel + Vue, Rails + webpack).
- Package manager(s) — prefer lockfiles over manifests for tool choice
- Required services as compose services (DB, cache, search, mail, etc.) —
  each becomes a separate container using official Docker images
- Long-running app processes the project needs (web server, queue worker,
  Vite/HMR dev server, scheduler, etc.) — these are the only processes
  managed by supervisord in the app container
- Primary workdir path
- Bootstrap/install command(s)
- Likely test command
- Git hosting provider (GitHub vs other)

## Decision Rules

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

## Multi-Container Model

Services run in their own containers using official Docker images. The app
container contains only the project runtime, dependencies, tooling, and
app-level processes. Supervisord manages only app-level processes (web server,
queue worker, Vite dev server), NOT infrastructure services (database, cache,
mail). Service hostnames use compose service names (e.g., `db`, `redis`,
`mail`) instead of `127.0.0.1`.

## Profile Schema

Output a single JSON object to `${RALPH_HOME}/sandbox/project-profile.json`.
The profile must conform to the schema below. Required fields must always be
present, even when empty (use `[]` for arrays, `{}` for objects).

### Required Top-Level Fields

| Field | Type | Description |
|---|---|---|
| `schema_version` | integer | Always `1`. |
| `stack` | string | Detected stack identifier (e.g., `"php-laravel"`, `"node"`, `"python-django"`). Empty string if unknown. |
| `runtimes` | array of objects | Language runtimes. Each object has: `name` (string, required), `version` (string, required), `evidence` (array of strings, required — cite source files). At least one entry. |
| `package_managers` | array of objects | Each object has: `name` (string, required), `install_command` (string, required). |
| `services` | array of objects | External services (DB, cache, mail). Each object has: `name` (string, required), `image` (string, required), `port` or `ports` (integer or array of integers, required), `reason` (string, required — cite evidence). Empty array if no services needed. |
| `system_packages` | array of strings | APT packages needed for the runtime (e.g., dev libraries). |
| `git_provider` | string | `"github"` or `"other"`. Determines credential setup and whether GitHub CLI is installed. |
| `git_remote` | string | Git clone URL for the project. |
| `workdir` | string | Container working directory (e.g., `"/var/www/html"`, `"/app"`). |
| `env_overrides` | object | Key-value pairs written to the project's `.env` on first boot. Service hostnames use compose service names (e.g., `"DB_HOST": "db"`). |
| `bootstrap` | object | See Bootstrap Fields below. |
| `supervisor_programs` | array of objects | Each object has: `name` (string, required), `command` (string, required). Must contain at least one entry. For projects with no long-running app processes, use `{"name": "keepalive", "command": "sleep infinity"}`. |
| `compose_ports` | object | Port mappings for compose. Keys are descriptive names (e.g., `"http"`, `"db"`), values are port numbers. |
| `assumptions` | array of strings | Decisions made without strong evidence. |
| `notes` | array of strings | Observations, warnings, or context for the user. |

### Bootstrap Fields (required)

| Field | Type | Description |
|---|---|---|
| `secret_generation` | string or null | Command to generate app secrets (e.g., `"php artisan key:generate --force"`). Null if not needed. |
| `migration` | string or null | Migration command. Null if no database. |
| `seeder` | string or null | Seeder command. Null if no seeders. |
| `post_install` | array of strings | Post-install commands (e.g., `["php artisan storage:link", "npm run build"]`). Empty array if none. |

### Optional Top-Level Fields

| Field | Type | Description |
|---|---|---|
| `php_extensions` | array of strings | PHP extensions to install. Only present for PHP stacks. |
| `test_env` | object or null | Test environment config: `file` (string), `test_db` (string or null), `secrets` (array of strings). |
| `pre_migration_sql` | array of strings | SQL statements to run before migrations (e.g., `CREATE EXTENSION`). |

## Example Profile (PHP/Laravel)

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

## Rules

- Output ONLY the JSON profile to `${RALPH_HOME}/sandbox/project-profile.json` — no Docker files, no bash scripts, no compose files.
- Every decision must cite evidence (the `evidence` and `reason` fields).
- Ambiguous or uncertain items go in `assumptions` or `notes`.
- Required fields must always be present, even when empty.
- Use the multi-container model: services run in their own containers using official Docker images.
- Supervisord manages only app-level processes (web server, queue worker, Vite), NOT infrastructure services (database, cache, mail).
- Create the output directory if it does not exist: `mkdir -p ${RALPH_HOME}/sandbox`

When complete, output: <promise>COMPLETE</promise>
