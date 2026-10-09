# Proposal: Workdir Subdirectory of `.ralph/`

## Status
Proposed — not yet committed.

## Summary

Make a workdir subdirectory of `.ralph/` so work files such as `implementation_plan.md`, `alignment_ledger.md`, `last_agent_output`, etc., do not clutter the project root directory.

## Design

Move transient work files under `.ralph/work/` (or similar). The `ralph` script already knows where `.ralph/` lives. Files that are meant to be read or committed by the user (like the implementation plan) could stay at root or be symlinked.

## Trade-offs

- Cleaner root directory — fewer ralph-internal files mixed with project files.
- Implementation plan currently lives at root for visibility and `git add` convenience. Moving it into `.ralph/` hides it. Symlink or a `ralph plan --output` flag could address this.
- Affects paths referenced in prompts, agent scripts, and the updater manifest.

## Decision Criteria

Implement when the number of work files at root grows beyond what is tolerable. Currently (~5 files) it is manageable.