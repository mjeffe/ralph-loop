#!/bin/bash
# Sandbox lifecycle commands, validation, and stack detection.
# Sourced eagerly by ralph at startup.

sandbox_ensure_name() {
    if [[ -z "${SANDBOX_NAME:-}" ]]; then
        local env_file="$RALPH_DIR/sandbox/.env"
        if [[ -f "$env_file" ]]; then
            local file_val
            file_val=$(grep -E '^SANDBOX_NAME=' "$env_file" 2>/dev/null | tail -1 | cut -d= -f2- || true)
            if [[ -n "$file_val" ]]; then
                export SANDBOX_NAME="$file_val"
                return
            fi
        fi
        local project_root
        project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        local hash
        hash=$(echo -n "$project_root" | sha1sum | cut -c1-8)
        local dir_name
        dir_name=$(basename "$project_root")
        export SANDBOX_NAME="${dir_name}-sandbox-${hash}"
        if [[ -f "$env_file" ]]; then
            echo "SANDBOX_NAME=${SANDBOX_NAME}" >> "$env_file"
        fi
    fi
}

sandbox_container_name() {
    local service="${1:-app}"
    local compose_file="$RALPH_DIR/sandbox/docker-compose.yml"
    local name
    name=$(docker compose -f "$compose_file" config --format json \
        | jq -r --arg svc "$service" '.services[$svc].container_name // empty' 2>/dev/null)
    if [[ -z "$name" ]]; then
        local project_name
        project_name=$(docker compose -f "$compose_file" config --format json \
            | jq -r '.name // empty' 2>/dev/null)
        if [[ -n "$project_name" ]]; then
            name="${project_name}-${service}-1"
        fi
    fi
    if [[ -z "$name" ]]; then
        echo "Error: could not determine container name for service '$service' from compose file." >&2
        exit 1
    fi
    echo "$name"
}

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

sandbox_validate_profile() {
    local profile_file="$1"
    local failures=""

    if [[ ! -f "$profile_file" ]]; then
        echo "[FAIL] profile file not found: $profile_file"
        return
    fi

    if ! jq empty "$profile_file" 2>/dev/null; then
        echo "[FAIL] profile is not valid JSON"
        return
    fi

    local required_fields=(schema_version stack runtimes package_managers services
        system_packages git_provider git_remote workdir env_overrides bootstrap
        supervisor_programs compose_ports assumptions notes)

    for field in "${required_fields[@]}"; do
        if ! jq -e "has(\"$field\")" "$profile_file" >/dev/null 2>&1; then
            failures+="[FAIL] missing required field: $field"$'\n'
        fi
    done

    local schema_version
    schema_version=$(jq -r '.schema_version // empty' "$profile_file" 2>/dev/null)
    if [[ -n "$schema_version" && "$schema_version" != "1" ]]; then
        failures+="[FAIL] schema_version must be 1, got: $schema_version"$'\n'
    fi

    local runtime_count
    runtime_count=$(jq '.runtimes | length' "$profile_file" 2>/dev/null || echo 0)
    if [[ "$runtime_count" -eq 0 ]]; then
        failures+="[FAIL] runtimes must have at least one entry"$'\n'
    fi

    local supervisor_count
    supervisor_count=$(jq '.supervisor_programs | length' "$profile_file" 2>/dev/null || echo 0)
    if [[ "$supervisor_count" -eq 0 ]]; then
        failures+="[FAIL] supervisor_programs must have at least one entry"$'\n'
    fi

    local service_count
    service_count=$(jq '.services | length' "$profile_file" 2>/dev/null || echo 0)
    if [[ "$service_count" -gt 0 ]]; then
        local service_errors
        service_errors=$(jq -r '
            .services | to_entries[] |
            ( if .value.name == null then "[FAIL] services[\(.key)] missing required field: name" else empty end ),
            ( if .value.image == null then "[FAIL] services[\(.key)] missing required field: image" else empty end ),
            ( if (.value.port == null and .value.ports == null) then "[FAIL] services[\(.key)] missing required field: port or ports" else empty end ),
            ( if .value.reason == null then "[FAIL] services[\(.key)] missing required field: reason" else empty end )
        ' "$profile_file" 2>/dev/null)
        if [[ -n "$service_errors" ]]; then
            failures+="$service_errors"$'\n'
        fi
    fi

    # Output failures (empty = pass)
    if [[ -n "$failures" ]]; then
        echo -n "$failures"
    fi
}

sandbox_validate() {
    local sandbox_dir="$1"
    local failures=""

    # --- Syntax checks ---
    if [[ -f "$sandbox_dir/entrypoint.sh" ]]; then
        if bash -n "$sandbox_dir/entrypoint.sh" 2>/dev/null; then
            : # pass
        else
            failures+="[FAIL] entrypoint.sh syntax error"$'\n'
        fi
    else
        failures+="[FAIL] entrypoint.sh not found"$'\n'
    fi

    if [[ -f "$sandbox_dir/docker-compose.yml" ]]; then
        if docker compose -f "$sandbox_dir/docker-compose.yml" config >/dev/null 2>&1; then
            : # pass
        else
            failures+="[FAIL] docker-compose.yml syntax error"$'\n'
        fi
    else
        failures+="[FAIL] docker-compose.yml not found"$'\n'
    fi

    if [[ -f "$sandbox_dir/sandbox-preferences.sh" ]]; then
        if bash -n "$sandbox_dir/sandbox-preferences.sh" 2>/dev/null; then
            : # pass
        else
            failures+="[FAIL] sandbox-preferences.sh syntax error"$'\n'
        fi
    fi

    # --- Structural: Dockerfile ---
    if [[ -f "$sandbox_dir/Dockerfile" ]]; then
        if ! grep -q 'FROM ralph-sandbox-base' "$sandbox_dir/Dockerfile"; then
            failures+="[FAIL] Dockerfile missing FROM ralph-sandbox-base"$'\n'
        fi
        if ! grep -q 'ENTRYPOINT.*tini' "$sandbox_dir/Dockerfile"; then
            failures+="[FAIL] Dockerfile ENTRYPOINT does not use tini"$'\n'
        fi
        if ! grep -q 'entrypoint.sh' "$sandbox_dir/Dockerfile"; then
            failures+="[FAIL] Dockerfile does not copy entrypoint.sh"$'\n'
        fi
        if ! grep -q 'WORKDIR' "$sandbox_dir/Dockerfile"; then
            failures+="[FAIL] Dockerfile missing WORKDIR"$'\n'
        fi
        if ! grep -q 'sandbox-preferences.sh' "$sandbox_dir/Dockerfile"; then
            failures+="[FAIL] Dockerfile does not COPY sandbox-preferences.sh"$'\n'
        fi
    else
        failures+="[FAIL] Dockerfile not found"$'\n'
    fi

    # --- Structural: entrypoint.sh ---
    if [[ -f "$sandbox_dir/entrypoint.sh" ]]; then
        local first_line second_line
        first_line=$(head -n1 "$sandbox_dir/entrypoint.sh")
        second_line=$(sed -n '2p' "$sandbox_dir/entrypoint.sh")
        if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
            failures+="[FAIL] entrypoint.sh does not start with #!/usr/bin/env bash"$'\n'
        fi
        if [[ "$second_line" != "set -euo pipefail" ]]; then
            failures+="[FAIL] entrypoint.sh missing set -euo pipefail on line 2"$'\n'
        fi
        if ! grep -q 'git.*credential\|credential.*git' "$sandbox_dir/entrypoint.sh"; then
            failures+="[FAIL] entrypoint.sh missing git credential configuration"$'\n'
        fi
        if ! grep -q '\.git/HEAD' "$sandbox_dir/entrypoint.sh"; then
            failures+="[FAIL] entrypoint.sh missing clone logic (.git/HEAD check)"$'\n'
        fi
        if ! grep -q 'exec supervisord' "$sandbox_dir/entrypoint.sh"; then
            failures+="[FAIL] entrypoint.sh does not end with exec supervisord"$'\n'
        fi
    fi

    # --- Structural: docker-compose.yml ---
    if [[ -f "$sandbox_dir/docker-compose.yml" ]]; then
        if ! grep -q 'app:' "$sandbox_dir/docker-compose.yml"; then
            failures+="[FAIL] docker-compose.yml missing app service"$'\n'
        fi
        if grep -qE '^\s+environment:' "$sandbox_dir/docker-compose.yml"; then
            # Check for map syntax (KEY: value) vs list syntax (- KEY=value) under environment
            if grep -A 20 'environment:' "$sandbox_dir/docker-compose.yml" | grep -qE '^\s+[A-Z_]+:'; then
                failures+="[FAIL] docker-compose.yml uses map syntax for environment (should use list syntax)"$'\n'
            fi
        fi
        if grep -q 'volumes:' "$sandbox_dir/docker-compose.yml" && grep -qE '^\s+-\s+[./]' "$sandbox_dir/docker-compose.yml"; then
            failures+="[FAIL] docker-compose.yml uses bind mounts (should use named volumes only)"$'\n'
        fi
        if ! grep -q 'env_file' "$sandbox_dir/docker-compose.yml"; then
            failures+="[FAIL] docker-compose.yml missing env_file directive"$'\n'
        fi
        if ! grep -q 'tty: true\|tty:true' "$sandbox_dir/docker-compose.yml"; then
            failures+="[FAIL] docker-compose.yml missing tty: true for app service"$'\n'
        fi
        if ! grep -q 'stdin_open: true\|stdin_open:true' "$sandbox_dir/docker-compose.yml"; then
            failures+="[FAIL] docker-compose.yml missing stdin_open: true for app service"$'\n'
        fi
    fi

    # --- Cross-file: ports ---
    if [[ -f "$sandbox_dir/Dockerfile" && -f "$sandbox_dir/docker-compose.yml" ]]; then
        local exposed_ports
        exposed_ports=$(grep -oP 'EXPOSE\s+\K\d+' "$sandbox_dir/Dockerfile" 2>/dev/null || true)
        for port in $exposed_ports; do
            if ! grep -q "$port" "$sandbox_dir/docker-compose.yml"; then
                failures+="[FAIL] Dockerfile EXPOSE $port has no corresponding port mapping in docker-compose.yml"$'\n'
            fi
        done
    fi

    # --- Cross-file: env vars in compose documented in .env.example ---
    if [[ -f "$sandbox_dir/docker-compose.yml" && -f "$sandbox_dir/.env.example" ]]; then
        local compose_vars
        compose_vars=$(grep -oP '\$\{?\K[A-Z_]+' "$sandbox_dir/docker-compose.yml" 2>/dev/null | sort -u || true)
        for var in $compose_vars; do
            if ! grep -qP "^#?\s*${var}=" "$sandbox_dir/.env.example" 2>/dev/null; then
                failures+="[FAIL] compose env var $var not documented in .env.example"$'\n'
            fi
        done
    fi

    # --- Cross-file: entrypoint references unprovisioned runtime managers ---
    if [[ -f "$sandbox_dir/entrypoint.sh" && -f "$sandbox_dir/Dockerfile" ]]; then
        local runtime_managers="nvm\.sh|pyenv init|rbenv init|\.asdf/asdf\.sh|sdkman-init\.sh|volta"
        local entrypoint_refs
        entrypoint_refs=$(grep -oP "$runtime_managers" "$sandbox_dir/entrypoint.sh" 2>/dev/null || true)
        for ref in $entrypoint_refs; do
            if ! grep -q "$ref" "$sandbox_dir/Dockerfile" 2>/dev/null; then
                failures+="[FAIL] entrypoint.sh references '$ref' but Dockerfile does not install it"$'\n'
            fi
        done
    fi

    # --- Profile consistency ---
    if [[ -f "$sandbox_dir/project-profile.json" ]]; then
        # Services in compose match profile
        if [[ -f "$sandbox_dir/docker-compose.yml" ]]; then
            local profile_services
            profile_services=$(jq -r '.services[].name' "$sandbox_dir/project-profile.json" 2>/dev/null || true)
            for svc in $profile_services; do
                if ! grep -q "${svc}:" "$sandbox_dir/docker-compose.yml" 2>/dev/null; then
                    failures+="[FAIL] profile service '$svc' not found in docker-compose.yml"$'\n'
                fi
            done
        fi
    fi

    # Output failures (empty = pass)
    if [[ -n "$failures" ]]; then
        echo -n "$failures"
    fi
}

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
    # shellcheck source=/dev/null
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

    # Copy base Dockerfile, wait-for-db, and sandbox-preferences into build context
    cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$sandbox_dir/Dockerfile.base"
    cp "$RALPH_DIR/prompts/templates/wait-for-db" "$sandbox_dir/wait-for-db"
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

    # Create sandbox-setup.md if it doesn't exist (user-owned, never overwritten)
    local setup_notes="$RALPH_DIR/sandbox-setup.md"
    if [[ ! -f "$setup_notes" ]]; then
        cat > "$setup_notes" <<'NOTES'
# Sandbox Setup Notes

## Host-Side Fixes
<!-- Corrections to generated sandbox files (Dockerfile, entrypoint,
     docker-compose.yml) that `ralph sandbox setup` got wrong.
     Reference these when regenerating with `sandbox setup --force`. -->

## In-Sandbox Bootstrap
<!-- Steps for getting the application working inside a fresh sandbox
     (after `sandbox reset` or first `sandbox up`): database migrations,
     test database setup, seed data, dev server config, etc. -->
NOTES
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
    echo ""
    echo "Tip: Use $RALPH_HOME/sandbox-setup.md to document sandbox fixes and bootstrap steps."
    echo "     See 'ralph help sandbox' for details."
}

sandbox_up() {
    sandbox_ensure_name
    local compose_file="$RALPH_DIR/sandbox/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        echo "Sandbox not configured. Run 'ralph sandbox setup' first." >&2
        exit 1
    fi

    local env_file="$RALPH_DIR/sandbox/.env"
    if [[ ! -f "$env_file" ]]; then
        echo "Warning: $env_file not found." >&2
        echo "Copy .env.example to .env and set GITHUB_TOKEN and AMP_API_KEY:" >&2
        echo "  cp $RALPH_DIR/sandbox/.env.example $env_file" >&2
        exit 1
    fi

    # Auto-refresh base image and sandbox-preferences from managed sources.
    # Docker layer cache makes this instant when nothing has changed.
    cp "$RALPH_DIR/prompts/templates/Dockerfile.base" "$RALPH_DIR/sandbox/Dockerfile.base"
    cp "$RALPH_DIR/sandbox-preferences.sh" "$RALPH_DIR/sandbox/sandbox-preferences.sh"
    docker build -t ralph-sandbox-base -f "$RALPH_DIR/sandbox/Dockerfile.base" "$RALPH_DIR/sandbox/"

    docker compose -f "$compose_file" up -d --build "$@"
    echo ""
    echo "Sandbox is starting. First build may take several minutes."
    echo "Use 'ralph sandbox shell' to connect once ready."
}

sandbox_stop() {
    sandbox_ensure_name
    docker compose -f "$RALPH_DIR/sandbox/docker-compose.yml" stop "$@"
}

sandbox_reset() {
    sandbox_ensure_name
    local compose_file="$RALPH_DIR/sandbox/docker-compose.yml"
    local reset_all=false

    if [[ "${1:-}" == "--all" ]]; then
        reset_all=true
    fi

    local project_name
    project_name=$(docker compose -f "$compose_file" config --format json \
        | jq -r '.name // empty' 2>/dev/null)

    if [[ -z "$project_name" ]]; then
        echo "Error: could not determine compose project name." >&2
        exit 1
    fi

    if [[ "$reset_all" == true ]]; then
        echo "This will delete ALL sandbox volumes (codebase, database, cache, etc.)."
    else
        echo "This will delete the app codebase volume and re-clone from git."
        echo "Service volumes (database, cache, etc.) will be preserved."
    fi
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$reset_all" == true ]]; then
            # Remove all containers and all volumes across every service
            docker compose -f "$compose_file" down -v
        else
            # Stop only the app service, remove its codebase volume
            docker compose -f "$compose_file" stop app
            docker volume rm "${project_name}_sandbox-codebase" 2>/dev/null || true
            docker compose -f "$compose_file" up -d --build app
        fi
        echo "Sandbox reset complete."
    fi
}

sandbox_shell() {
    sandbox_ensure_name
    local container_name
    container_name=$(sandbox_container_name "app")
    docker exec -it -u ralph "$container_name" bash
}

sandbox_status() {
    sandbox_ensure_name
    local compose_file="$RALPH_DIR/sandbox/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        echo "Sandbox not configured. Run 'ralph sandbox setup' first." >&2
        exit 1
    fi
    docker compose -f "$compose_file" ps "$@"
}
