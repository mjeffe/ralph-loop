# Technical Debt & Migration Strategy

## Overview

This spec tracks known structural debt, brittle areas, and the conditions under which a
language migration should be considered. It is not a to-do list — items here represent
intentional tradeoffs that are acceptable today but have a known remediation path when
(or if) they become too expensive.

## Current Assessment

Ralph is ~5,500 lines of bash across the main controller, library modules, agent scripts,
installer/updater, and test suite. Bash is the right tool for ~85% of the codebase:

- **Process orchestration** (calling agent CLIs, piping streams, docker compose) — bash
  is the best tool for this.
- **Filesystem operations** (directory validation, log creation, file copying).
- **Distribution** (curl-pipe-bash install/update — zero-friction and universal).
- **Plugin model** (sourcing agent scripts — elegant, discoverable, no framework needed).
- **Template substitution** (envsubst + .md files — clean and simple).

One component has crossed the threshold where bash is the right tool:

### 1. `lib/plan-filter.sh` — Custom Markdown Parser in Bash (562 lines) — HIGH

This is a real parser implemented entirely in bash regex. It scans plan files for task
headings, tracks section boundaries with associative arrays, resolves task dependencies
by extracting `Task N` numbers from free text, implements progressive disclosure for
large plans, and operates in six modes (header, overview, select, summary, validate,
meta). It is well-structured and tested, but modifying it is the highest-risk activity
in the project.

**Remediation:** Extract to Python as a drop-in replacement. The 562-line bash module
would become ~120-150 lines of Python using `re`, dataclasses, and dicts — a drop-in
replacement callable from the `ralph` script via `python3 "$RALPH_DIR/lib/plan-filter.py"`.
Zero changes required to the loop controller, agent scripts, prompts, or test harness
(plan-filter tests would be rewritten in pytest, making them cleaner). Python 3.9+ is
universal; no pip dependencies needed — stdlib only.

### 2. Duplicated File Manifests — MEDIUM

`install.sh` and `update.sh` each contain identical copies of the `MANAGED_FILES` array
and `SOURCE_PATHS` associative array (~80 lines each). The duplication exists because
bash has no clean mechanism for sharing associative arrays between scripts (sourcing
works for variables and functions but is fragile for complex data structures).

**Remediation:** Extract the manifest into `lib/managed-files.sh` as a sourced module
that defines the arrays once. Both `install.sh` and `update.sh` source it.
Alternatively, if item 1 is addressed first, consolidate install and update into a
single Python script since the manifest shapes are natural to share.

### 3. Agent Output Pipeline — Three-Pass Parsing in Bash — HIGH

Each agent script (`agents/*.sh`) must implement 3-5 functions that parse the
agent CLI's NDJSON output. The same data is parsed three separate times:

1. `agent_format_display` — streams stdin through per-line jq for the terminal
   and session log. Shows text, thinking, and tool-use blocks.
2. `agent_extract_response` — re-reads `last_agent_output` from disk to scan
   for COMPLETE/REPLAN signals.
3. `agent_post_iteration` — greps `last_agent_output` with regex to extract
   token counts and context window usage.

Problems with the current approach:

- **46% of content blocks never reach the log.** Tool results (what the agent
  read or executed) and the final result message are invisible. The log shows
  `[tool] Read: specs/foo.md` but not what was read, making session logs far
  less useful for debugging.
- **Three parsing passes that can drift apart.** If the jq filter in
  `agent_format_display` is updated for a new content type but
  `agent_extract_response` is not, signal detection silently misses things.
- **Fragile grep-on-JSON for usage extraction.**
  `grep -o '"usage":{[^}]*}'` assumes the usage object is flat and single-line.
  A nested field (e.g., `"details":{"reasoning_tokens":5}`) breaks the regex
  silently.
- **Signal detection misses the `result` message type.** The COMPLETE signal
  often appears in the agent's final `result` message, but `agent_extract_response`
  only scans `assistant` type messages — depending entirely on the signal also
  appearing in an assistant text block.
- **Per-agent implementation quality varies.** amp.sh got the full treatment
  (tool inputs, thinking blocks, cost tracking). claude.sh is thinner (no tool
  inputs, no cost). cline.sh has its own entirely different schema. codex.sh is
  a stub. Each agent script carries its own completeness level.

**Remediation:** Extract output processing to a shared Python module with
per-agent block-type handlers. The stream reading, signal detection, file I/O,
and error handling are implemented once. Agent-specific code is only the
block-type dispatch (what content types exist and how to format them).

A single-pass Python processor replaces all three functions:

```python
# Shared infrastructure (once)
class OutputProcessor:
    def process_stream(self, stream):
        for line in stream:
            obj = self.parse_line(line)
            handler = getattr(self, f'handle_{obj["type"]}', None)
            if handler: handler(obj)

# Agent-specific (amp.py, ~30 lines)
class AmpProcessor(OutputProcessor):
    def handle_assistant(self, obj):
        for block in obj['message']['content']:
            if block['type'] == 'thinking':
                self.emit(f"[thinking] {block['thinking']}")
            elif block['type'] == 'text':
                self.emit(block['text'])
                self.check_signals(block['text'])
            elif block['type'] == 'tool_use':
                self.emit(f"[tool] {block['name']}: {self.tool_summary(block)}")
```

Claude and cline get the same quality of implementation as amp because the shared
infrastructure handles the boilerplate. Codex becomes implementable in under an
hour instead of "needs investigation." The session log gains tool results
(opt-in, truncated) and the final result message. Signal detection checks all
message types, not just assistant text blocks. Usage extraction uses
`json.loads()` dictionary access instead of grep regex.

Replaces the pipeline step in `run_iteration`:

```bash
agent_invoke "$tmp_prompt" \
    | python3 "$RALPH_DIR/lib/format-output.py" --agent "$AGENT" \
    | tee -a "$SESSION_LOG"
```

Stdlib only — no pip dependencies. Same drop-in model as the plan-filter
extraction.

## Migration Triggers

Do not undertake a full language migration unless one of these conditions is met:

1. **Plan format evolution makes plan-filter.sh painful to extend.** If multiple
   consecutive features require non-trivial changes to the bash parser, bite the
   bullet and extract it to Python. Do not wait for a crisis.
2. **A second component crosses the bash threshold.** If another module reaches
   the complexity of plan-filter.sh (multi-hundred-line data processing in bash
   regex), that signals the project has outgrown bash for data work and a broader
   migration should be planned.
3. **Agent scripts need richer data handling.** If agent output parsing requires
   stateful processing, streaming aggregation, or complex conditionals that strain
   jq expressions, Python's `json` and iterator patterns would be superior.

## Target Language: Python

If a full migration becomes warranted, Python is the target. Its advantages map
directly to ralph's needs:

- **Data processing is where bash strains and Python excels.** Plan parsing,
  NDJSON stream processing, usage extraction — all become stdlib operations
  (`re`, `json`, `dataclasses`) instead of regex-on-JSON contortions.
- **Same distribution model.** A curl-pipe-bash bootstrap installer that checks
  for `python3` works identically to the current install flow. The entry point
  stays a shell script:
  ```bash
  #!/bin/bash
  exec python3 "$(dirname "$0")/ralph.py" "$@"
  ```
  The installer ships `.py` files alongside the existing prompts, specs, and
  agent scripts. Stdlib only — no pip dependencies.
- **No compilation step.** Preserves the "just run it" experience. Edit, save,
  run — same as bash.
- **Gradual migration is natural.** Individual components (plan-filter, output
  formatter, installer) can be extracted one at a time as Python callouts from
  the existing bash controller. No big-bang rewrite required.
- **Test framework.** pytest with fixtures and parameterized tests replaces the
  current bash assertion helpers, making the test suite more expressive with
  less boilerplate.
- **Cleaner error handling.** Exceptions and result types replace `set -e`
  contortions (`|| true`, `|| rc=$?`).

Estimated line count reduction if fully migrated: ~5,500 bash to ~2,500 Python.

### 4. Dual Agent-Sourcing Pattern in Sandbox Mode — LOW

Two places in `lib/sandbox.sh` source the agent script, with implicit coupling about
who does it when:

- `sandbox_setup` (line ~440) sources the agent script unconditionally.
- `sandbox_build_base` and `sandbox_agent_env_keys` conditionally source the agent
  script only "when sandbox_up called me, because sandbox_setup already sourced it."

This is documented in comments but fragile: a third sandbox command that needs to
build the base image must remember to source the agent first or rely on the
conditional fallback.

**Remediation:** Source the agent script unconditionally in `ralph`'s main body,
then remove the source from both `sandbox_setup` and `sandbox_build_base`.
`validate_prerequisites` already returns early for sandbox/help modes, so sourcing
the agent in sandbox mode will not trigger the `command -v "$AGENT_CLI"` check.
Removes ~8 lines of conditional sourcing logic.

### 5. pi Agent: No Context-Window Warnings — LOW

pi.sh does not set `_ITER_CONTEXT_PCT`, `_ITER_CONTEXT_USED`, or `_ITER_CONTEXT_MAX`
because pi's NDJSON stream does not expose the model's max context window
(`maxTokens` is not in pi's `usage` object). This means pi users lose:

- The "context usage high" warning in the terminal
- Session-level context min/avg/max in the summary

This is a pi limitation, not a bug, but it is a meaningful feature gap compared to
amp/claude.

**Remediation:** pi's model name is known from `PI_MODEL` or the stream metadata.
A lookup table of model -> max context (or shelling out to `pi --list-models`)
could provide the missing value. Alternatively, accept it as not worth the
complexity — pi is positioned as the "cheap model on low-value iterations" agent
where context warnings matter less.

### 6. pi.sh Token/Cost Asymmetry Comment — TRIVIAL

In `agents/pi.sh`, the `agent_post_iteration` awk block sums cost across all
`message_end` events but captures `totalTokens` from only the last message:

```awk
{ cost += $1; tokens = $2 }
```

This is intentional (cost is cumulative; only the final turn's context size
matters for context pressure), but the asymmetry could confuse a future maintainer.

**Remediation:** Add a one-line comment in the awk block.

## Non-Goals

- Multi-agent coordination, parallel execution, Web UI, cloud deployment (see
  `specs/overview.md` for the full non-goals list).
- Rewriting the prompt templates or specs — those are the real IP and carry forward
  unchanged regardless of orchestration language.
- Adopting a compiled language — the "just run it" experience is a core design
  principle and a build/compile step adds friction with no benefit for an
  orchestration tool whose bottleneck is LLM API calls.