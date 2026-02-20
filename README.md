# Ralph Wiggum Loop

> [!CAUTION]
> **This is my sandbox for learning the Ralph Wiggum approach to using an LLM coding agent. It is a research project. DO NOT USE.**
>
> This software is experimental, unstable, and under active development. There is no support, no documentation guarantees, and no warranty of any kind. Use at your own risk.

## Overview

The Ralph Wiggum Loop is an iterative development system that enables LLM coding
agents to work on large projects by breaking work into discrete, manageable
chunks with fresh context per iteration.

The Ralph Wiggum Loop addresses the context window limitations of Large Language Models by:

- **Fresh Context Per Iteration** - Each loop iteration starts the agent with a clean slate
- **Persistent Memory** - Critical information persists in files between iterations
- **Incremental Progress** - Agent completes one focused task per iteration
- **Self-Documenting** - All decisions and progress tracked in version control

This enables agents to work on projects of arbitrary size while maintaining coherence through persistent documentation.

## Coding Agents

I have invested several months in working with Cline in VSCode so for now, I'd like to stick with it.
However, here are some alternatives I may investigate:

**Free/OSS:**

- [Cline](https://docs.cline.bot/introduction/welcome)
- [Roo](https://github.com/RooCodeInc/Roo-Code?ref=ghuntley.com) - a fork of Cline
- [Crush](https://github.com/charmbracelet/crush)
- [Qwen Code](https://github.com/QwenLM/qwen-code)

**Paid:**
- [Claude Code](https://claude.com/product/claude-code)
- [amp](https://ampcode.com/)

---

## Prerequisites

- Git repository initialized (`git init`)
- Cline CLI installed and available in PATH
- At least one specification document in `specs/`

## References

- [Original Ralph post](https://ghuntley.com/ralph/)
- [Geoffrey Huntley's Loom project](https://github.com/ghuntley/loom/)
- [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook)
- [Accountability project](https://github.com/mikearnaldi/accountability)
- [The Real Ralph Wiggum Loop](https://thetrav.substack.com/p/the-real-ralph-wiggum-loop-what-everyone)

## License

See LICENSE file for details.
