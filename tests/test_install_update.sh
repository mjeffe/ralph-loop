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

test_installer_piped_fetches_from_upstream() {
    echo "--- Installer piped into bash fetches upstream files, not the target's (#37) ---"
    # The target repo has its own .gitignore and config; a piped install must not copy them.
    local target="$TMP_DIR/piped_install" bin="$TMP_DIR/piped_install_bin"
    mkdir -p "$target" "$bin"
    git -C "$target" init -q
    printf 'target-ignore\n' > "$target/.gitignore"
    printf 'TARGET_CONFIG=1\n' > "$target/config"
    git -C "$target" add -A
    git -C "$target" -c user.name=t -c user.email=t@t commit -qm init

    # Stub curl serves raw GitHub URLs from this checkout, failing like curl -f (exit 22, no output
    # file) for the path in STUB_CURL_FAIL; stub git answers ls-remote offline.
    cat > "$bin/curl" <<EOF
#!/bin/bash
out="" url=""
while [[ \$# -gt 0 ]]; do case "\$1" in -o) out="\$2"; shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
path="\${url#https://raw.githubusercontent.com/mjeffe/ralph-loop/main/}"
if [[ "\$path" == "\${STUB_CURL_FAIL:-}" ]]; then
    echo "curl: (22) The requested URL returned error: 404" >&2
    exit 22
fi
cp "$RALPH_DIR/\$path" "\$out"
EOF
    printf '#!/bin/bash\necho "abcdef0123456789  HEAD"\n' > "$bin/git"
    chmod +x "$bin/curl" "$bin/git"

    local rc=0
    (cd "$target" && PATH="$bin:$PATH" bash < "$RALPH_DIR/install.sh" >/dev/null) || rc=$?
    assert_eq "piped install exits 0" "0" "$rc"
    assert_eq "piped .gitignore is upstream's" "$(cat "$RALPH_DIR/.gitignore")" "$(cat "$target/.ralph/.gitignore")"
    assert_eq "piped config is upstream's" "$(cat "$RALPH_DIR/config")" "$(cat "$target/.ralph/config")"
    assert_eq "piped .version is upstream HEAD" "abcdef0" "$(cat "$target/.ralph/.version")"

    # A failed download stops the install, names the file, and leaves .ralph/ for inspection.
    rm -rf "$target/.ralph" "$target/AGENTS.md" "$target/specs"
    local output
    rc=0
    output=$(cd "$target" && PATH="$bin:$PATH" STUB_CURL_FAIL=lib/sandbox.sh \
        bash < "$RALPH_DIR/install.sh" 2>&1) || rc=$?
    assert_ne "failed download exits non-zero" "0" "$rc"
    assert_contains "failed download names the URL" \
        "Failed to download https://raw.githubusercontent.com/mjeffe/ralph-loop/main/lib/sandbox.sh" "$output"
    assert_contains "failed download gives cleanup instructions" "rm -rf .ralph" "$output"
    assert_eq "partial .ralph/ is kept" "true" "$( [[ -f "$target/.ralph/ralph" ]] && echo true || echo false )"
    assert_eq "no AGENTS.md after failure" "false" "$( [[ -e "$target/AGENTS.md" ]] && echo true || echo false )"
    assert_eq "no manifest after failure" "false" "$( [[ -e "$target/.ralph/.manifest" ]] && echo true || echo false )"
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

test_updater_clean_merge_records_upstream_checksum() {
    echo "--- update.sh: clean merge records upstream checksum (not merged result) ---"
    # Extract the clean-merge branch (between "merge_rc.*-eq 0" and the "else" for conflicts)
    local clean_branch
    clean_branch=$(sed -n '/merge_rc.*-eq 0/,/^[[:space:]]*else/p' "$RALPH_DIR/update.sh")
    assert_contains "clean merge checksums upstream_tmp" 'compute_checksum "$upstream_tmp"' "$clean_branch"
}
