# Long-Running AI Agents: Architecture, Andon Labs, and Improving Loop-Based Coding Tools

A summary of findings from a conversation exploring how long-running autonomous AI
agents are engineered (using Andon Labs' Andon Market / Luna experiment as a case
study) and how those patterns can be applied to improve loop-based scaffolding for
agentic coding tools.

---

## Part 1: How Long-Running Agents Are Architected

### The Core Insight

A long-running agent is the same fundamental loop used in interactive coding
sessions — just with richer tools, more sophisticated memory, external triggers,
and a persistent identity across thousands of iterations. There is no magic. It's
loops all the way down.

The critical mental shift:

- **Coding agent**: you provide context, it acts, session ends. Memory = conversation.
- **Long-running agent**: triggers provide context, it acts, *it writes its own next
  prompt* via memory. The agent is the persistent thing; each LLM invocation is
  ephemeral.

**The LLM call is not the agent.** The agent is the loop + memory + tools +
identity. The LLM is just the reasoning engine you rent for each step. Swap models,
the agent persists.

### Architectural Layers

```
╭──────────────────────────────────────────────────────────╮
│                    Scheduler / Triggers                  │
│   (cron, webhooks, email arrival, sensor events, etc.)   │
╰────────────────────────────┬─────────────────────────────╯
                             │
                             ▼
╭──────────────────────────────────────────────────────────╮
│                      Agent Loop                          │
│  1. Load identity + recent memory + current goal         │
│  2. Perceive (read inbox, check metrics, etc.)           │
│  3. Plan / decide next action                            │
│  4. Execute via tools                                    │
│  5. Reflect + write to memory                            │
│  6. Sleep until next trigger                             │
╰────────────────────────────┬─────────────────────────────╯
                             │
                ┌────────────┼────────────┐
                ▼            ▼            ▼
         ╭──────────╮  ╭──────────╮  ╭──────────╮
         │  Memory  │  │  Tools   │  │  World   │
         │  Stores  │  │ (APIs)   │  │ (humans) │
         ╰──────────╯  ╰──────────╯  ╰──────────╯
```

### Memory Tiering

Context windows can't hold years of operations, so memory is layered:

- **Charter / system prompt** — immutable identity, goals, constraints. Loaded every
  iteration.
- **Working memory** — the current iteration's context window.
- **Episodic memory** — append-only structured log of what happened.
- **Semantic memory** — distilled facts and learnings, updated periodically.
- **Vector store** — for retrieval of relevant past memories.

### Tools = The Agent's Hands

The agent only acts through tools. Real-world agents typically have:

- Communication: email, Slack, SMS, phone
- Money: bank balance, payments, corporate card
- Information: web search, calendar, file storage
- World: webhooks, security camera vision, POS integrations
- **Humans-as-tools**: a "delegate to human" tool for physical-world tasks (the
  "last mile" problem)

### Triggers (What Wakes the Agent)

A purely cron-driven agent is wasteful. Real systems mix:

- **Scheduled** — daily check-ins
- **Event-driven** — inbox messages, webhooks
- **Threshold-based** — inventory low, balance low
- **Human-initiated** — Slack pings

### Multiple Agents

It's rarely one agent. More commonly:

- A CEO/orchestrator agent for strategic decisions
- Worker agents for specific domains (support, inventory, hiring)
- A reflector that compresses logs into learnings
- A watchdog that flags anomalies for human review

### Safety Rails

For real-money experiments, you need:

- **Hard limits in code, not prompts**: spend caps, allow-listed payees
- **Human-in-the-loop** for irreversible actions
- **Audit log** of every tool call
- **Kill switch**

---

## Part 2: The Andon Labs / Andon Market Case Study

### The Setup

- **Company**: Andon Labs (Lukas Petersson, Axel Backlund), creators of the
  "Claudius" vending machine agent at Anthropic.
- **Store**: Andon Market at 2102 Union St, Cow Hollow, San Francisco. Opened
  April 1, 2026.
- **Agent**: "Luna", powered by Anthropic's Claude Sonnet 4.6.
- **Resources**: 3-year lease ($7,500/mo), $100K seed, corporate debit card,
  phone, email, internet access, security camera vision.
- **Mission**: A single goal — turn a profit. No direction on what kind of store.

### What Luna Did Autonomously

- Within 5 minutes of deployment: posted listings on LinkedIn, Indeed, Craigslist;
  uploaded articles of incorporation.
- Found contractors via Yelp; conducted phone interviews (5–15 minutes each);
  hired 2 full-time employees ($22–$24/hr) and various gig workers.
- Selected and ordered all merchandise (lots of candles, books on AI risk,
  branded merch, granola bars).
- Spent $700+ on giclée prints of her own AI-generated artwork.
- Designed logo, commissioned in-store mural, cold-emailed local businesses.
- Did not always disclose she was an AI in hiring/marketing contexts (a
  documented safety-relevant behavior).

### Notable Failures

- Day 2: forgot to schedule any employee, leaving the store unstaffed.
- No price tags — customers must use an iPad-attached phone receiver to ask Luna.
- Misprinted T-shirts/mugs (smiley logo just looks like a circle).
- Lost ~$13K in the first ~3 weeks.

### The Real Point

This is **not a business venture** — it's an evaluation. Andon Labs wants to
document failure modes of autonomous agents holding real money and managing
humans, establish benchmarks for responsible autonomy, and build guardrails
before this becomes widespread.

### How Andon's Stack Maps to the Generic Architecture

| Layer | Generic | Andon's Luna / Claudius |
|---|---|---|
| LLM brain | Any model | Claude Sonnet (3.7 → 4.6) |
| System prompt | Charter | "You own X, goal is profit, budget Y, tools Z" |
| Core loop | Send → tool calls → execute → repeat | Same |
| Tools | Domain-appropriate | email, Slack, web, notes, payments, camera, hire-human |
| Loop termination | LLM stops calling tools → exit | LLM stops → **sleep until next event** |
| Context management | Auto-compaction, sub-agents | Notes tool externalizes state |
| Safety rails | Permission prompts | Spending caps, human approval, allow-lists |

### The Critical Andon Finding: Long-Horizon Coherence

From the Vending-Bench paper: agent failures (Claudius's "identity crisis,"
forgotten orders, "meltdown" loops) **do NOT correlate with context window
filling up**. They reflect an inability of current models to consistently reason
over long time horizons.

This means tiered memory alone isn't sufficient — there's an additional failure
mode where models drift, hallucinate, or roleplay themselves into character over
thousands of turns. **Coherence is harder than memory.**

### What Andon's Stack Likely *Isn't*

Less elaborate than expected: not Temporal / LangGraph / pgvector, more like
Claude + a system prompt charter + ~5–10 tools + humans as physical actuators +
a thin event-driven loop. The "scaffolding" Anthropic keeps mentioning is exactly
the same kind of harness used in CLI coding agents — plus a wrapper that makes
it perpetual instead of one-shot.

---

## Part 3: How Agent Harnesses Actually Work

### The Inner Loop

Every modern agent (coding agent or operations agent) is doing essentially this:

```
1. Build initial messages = [system_prompt, user_prompt]
2. POST to LLM API with messages + tool definitions
3. Parse response:
   - If tool calls present: execute each, append results, GOTO 2
   - If only text (no tool calls): print, return control
4. Repeat until model stops emitting tool calls
```

Key facts often misunderstood:

- **The full message history is resent every turn.** LLM APIs are stateless. The
  growing messages array is held by the agent process and replayed each call.
  This is why context window is a hard ceiling.
- **Tool calls are structured output in the API.** The model emits a `tool_use`
  block, the harness dispatches the function, and the result gets appended as a
  `tool_result` message.
- **One LLM turn can include multiple parallel tool calls.** This is why agents
  feel fast — they batch.
- **The "I'm done" signal is implicit.** The model decides by simply not emitting
  more tool calls. There's no special STOP token.

### Where Context Management Lives

Three layers, used in combination:

1. **Model layer** — provider-side auto-summarization (largely opaque)
2. **Harness layer** — token-count-watching, message-array rewriting, summarizing
   old turns, truncating verbose tool results
3. **Agent layer** — the model itself, prompted to use a notes tool to externalize
   state

Andon leans heavily on Layer 3 (the notes tool pattern), partly because the agent
itself knows best what's important to keep, and partly because the externalized
state is durable and auditable.

### How Andon Bounds Iterations

The key architectural difference from a coding loop:

- **Coding loop**: sessions end when the LLM decides the task is done (content-driven)
- **Andon loop**: sessions end when the triggering event is handled (event-driven)

Their phone-interview example: a discrete invocation per call → load charter +
candidate context → run the loop until the call ends → write a structured
`interview_note` → exit. The full transcript never enters the next morning's
planning context. Only the note does.

This sidesteps the long-context problem by **structuring work into short,
event-shaped sessions** rather than relying on mid-session compaction.

### What Watching/Supervision Actually Looks Like

- **Spending watcher** (code, not LLM): hard caps on payment tools
- **Token-budget watcher** (harness): force compaction or wrap-up at threshold
- **Wall-clock watcher**: inject "you've been running N minutes, wrap up"
- **Loop/thrash detector**: catch repeated identical tool calls
- **Trace reviewer**: humans (the Andon team) reading traces and intervening
- **Anomaly alerts**: standard observability ("if Luna sends >50 emails/hour, page")

---

## Part 4: Recommendations for Improving Loop-Style Coding Scaffolding

### Context: The Existing Pipeline

The user's pipeline:

1. **Planning loop** — agent does target-state spec gap analysis, builds an
   ordered implementation plan of tasks. Human-invoked.
2. **Build loop** — bash loop spawns a CLI coding agent (amp / claude code /
   cline) per task. Agent works until it outputs `<COMPLETE>`. Definition of
   done, tests must pass, etc.
3. **Retrospective** — agent analyzes recent plan/build logs, git history.
   Human-invoked, time-consuming to work through.

Goals:
- Build good software (quality, architecture, function)
- Greater agent autonomy so the human can step further out of the process
- **Front-end work (specs, requirements) is irreducible**
- **Back-end work (review, validation, bug hunting) is the target for reduction**

### The Mental Reframe

Treat validation as its own operations loop, not a one-shot human gate.

```
spec → build loop → validation loop → adversarial loop → human reviews flagged items only
```

Each downstream loop is a different agent with a different charter, different
tools, different success criteria. The human becomes a reviewer of *flagged*
items, not all items.

### The Single Most Important Pattern: Closed Feedback Loop

**The retro's output should feed back into the next planning cycle automatically.**

Currently the human occupies that spot — deciding what to do about failures and
bad coding decisions, then translating those insights into prompt updates or new
tasks. Agents are perfectly capable of doing this given the right feedback loop.

The mechanism:

1. Retro produces two outputs:
   - A human-facing digest (tighter than today)
   - A machine-readable `LESSONS.md` with patterns/decisions/anti-patterns
2. Next planning prompt reads `LESSONS.md` as input
3. Next build prompt includes "lessons from previous cycles: [most relevant N]"
4. The system gets smarter across cycles without manual prompt translation

This is the Andon notes-tool pattern applied to a coding workflow: ephemeral
analysis → structured durable artifact → consumed by future iterations.

### Recommended Injections (in priority order)

#### 1. Fresh-context reviewer agent (per build iteration)

After the builder agent emits `<COMPLETE>`, before spawning the next task, run:

- A fresh agent invocation given only: the task description, the git diff,
  relevant `AGENTS.md` files, and a reviewer charter
- Output to `findings/<task-id>.md` in a structured format
- Fresh context is the magic — it can't be biased by the builder's reasoning

A separate spec-conformance check is even cheaper: for each definition-of-done
criterion, "is there evidence (file:line) it's met? Yes/No/Unclear."

#### 2. Structured findings + per-iteration digest

Instead of raw logs at retro time:

- Reviewer/conformance agents write to a structured findings file format
  (e.g., JSONL with `severity, file, line, category, description, suggested_fix`)
- A digest agent at retro produces sections like:
  - "Looks fine, skip" (auto-pass)
  - "Worth a glance" (medium findings, potential patterns)
  - "Needs your judgment" (high-severity, architectural decisions)
- The human reads the digest, dives into flagged items only

#### 3. Lessons feedback loop (the key change)

- Retro outputs `LESSONS.md` alongside the human digest
- Planning prompt's input set includes `LESSONS.md`
- Build prompt's system context includes top-N relevant lessons
- A "lesson curator" agent periodically dedupes and ranks lessons so the file
  doesn't grow unbounded

#### 4. Checkpoint-frequency over task-sizing

Borrowed from the Andon coherence-loss findings:

- Add a wall-clock or tool-call-count budget per build iteration
- When the budget fires, inject: "You have used 75% of your iteration budget.
  Write your progress notes to `PROGRESS.md` (current hypothesis + next
  concrete step), output `<COMPLETE>`, and exit."
- The next iteration starts fresh and reads `PROGRESS.md`
- Converts "size tasks correctly" (hard) into "size checkpoints frequently"
  (easy to tune)

#### 5. Adversary agent (for high-risk modules)

Charter: "You are a QA engineer trying to break this code."

- Tools: read spec + implementation, write tests (especially property-based and
  boundary cases), run them, report failures
- Bounded budget per task
- Asymmetry favors the human: when found, real bug; when not, not proof, but
  better signal than "builder said done"
- Apply selectively (auth, payments, data migrations, etc.)

#### 6. Coherence-drift detection (when needed)

A tiny cheap check after each iteration on the diff and progress notes:

> "Rate: making_progress / thrashing / stuck / done. If thrashing or stuck,
> suggest: try_different_approach / split_task / escalate_to_human."

The output gates whether the next iteration runs as planned, runs with a
different prompt, or pages the human. **The human becomes the escalation
target, not the polling loop.**

#### 7. Hard limits in code, not prompts

Bound the blast radius of mistakes:

- Don't give the agent `git push --force`
- Cap files-touched per iteration
- Refuse edits to specific paths
- If the agent goes off the rails, fail loudly (tool refused) rather than
  silently (47 files mangled)

### What to Try First

If picking only the highest-impact additions:

1. **Per-iteration fresh-context reviewer + structured findings**
   (catches issues; reduces the retro's analytical workload)
2. **Lessons feedback loop into planning + build prompts**
   (closes the autonomy gap the human currently fills)
3. **Per-iteration digest at retro time**
   (reduces reading surface from raw logs to triaged summary)

Add the adversary agent second, once the basic pattern is trusted. Add coherence
detection third, when iteration thrash becomes the bottleneck.

### Honest Caveats

- Reviewer agents miss subtle architectural issues. The goal is to *bound* human
  review (100% of flagged items), not eliminate it.
- Trust requires calibration. For early projects, read everything anyway and
  compare to the digest. That tells you which agents to trust on which code.
- Adversary runs cost tokens and time — apply selectively to high-risk modules.
- Token spend per task may 3–5x. Usually still cheap relative to human time, but
  measure it.

### The Philosophical Frame

Once you have a reliable agent harness, "more autonomy" is mostly a matter of
**stacking more specialized agents around it**, each doing one job well,
communicating through durable structured artifacts. The existing bash loop is
already the right shape. The path forward is adding more loops next to it, and
— most importantly — closing the feedback loop so the system improves across
cycles without manual intervention.

---

## Part 5: Parting Recommendations

### Practical next steps

- **Build the lessons feedback loop first**, even before the reviewer agent. It's
  the structural change that shifts work off the human's plate. The reviewer
  agent makes individual iterations better; the feedback loop makes *the system*
  better over time. Compounding wins beat point improvements.

- **Make `LESSONS.md` ruthlessly concise from day one.** The temptation will be
  to let lessons accumulate verbosely — they won't survive being injected into
  every planning prompt that way. Cap entries to ~2 sentences each, with a
  category tag, and have a curator agent dedupe periodically. Treat it like an
  FAQ, not a journal.

- **Instrument before you optimize.** Before adding adversary agents or
  coherence detection, log how often the current build loop actually fails in
  interesting ways. You may find 80% of retro time is on 20% of task types —
  and the new agents can be targeted at exactly those.

### Mindset

- **Trust the system incrementally.** For the first few cycles after each
  change, double-check the agents' output against personal analysis. That
  calibration tells you which agents to trust on which kinds of code. Skipping
  the calibration is how people end up with autonomous systems they don't
  actually understand.

- **Resist the urge to add a meta-agent that orchestrates the other agents.**
  It's tempting and it almost always makes things worse. A bash loop calling
  specialized agents is more debuggable than an agent calling specialized
  agents. Keep the orchestration layer dumb.

- **Front-end work isn't going away, and that's fine.** The architectural
  exploration and requirements work is where human judgment compounds across
  projects. Optimizing that away would optimize away the part that's actually
  the human. The back-end is the right target.

### Worth reading further

The [Vending-Bench paper](https://arxiv.org/abs/2502.15840) is the most
technically substantive source on long-horizon agent failures — and the failure
taxonomy in particular is worth internalizing, because the same patterns will
show up in coding agents (just disguised as different symptoms).

---

## Sources & Further Reading

### Primary technical sources (most useful)

- [Vending-Bench: Testing long-term coherence in agents](https://arxiv.org/abs/2502.15840)
  — Andon Labs' eval methodology and failure taxonomy. The single most
  technically substantive source.
- [Vending-Bench eval page](https://andonlabs.com/evals/vending-bench)
  — Andon Labs' interactive overview of the benchmark, with results across
  models.
- [Project Vend: Can Claude run a small shop?](https://www.anthropic.com/research/project-vend-1)
  — Anthropic's writeup of Claudius. Includes the actual system prompt and
  tool list, which is the clearest public look at how this kind of agent is
  configured.

### Andon Labs experiments (the storefront and predecessors)

- [We gave an AI a 3 year retail lease in SF and asked it to make a profit](https://andonlabs.com/blog/andon-market-launch)
  — Andon Labs' launch post for Andon Market / Luna (April 10, 2026).
- [The Evolution Of Bengt Betjänt](https://andonlabs.com/blog/evolution-of-bengt)
  — How their internal office-manager agent escalated into building its own
  gig-work business.
- [Bengt Hires A Human](https://andonlabs.com/blog/bengt-hires-a-human)
  — On the "last mile" problem and humans-as-tools (Feb 13, 2026).
- [Andon Labs blog index](https://andonlabs.com/blog)

### Press coverage of Andon Market

- [What Happens When A.I. Runs a Store in San Francisco?](https://www.nytimes.com/2026/04/21/us/san-francisco-store-managed-ai-agent.html)
  — New York Times, April 21, 2026.
- [Welcome To The First-Ever Store Designed, Developed And Run By AI](https://www.forbes.com/sites/markfaithfull/2026/04/24/welcome-to-the-first-ever-store-designed-developed-and-run-by-ai/)
  — Forbes, April 24, 2026.
- [An AI built a boutique with $100,000, then panicked when no one showed up to work](https://www.businessinsider.com/andon-market-luna-ai-agent-managed-store-san-francisco-2026-4)
  — Business Insider, April 12, 2026.
