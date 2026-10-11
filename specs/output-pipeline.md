# Agent Output Processor (`lib/format_output.py`)

## Purpose

`lib/format_output.py` is a single-pass Python processor that turns an agent CLI's output
stream (usually NDJSON) into human-readable display lines and a small JSON summary: the
completion signal, response size, error state, context usage, and cost.

It exists to replace the per-agent bash parsing in `agents/*.sh`
(`agent_format_display`, `agent_extract_response`, and the stream-parsing half of
`agent_post_iteration`), which parses the same stream three times and drifts apart (see
`tech-debt.md` item 3). The processor was built from the process spec
`process/output-pipeline-python.md`.

## Integration Status

The processor is built and tested but **not yet called by `ralph` or any agent script**.
The loop still uses the bash functions described in `loop-behavior.md` and
`agent-scripts.md`. The cutover is a separate, supervised step (process spec, "What This
Spec Does NOT Cover"). It covers:

- Wiring the processor into `run_iteration` in `ralph`. The processor writes the session
  log itself (`--log "$SESSION_LOG"` replaces `| tee -a "$SESSION_LOG"`), while
  `tee "$RALPH_DIR/last_agent_output"` stays as the raw debug record.
- Reading the summary for signals, context, cost, and empty-response detection based on
  `response_chars` and `is_error`.
- An `AGENT_OUTPUT_FORMAT` variable in each agent script, passed to `--format`, and
  removal of `agent_format_display` / `agent_extract_response`.
- Declaring `python3` in `dependencies` and `prompts/templates/Dockerfile.base`, and
  shipping `lib/format_output.py` through `install.sh` / `update.sh` `MANAGED_FILES`.
- Updating `loop-behavior.md`, `agent-scripts.md`, `project-structure.md`, `tech-debt.md`,
  and `README.md`.

Until then, the processor is not installed into parent projects.

Intended pipeline after integration:

```bash
agent_invoke "$tmp_prompt" \
    | tee "$RALPH_DIR/last_agent_output" \
    | python3 "$RALPH_DIR/lib/format_output.py" --format "$AGENT_OUTPUT_FORMAT" \
        --summary "$summary_file" --log "$SESSION_LOG"
```

## Files

```
lib/format_output.py                    # the processor (single file, stdlib only)
tests/test_format_output.py             # unittest suite, drives the CLI as a subprocess
tests/fixtures/format_output/           # NDJSON fixtures + README recording provenance
tests/test_ralph.sh                     # "format_output" group runs the unittest suite
```

## Interface

### Invocation

```bash
python3 lib/format_output.py --format FORMAT --summary PATH [--log PATH] < agent.ndjson
```

- `--format` (required): one of the registered formats (`text`, `stream-json`,
  `pi-json`). The format names a stream schema, not an agent: amp and claude share
  `stream-json`, so a new agent can reuse an existing format without Python changes.
- `--summary` (required): path the summary JSON is written to.
- `--log` (optional): a file the processor **appends** to (never truncates). It receives
  everything written to stdout plus the log-only detail (see "Screen vs. log"). Without
  `--log`, log-only detail is dropped.
- Reads stdin, writes the screen display to stdout, and writes diagnostics to stderr.
  Diagnostics are not copied to the log.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Stream processed, including empty or malformed input |
| 1 | `--log` cannot be opened (checked before reading stdin), or the summary cannot be written |
| 2 | Usage error, such as an unknown format (argparse `choices` lists the valid values) |

### Summary File

Written exactly once at end of stream, in a `finally` block, so it exists even after an
unexpected exception. Every key is always present; `null` means "not available".

```json
{
  "format": "stream-json",
  "signal": "COMPLETE",
  "response_chars": 2082,
  "is_error": false,
  "error": null,
  "context_used": 130615,
  "context_max": 300000,
  "context_pct": 44,
  "cost": null,
  "malformed_lines": 0
}
```

| Key | Meaning |
|---|---|
| `format` | The `--format` value |
| `signal` | `"COMPLETE"`, `"REPLAN"`, or `null`. If both appear in signal-eligible text, `COMPLETE` wins (same as the bash loop, see `tests/test_signals.sh` `test_signal_both_complete_and_replan`). |
| `response_chars` | Sum of `len()` of every signal-eligible text block. `0` means the agent produced no response. A missing signal is normal and is not an empty response. |
| `is_error` | `true` if the stream reported a terminal agent error, `false` if it reported a normal finish, `null` if the format has no such indicator or none was seen. |
| `error` | Error message when `is_error` is `true`, else `null`. Falls back to `"unknown error"` when the stream gives no message. |
| `context_used` | Tokens in the context window on the final top-level model call |
| `context_max` | Model context window size, when the stream exposes it |
| `context_pct` | `round(context_used * 100 / context_max)` as an int, only when both are known and `context_max > 0` |
| `cost` | USD for the whole iteration, when the stream exposes it |
| `malformed_lines` | Count of non-blank lines that were not JSON objects, plus lines whose handling raised an exception |

## Signal Detection Constraint

Signals (`<promise>COMPLETE</promise>`, `<promise>REPLAN</promise>`) are detected **only in
assistant-authored, top-level response text**: never in echoed prompts, tool results,
thinking, subagent output, `result` lines, or malformed (non-JSON) lines. Every ralph
prompt contains the signal string as an instruction, and agents routinely read prompt and
spec files, so tool results contain it too. In the real amp capture, the echoed prompt and
10 of 56 tool results contain `<promise>COMPLETE</promise>`. Scanning anything wider
produces false completions (see `loop-behavior.md`, "Completion Detection").

This is the bug the processor fixes for pi: `agents/pi.sh` `agent_extract_response` does
not filter on role, so it matches pi's echoed user prompt and reports COMPLETE on every
iteration.

## Display Conventions

The same for every format. Each item is written and flushed as soon as its source line is
processed.

### Screen vs. Log

The screen stays readable: what the agent thinks, says, and does, plus failures. The log
adds what tools returned, for debugging and for `ralph prompt adhoc-retro-analyze`, which
reads session logs. Full tool output is kept out of both: one amp iteration returned
358 KB of tool output, and retrospective agents read logs within a context budget.

| Item | Screen (stdout) | Log (`--log`) |
|---|---|---|
| Assistant text | the text as-is (no prefix, may be multi-line) | same |
| Thinking / reasoning | `[thinking] <text>` | same |
| Tool call (includes file writes) | `[tool] <name>: <summary>` | same |
| Successful tool result | not shown | `[tool result] <name>: <first line>` |
| Failed tool result | `[tool error] <name>: <first line>` | same line, followed by the error detail block |
| Agent error | `[error] <message>` | same |
| Non-JSON line (JSON formats) | the raw line as-is | same |

- `<summary>` for a tool call: the first present, non-empty value among the input keys
  `path`, `file_path`, `cmd`, `command`, `pattern`, `filePattern`, `query`, `url`,
  `description`, `prompt` (non-string values as compact JSON); otherwise the compact JSON
  of the whole input. Newlines become spaces. Truncated to 200 characters. File contents
  are never shown, only the path.
- Tool result content may be a string or a list of `{"type":"text","text":...}` blocks
  (joined with newlines); any other value is rendered as compact JSON. "Lines" means the
  non-blank lines of that content.
- `<first line>`: the first line truncated to 200 characters, followed by
  ` (+N more lines)` when there are more. Empty content shows `(no output)`.
- Error detail block (log only): the remaining lines of a failed result, each indented 4
  spaces and not truncated. When more than 20 lines remain, keep the first 5 and the last
  15 with an indented `... (N lines omitted)` between them. Compiler errors tend to sit at
  the top of the output; test summaries and tracebacks at the bottom.
- Tool results are matched to the tool name through the tool call id. `?` is used when
  the id is unknown.
- Echoed user prompts appear in neither output.
- The limits are module constants: `MAX_CHARS = 200`, `DETAIL_MAX_LINES = 20`,
  `DETAIL_HEAD_LINES = 5`, `DETAIL_TAIL_LINES = 15`.

## Robustness

- Reads `sys.stdin.buffer` line by line and decodes each line as UTF-8 with
  `errors="replace"`; stdout is reconfigured to UTF-8 with `errors="replace"`. Invalid
  bytes never crash the processor.
- Blank lines are skipped silently.
- In JSON formats, a non-blank line that does not parse to a JSON object is written to
  stdout unchanged and counted in `malformed_lines`. It is never signal-eligible. No
  stderr warning.
- Every field access uses `.get()` with defaults. Unknown event and block types are
  ignored silently (pi `message_update`, `turn_end`, `tool_execution_*`, `agent_end`; amp
  `system`).
- If handling one parsed line raises, it is counted in `malformed_lines`, one stderr line
  `format_output: skipped line N: <exception>` is written, and processing continues. `N`
  counts physical input lines, including blank ones.
- **Real-time output:** stdout and the log are flushed after every write. Python
  block-buffers stdout when it is a pipe, which would otherwise delay the live display
  until the end of the iteration; flushing the log keeps `tail -f` on the session log live.
- **Broken pipe:** on `BrokenPipeError` writing stdout, the processor stops writing stdout
  and points it at `os.devnull` (`os.dup2`), keeps reading stdin to EOF (so the agent CLI
  is not killed by SIGPIPE), keeps writing the log, still writes the summary, and exits 0.
  Without the `dup2`, the interpreter's shutdown flush raises again and Python exits with
  status 120.

## Implementation Shape

- One file, Python 3.9+, stdlib only (`argparse`, `json`, `os`, `sys`), with
  `from __future__ import annotations`. The underscore file name keeps it importable;
  tests still exercise it through the CLI.
- A base `Processor` class owns the stream loop, JSON parsing, error recovery, flushing,
  signal scanning, summary accumulation, and the emit helpers `text`, `thinking`, `tool`,
  `tool_result`, and `error`. Only `text` is signal-eligible and counts toward
  `response_chars`. `tool_result` alone decides screen versus log-only, so formats never
  deal with the split. Underneath, one `write(text, log_only=False)` method does all
  output.
- Each JSON format is a subclass with one `handle(obj)` method that calls the emit helpers
  and sets `is_error`, `error_message`, `context_used`, `context_max`, and `cost`. The
  `text` format overrides per-line handling instead, because its input is not JSON.
- The module-level `FORMATS` dict maps format names to classes and feeds argparse
  `choices`.

## Formats

### `text` (plain passthrough)

For agents whose stdout is plain text: the test stub agent (`tests/stub_agent.sh`) and any
agent without a parser. Every non-blank line is displayed as-is and is signal-eligible.
All usage fields, `is_error`, and `error` are `null`. Not safe for an agent that echoes
its prompt or emits JSON to stdout: it would detect the prompt's or a tool result's signal.

### `stream-json` (amp, claude)

Schema sources: the real amp capture `tests/fixtures/format_output/amp.ndjson`, and Claude
Code's documentation (https://code.claude.com/docs/en/headless,
https://code.claude.com/docs/en/agent-sdk/cost-tracking, and the result-message schema in
the Agent SDK reference). There is no real claude capture yet.

```json
{"type":"system","subtype":"init","session_id":"...","tools":[...]}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<echoed prompt>"}]}}
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"..."},{"type":"tool_use","id":"toolu_1","name":"Read","input":{"path":"AGENTS.md"}}],"usage":{"input_tokens":1,"cache_creation_input_tokens":297,"cache_read_input_tokens":130234,"output_tokens":83,"max_tokens":300000}}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"...","is_error":false}]}}
{"type":"assistant","parent_tool_use_id":"toolu_parent","message":{...}}
{"type":"result","subtype":"success","is_error":false,"result":"<final assistant text>","total_cost_usd":0.0123,"modelUsage":{"claude-sonnet-4-5":{"contextWindow":200000}}}
```

Rules:

- `assistant`: `thinking`, `text`, and `tool_use` blocks are displayed in order. `text` is
  signal-eligible only when the line's `parent_tool_use_id` is absent or null; subagent
  text is displayed but not scanned or counted.
- `user`: `tool_result` blocks become tool results (`is_error: true` gives a failed
  result). `text` blocks are the echoed prompt: not displayed, not scanned.
- `result`: not displayed and not scanned (its `result` string duplicates the final
  assistant text). It sets:
  - `is_error` from `is_error`, only when that is a boolean. When true, `error` is the
    first available of `errors` joined with `"; "`, `error`, `subtype`, or
    `"unknown error"`, and `[error] <error>` is emitted.
  - `cost` from `total_cost_usd` when present.
  - `context_max` from the largest `modelUsage.*.contextWindow`, only when `context_max`
    was not already set from `usage.max_tokens`.
- Context comes only from the `usage` of top-level assistant messages; the last one wins.
  `context_used = input_tokens + cache_creation_input_tokens + cache_read_input_tokens +
  output_tokens` (missing keys count as 0). `context_max = usage.max_tokens` when present
  (amp includes it; claude does not).
- Without a `result` line, `is_error` stays `null`. amp's stream carries no cost, so
  `cost` stays `null` for amp; amp's balance-based cost stays in its bash hooks.

### `pi-json` (pi)

Schema sources: the real captures `tests/fixtures/format_output/pi.ndjson` and
`pi-error.ndjson`, and https://pi.dev/docs/latest/programmatic-usage/json-event-stream-mode.

```json
{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"<echoed prompt>"}]}}
{"type":"message_end","message":{"role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"toolCall","id":"call_1","name":"read","arguments":{"path":"notes.txt"}}],"stopReason":"toolUse","usage":{"totalTokens":4049,"cost":{"total":0.00397}}}}
{"type":"message_end","message":{"role":"toolResult","toolCallId":"call_1","toolName":"read","content":[{"type":"text","text":"hello\n"}],"isError":false}}
{"type":"message_end","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"400: {...not a valid model ID...}","usage":{...}}}
```

Rules:

- Only `type == "message_end"` is handled. All other events are ignored, including
  `message_update` (all-zero `usage`) and `turn_end` / `agent_end` (repeat message
  content, including the echoed prompt).
- `role == "assistant"`: `thinking`, `text` (signal-eligible), and `toolCall` (`name`,
  `arguments`) blocks are displayed. `stopReason == "error"` sets `is_error = true`,
  `error = errorMessage` (or `"unknown error"`), and emits `[error] <errorMessage>`.
  Otherwise, if no assistant message has errored yet, `is_error = false`.
- `role == "toolResult"`: emitted as a tool result using `toolName`, `content`, `isError`.
- `role == "user"` / `"system"`: ignored (echoed prompt and system prompt).
- `cost` is the sum of `usage.cost.total` over assistant messages (cost accrues per call).
  `context_used` is `usage.totalTokens` of the last assistant message (the context size of
  the final call). Missing `cost.total` or `totalTokens` inside a present `usage` counts as
  0, so `pi-error.ndjson` yields `cost: 0` and `context_used: 0`. Both are `null` only when
  no assistant `usage` was seen.
- `context_max` is always `null`: pi's stream does not expose the window (`tech-debt.md`
  item 5).

### Agents Without a Format

cline and codex have no parser: no real capture of their current CLI streams exists.
`text` is not a safe fallback because both emit JSON. See `tech-debt.md` item 7 for the
researched schemas and the procedure for adding a format.

## Adding a Format

1. Capture a real stream with the same arguments as `agents/<name>.sh` and save it as
   `tests/fixtures/format_output/<name>.ndjson`. `last_agent_output` in a ralph project
   holds the raw stream of the most recent iteration.
2. Record its provenance in `tests/fixtures/format_output/README.md`. Synthesized fixtures
   must say so and cite the documentation or source file their shapes came from.
3. Add a `Processor` subclass with a `handle(obj)` method and register it in `FORMATS`.
   Route only assistant-authored, top-level response text through `text`.
4. Add fixture tests whose expected values are derived independently of the
   implementation (for example with `jq`), including a false-positive guard: the fixture
   minus its final assistant response must give `signal: null`.

## Testing

- `tests/test_format_output.py` uses stdlib `unittest` (pytest is not stdlib and is not
  assumed installed). Every test runs the processor as a subprocess
  (`sys.executable lib/format_output.py ...`) and asserts on stdout, the summary JSON, the
  log file, and the exit code.
- Coverage: CLI exit codes, log append, invalid UTF-8, signal precedence, streaming
  without closing stdin, broken pipe with a 10,000-line input, the amp and pi fixtures
  (summary values, screen/log split, echoed prompt suppression, false-positive guards),
  and inline claude shapes from the docs (list-of-blocks tool results, the 30-line error
  detail block, `result` cost and context window, `error_max_turns`, subagent text,
  malformed lines).
- Fixtures in `tests/fixtures/format_output/` are not regenerated; tests that need a
  reduced input build it from the fixture lines in the test.
- `./tests/test_ralph.sh format_output` runs `python3 -m unittest discover -s tests -p
  'test_format_output.py'` from the project root and records one pass/fail assertion,
  printing the unittest output on failure. The group is part of the default all-groups run.
- Running the suite creates `tests/__pycache__/`, which `.gitignore` excludes.
