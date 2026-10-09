# Proposal: Test Guidance Policy

## Status
Proposed — not yet committed.

## Summary

Current policy in `prompts/build.md` step 7 nudges agents toward coverage where it matters most (bug fixes, behavior changes) while avoiding ritualized test-writing for low-value cases. Agents document meaningful skipped coverage in the implementation plan.

This proposal defines an escalation path for tightening the policy if agents repeatedly skip easy, high-value tests.

## Design

### Current State (Baseline)

The prompt already encourages testing where it matters, with documentation of skipped coverage.

### Escalation Step 1: Strengthen Critical Rules

If agents repeatedly skip easy, high-value tests, tighten by adding to build.md "Critical Rules":

> Add or update targeted tests when your change affects behavior or fixes a bug, unless a reliable test would be disproportionately costly; document meaningful skipped coverage in the plan.

### Escalation Step 2: Explicit Heuristics

If Step 1 is not enough, escalate to explicit heuristics:

- Bug fix → regression test expected unless impractical
- Behavior change → update or add tests
- Pure refactor / dead code removal → tests optional

## Failure Modes to Watch For

- Bug fixes shipping without regression tests
- Agents repeatedly skipping easy, high-value tests
- Refactors causing regressions in under-tested areas
- Lots of plan notes about skipped coverage with no follow-up

## Decision Criteria

Monitor the failure modes above across several build cycles. If any pattern emerges consistently, escalate one step at a time. Do not jump to Step 2 before trying Step 1 — each escalation tightens agent constraints and may reduce flexibility in legitimate edge cases.