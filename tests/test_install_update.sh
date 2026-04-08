#!/bin/bash
# Installer and updater tests — three-way merge, .originals, managed files.

test_installer_creates_originals() {
    echo "--- Installer creates .originals/ ---"
    # Verify install.sh populates .originals/ by checking the populate_originals function exists
    local has_fn
    has_fn=$(grep -c "populate_originals" "$RALPH_DIR/install.sh")
    assert_eq "install.sh has populate_originals" "true" "$( [[ "$has_fn" -ge 2 ]] && echo true || echo false )"

    # Verify .originals/ is created in install_ralph_dir
    local has_mkdir
    has_mkdir=$(grep -c '\.originals' "$RALPH_DIR/install.sh")
    assert_eq "install.sh references .originals" "true" "$( [[ "$has_mkdir" -ge 1 ]] && echo true || echo false )"
}

test_updater_three_way_merge_clean() {
    echo "--- Three-way merge: clean merge ---"
    # Simulate: originals has base, user modified one section, upstream modified another
    local test_dir="$TMP_DIR/merge_clean"
    mkdir -p "$test_dir"

    # Base (originals)
    cat > "$test_dir/base.md" <<'EOF'
# Config
setting_a=1
setting_b=2
setting_c=3
EOF

    # User's version (modified setting_a)
    cat > "$test_dir/ours.md" <<'EOF'
# Config
setting_a=100
setting_b=2
setting_c=3
EOF

    # Upstream (modified setting_c)
    cat > "$test_dir/theirs.md" <<'EOF'
# Config
setting_a=1
setting_b=2
setting_c=300
EOF

    local merge_rc=0
    git merge-file "$test_dir/ours.md" "$test_dir/base.md" "$test_dir/theirs.md" || merge_rc=$?
    assert_eq "clean merge exits 0" "0" "$merge_rc"
    assert_contains "merge preserves user change" "setting_a=100" "$(cat "$test_dir/ours.md")"
    assert_contains "merge includes upstream change" "setting_c=300" "$(cat "$test_dir/ours.md")"
}

test_updater_three_way_merge_conflict() {
    echo "--- Three-way merge: conflict ---"
    # Both user and upstream modify the same line
    local test_dir="$TMP_DIR/merge_conflict"
    mkdir -p "$test_dir"

    cat > "$test_dir/base.md" <<'EOF'
# Config
setting_a=1
EOF

    cat > "$test_dir/ours.md" <<'EOF'
# Config
setting_a=user_value
EOF

    cat > "$test_dir/theirs.md" <<'EOF'
# Config
setting_a=upstream_value
EOF

    local merge_rc=0
    git merge-file "$test_dir/ours.md" "$test_dir/base.md" "$test_dir/theirs.md" || merge_rc=$?
    assert_eq "conflict merge exits non-zero" "true" "$( [[ "$merge_rc" -gt 0 ]] && echo true || echo false )"
    assert_contains "conflict has markers" "<<<<<<<" "$(cat "$test_dir/ours.md")"
}

test_updater_originals_not_in_gitignore() {
    echo "--- .originals/ NOT in .gitignore (must be committed for sandbox persistence) ---"
    local gitignore
    gitignore=$(cat "$RALPH_DIR/.gitignore")
    local has_originals
    has_originals=$(echo "$gitignore" | grep -c '\.originals/' || true)
    assert_eq ".gitignore does not exclude .originals/" "0" "$has_originals"
}

test_updater_has_merge_logic() {
    echo "--- update.sh contains three-way merge logic ---"
    local updater
    updater=$(cat "$RALPH_DIR/update.sh")
    assert_contains "update.sh uses git merge-file" "git merge-file" "$updater"
    assert_contains "update.sh references .originals" ".originals" "$updater"
    assert_contains "update.sh reports merged status" "done (merged)" "$updater"
    assert_contains "update.sh reports CONFLICT status" "CONFLICT" "$updater"
}
