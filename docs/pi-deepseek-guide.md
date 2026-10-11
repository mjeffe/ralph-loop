# Using Pi with DeepSeek Models: Prompting & Delegation Guide

## The Core Dynamic

Cheaper models (DeepSeek) are more literal and stay closer to the explicit task.
Expensive models (Claude Opus, GPT-5.5) default to a broader frame — they read
between the lines and trace implications further. Both are capable. The difference
is what frame they pick when the prompt is ambiguous.

## Prompting for Analysis/Review

### Always end analysis prompts with "validate end-to-end"

❌ _"Review this commit and give me your analysis."_
→ Gets diff review. Misses integration gaps in untouched files.

✅ _"Review this commit and give me your analysis. Verify that the feature works
end-to-end by tracing every path a user would hit."_
→ Gets system-level review. Surfaces hidden coupling and hardcoded assumptions.

The phrase "verify end-to-end" is generic — it applies to any review, regardless
of what kind of change it is. It forces the model out of diff-review mode.

### Ask "what would break?" not "is this correct?"

"Is this correct?" judges the patch. "What would break if a user tried this?"
forces impact analysis across the whole codebase.

## When to Use Specialist Agents

| Task | Agent | Why |
|------|-------|-----|
| Straightforward coding from clear specs | pi/DeepSeek | No need for stronger reasoning |
| Diff review of small, well-scoped change | pi/DeepSeek + "verify end-to-end" prompt | The prompt addition closes the frame gap |
| Review of a change touching multiple systems with hidden coupling | **oracle** (GPT-5.5) | Broader default frame is the whole point |
| Debugging a hard problem | **oracle** for plan, then pi for implementation | Plan with strength, implement with speed |
| Finding all uses of a pattern across the codebase | **librarian** (Flash) | Search-and-report, no editing |
| Simple isolated changes (formatting, docstrings) | **rush** (Flash) | Fast, cheap, well-scoped |
| Pre-merge security/bug review | **review** (V3) | Catch issues before merging |

### How to delegate to oracle

Say: **"Use the oracle to review this."** — not "consult the oracle."

✅ "Use oracle" → the main agent gathers context (diff + key files) and hands
the entire analysis to the oracle. Clean handoff, oracle operates with full context.

❌ "Consult the oracle" → suggests the oracle is a side-resource mid-task. Adds
overhead without reliably changing the main agent's frame.

Oracle has isolated context — it can't see the conversation. Include all
needed file paths and instructions in the task description.

## Recommended AGENTS.md Addition

One line, applies universally:

> **On analysis/review tasks:** verify the change works end-to-end by tracing the
> full user path, not just judging the diff. Search the codebase for references
> to the old behavior and confirm every occurrence is handled.

This catches hidden coupling regardless of what kind of change is being reviewed.