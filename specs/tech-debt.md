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

`lib/format_output.py` reports `context_max: null` (and therefore `context_pct: null`) for
the `pi-json` format, because pi's NDJSON stream does not expose the model's max context
window (`maxTokens` is not in pi's `usage` object). ralph logs `Context: N tokens` without a
percentage, and `_ITER_CONTEXT_PCT` stays empty. This means pi users lose:

- The "context usage high" warning in the terminal
- Session-level context min/avg/max in the summary

This is a pi limitation, not a bug, but it is a meaningful feature gap compared to
amp/claude.

**Remediation:** pi's model name is known from `PI_MODEL` or the stream metadata.
A lookup table of model -> max context (or shelling out to `pi --list-models`)
could provide the missing value, set from `agent_post_iteration` in `agents/pi.sh` via
`_ITER_CONTEXT_MAX` / `_ITER_CONTEXT_PCT`. Alternatively, accept it as not worth the
complexity — pi is positioned as the "cheap model on low-value iterations" agent
where context warnings matter less.

### 7. cline and codex: No Output Parser - LOW

`lib/format_output.py` has parsers only for streams we could capture for real
(`stream-json` for amp/claude, `pi-json` for pi). `agents/cline.sh` and `agents/codex.sh`
do not set `AGENT_OUTPUT_FORMAT`, so ralph refuses to run them with a clear error rather
than misparse their output. A `text` passthrough is not a safe fallback: both CLIs emit
JSON, so the raw lines would flood the screen, and tool output that contains
`<promise>COMPLETE</promise>` would trigger a false completion.

**Remediation:** Whoever has the agent available captures a real stream with the
agent script's arguments and adds it as `tests/fixtures/format_output/<agent>.ndjson`.
They then add a format subclass in `lib/format_output.py` following the `pi-json`
pattern, and set `AGENT_OUTPUT_FORMAT` in the agent script. The notes below were
researched from upstream source (2026-10) and are a starting point, not verified
against a live CLI. The old `agents/cline.sh` parsed the VS Code extension's
`ClineMessage` ask/say schema, which the cline 3.x CLI does not emit.

#### `codex-json` (`codex exec --json`)

Source: `codex-rs/exec/src/exec_events.rs` and
`codex-rs/exec/tests/event_processor_with_json_output.rs` in https://github.com/openai/codex.
The stream does not echo the prompt.

```json
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"Inspected the failing test."}}
{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"pytest","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"pytest","aggregated_output":"1 passed\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"Finished. <promise>COMPLETE</promise>"}}
{"type":"turn.completed","usage":{"input_tokens":42,"cached_input_tokens":12,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}
{"type":"turn.failed","error":{"message":"provider unavailable"}}
{"type":"error","message":"connection lost"}
```

Rules: `item.completed` + `agent_message` gives signal-eligible text. `reasoning` gives
thinking. `command_execution`: `[tool] command: <command>` on `item.started`, and a tool
result on `item.completed` (`[tool error]` when `exit_code` is non-zero). `file_change`
on completion gives `[tool] file_change: <comma-joined paths>`. `mcp_tool_call` on
completion gives `[tool] <server>.<tool>: <arguments summary>`. `web_search` gives
`[tool] web_search: <query>`. An `error` item gives `[error]` but is non-fatal.
`turn.completed` sets `is_error = false`. `turn.failed` and a top-level `error` set
`is_error = true` with the message. `turn.completed.usage` is cumulative for the turn,
not a context size, and the stream has no cost or window, so all usage fields stay `null`.

#### `cline-json` (`cline --json`, CLI 3.x)

Source: `apps/cli/src/utils/events.ts`, `apps/cli/src/runtime/run-agent.ts`,
`sdk/packages/shared/src/agents/types.ts` and `docs/cli/cli-reference.mdx` in
https://github.com/cline/cline. The stream does not echo the prompt. This replaces the
`ClineMessage` ask/say schema that `agents/cline.sh` used to parse, which is the
VS Code extension's transcript format, not the CLI's.

```json
{"ts":"...","type":"agent_event","event":{"type":"content_start","contentType":"text","text":"Finished. ","accumulated":"Finished. "}}
{"ts":"...","type":"agent_event","event":{"type":"content_end","contentType":"text","text":"Finished. <promise>COMPLETE</promise>"}}
{"ts":"...","type":"agent_event","event":{"type":"content_end","contentType":"reasoning","reasoning":"I should inspect..."}}
{"ts":"...","type":"agent_event","event":{"type":"content_start","contentType":"tool","toolName":"run_commands","toolCallId":"call_1","input":{"commands":["pytest"]}}}
{"ts":"...","type":"agent_event","event":{"type":"content_end","contentType":"tool","toolName":"run_commands","toolCallId":"call_1","output":"1 passed\n","durationMs":812}}
{"ts":"...","type":"agent_event","event":{"type":"usage","inputTokens":120,"outputTokens":12,"cacheReadTokens":50,"cacheWriteTokens":0,"cost":0.0012,"totalCost":0.0012}}
{"ts":"...","type":"run_result","finishReason":"completed","iterations":1,"usage":{"inputTokens":120,"outputTokens":12,"cacheReadTokens":50,"cacheWriteTokens":0,"totalCost":0.0012},"text":"Finished. <promise>COMPLETE</promise>"}
{"ts":"...","type":"run_aborted"}
```

Rules: only `content_end` is displayed (`content_start`/`content_update` are streaming
chunks). `contentType` `text` gives signal-eligible text, `reasoning` gives thinking, and
`tool` gives a tool result (`toolName`, `output`). The tool call line comes from the
`tool` `content_start` (`toolName`, `input`). `run_result.text` is scanned for signals
but not displayed and not counted in `response_chars`. `run_result` with `finishReason`
`completed` sets `is_error = false`; any other `finishReason`, or `run_aborted`, sets
`is_error = true` with the reason. `cost` = `run_result.usage.totalCost`. Context fields
stay `null` (per-request token semantics are unverified and the window is not exposed).

## Non-Goals

- Multi-agent coordination, parallel execution, Web UI, cloud deployment (see
  `specs/overview.md` for the full non-goals list).
- Rewriting the prompt templates or specs — those are the real IP and carry forward
  unchanged regardless of orchestration language.
- Adopting a compiled language — the "just run it" experience is a core design
  principle and a build/compile step adds friction with no benefit for an
  orchestration tool whose bottleneck is LLM API calls.