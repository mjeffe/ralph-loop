# Proposal: Promote Retro Adhocs to `ralph retro`

## Status
Proposed — not yet committed.

## Summary

The retro workflow is shipped as ad-hoc prompts:

- `ralph prompt .ralph/prompts/adhoc-retro-analyze.md` — produces a structured retro report at `.ralph/retro-report.md`
- `ralph prompt .ralph/prompts/adhoc-retro-feedback.md` — sanitizes the report into `.ralph/retro-feedback.md` for sharing as a ralph-loop GitHub issue
- An interactive discussion prompt in `lib/help/retro.txt` for stage 2

Once there is enough real-world experience with this workflow, consider promoting it to a formal top-level command. This would be a purely mechanical change to invocation — the underlying prompts and behavior stay the same.

## Design

Possible CLI shape (mirrors `ralph plan` / `ralph plan --process`):

- `ralph retro` → invokes the analyze prompt
- `ralph retro --feedback` → invokes the feedback prompt
- `ralph help retro` → already covers the full three-stage workflow

## Trade-offs

**Pros:**
- Discoverability: `ralph --help` lists it next to plan/build/align-specs
- Shorter to type than the full adhoc path
- Conceptually elevates retro to a first-class capability

**Cons:**
- Adds another top-level command to maintain
- Demotes "adhoc prompts as first-class workflows" — currently the retro adhocs are the most polished example of that pattern
- Forces a choice on the `--feedback` flag shape; alternatives (e.g., `ralph retro feedback` as a subcommand) each carry their own trade-offs

## Decision Criteria

Decide after using the adhoc workflow on several real plan+build cycles. If the bare `ralph prompt .ralph/prompts/adhoc-retro-analyze.md` invocation feels like friction, promote. If it feels fine, leave it alone — the adhoc form already works.