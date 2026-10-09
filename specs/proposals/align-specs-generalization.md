# Proposal: Generalize `ralph align-specs` with `--process` Flag

## Status
Proposed — not yet committed.

## Summary

Today `ralph align-specs` only handles post-process-cycle alignment using the decomposition ledger. But spec/code drift also accumulates from interactive sessions, ad-hoc edits, and `ralph prompt` runs that bypass the planner — and there is no equivalent reconciliation pass for those.

Refactor to follow the `ralph plan` / `ralph plan --process` pattern.

## Design

| Today | Proposed |
|---|---|
| `ralph align-specs` (only mode, post-process-cycle) | `ralph align-specs` — **NEW**: general spec/code drift reconciliation (interactive sessions, ad-hoc edits, anything that bypasses the planner) |
| — | `ralph align-specs --process` — current behavior (post-process-cycle alignment using the decomposition ledger) |

### Implementation Outline

1. Move existing `prompts/align-specs.md` → `prompts/align-specs-process.md`.
2. Create new `prompts/align-specs.md` (general drift) — substantive design work: survey recent changes, identify which specs they touch, update specs to match reality, flag conflicts.
3. Update `ralph` dispatcher to select template by flag.
4. Update `specs/align-specs.md` to document both modes.
5. Update `lib/help/align-specs.txt`.
6. Update `install.sh` / `update.sh` MANAGED_FILES.
7. Update tests.

## Trade-offs

- **Breaking change:** `ralph align-specs` today means "align after process cycle"; after the change, it means "align after general drift." Anyone with muscle memory or scripts using the bare command needs to add `--process`.
- **Why not an adhoc instead:** Spec/code alignment is a core ralph capability (same category as plan/build/sandbox), not a user-defined workflow. Pushing it to an adhoc demotes it conceptually and loses help-system integration.

## Decision Criteria

The new general-drift prompt is the hard part — worth its own design pass before implementation. Implement when the need for general drift reconciliation is felt in practice.