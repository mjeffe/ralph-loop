# Ralph Wiggum Loop — Usage & Best Practices Guide

This guide helps you get the most out of Ralph by addressing the common workflow
bottleneck: you spend weeks writing specs, one day building, and weeks more testing and
fixing. The goal is to reduce the human time on both ends while maintaining quality.

---

## Understanding Your Workflow

A typical Ralph cycle looks like this:

```
┌─────────────────────┐     ┌───────────┐     ┌─────────────────────┐
│  Spec Writing        │ ──→ │  ralph    │ ──→ │  Testing & Fixing    │
│  (weeks)             │     │  build    │     │  (weeks)             │
│                      │     │  (hours)  │     │                      │
│  Interactive sessions│     │           │     │  Punch lists,        │
│  Detailed specs      │     │  Autonomous│    │  interactive fixes   │
└─────────────────────┘     └───────────┘     └─────────────────────┘
```

Ralph's build phase is already optimized. The leverage is in compressing the two human-
intensive bookends.

---

## Part 1: Compressing Spec Writing

### Use Agents to Draft Specs, Not Write Them From Scratch

You are the domain expert, but you don't have to be the typist. Instead of hand-writing
every spec in `specs/`, try this pattern:

1. **Describe what you want conversationally** in an interactive session — as if
   explaining it to a colleague
2. **Have the agent produce the spec draft** following your project's spec format
   (point it at `specs/spec-lifecycle.md` and an existing spec as a template)
3. **Review and edit** the draft — you're an editor now, not an author

This exploits what agents are good at (structured document generation, completeness
checklists) while keeping you in control of intent.

### Have the Agent Interview You

Instead of trying to think of everything upfront, start a session with:

> "I want to build X. Ask me questions until you have enough information to write a
> complete spec following the format in specs/spec-lifecycle.md."

The agent will ask about edge cases, error handling, constraints, and dependencies you
might not think to write down. This is especially effective for complex features where
requirements emerge through conversation.

### Use `ralph prompt` for Discovery Work

> **Note:** The example prompts throughout this guide are abbreviated sketches for
> clarity. Real prompts need significantly more structure — fresh-context reminders,
> progress tracking, scope constraints, verification steps, and commit discipline.
> Use the existing prompts in `prompts/` as templates for the right level of detail.

Before writing specs for an existing codebase, use `ralph prompt` with a custom prompt
to have the agent survey and document what exists:

```bash
# Create a discovery prompt
cat > prompts/discovery.md << 'EOF'
Survey the codebase and produce a structured inventory of:
- All major components and their responsibilities
- External dependencies and integrations
- Data models and their relationships
- Existing test coverage

Write findings to docs/codebase-inventory.md.
When complete, output: <promise>COMPLETE</promise>
EOF

ralph prompt prompts/discovery.md
```

This gives you a foundation to write specs against, rather than discovering the codebase
yourself.

### Tiered Spec Detail

Not every spec needs the same level of detail. Match detail to risk:

| Risk Level | What to Specify | What to Leave to the Agent |
|---|---|---|
| **High** (auth, payments, data integrity) | Exact behavior, error cases, constraints, security rules | Internal code structure |
| **Medium** (CRUD features, UI flows) | Behavior, API shape, validation rules | Implementation approach, edge case handling |
| **Low** (config, scaffolding, docs) | Desired outcome | Everything else |

Ralph's build prompt already tells agents to resolve ambiguity using the precedence chain:
spec → existing code/tests → repo conventions → framework conventions. For low-risk
features, this fallback chain is usually sufficient with minimal spec detail.

### Reference-Driven Specs

For features similar to something that already exists (in your project or elsewhere):

> "Build an admin management page following the same patterns as the existing user
> management page in `src/pages/Users/`. Differences: [list only the differences]."

This is dramatically faster than describing everything from scratch and produces more
consistent output because the agent has a concrete reference.

---

## Part 2: Compressing the Testing & Fixing Phase

This is where the biggest gains are hiding. Most of your punch list items fall into
predictable categories that can be prevented or automated.

### Require Tests in Specs

Ralph's build prompt already encourages targeted tests, but the agent treats it as
discretionary. Make it mandatory by adding test requirements to your specs:

```markdown
## Testing

- Unit tests for all business logic methods
- Integration tests for all API endpoints (happy path + error cases)
- Tests for all validation rules listed above
```

When the spec says "test this," the build agent writes tests. When those tests exist,
they catch regressions in future iterations — preventing the cascading issues that fill
punch lists.

### Add Verification Blocks to Every Task

During plan mode, Ralph already requires `Verify:` blocks on every task. But the quality
of verification matters enormously. If you review the implementation plan before running
build and see weak verification blocks like "Run tests" or "Verify it works," edit them
before building:

```markdown
Verify:
  - `curl -s localhost:3000/api/health | jq .status` returns "ok"
  - `npm test -- --filter=auth` passes
  - `grep -r 'JWT_SECRET' .env.example` shows the variable documented
```

Concrete verification catches issues during build, not during your manual testing phase.

### Use `ralph prompt` for Automated Testing Passes

After a build cycle, instead of manually testing everything, create a test-sweep prompt:

```bash
cat > prompts/test-sweep.md << 'EOF'
You are a QA engineer. Survey the codebase and specs/ directory.

For each spec:
1. Read the spec's requirements and test criteria
2. Check whether adequate tests exist
3. Run the existing tests
4. For any spec requirement without test coverage, write a test
5. Fix any failing tests

Track progress in docs/test-sweep-progress.md.
When all specs have been reviewed and all tests pass,
output: <promise>COMPLETE</promise>
EOF

ralph prompt prompts/test-sweep.md 10
```

This lets the agent do first-pass QA — finding the obvious issues before you start
manual review.

### Agent-Assisted Punch List Processing

When you do find issues during testing, resist the urge to pre-diagnose. Instead of
writing "the problem is in line 47 of auth.js where the token validation...", write:

> "When I click 'Save' on the profile page, nothing happens. No error in the console.
> The network tab shows the POST returns 200 but the data doesn't update."

Give the agent the **symptom**, not the diagnosis. Agents are good at tracing through
code to find root causes — better than you might expect, and certainly faster.

### Batch Punch List Items as Specs

For punch lists with many items, convert them into a spec or process spec rather than
fixing them one by one in interactive sessions:

```markdown
# Post-Build Fixes

## Requirements

### Profile Page
- Save button must persist changes to the database (currently silently fails)
- Email validation must reject emails without TLD (currently accepts "user@localhost")

### Dashboard
- Widget count must update in real-time when items are added (currently stale until refresh)
- Empty state must show "No items yet" instead of a blank area

## Testing
- Each fix must include a regression test
```

Then run `ralph plan` → `ralph build`. This converts your interactive fix sessions into
autonomous build iterations.

### Use Process Specs for Post-Build Cleanup

If your punch list has ordering dependencies (e.g., "fix the data model first, then fix
the UI that depends on it"), write it as a process spec:

```markdown
# Post-Build Fixes

## Phase 1 — Data Layer
1. Fix profile save (silent failure on POST)
2. Fix email validation (missing TLD check)

## Phase 2 — UI (depends on Phase 1)
1. Fix dashboard widget real-time updates
2. Add empty state messaging
```

Then use `ralph plan --process` → `ralph build`.

---

## Part 3: Shrinking the Cycle

### Smaller Batches

Instead of writing all specs → building everything → testing everything:

```
Spec Feature A → Plan → Build → Test → ✓
Spec Feature B → Plan → Build → Test → ✓
Spec Feature C → Plan → Build → Test → ✓
```

Smaller cycles surface problems earlier. A bug in Feature A might affect how you spec
Feature B — finding it after 3 weeks of building means rework.

### Build-Test-Fix Loops

After each build cycle, run a tight loop instead of a big-bang test phase:

```bash
# Build
ralph build 10

# Agent-driven test sweep
ralph prompt prompts/test-sweep.md 5

# Review results, write punch list spec
vim specs/fixes.md

# Build the fixes
ralph plan
ralph build 5
```

### Spec Refinement as a Continuous Practice

When you find issues during testing, **update the spec** — not just the code. This has
two benefits:

1. If ralph ever rebuilds (replan), the fix is captured in the spec
2. Your specs get more precise over time, reducing future punch lists

Ralph's build prompt tells agents to document assumptions as `Assumption / Spec gap:` in
the plan. Reviewing these after a build cycle tells you exactly where your specs were
ambiguous — those are the spots to tighten.

---

## Part 4: Building Institutional Knowledge

### AGENTS.md as Accumulated Wisdom

`AGENTS.md` is read by every build iteration. Use it to capture patterns that prevent
recurring issues:

```markdown
## Known Pitfalls

- All database queries must use parameterized queries, not string interpolation
- The `UserService` class is the only entry point for user mutations — do not
  write directly to the users table
- CSS classes must use the project's design system tokens — do not hardcode colors

## Testing

Run the test suite:
    npm test

Run linting:
    npm run lint

Both must pass before committing.
```

Every issue you fix twice should become an AGENTS.md entry so you never fix it a third
time.

### Post-Cycle Retrospectives

Ralph has a built-in retro guide (`ralph help retro`). After each significant cycle:

1. Review session logs — which tasks took multiple iterations? Why?
2. Review the implementation plan — look for `Assumption / Spec gap:` notes
3. Review blocked tasks — what caused them?
4. Apply fixes to specs, AGENTS.md, or your spec-writing process

The patterns you find here tell you exactly where to invest spec-writing effort and where
you can safely leave things to the agent.

---

## Quick Reference: Which Ralph Mode to Use

| Situation | Mode | Command |
|---|---|---|
| New features, independent improvements | Gap-driven | `ralph plan` → `ralph build` |
| Phased migration, ordered refactor | Sequence-constrained | `ralph plan --process` → `ralph build` |
| Post-migration spec updates | Align specs | `ralph align-specs` |
| Discovery, audit, test sweep, one-shot | Ad-hoc prompt | `ralph prompt <file>` |
| Spec drafting | Interactive session | (use your coding agent directly) |
| Punch list with many items | Convert to spec | write spec → `ralph plan` → `ralph build` |
| Punch list with ordering | Convert to process spec | write process spec → `ralph plan --process` → `ralph build` |

---

## The Letting-Go Checklist

When you catch yourself doing work manually, ask:

1. **Could I describe this as a spec and let ralph build it?**
   Most punch list items can be expressed as requirements.

2. **Could I use `ralph prompt` for this?**
   Test sweeps, code audits, documentation — anything iterative but unstructured.

3. **Am I pre-diagnosing?**
   Give the agent the symptom, not the diagnosis. Let it trace the problem.

4. **Am I writing a spec or editing one?**
   Have the agent draft it first. You review.

5. **Have I seen this class of issue before?**
   Add it to AGENTS.md so the agent prevents it next time.

6. **Am I testing something that should have an automated test?**
   Add test requirements to the spec. Let the next build cycle write the tests.

The goal isn't to remove yourself entirely — it's to move from **doing the work** to
**reviewing the work**, and eventually to **spot-checking the work**.
