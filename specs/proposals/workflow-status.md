# Proposal: Workflow Status Awareness (`ralph status`)

## Status
Proposed — not yet committed.

## Summary

Add a `ralph status` command that surfaces where the user is in the current workflow and suggests the next step. Ralph already has the information (plan type, task statuses, process dir configuration) — it just doesn't present it as workflow guidance.

## Design

Example output:

```
Mode: process
Plan: complete (42 tasks)
Build: 38/42 complete, 4 planned
Next: ralph build 4
After build: ralph align-specs
```

This would benefit all modes, not just process workflows. Non-prescriptive — it shows state and suggests, does not automate.

## Trade-offs

- Adds a top-level command for information that is partly derivable from `git log`, `cat implementation_plan.md`, and `ralph --help`.
- The value is in reducing cognitive load: the user does not need to remember what mode they are in or what step comes next after repeated interruptions.
- Risk of becoming stale if not maintained as new modes and workflows are added.

## Decision Criteria

Implement when workflow complexity (multiple modes, long-running process cycles) makes it hard to remember state between sessions. Low implementation cost — mostly reading existing state files and printing a summary.