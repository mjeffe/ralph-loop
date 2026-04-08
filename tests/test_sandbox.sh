#!/bin/bash
# Sandbox tests — ensure_name, validate, setup args, preconditions.

test_sandbox_usage_output() {
    echo "--- Sandbox usage in help ---"
    local output
    output=$("$RALPH_DIR/ralph" --help 2>&1)
    assert_contains "shows sandbox setup" "sandbox setup" "$output"
    assert_contains "shows sandbox up" "sandbox up" "$output"
    assert_contains "shows sandbox stop" "sandbox stop" "$output"
    assert_contains "shows sandbox reset" "sandbox reset" "$output"
    assert_contains "shows sandbox shell" "sandbox shell" "$output"
    assert_contains "shows sandbox status" "sandbox status" "$output"
}

test_sandbox_no_subcommand_exits_nonzero() {
    echo "--- Sandbox with no subcommand ---"
    assert_exit_code "sandbox without subcommand exits 1" 1 "$RALPH_DIR/ralph" sandbox
}

test_sandbox_bad_subcommand_exits_nonzero() {
    echo "--- Sandbox with bad subcommand ---"
    assert_exit_code "sandbox bogus exits 1" 1 "$RALPH_DIR/ralph" sandbox bogus
}

test_sandbox_guard_inside_sandbox() {
    echo "--- Sandbox guard: SANDBOX=1 ---"
    local rc=0
    local output
    output=$(SANDBOX=1 "$RALPH_DIR/ralph" sandbox up 2>&1) || rc=$?
    assert_eq "SANDBOX=1 exits 1" "1" "$rc"
    assert_contains "error message mentions already inside" "already inside the sandbox" "$output"
}

test_sandbox_ensure_name_from_env() {
    echo "--- sandbox_ensure_name: reads SANDBOX_NAME from .env ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    echo "SANDBOX_NAME=my-sandbox" > "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "picks up name from .env" "my-sandbox" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_missing_from_env() {
    echo "--- sandbox_ensure_name: falls back when SANDBOX_NAME missing from .env ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    echo "OTHER_VAR=hello" > "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "derives name (not empty)" "1" "$( [[ -n "$SANDBOX_NAME" ]] && echo 1 || echo 0 )"
        assert_contains "derived name has -sandbox-" "-sandbox-" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_no_env_file() {
    echo "--- sandbox_ensure_name: falls back when no .env file ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    rm -f "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "derives name (not empty)" "1" "$( [[ -n "$SANDBOX_NAME" ]] && echo 1 || echo 0 )"
        assert_contains "derived name has -sandbox-" "-sandbox-" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_already_set() {
    echo "--- sandbox_ensure_name: no-op when SANDBOX_NAME already set ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    (
        export SANDBOX_NAME="pre-existing"
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        assert_eq "preserves existing value" "pre-existing" "$SANDBOX_NAME"
    )
}

test_sandbox_ensure_name_writes_back_to_env() {
    echo "--- sandbox_ensure_name: appends derived name to .env ---"
    source <(sed -n '/^sandbox_ensure_name()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/project/.ralph/sandbox"
    mkdir -p "$sdir"
    echo "OTHER_VAR=hello" > "$sdir/.env"

    (
        unset SANDBOX_NAME
        RALPH_DIR="$TMP_DIR/project/.ralph"
        sandbox_ensure_name
        local written
        written=$(grep '^SANDBOX_NAME=' "$sdir/.env" || true)
        assert_eq "wrote name back to .env" "1" "$( [[ -n "$written" ]] && echo 1 || echo 0 )"
    )
}

test_sandbox_up_no_compose_file() {
    echo "--- sandbox_up: exits when no compose file ---"
    local output rc=0
    local sandbox_dir="$TMP_DIR/no_compose/.ralph/sandbox"
    mkdir -p "$sandbox_dir"
    # Create a .env so that check passes, but no docker-compose.yml
    echo "SANDBOX_NAME=test" > "$sandbox_dir/.env"
    output=$(SANDBOX_NAME=test RALPH_DIR="$TMP_DIR/no_compose/.ralph" \
        bash -c "source <(sed -n '/^sandbox_up()/,/^}/p' \"$RALPH_DIR/ralph\")
                 source <(sed -n '/^sandbox_ensure_name()/,/^}/p' \"$RALPH_DIR/ralph\")
                 sandbox_up" 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions setup first" "sandbox setup" "$output"
}

test_sandbox_up_no_env_file() {
    echo "--- sandbox_up: exits when no .env file ---"
    local sandbox_dir="$TMP_DIR/no_env/.ralph/sandbox"
    mkdir -p "$sandbox_dir"
    # Create compose but no .env
    echo "services:" > "$sandbox_dir/docker-compose.yml"
    cat > "$sandbox_dir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
DOCK
    local output rc=0
    output=$(SANDBOX_NAME=test RALPH_DIR="$TMP_DIR/no_env/.ralph" \
        bash -c "source <(sed -n '/^sandbox_up()/,/^}/p' \"$RALPH_DIR/ralph\")
                 source <(sed -n '/^sandbox_ensure_name()/,/^}/p' \"$RALPH_DIR/ralph\")
                 sandbox_up" 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions .env" ".env" "$output"
}

test_sandbox_status_no_compose_file() {
    echo "--- sandbox_status: exits when no compose file ---"
    local sandbox_dir="$TMP_DIR/no_compose_status/.ralph/sandbox"
    mkdir -p "$sandbox_dir"
    local output rc=0
    output=$(SANDBOX_NAME=test RALPH_DIR="$TMP_DIR/no_compose_status/.ralph" \
        bash -c "source <(sed -n '/^sandbox_status()/,/^}/p' \"$RALPH_DIR/ralph\")
                 source <(sed -n '/^sandbox_ensure_name()/,/^}/p' \"$RALPH_DIR/ralph\")
                 sandbox_status" 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions setup first" "sandbox setup" "$output"
}

test_sandbox_setup_unknown_flag() {
    echo "--- sandbox_setup: rejects unknown flags ---"
    local output rc=0
    output=$("$RALPH_DIR/ralph" sandbox setup --bogus 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions unknown option" "unknown option" "$output"
}

test_sandbox_setup_render_only_without_profile() {
    echo "--- sandbox_setup: --render-only without profile exits 1 ---"
    # This tests flag parsing AND the render-only precondition in one shot.
    # No Docker or agent needed — fails before reaching either.
    local output rc=0
    output=$(cd "$TMP_DIR" && "$RALPH_DIR/ralph" sandbox setup --render-only 2>&1) || rc=$?
    assert_eq "exits non-zero" "1" "$rc"
    assert_contains "mentions missing profile" "project profile" "$output"
}

test_sandbox_validate_profile_valid() {
    echo "--- sandbox_validate_profile: valid profile ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/valid-profile.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 1,
    "stack": "php-laravel",
    "runtimes": [{"name": "php", "version": "8.3", "evidence": ["composer.json"]}],
    "package_managers": [{"name": "composer", "install_command": "composer install"}],
    "services": [{"name": "postgres", "image": "postgres:16", "port": 5432, "reason": "DB_CONNECTION=pgsql"}],
    "system_packages": ["libpq-dev"],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/var/www/html",
    "env_overrides": {"DB_HOST": "db"},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "web", "command": "php artisan serve"}],
    "compose_ports": {"http": 80},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_eq "valid profile produces no errors" "" "$output"
}

test_sandbox_validate_profile_missing_fields() {
    echo "--- sandbox_validate_profile: missing required fields ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/missing-fields.json"
    echo '{"schema_version": 1, "stack": "node"}' > "$profile"

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches missing runtimes" "missing required field: runtimes" "$output"
    assert_contains "catches missing services" "missing required field: services" "$output"
    assert_contains "catches missing supervisor_programs" "missing required field: supervisor_programs" "$output"
    assert_contains "catches missing workdir" "missing required field: workdir" "$output"
}

test_sandbox_validate_profile_bad_schema_version() {
    echo "--- sandbox_validate_profile: wrong schema_version ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/bad-version.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 2,
    "stack": "node",
    "runtimes": [{"name": "node", "version": "20", "evidence": ["package.json"]}],
    "package_managers": [{"name": "npm", "install_command": "npm ci"}],
    "services": [],
    "system_packages": [],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/app",
    "env_overrides": {},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "keepalive", "command": "sleep infinity"}],
    "compose_ports": {},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches bad schema_version" "schema_version must be 1" "$output"
}

test_sandbox_validate_profile_empty_runtimes() {
    echo "--- sandbox_validate_profile: empty runtimes ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/empty-runtimes.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 1,
    "stack": "node",
    "runtimes": [],
    "package_managers": [],
    "services": [],
    "system_packages": [],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/app",
    "env_overrides": {},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "keepalive", "command": "sleep infinity"}],
    "compose_ports": {},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches empty runtimes" "runtimes must have at least one entry" "$output"
}

test_sandbox_validate_profile_service_missing_fields() {
    echo "--- sandbox_validate_profile: service missing required fields ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/bad-service.json"
    cat > "$profile" <<'EOF'
{
    "schema_version": 1,
    "stack": "node",
    "runtimes": [{"name": "node", "version": "20", "evidence": ["package.json"]}],
    "package_managers": [{"name": "npm", "install_command": "npm ci"}],
    "services": [{"name": "postgres"}],
    "system_packages": [],
    "git_provider": "github",
    "git_remote": "https://github.com/example/project.git",
    "workdir": "/app",
    "env_overrides": {},
    "bootstrap": {"secret_generation": null, "migration": null, "seeder": null, "post_install": []},
    "supervisor_programs": [{"name": "keepalive", "command": "sleep infinity"}],
    "compose_ports": {},
    "assumptions": [],
    "notes": []
}
EOF

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches missing image" "missing required field: image" "$output"
    assert_contains "catches missing port" "missing required field: port or ports" "$output"
    assert_contains "catches missing reason" "missing required field: reason" "$output"
}

test_sandbox_validate_profile_invalid_json() {
    echo "--- sandbox_validate_profile: invalid JSON ---"
    source <(sed -n '/^sandbox_validate_profile()/,/^}/p' "$RALPH_DIR/ralph")

    local profile="$TMP_DIR/bad.json"
    echo "not json at all" > "$profile"

    local output
    output=$(sandbox_validate_profile "$profile")
    assert_contains "catches invalid JSON" "not valid JSON" "$output"
}

test_sandbox_validate_structural() {
    echo "--- sandbox_validate: structural checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_validate_test"
    mkdir -p "$sdir"

    # Missing all files
    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches missing entrypoint" "entrypoint.sh not found" "$output"
    assert_contains "catches missing Dockerfile" "Dockerfile not found" "$output"
    assert_contains "catches missing compose" "docker-compose.yml not found" "$output"

    # Create minimal valid entrypoint
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY

    # Create minimal Dockerfile
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
DOCK

    output=$(sandbox_validate "$sdir")
    # entrypoint and Dockerfile should pass structural checks; compose still missing
    assert_contains "still catches missing compose" "docker-compose.yml not found" "$output"

    rm -rf "$sdir"
}

test_sandbox_setup_render_only_requires_profile() {
    echo "--- sandbox setup --render-only requires existing profile ---"
    local sdir="$TMP_DIR/project/sandbox"
    mkdir -p "$sdir"
    rm -f "$sdir/project-profile.json"

    local output rc=0
    output=$("$RALPH_DIR/ralph" sandbox setup --render-only 2>&1) || rc=$?
    assert_eq "--render-only without profile exits 1" "1" "$rc"
    assert_contains "error mentions missing profile" "no project profile found" "$output"
    assert_contains "suggests running without --render-only" "without --render-only" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_entrypoint_structural() {
    echo "--- sandbox_validate: entrypoint structural checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_entrypoint_test"
    mkdir -p "$sdir"

    # Create Dockerfile to avoid those errors
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
DOCK

    # Create a bad entrypoint missing required elements
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/bin/bash
echo "hello"
ENTRY

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches wrong shebang" "does not start with #!/usr/bin/env bash" "$output"
    assert_contains "catches missing set -euo" "missing set -euo pipefail" "$output"
    assert_contains "catches missing git credential" "missing git credential configuration" "$output"
    assert_contains "catches missing clone logic" "missing clone logic" "$output"
    assert_contains "catches missing exec supervisord" "does not end with exec supervisord" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_compose_structural() {
    echo "--- sandbox_validate: docker-compose.yml structural checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_compose_test"
    mkdir -p "$sdir"

    # Provide valid Dockerfile and entrypoint so we isolate compose checks
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /var/www/html
DOCK
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY

    # Create a compose file missing required elements
    cat > "$sdir/docker-compose.yml" <<'COMPOSE'
services:
  web:
    image: nginx
COMPOSE

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches missing app service" "missing app service" "$output"
    assert_contains "catches missing env_file" "missing env_file" "$output"
    assert_contains "catches missing tty" "missing tty: true" "$output"
    assert_contains "catches missing stdin_open" "missing stdin_open: true" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_cross_file_env_vars() {
    echo "--- sandbox_validate: cross-file env var checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_crossfile_test"
    mkdir -p "$sdir"

    # Minimal valid files
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /app
DOCK
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY
    cat > "$sdir/docker-compose.yml" <<'COMPOSE'
services:
  app:
    build: .
    env_file: .env
    tty: true
    stdin_open: true
    environment:
      - DB_HOST=${DB_HOST}
      - SECRET_KEY=${SECRET_KEY}
COMPOSE
    # .env.example only has DB_HOST, missing SECRET_KEY
    cat > "$sdir/.env.example" <<'ENV'
DB_HOST=localhost
ENV

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches undocumented env var" "SECRET_KEY not documented in .env.example" "$output"

    # Commented-out entries should count as documented
    cat > "$sdir/.env.example" <<'ENV'
DB_HOST=localhost
# SECRET_KEY=my-secret
ENV
    output=$(sandbox_validate "$sdir")
    assert_not_contains "accepts commented-out env var" "SECRET_KEY not documented" "$output"

    rm -rf "$sdir"
}

test_sandbox_validate_runtime_manager_refs() {
    echo "--- sandbox_validate: unprovisioned runtime manager checks ---"
    source <(sed -n '/^sandbox_validate()/,/^}/p' "$RALPH_DIR/ralph")

    local sdir="$TMP_DIR/sandbox_rtmgr_test"
    mkdir -p "$sdir"

    # Minimal valid files — entrypoint references nvm.sh but Dockerfile doesn't install it
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /app
DOCK
    cat > "$sdir/entrypoint.sh" <<'ENTRY'
#!/usr/bin/env bash
set -euo pipefail
git credential approve <<< "host=github.com"
if [[ ! -f .git/HEAD ]]; then
    git clone "$REPO" .
fi
source /usr/local/nvm/nvm.sh
nvm use 12
npm ci
exec supervisord -n -c /etc/supervisor/supervisord.conf
ENTRY
    cat > "$sdir/docker-compose.yml" <<'COMPOSE'
services:
  app:
    build: .
    env_file: .env
    tty: true
    stdin_open: true
    environment:
      - SANDBOX=1
COMPOSE
    cat > "$sdir/.env.example" <<'ENV'
SANDBOX=1
ENV

    local output
    output=$(sandbox_validate "$sdir")
    assert_contains "catches unprovisioned nvm.sh" "nvm.sh" "$output"

    # Now add nvm install to Dockerfile — should pass
    cat > "$sdir/Dockerfile" <<'DOCK'
FROM ralph-sandbox-base
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && source /usr/local/nvm/nvm.sh && nvm install 12
COPY sandbox-preferences.sh /tmp/sandbox-preferences.sh
RUN bash /tmp/sandbox-preferences.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
WORKDIR /app
DOCK
    output=$(sandbox_validate "$sdir")
    assert_not_contains "accepts provisioned nvm.sh" "nvm.sh" "$output"

    rm -rf "$sdir"
}
