# Proposal: Sandbox Reset Warnings and Backup

## Status
Proposed — not yet committed.

## Summary

Improve `ralph sandbox reset` confirmation prompts to explicitly warn about data that will be
lost (session logs, uncommitted work, unpushed commits) and optionally offer to back up
`.ralph/logs/` to the host before reset.

## Problem

When the sandbox is rebuilt via `ralph sandbox reset` (or `ralph sandbox reset --all`), the
codebase volume is removed and re-cloned from git. Anything inside the cloned working tree that
is not committed and pushed is silently destroyed. The most painful case is `.ralph/logs/`
(session logs), but the same applies to:

- `.ralph/logs/session-*.log`
- Uncommitted changes in the working tree (agent work-in-progress)
- Unpushed commits on local branches inside the sandbox
- `.ralph/sandbox-setup.md` if the user edited it inside the sandbox and didn't commit
- Any other ad-hoc state the agent or user wrote into the codebase volume

`reset --all` additionally wipes service volumes (database, cache, etc.).

### Current Behavior

`sandbox_reset()` in `lib/sandbox.sh` prompts `Continue? [y/N]`, but the warning only names
the volumes generically:

> This will delete the app codebase volume and re-clone from git.
> Service volumes (database, cache, etc.) will be preserved.

A user reading that wouldn't necessarily realize their session logs (which live under
`.ralph/logs/` inside the codebase volume) are about to disappear.

## Design

### Minimum

1. **Spell out what will be lost** in the confirmation prompt — explicitly call out
   `.ralph/logs/`, uncommitted changes, and unpushed commits as casualties of the codebase-volume
   removal. For `--all`, also mention service-volume data loss (DB contents, etc.).

2. **Detect uncommitted/unpushed work** inside the sandbox before destroying the volume (e.g.,
   `git status --porcelain` and `git log @{u}..` in the app container) and surface it in the
   prompt so the user can bail out and commit first.

### Optional (Nice-to-Have)

3. **Offer to back up `.ralph/logs/` to the host** before reset, and restore it afterward. The
   host already owns `.ralph/sandbox/` next to the cloned codebase, so a backup target like
   `.ralph/sandbox/backups/logs-<timestamp>/` would be natural. Could be opt-in via
   `--backup-logs` or default-on with `--no-backup` to skip.

4. Consider a `--yes`/`-y` flag for scripted use, since adding more detail to the prompt makes
   it longer.

## Acceptance Criteria

- Running `ralph sandbox reset` shows a confirmation prompt that explicitly mentions session
  logs and uncommitted work, not just "the codebase volume."
- Running `ralph sandbox reset --all` additionally warns about service-volume data loss
  (database, etc.).
- If the sandbox app container is reachable, the prompt reports a count of uncommitted files
  and/or unpushed commits.
- Tests in `tests/test_sandbox.sh` cover the new prompt text.
- Specs updated: `specs/sandbox-cli.md` reset section, and any user-facing wording in
  `lib/help/sandbox.txt`.