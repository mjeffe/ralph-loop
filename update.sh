#!/bin/bash
# Ralph Wiggum Loop - Updater
#
# Updates an existing .ralph/ installation to the latest upstream version
# while preserving user customizations.
#
# This script is fetched and executed by `ralph update`:
#   curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/update.sh | bash

set -euo pipefail

RALPH_REPO="https://raw.githubusercontent.com/mjeffe/ralph-loop/main"
RALPH_GIT_REPO="https://github.com/mjeffe/ralph-loop.git"
RALPH_DIR=".ralph"

# Files managed by the installer/updater (relative to .ralph/)
MANAGED_FILES=(
    ralph
    config
    dependencies
    sandbox-preferences.sh
    agents/amp.sh
    agents/claude.sh
    agents/cline.sh
    agents/codex.sh
    prompts/plan.md
    prompts/plan-process.md
    prompts/build.md
    prompts/build-process.md
    prompts/sandbox-analyze.md
    prompts/sandbox-render.md
    prompts/sandbox-repair.md
    prompts/align-specs.md
    prompts/adhoc-test-analysis.md
    prompts/adhoc-process-spec-review.md
    prompts/templates/Dockerfile.base
    prompts/templates/wait-for-db
    prompts/playbooks/php-laravel.md
    lib/plan-filter.sh
    lib/sandbox.sh
    lib/help/index.txt
    lib/help/overview.txt
    lib/help/specs.txt
    lib/help/plan.txt
    lib/help/build.txt
    lib/help/prompt.txt
    lib/help/sandbox.txt
    lib/help/align-specs.txt
    lib/help/retro.txt
    README.md
    .gitignore
)

# Source paths in the ralph-loop repo for each managed file
declare -A SOURCE_PATHS=(
    [ralph]="ralph"
    [config]="config"
    [dependencies]="dependencies"
    [sandbox-preferences.sh]="sandbox-preferences.sh"
    [agents/amp.sh]="agents/amp.sh"
    [agents/claude.sh]="agents/claude.sh"
    [agents/cline.sh]="agents/cline.sh"
    [agents/codex.sh]="agents/codex.sh"
    [prompts/plan.md]="prompts/plan.md"
    [prompts/plan-process.md]="prompts/plan-process.md"
    [prompts/build.md]="prompts/build.md"
    [prompts/build-process.md]="prompts/build-process.md"
    [prompts/align-specs.md]="prompts/align-specs.md"
    [prompts/adhoc-test-analysis.md]="prompts/adhoc-test-analysis.md"
    [prompts/adhoc-process-spec-review.md]="prompts/adhoc-process-spec-review.md"
    [prompts/sandbox-analyze.md]="prompts/sandbox-analyze.md"
    [prompts/sandbox-render.md]="prompts/sandbox-render.md"
    [prompts/sandbox-repair.md]="prompts/sandbox-repair.md"
    [prompts/templates/Dockerfile.base]="prompts/templates/Dockerfile.base"
    [prompts/templates/wait-for-db]="prompts/templates/wait-for-db"
    [prompts/playbooks/php-laravel.md]="prompts/playbooks/php-laravel.md"
    [lib/plan-filter.sh]="lib/plan-filter.sh"
    [lib/sandbox.sh]="lib/sandbox.sh"
    [lib/help/index.txt]="lib/help/index.txt"
    [lib/help/overview.txt]="lib/help/overview.txt"
    [lib/help/specs.txt]="lib/help/specs.txt"
    [lib/help/plan.txt]="lib/help/plan.txt"
    [lib/help/build.txt]="lib/help/build.txt"
    [lib/help/prompt.txt]="lib/help/prompt.txt"
    [lib/help/sandbox.txt]="lib/help/sandbox.txt"
    [lib/help/align-specs.txt]="lib/help/align-specs.txt"
    [lib/help/retro.txt]="lib/help/retro.txt"
    [README.md]="specs/overview.md"
    [.gitignore]=".gitignore"
)

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

# Print a status line with dot padding (matches spec output format)
print_status() {
    local file="$1"
    local status="$2"
    local label="Updating $file"
    local total_width=35
    local pad_len=$(( total_width - ${#label} ))
    if [[ $pad_len -lt 2 ]]; then pad_len=2; fi
    local dots
    dots="$(printf '.%.0s' $(seq 1 "$pad_len"))"
    echo "$label$dots $status"
}

# ---------------------------------------------------------------------------
# Pre-update checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    if [[ ! -d "$RALPH_DIR" ]]; then
        die "Ralph is not installed. Run the installer."
    fi

    if [[ ! -d ".git" ]]; then
        die "Not a git repository."
    fi

    if ! curl -sSf --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
        die "Cannot reach GitHub. Check your network connection."
    fi
}

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------
get_current_version() {
    if [[ -f "$RALPH_DIR/.version" ]]; then
        cat "$RALPH_DIR/.version"
    else
        echo ""
    fi
}

get_latest_version() {
    git ls-remote "$RALPH_GIT_REPO" HEAD | cut -c1-7
}

# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------
read_manifest_checksum() {
    local file="$1"
    if [[ -f "$RALPH_DIR/.manifest" ]]; then
        grep -E "  ${file}$" "$RALPH_DIR/.manifest" | awk '{print $1}' || true
    fi
}

compute_checksum() {
    local filepath="$1"
    if [[ -f "$filepath" ]]; then
        sha256sum "$filepath" | awk '{print $1}'
    fi
}

# ---------------------------------------------------------------------------
# Fetch a file from the upstream repo into a temp directory
# ---------------------------------------------------------------------------
fetch_upstream_file() {
    local src_path="$1"
    local dest="$2"
    curl -sSL "$RALPH_REPO/$src_path" -o "$dest"
}

# ---------------------------------------------------------------------------
# Main update logic
# ---------------------------------------------------------------------------
main() {
    check_prerequisites

    local current_version latest_version
    current_version="$(get_current_version)"
    latest_version="$(get_latest_version)"

    if [[ -z "$latest_version" ]]; then
        die "Could not determine latest version from GitHub."
    fi

    if [[ -n "$current_version" && "$current_version" == "$latest_version" ]]; then
        info "Ralph is already up to date ($current_version)."
        exit 0
    fi

    local has_manifest=true
    if [[ ! -f "$RALPH_DIR/.manifest" ]]; then
        has_manifest=false
    fi

    info "Updating Ralph..."
    if [[ -n "$current_version" ]]; then
        info "Current: $current_version"
    else
        info "Current: unknown (pre-manifest install)"
    fi
    info "Latest:  $latest_version"
    info ""

    if [[ "$has_manifest" == false ]]; then
        info "No manifest found — treating all customizable files as modified (safe default)."
        info ""
    fi

    # Fetch all upstream files into a temp directory first (atomic: no partial updates)
    # TMP_DIR is script-scoped (not local) so the EXIT trap can reference it
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    for file in "${MANAGED_FILES[@]}"; do
        local src_path="${SOURCE_PATHS[$file]}"
        local dest_dir
        dest_dir="$(dirname "$TMP_DIR/$file")"
        mkdir -p "$dest_dir"
        if ! fetch_upstream_file "$src_path" "$TMP_DIR/$file"; then
            die "Failed to fetch $src_path from GitHub."
        fi
    done

    # Apply updates
    local has_upstream_files=false
    local has_conflicts=false
    local conflict_count=0
    local new_manifest_entries=()

    for file in "${MANAGED_FILES[@]}"; do
        local local_file="$RALPH_DIR/$file"
        local upstream_tmp="$TMP_DIR/$file"

        # File doesn't exist locally
        if [[ ! -f "$local_file" ]]; then
            local manifest_checksum_check
            manifest_checksum_check="$(read_manifest_checksum "$file")"
            if [[ -n "$manifest_checksum_check" ]]; then
                # Was in manifest but deleted by user — skip
                info "Skipping $file (deleted locally)"
            else
                # New upstream file — add it
                local dest_dir
                dest_dir="$(dirname "$local_file")"
                mkdir -p "$dest_dir"
                cp "$upstream_tmp" "$local_file"
                if [[ "$file" == "ralph" ]]; then
                    chmod +x "$local_file"
                fi
                print_status "$file" "done (new file)"
                local new_checksum
                new_checksum="$(compute_checksum "$local_file")"
                new_manifest_entries+=("$new_checksum  $file")
            fi
            continue
        fi

        local current_checksum manifest_checksum
        current_checksum="$(compute_checksum "$local_file")"
        manifest_checksum="$(read_manifest_checksum "$file")"

        local file_modified=false

        if [[ "$has_manifest" == false ]]; then
            # Pre-manifest install: treat all as modified
            file_modified=true
        elif [[ -z "$manifest_checksum" ]]; then
            # File not in manifest — treat as modified
            file_modified=true
        elif [[ "$current_checksum" != "$manifest_checksum" ]]; then
            # Checksum differs from manifest — user modified
            file_modified=true
        fi

        if [[ "$file_modified" == true ]]; then
            local originals_file="$RALPH_DIR/.originals/$file"

            if [[ -f "$originals_file" ]]; then
                # Three-way merge: ours (user's file), base (originals), theirs (upstream)
                # git merge-file modifies the first arg in place; work on a copy
                local merge_tmp="$TMP_DIR/merge_${file//\//_}"
                cp "$local_file" "$merge_tmp"
                local merge_rc=0
                git merge-file "$merge_tmp" "$originals_file" "$upstream_tmp" || merge_rc=$?

                if [[ "$merge_rc" -eq 0 ]]; then
                    # Clean merge
                    cp "$merge_tmp" "$local_file"
                    if [[ "$file" == "ralph" ]]; then
                        chmod +x "$local_file"
                    fi
                    print_status "$file" "done (merged)"
                    local upstream_checksum
                    upstream_checksum="$(compute_checksum "$upstream_tmp")"
                    new_manifest_entries+=("$upstream_checksum  $file")
                else
                    # Conflict — write conflict-marked file and keep .upstream as clean reference
                    cp "$merge_tmp" "$local_file"
                    cp "$upstream_tmp" "${local_file}.upstream"
                    has_upstream_files=true
                    has_conflicts=true
                    conflict_count=$(( conflict_count + 1 ))
                    print_status "$file" "CONFLICT"
                    info "  → Conflict markers written to $RALPH_DIR/${file}"
                    info "  → Clean upstream version saved as $RALPH_DIR/${file}.upstream"
                    local upstream_checksum
                    upstream_checksum="$(compute_checksum "$upstream_tmp")"
                    new_manifest_entries+=("$upstream_checksum  $file")
                fi
            else
                # No originals — fall back to .upstream file approach
                cp "$upstream_tmp" "${local_file}.upstream"
                has_upstream_files=true
                if [[ "$has_manifest" == false ]]; then
                    print_status "$file" "SKIPPED (no manifest; assuming modified)"
                else
                    print_status "$file" "SKIPPED (locally modified)"
                fi
                info "  → New version saved as $RALPH_DIR/${file}.upstream"
                local upstream_checksum
                upstream_checksum="$(compute_checksum "$upstream_tmp")"
                new_manifest_entries+=("$upstream_checksum  $file")
            fi
        else
            # Checksums match — safe to overwrite
            cp "$upstream_tmp" "$local_file"
            # ralph must be executable
            if [[ "$file" == "ralph" ]]; then
                chmod +x "$local_file"
            fi
            print_status "$file" "done"
            # New checksum for manifest
            local new_checksum
            new_checksum="$(compute_checksum "$local_file")"
            new_manifest_entries+=("$new_checksum  $file")
        fi
    done

    # Check for files removed upstream (in old manifest but no longer managed)
    if [[ -f "$RALPH_DIR/.manifest" ]]; then
        while IFS= read -r line; do
            local old_file
            old_file="$(echo "$line" | awk '{print $2}')"
            local still_managed=false
            for mf in "${MANAGED_FILES[@]}"; do
                if [[ "$mf" == "$old_file" ]]; then
                    still_managed=true
                    break
                fi
            done
            if [[ "$still_managed" == false && -f "$RALPH_DIR/$old_file" ]]; then
                info "$old_file is no longer part of Ralph and can be removed"
            fi
        done < "$RALPH_DIR/.manifest"
    fi

    # Write updated manifest
    printf '%s\n' "${new_manifest_entries[@]}" > "$RALPH_DIR/.manifest"

    # Write updated version
    echo "$latest_version" > "$RALPH_DIR/.version"

    # Update .originals/ with new upstream versions for all managed files
    mkdir -p "$RALPH_DIR/.originals"
    for file in "${MANAGED_FILES[@]}"; do
        local upstream_tmp="$TMP_DIR/$file"
        if [[ -f "$upstream_tmp" ]]; then
            local orig_dir
            orig_dir="$(dirname "$RALPH_DIR/.originals/$file")"
            mkdir -p "$orig_dir"
            cp "$upstream_tmp" "$RALPH_DIR/.originals/$file"
        fi
    done

    info ""
    info "Updated to $latest_version."

    if [[ "$has_manifest" == false ]]; then
        info "Manifest created. Future updates will detect modifications automatically."
    fi

    if [[ "$has_conflicts" == true ]]; then
        if [[ "$conflict_count" -eq 1 ]]; then
            info "$conflict_count file has merge conflicts. Resolve conflicts and delete .upstream files when done."
        else
            info "$conflict_count files have merge conflicts. Resolve conflicts and delete .upstream files when done."
        fi
    elif [[ "$has_upstream_files" == true ]]; then
        info "Review .upstream files for changes you may want to merge."
    fi
}

main "$@"
