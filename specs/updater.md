# Ralph Updater

## Overview

The Ralph updater brings an existing `.ralph/` installation up to date with the latest upstream
ralph-loop repository while preserving user customizations. It uses a manifest of checksums to
detect which files the user has modified and avoids overwriting them.

## Update Method

```bash
# Direct invocation
.ralph/ralph update

# Or via symlink
./ralph update
```

The `update` mode in the ralph script fetches and executes a remote update script from the
ralph-loop repository:

```bash
curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/update.sh | bash
```

This ensures the update logic is always current — the local ralph script only needs to know
how to fetch and run it.

## Version Tracking

Ralph tracks the upstream commit it was installed or last updated from using a git commit hash
stored in `.ralph/.version`.

```
# Example .ralph/.version
a3f7b2c
```

The version is the short git commit hash from the ralph-loop repository at the time of install
or update. This is used to detect whether a newer version is available.

## Manifest

The manifest (`.ralph/.manifest`) records SHA256 checksums of all installed files as they were
originally written by the installer or updater. This is the mechanism for detecting user
customizations.

```
# Example .ralph/.manifest
e3b0c44298fc1c14...  ralph
a1b2c3d4e5f6a7b8...  config
c7d6e5f4a3b2c1d0...  agents/amp.sh
f9e8d7c6b5a4f3e2...  prompts/plan.md
d4c3b2a1e5f6d7c8...  prompts/build.md
b5a4c3d2e1f0a9b8...  README.md
```

Paths in the manifest are relative to `.ralph/`.

## File Classification

Files in `.ralph/` fall into three categories that determine update behavior:

| Category | Files | Update Behavior |
|----------|-------|-----------------|
| **Core** | `ralph`, `README.md`, `.gitignore`, `agents/*.sh` | Update unless user modified |
| **Customizable** | `config`, `prompts/plan.md`, `prompts/build.md` | Update unless user modified |
| **Project state** | `implementation_plan.md`, `logs/` | Never touched |

All core and customizable files are tracked in the manifest and follow the same checksum-based
update logic. The distinction is conceptual — core files are unlikely to be modified, while
customizable files frequently are.

Project state files are never listed in the manifest and are never touched by the updater.

## Update Behavior

### Pre-update Checks

1. **Verify `.ralph/` exists** — if not, advise the user to run the installer instead
2. **Verify git repository** — `.git/` directory must exist
3. **Check network access** — must be able to reach GitHub
4. **Determine current version** — read `.ralph/.version` (may not exist for pre-manifest installs)
5. **Determine latest version** — query the ralph-loop repository for the latest commit hash
6. **Compare versions** — if already up to date, report and exit

### Update Logic

For each file that would be installed (same file list as `install.sh`):

1. **Compute current checksum** of the file on disk
2. **Look up original checksum** from `.ralph/.manifest`
3. **Compare:**
   - **Checksums match** → user has not modified the file → overwrite with new version
   - **Checksums differ** → user has customized the file → preserve user's version, write
     the new upstream version as `<file>.upstream` for manual review
   - **File missing from manifest** (pre-manifest install) → treat as modified (safe default)
   - **File does not exist on disk** (deleted by user) → skip, do not recreate
4. **New upstream files** that did not exist in the previous version are added normally

### Post-update

1. **Update `.ralph/.manifest`** with checksums of all files as written (for overwritten files,
   the new checksum; for preserved files, keep the existing manifest entry)
2. **Update `.ralph/.version`** with the new commit hash
3. **Display summary** of what was updated, skipped, and any `.upstream` files to review

### Files Outside `.ralph/`

The updater **never touches** files outside `.ralph/`:
- `specs/` — project-specific, never modified
- `AGENTS.md` — project-specific, never modified
- Any other project files

This matches the installer's additive-only policy for files outside `.ralph/`.

## User-Facing Output

### Up to date

```
Ralph is already up to date (a3f7b2c).
```

### Successful update

```
Updating Ralph...
Current: a3f7b2c
Latest:  e91d4f0

Updating ralph.............. done
Updating README.md.......... done
Updating config............. SKIPPED (locally modified)
  → New version saved as .ralph/config.upstream
Updating prompts/plan.md.... done
Updating prompts/build.md... SKIPPED (locally modified)
  → New version saved as .ralph/prompts/build.md.upstream

Updated to e91d4f0.
Review .upstream files for changes you may want to merge.
```

### Pre-manifest install (first update)

```
Updating Ralph...
No manifest found — treating all customizable files as modified (safe default).

Updating ralph.............. done
Updating README.md.......... done
Updating config............. SKIPPED (no manifest; assuming modified)
  → New version saved as .ralph/config.upstream
Updating prompts/plan.md.... SKIPPED (no manifest; assuming modified)
  → New version saved as .ralph/prompts/plan.md.upstream
Updating prompts/build.md... SKIPPED (no manifest; assuming modified)
  → New version saved as .ralph/prompts/build.md.upstream

Updated to e91d4f0.
Manifest created. Future updates will detect modifications automatically.
Review .upstream files for changes you may want to merge.
```

## Upstream Files

When a file is skipped due to user modifications, the new upstream version is saved alongside
it with an `.upstream` suffix:

```
.ralph/config              ← user's customized version (preserved)
.ralph/config.upstream     ← new upstream version (for review)
```

The user can then:
- **Diff** the two files to see what changed upstream
- **Merge** upstream changes into their customized version
- **Delete** the `.upstream` file when done

`.upstream` files should be added to `.ralph/.gitignore` so they are not committed to the
parent project.

## Edge Cases

### Pre-manifest Install

Installations made before the manifest feature was added will not have `.ralph/.version` or
`.ralph/.manifest`. On first update:

- Treat all core and customizable files as "modified" (do not overwrite)
- Write `.upstream` files for everything
- Create the manifest and version file
- Future updates will work normally

### Files Removed Upstream

If a file existed in the previous version but is no longer part of Ralph:

- Leave the file in place
- Warn the user: `"<file> is no longer part of Ralph and can be removed"`

### Files Deleted by User

If a file tracked in the manifest has been deleted by the user:

- Do not recreate it
- Log: `"Skipping <file> (deleted locally)"`

### Network Failure

If the update script cannot reach GitHub:

- Exit with a clear error message
- Do not modify any files
- Exit code 1

## Error Handling

- Missing `.ralph/` directory → exit with message: "Ralph is not installed. Run the installer."
- Missing `.git/` directory → exit with message: "Not a git repository."
- Network failure → exit with message: "Cannot reach GitHub. Check your network connection."
- All errors exit with non-zero code and clear message
- No files are modified until all new versions have been successfully fetched

## Changes to Existing Files

### install.sh

The installer must be updated to:
1. Generate `.ralph/.version` with the current commit hash at install time
2. Generate `.ralph/.manifest` with SHA256 checksums of all installed files

### ralph

The ralph script must be updated to:
1. Accept `update` as a mode
2. Fetch and execute the remote `update.sh` script

### .ralph/.gitignore

Add `*.upstream` pattern to exclude upstream review files from git.

## New Files

### update.sh

A new script at the root of the ralph-loop repository (alongside `install.sh`) containing the
update logic. Fetched and executed at runtime by `ralph update`.

## Update Script Location

The update script lives at the root of the ralph-loop repository:
```
update.sh
```

Accessible via GitHub raw URL:
```
https://raw.githubusercontent.com/mjeffe/ralph-loop/main/update.sh
```
