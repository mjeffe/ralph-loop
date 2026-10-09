# Open Questions

This spec captures unresolved questions, speculative ideas, and design
tensions that need more thought or real-world experience before a decision
can be made. Items here are not proposals, not tasks, and not bugs.
They are things the project does not yet know.

Each entry should include what would resolve it (a "resolution criterion").
Remove items when they are resolved — promote to a spec, proposal, or
issue as appropriate.

---

## Monitoring / Watcher Agent

**Question:** Could ralph kick off a parallel "watcher" agent that monitors
the build loop and provides analysis? Example: run `ralph plan`, then use
an interactive session to analyze the plan against specific criteria.
This often surfaces spec changes or things to watch for during the build.

**Context:** This has been done manually — running an interactive agent
alongside a ralph build to analyze what ralph was doing. It was productive
enough to consider making it a first-class capability.

**Resolution criteria:** Prototype it manually a few more times. If the
pattern consistently produces value, write a design proposal.

---

## Context Window Monitoring

**Question:** How can the user monitor the percentage of the agent's
context window used during an iteration?

**Context:** Token usage is tracked in aggregate (session totals), but
there is no per-iteration visibility into how close each iteration
gets to the model's context limit. This makes it hard to know when
an iteration is at risk of context overflow.

**Resolution criteria:** Investigate what agent CLIs expose about
context usage. If the data is available in the NDJSON stream, this
is a feature addition to the agent output pipeline (see
`specs/tech-debt.md` item 3). If not, it goes nowhere.

---

## Token Usage Reduction

**Question:** What patterns or prompt changes would reduce token usage
per iteration? Iterations can get expensive.

**Context:** This is a general concern, not a specific proposal. It
could mean shorter prompts, more aggressive summarization, fewer
files read per iteration, or architectural changes to how state
is passed between iterations.

**Resolution criteria:** Gather data first. Instrument the loop to
report token cost per iteration. Identify the biggest cost drivers,
then propose targeted changes.

---

## TDD Approach

**Question:** Should ralph adopt a test-driven development workflow:
write tests before implementation?

**Context:** The current workflow is implementation-first with test
guidance nudging agents toward coverage where it matters. A TDD
approach would invert this: tasks would include writing failing
tests first, then implementing to make them pass.

**Resolution criteria:** Try TDD on a self-contained feature cycle
and compare outcomes (defect rate, iteration count, time to
completion) against the current workflow.

---

## "Deployable, Functional, and Tested" Mandate

**Question:** Should prompts be modified to say that all tasks must
be deployable, functional, and tested by the end of the build?

**Context:** This would raise the bar for what "done" means per
iteration. Currently, an iteration can complete without tests if
the agent documents why. A mandate would require every task to
produce test coverage and pass deployment checks.

**Resolution criteria:** Evaluate against the test guidance policy
proposal (`specs/proposals/test-guidance-policy.md`). If the
escalation ladder in that policy proves insufficient, a mandate
may be warranted.

---

## Multi-Service vs. Monolithic Sandbox

**Question:** What are the pros and cons of converting the sandbox
from a single monolithic container to a multi-service architecture?

**Context:** The sandbox currently runs as a single container. A
multi-service setup (app container + separate DB, cache, mail
containers) would better reflect real deployment topologies and
allow official Docker images for services, but adds complexity
to the sandbox lifecycle commands and setup prompt.

**Resolution criteria:** This was partially explored in the sandbox
specs. Revisit when someone needs multi-service sandbox support
for a real project.