# Proposal: Improve `ralph update` for Customized Files

## Status
Proposed — not yet committed.

## Summary

The current updater uses manifest checksums to detect user-modified files and drops a `.upstream` file for manual diff/merge. This is safe but tedious once users customize prompts (the common case).

## Design Options

### Option 1: Three-Way Merge (Recommended — Implement First)

Store the **original upstream version** at install/update time (e.g., `.ralph/.originals/prompts/build.md`). On update, perform a three-way merge using `git merge-file`:

- **base** = upstream version the user started from (`.originals/`)
- **theirs** = new upstream version (fetched)
- **ours** = user's current file

If `git merge-file` succeeds cleanly, apply the result. If there are conflicts, write the conflict-marked file and inform the user. This resolves most updates automatically since user changes and upstream changes usually touch different sections.

### Option 2: Agent-Assisted Merge

When `git merge-file` produces conflicts (or as an opt-in for all modified files), invoke the configured agent with a merge prompt: provide the user's version, the new upstream version, and the original base, and ask the agent to merge upstream improvements while preserving user customizations. Offer as `ralph update --agent-merge`. Powerful but expensive — best as a complement to Option 1 for unresolved conflicts.

### Option 3: Structured Prompts with User Override Sections

Redesign prompts with clearly delimited extension points (`<!-- USER CUSTOMIZATIONS BELOW -->`). The updater replaces everything outside those markers and preserves what's inside. Constrains where users can customize but makes updates trivial for common cases.

### Option 4: Layered Prompts (Composition over Modification)

Split prompts into `base` (upstream-managed, always overwritten) and `overrides` (user-owned, never touched). At runtime, ralph concatenates them. Users never edit the base files. Updates become zero-friction since base files are always safe to overwrite. Requires restructuring prompts and changing user habits.

## Decision Criteria

Start with Option 1. It is a drop-in improvement to the current flow with no user-facing behavior change except fewer manual merges. Options 3 and 4 are more invasive (they change how users interact with prompt files) and should only be considered if Option 1 + Option 2 still leave too much merge friction.