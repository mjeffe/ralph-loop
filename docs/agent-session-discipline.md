# Agent Session Discipline

My notes on how to keep interactive coding-agent costs down, and achieve better
results, by keeping the session in proportion to the work being done.

## Context

I often fire up an amp session and begin discussing an idea, or researching a
new feature, or debugging an issue, and continue until I'm done, only handing
off to a new session when context reaches given threashold. However, this can
lead to expensive sessions and sometimes thrashing, innacurrate results. This
doc explores a more disciplined approach to managing agent sessions.

## Core Principle

> **Every agent session has a named artifact it is producing, and ends when that artifact exists.**

The expensive agent's job is to produce artifacts, not to think with me.
Thinking is cheap; grounding is what I am paying for.

## Why This Matters

- Each turn re-sends the entire conversation as input. Long sessions cost
  non-linearly even with prompt caching.
- Accumulated tool output (file reads, command logs, search results) lives in
  context forever once it enters.
- The cheap-feeling instinct ("context is already loaded, keep going") is the
  most expensive habit. Late turns are the costly turns.

## Stage Discipline

Most expensive work collapses into one session because the stages feel
continuous. Force the break.

| Stage         | What it needs                          | Right tool                          |
|---------------|----------------------------------------|-------------------------------------|
| **Diverge**   | Breadth, brainstorming, options        | Cheap chat, or me alone             |
| **Ground**    | Real codebase / system access          | Amp (worth the price)               |
| **Specify**   | Write the artifact to disk             | Me, or agent draft + my edit        |
| **Converge**  | Implement, test, verify                | Amp or Ralph                        |

Rule: **never run diverge inside a grounded session.** Brainstorming on top of
loaded codebase context is the most expensive way to think.

## Cost-Inflating Patterns to Avoid

- **Bundled debugging.** Multiple unrelated bugs in one thread. Each new bug
  carries every previous bug's context.
- **Strategy discussion inside grounded sessions.** Option A vs B, library
  tradeoffs, "what about X?" — pure cognition that does not need grounding.
- **Documentation prose inside grounded sessions.** Tech-debt notes, AGENTS.md
  updates, runbook prose. Write these myself from the agent's findings.
- **Context-driven handoffs at 80% full.** Hand off at stage boundaries
  (~60% context), not when forced.
- **Iterative edits of evolving planning docs.** Capture decisions as bullets
  during the session, edit the doc once at the end.
- **Verbose tool output in context.** Redirect to files
  (`composer install > /tmp/install.log 2>&1`), then `tail` / `grep` what
  matters.
- **"While we're here, let's also..."** The single most expensive sentence.

## Workflow: New Feature

| Feature size                                | Pattern                                                   |
|---------------------------------------------|-----------------------------------------------------------|
| Trivially small (1 file, no design choice)  | Same session, keep it short                               |
| Small to moderate (a few files, half-day)   | **Default:** Research session → minimal spec → fresh build session |
| Moderate to large (many files, multi-day)   | Research session → spec → **Ralph** for the build         |
| Strong existing design opinions             | Write the spec myself; agent only confirms facts          |

Default workflow in detail:

1. **Research session (Amp).** Goal: produce a minimal spec.
   - Ask for: goal, approach in 3–5 bullets, files to touch, test strategy,
     non-goals. No background, no rationale.
   - Stop when the spec exists. Do not discuss tradeoffs further.
2. **Edit the spec myself.** Five minutes catches over-specification and
   subtle mistakes. This is the cheapest design-review opportunity.
3. **Build session (fresh Amp, or Ralph if multi-task).** Open with the spec,
   the test command, and nothing else. Do not paste the research conversation.

## Workflow: Multi-Bug Debugging

- **One bug per thread.** Unrelated bugs do not share context productively.
- Each thread ends when its bug is fixed, tested, and committed.
- Update tech-debt / AGENTS.md / runbooks **myself**, after, from commit
  messages.

## Workflow: Exploratory / Architecture / Spec Writing

Where most of my token cost actually goes. Highest leverage for discipline.

1. **Grounding session (Amp).** Ask for a structured artifact (table, list,
   summary). No commentary. No discussion. Stop when artifact exists.
2. **Diverge (cheap chat, or me alone with the artifact).** Think, brainstorm,
   decide.
3. **Re-grounding (Amp, optional).** Only if the discussion raised one
   specific question that needs codebase evidence.
4. **Write the doc myself, in my editor.** Better doc, cheaper, and the act
   of writing is when synthesis happens.

## Quick Checks Before Opening a Session

- [ ] What artifact will this session produce?
- [ ] What is the stop condition?
- [ ] Does this work actually need grounding, or am I just thinking out loud?
- [ ] Could the next thing I'm about to do happen in a cheaper tool?

## Quick Checks During a Session

- [ ] Am I about to say "while we're here, let's also..."? Stop.
- [ ] Am I discussing tradeoffs inside a grounded session? End it, decide elsewhere.
- [ ] Has the artifact already been produced? End the session.
- [ ] Is context above ~60% and approaching a new sub-task? Hand off.

## The Sentence to Internalize

> **Use Amp for shorter, more focused things, more often.**

Not "use Amp less."
