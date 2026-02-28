#!/bin/bash
# Ralph Wiggum Loop - Installer
#
# Installs Ralph into the current directory (which must be a git repository).
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/install.sh | bash
#   # or, from within the ralph-loop repo:
#   ./install.sh

set -euo pipefail

RALPH_REPO="https://raw.githubusercontent.com/mjeffe/ralph-loop/main"
RALPH_DIR=".ralph"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() {
    echo "$*"
}

error() {
    echo "Error: $*" >&2
}

die() {
    error "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# Pre-installation checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    # Refuse if already installed
    if [[ -d "$RALPH_DIR" ]]; then
        die "Ralph is already installed. Remove .ralph/ directory to reinstall."
    fi

    # Must be a git repository
    if [[ ! -d ".git" ]]; then
        die "Not a git repository. Please run this installer from the root of a git repository."
    fi

    # Check required tools
    local missing=()
    for tool in bash mkdir cp curl envsubst; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}"
    fi
}

# ---------------------------------------------------------------------------
# Fetch a file from the ralph-loop repo (GitHub) or copy from local repo
# ---------------------------------------------------------------------------
fetch_file() {
    local src_path="$1"   # relative path within ralph-loop repo
    local dest="$2"

    # If running from within the ralph-loop repo, copy directly
    local script_dir
    script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    local local_src="$script_dir/$src_path"

    if [[ -f "$local_src" ]]; then
        cp "$local_src" "$dest"
    else
        curl -sSL "$RALPH_REPO/$src_path" -o "$dest"
    fi
}

# ---------------------------------------------------------------------------
# Determine the upstream commit hash for version tracking
# ---------------------------------------------------------------------------
get_upstream_version() {
    local script_dir
    script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

    if [[ -d "$script_dir/.git" ]]; then
        # Running locally from the ralph-loop repo
        git -C "$script_dir" rev-parse --short HEAD
    else
        # Running remotely via curl — query GitHub
        git ls-remote https://github.com/mjeffe/ralph-loop.git HEAD \
            | cut -c1-7
    fi
}

# ---------------------------------------------------------------------------
# Generate manifest with SHA256 checksums of managed files
# ---------------------------------------------------------------------------
generate_manifest() {
    local managed_files=(
        ralph
        config
        agents/amp.sh
        prompts/plan.md
        prompts/build.md
        README.md
        .gitignore
    )

    for file in "${managed_files[@]}"; do
        local filepath="$RALPH_DIR/$file"
        if [[ -f "$filepath" ]]; then
            sha256sum "$filepath" | awk -v f="$file" '{print $1 "  " f}'
        fi
    done > "$RALPH_DIR/.manifest"
}

# ---------------------------------------------------------------------------
# Create .ralph/ directory structure
# ---------------------------------------------------------------------------
install_ralph_dir() {
    info "Creating .ralph/ directory structure..."

    mkdir -p "$RALPH_DIR/agents"
    mkdir -p "$RALPH_DIR/prompts"
    mkdir -p "$RALPH_DIR/logs"

    # Copy ralph executable
    fetch_file "ralph" "$RALPH_DIR/ralph"
    chmod +x "$RALPH_DIR/ralph"

    # Copy config
    fetch_file "config" "$RALPH_DIR/config"

    # Copy agent scripts
    fetch_file "agents/amp.sh" "$RALPH_DIR/agents/amp.sh"

    # Copy prompt templates
    fetch_file "prompts/plan.md" "$RALPH_DIR/prompts/plan.md"
    fetch_file "prompts/build.md" "$RALPH_DIR/prompts/build.md"

    # Copy overview as README
    fetch_file "specs/overview.md" "$RALPH_DIR/README.md"

    # Create implementation_plan.md template
    cat > "$RALPH_DIR/implementation_plan.md" <<'EOF'
# Implementation Plan
EOF

    # Create .gitignore
    cat > "$RALPH_DIR/.gitignore" <<'EOF'
# Ralph session logs (generated, not committed)
logs/

# Generated each iteration by the loop
last_agent_output

# Upstream review files from ralph update
*.upstream
EOF

    # Generate version and manifest for update tracking
    info "Writing version and manifest..."
    get_upstream_version > "$RALPH_DIR/.version"
    generate_manifest
}

# ---------------------------------------------------------------------------
# Create specs/ directory and README (additive only)
# ---------------------------------------------------------------------------
install_specs_dir() {
    if [[ ! -d "specs" ]]; then
        info "Creating specs/ directory..."
        mkdir -p "specs"
    fi

    if [[ ! -f "specs/README.md" ]]; then
        info "Creating specs/README.md template..."
        cat > "specs/README.md" <<'EOF'
# Specs Index

This directory contains the specifications that define this project's desired behavior.
Specs are the source of truth. When adding or removing a spec, update this index.

| Spec | Description |
|------|-------------|
| [example.md](example.md) | Brief description of this spec |
EOF
    fi
}

# ---------------------------------------------------------------------------
# Create AGENTS.md (additive only)
# ---------------------------------------------------------------------------
install_agents_md() {
    if [[ ! -f "AGENTS.md" ]]; then
        info "Creating AGENTS.md template..."
        cat > "AGENTS.md" <<'EOF'
# Agent Configuration

## Project Overview

Brief description of this project and its structure.

## Build & Test

Describe how to run tests and verify the project builds correctly.
For example:
- Run `npm test` to execute the test suite
- Run `npm run lint` to check code style
- Run `npm run build` to verify the project compiles

## Project-Specific Guidelines

- Any project-specific rules agents should follow
- e.g., "Always run migrations after modifying schema files"
- e.g., "Keep docs/ in sync with API changes"
EOF
    fi
}

# ---------------------------------------------------------------------------
# Display post-install success message
# ---------------------------------------------------------------------------
show_success() {
    cat <<'EOF'

Ralph installed successfully!

Ralph is installed in .ralph/ (a hidden directory).

Next steps:
1. Review and customize .ralph/config
2. Review and customize .ralph/prompts/*.md  (optional)
3. Create your specs in specs/
4. Fill in AGENTS.md with project-specific configuration
5. Optionally create a convenience symlink:
   ln -s .ralph/ralph ralph
6. Commit Ralph files:
   git add .ralph/ specs/ AGENTS.md && git commit -m "Add Ralph"
7. Run Ralph:
   .ralph/ralph plan   (or: ./ralph plan  if you created the symlink)
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    check_prerequisites
    install_ralph_dir
    install_specs_dir
    install_agents_md
    show_success
}

main "$@"
