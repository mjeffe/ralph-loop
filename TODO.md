# TODO

This doc is primarily for the humans. It is an active doc to keep current
thoughs, reminders, ideas, things to watch for, etc.

## List of Items to Implement

- How can I monitor/track the % of context window used during an iteration?
- how can we reduce token usage. These iterations can get expensive
- tdd approach: write tests before implementation?
- need to modify prompts to say all tasks should be deployable, functional, and tested?
- analyze current ralph implementation, think of it as a prototype, suggest what
  we would do to create a production version. What needs to be cleaned up, what
  would be a more appropriate programming language than bash, what should be
  modularized, etc.

## Test Guidance Policy (prompts/build.md step 7)

Current policy nudges agents toward coverage where it matters most (bug fixes,
behavior changes) while avoiding ritualized test-writing for low-value cases.
Agents document meaningful skipped coverage in the implementation plan.

**If agents repeatedly skip easy, high-value tests**, tighten by adding to
build.md "Critical Rules":

> Add or update targeted tests when your change affects behavior or fixes a bug,
> unless a reliable test would be disproportionately costly; document meaningful
> skipped coverage in the plan.

**If that's still not enough**, escalate to explicit heuristics:

- Bug fix → regression test expected unless impractical
- Behavior change → update or add tests
- Pure refactor / dead code removal → tests optional

**Watch for these failure modes:**

- Bug fixes shipping without regression tests
- Agents repeatedly skipping easy, high-value tests
- Refactors causing regressions in under-tested areas
- Lots of plan notes about skipped coverage with no follow-up

