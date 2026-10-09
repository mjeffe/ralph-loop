# Proposal: Scoped Process Planning

## Status
Proposed — not yet committed.

## Summary

Allow focusing `ralph plan --process` on a single process spec file, ignoring others.

## Design

Two changes recommended:

### 1. Scoping via Shell, Not Prompt

Copy the specified file into a temp dir, point `PROCESS_DIR` at it. The prompt runs unmodified — zero new branching. Inject the original command into `Plan Command:` via a template variable so regeneration knows what was scoped.

### 2. Split `plan-process.md` by Volume (Option A)

The prompt already has 6 decision points; adding scoping would push it to ~9 interacting branches. Split into:

- `plan-process.md` — small / single-iteration
- `plan-process-incremental.md` — large / skeleton-first

The shell already computes the volume hint, so it can select the right prompt with no new detection logic. Accept the duplication of shared reference sections (Task Sizing, Discovered Work, Conflicts, etc.) rather than using partial templates — partials add indirection that makes it harder for agents working on ralph-loop to understand and modify the prompts.

Add a sync comment at the top of each file to keep them in alignment.

## Related

- `specs/process-planning.md`
- `specs/incremental-planning.md`