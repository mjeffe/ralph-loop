# Agent Output Pipeline: Python Processor

## Purpose

Build `lib/format_output.py`, a single-pass Python processor that turns an agent CLI's
NDJSON stream into human-readable log lines and a small JSON summary (signal, response
size, error state, context usage, cost). It will replace the per-agent bash functions
`agent_format_display` and `agent_extract_response`, and the stream-parsing half of
`agent_post_iteration` (see `specs/tech-debt.md` item 3).

This process spec covers only the new, purely additive files: the processor, its tests,
and the test-suite hook. Nothing in `ralph` or `agents/*.sh` calls the processor yet.
The cutover is done afterwards in a supervised interactive session (see "What This Spec
Does NOT Cover").

## Problems Being Fixed (verified)

Evidence comes from the real captures in `tests/fixtures/format_output/` and the current
agent scripts.

1. **Three passes over one stream.** Display (`agent_format_display`), signal detection
   (`agent_extract_response`) and usage (`agent_post_iteration`) parse the same data
   separately, so they can drift apart.
2. **Usage is grepped out of the JSON.** `grep -o '"usage":{[^}]*}'` in `agents/amp.sh` and
   `agents/claude.sh` breaks as soon as the usage object contains a nested object.
3. **Tool results never reach the session log.** In `amp.ndjson`, 56 tool calls produce
   56 `tool_result` blocks, and none of them are displayed. A reader of the log sees
   `[tool] Read: specs/foo.md` but never sees whether the read or the command failed.
4. **pi signal detection scans the echoed prompt.** pi emits the user prompt as a
   `message_end` with `role: "user"` (see `pi.ndjson`). `agents/pi.sh`
   `agent_extract_response` does not filter on role. Every ralph prompt contains
   `<promise>COMPLETE</promise>` as an instruction, so pi reports COMPLETE on every iteration.
5. **Uneven per-agent quality.** claude.sh shows no tool inputs or thinking. cline.sh
   parses the VS Code `ClineMessage` ask/say schema, but the current npm `cline` CLI (3.x)
   emits a different envelope. codex.sh is a stub. Parsers for cline and codex are out of
   scope until real captures exist (`specs/tech-debt.md` item 7).

### The constraint that must not regress

Signals are detected **only in assistant-authored response text**. Never in echoed
prompts, tool results, thinking, or subagent output. In `amp.ndjson` the echoed prompt
(a `user` text block) and 10 of the 56 tool results contain `<promise>COMPLETE</promise>`
because the agent read prompt and spec files. `specs/loop-behavior.md` ("Completion
Detection") explains why. Scanning anything wider produces false completions.

## End State

```
lib/format_output.py                    # the processor (single file, stdlib only)
tests/test_format_output.py             # unittest suite, drives the CLI as a subprocess
tests/fixtures/format_output/           # NDJSON fixtures + README recording provenance
tests/test_ralph.sh                     # gains a "format_output" group that runs the suite
```

Already present (captured before this spec was written; do not regenerate):

- `tests/fixtures/format_output/amp.ndjson`: real amp capture
- `tests/fixtures/format_output/pi.ndjson`: real pi capture
- `tests/fixtures/format_output/pi-error.ndjson`: real pi capture of a provider error
- `tests/fixtures/format_output/README.md`: provenance table

## Interface

### Invocation

```bash
python3 lib/format_output.py --format FORMAT --summary PATH [--log PATH] < agent.ndjson
```

- `--format` is required and must be one of the registered formats (see "Formats").
  The format describes the stream schema, not the agent: amp and claude share
  `stream-json`. During integration each agent script will declare its format in an
  `AGENT_OUTPUT_FORMAT` variable, so new agents can reuse an existing format without
  Python changes.
- `--summary` is required: the path the summary JSON is written to.
- `--log` is optional: a file the processor **appends** to (never truncates). It receives
  everything written to stdout plus the log-only detail (see "Screen vs. log"). Without
  `--log`, log-only detail is dropped.
- Reads stdin, writes the concise screen display to stdout, and writes diagnostics to
  stderr. Diagnostics are not copied to the log.
- Exit codes: `0` when the stream was processed (including empty or malformed input).
  `1` when the `--log` file cannot be opened (checked before reading stdin) or the
  summary file cannot be written. `2` on usage errors such as an unknown format
  (argparse `choices` lists the valid values).

Intended pipeline after integration (for context only, not built here). The processor
writes the session log itself, replacing `| tee -a "$SESSION_LOG"`:

```bash
agent_invoke "$tmp_prompt" \
    | tee "$RALPH_DIR/last_agent_output" \
    | python3 "$RALPH_DIR/lib/format_output.py" --format "$AGENT_OUTPUT_FORMAT" \
        --summary "$summary_file" --log "$SESSION_LOG"
```

### Summary file

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
| `signal` | `"COMPLETE"`, `"REPLAN"`, or `null`. If both appear anywhere in signal-eligible text, `COMPLETE` wins (preserves current behavior, see `tests/test_signals.sh` `test_signal_both_complete_and_replan`). |
| `response_chars` | Sum of `len()` of every signal-eligible text block, as received. `0` means the agent produced no response; the loop uses this for empty-response detection (a missing signal is normal and is NOT an empty response). |
| `is_error` | `true` if the stream reported a terminal agent error, `false` if it reported a normal finish, `null` if the format has no such indicator or none was seen. |
| `error` | Error message when `is_error` is `true`, else `null`. |
| `context_used` | Tokens in the context window on the final top-level model call. |
| `context_max` | Model context window size, when the stream exposes it. |
| `context_pct` | `round(context_used * 100 / context_max)` as an int, only when both are known and `context_max > 0`. |
| `cost` | USD for the whole iteration, when the stream exposes it. |
| `malformed_lines` | Count of non-blank lines that were not JSON objects, plus lines whose handling raised an exception. |

### Display conventions

The same for every format. Each item is written and flushed as soon as its source line is
processed.

#### Screen vs. log

The screen stays readable: what the agent thinks, says, and does, plus failures. The
session log adds what tools returned, for debugging and for `ralph prompt
adhoc-retro-analyze`, which reads session logs. Full tool output is deliberately kept
out of both. One iteration in `amp.ndjson` returned 358 KB of tool output, and
retrospective agents read the logs within a context budget.

| Item | Screen (stdout) | Log (`--log`) |
|---|---|---|
| Assistant text | the text as-is (no prefix, may be multi-line) | same |
| Thinking / reasoning | `[thinking] <text>` | same |
| Tool call (includes file writes) | `[tool] <name>: <summary>` | same |
| Successful tool result | not shown | `[tool result] <name>: <first line>` |
| Failed tool result | `[tool error] <name>: <first line>` | same line, followed by the error detail block |
| Agent error | `[error] <message>` | same |
| Non-JSON line (JSON formats) | the raw line as-is | same |

- `<summary>` for a tool call: the first present value among the input keys `path`,
  `file_path`, `cmd`, `command`, `pattern`, `filePattern`, `query`, `url`, `description`,
  `prompt`; otherwise the compact JSON of the whole input. Newlines become spaces.
  Truncate to 200 characters. File contents are never shown, only the path.
- Tool result content may be a string or a list of `{"type":"text", "text":...}` blocks;
  join the text blocks with newlines. "Lines" below means the non-blank lines of that
  content.
- `<first line>`: the first line, truncated to 200 characters, followed by
  ` (+N more lines)` when there are more. Empty content shows `(no output)`.
- Error detail block (log only): the remaining lines of a failed result, each indented 4
  spaces. When there are more than 20 remaining lines, keep the first 5 and the last 15
  with an indented `... (N lines omitted)` between them. Compiler errors tend to sit at
  the top of the output and test summaries and tracebacks at the bottom.
- Tool results are matched to the tool name through the tool call id. Use `?` when the
  id is unknown.
- Echoed user prompts appear in neither output.
- Put the limits (200 characters, 20 / 5 / 15 lines) in module constants.

### Robustness

- Read `sys.stdin.buffer` line by line. Decode each line as UTF-8 with
  `errors="replace"`, so invalid bytes never crash the processor. Reconfigure stdout to
  UTF-8 with `errors="replace"`.
- Skip blank lines silently.
- In JSON formats, a non-blank line that does not parse to a JSON object is written to
  stdout unchanged and counted in `malformed_lines`. It is never signal-eligible. No
  per-line stderr warning.
- Use `.get()` with defaults for every field access. Unknown event and block types are
  ignored silently: real streams carry many types the processor does not need (pi
  `message_update`, `turn_end`, `tool_execution_*`, `agent_end`; amp `system`).
- If handling one parsed line raises, count it in `malformed_lines`, write one stderr line
  `format_output: skipped line N: <exception>`, and continue.
- **Real-time output:** flush stdout and the log after every write. Python block-buffers
  stdout when it is a pipe, which would delay the live display until the end of the
  iteration. Flushing the log keeps `tail -f` on the session log live.
- **Broken pipe:** on `BrokenPipeError` writing stdout, stop writing to stdout but keep
  reading stdin to EOF (so the agent CLI is not killed by SIGPIPE), keep writing the
  log, and still write the summary. Exit 0. After the error, point stdout at `os.devnull`
  (`os.dup2`). Otherwise the interpreter's shutdown flush raises again and Python exits
  with status 120.

### Implementation shape

- One file, about 300-350 lines, Python 3.9+, stdlib only (`argparse`, `json`, `os`, `sys`).
  Use `from __future__ import annotations` if using `X | None` hints.
- A base class owns the stream loop, JSON parsing, error recovery, flushing, signal
  scanning, summary accumulation and summary writing. It exposes small emit helpers
  (`text`, `thinking`, `tool`, `tool_result`, `error`). Only `text` is signal-eligible and
  counts toward `response_chars`. `tool_result` alone decides what goes to the screen
  versus the log only, so formats never deal with the split. Underneath, one writer
  method takes a `log_only` flag.
- Each format is a subclass with one `handle(obj)` method that calls the emit helpers and
  sets usage/error fields. The `text` format instead overrides per-line handling, because
  its input is not JSON.
- A module-level dict maps format names to classes and feeds argparse `choices`.
- Keep the file name `format_output.py` (underscore) so it is importable if ever needed.
  Tests still exercise it through the CLI.

## Formats

### `text` (plain passthrough)

For agents whose stdout is plain text: the test stub agent (`tests/stub_agent.sh`) and
any agent without a parser yet. Every non-blank line is displayed as-is and is
signal-eligible. All usage fields, `is_error` and `error` are `null`. Do not use it for an
agent that echoes its prompt to stdout; it would detect the prompt's signal.

### `stream-json` (amp, claude)

Real fixture: `amp.ndjson`. Claude-specific shapes come from Claude Code's documentation:
https://code.claude.com/docs/en/headless,
https://code.claude.com/docs/en/agent-sdk/cost-tracking, and the result-message schema in
the Agent SDK reference.

```json
{"type":"system","subtype":"init","session_id":"...","tools":[...]}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<echoed prompt>"}]}}
{"type":"assistant","message":{"type":"message","role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"..."},{"type":"tool_use","id":"toolu_1","name":"Read","input":{"path":"AGENTS.md"}}],"usage":{"input_tokens":1,"cache_creation_input_tokens":297,"cache_read_input_tokens":130234,"output_tokens":83,"max_tokens":300000}}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"...","is_error":false}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":17,"result":"<final assistant text>"}
```

Claude additions (from docs; no real capture yet):

```json
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_2","content":[{"type":"text","text":"Task completed"}]}]}}
{"type":"assistant","parent_tool_use_id":"toolu_parent","message":{...}}
{"type":"result","subtype":"success","is_error":false,"result":"Done.","total_cost_usd":0.0123,"usage":{...},"modelUsage":{"claude-sonnet-4-5":{"inputTokens":200,"outputTokens":150,"costUSD":0.0123,"contextWindow":200000}}}
{"type":"result","subtype":"error_max_turns","is_error":true,"errors":["Reached maximum number of turns"],"total_cost_usd":0.001}
```

Rules:

- `assistant` messages: `thinking`, `text`, and `tool_use` blocks are displayed in order.
  `text` blocks are signal-eligible only when the line's `parent_tool_use_id` is absent
  or null. Subagent text is displayed but not scanned.
- `user` messages: `tool_result` blocks are emitted as tool results (`is_error: true`
  gives a failed result; see "Screen vs. log"). `text` blocks are the echoed prompt: not displayed, not scanned.
- `result`: not displayed and not scanned. Its `result` string duplicates the final
  assistant text. It sets:
  - `is_error` from `is_error`. When true, `error` is the first available of: `errors`
    joined with `"; "`, `error`, or `subtype`. Also emit `[error] <error>`.
  - `cost` from `total_cost_usd` when present.
  - `context_max` from the largest `modelUsage.*.contextWindow` when present and
    `context_max` was not already set from `usage.max_tokens`.
- Context: from the `usage` of the **last top-level** assistant message,
  `context_used = input_tokens + cache_creation_input_tokens + cache_read_input_tokens +
  output_tokens` (missing keys count as 0). `context_max = usage.max_tokens` when present
  (amp includes it; claude does not).
- Without a `result` line, `is_error` stays `null`. amp's stream carries no cost, so
  `cost` stays `null` for amp. amp's balance-based cost stays in its bash hooks.

### `pi-json` (pi)

Real fixtures: `pi.ndjson`, `pi-error.ndjson`. Schema reference:
https://pi.dev/docs/latest/programmatic-usage/json-event-stream-mode

```json
{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"<echoed prompt>"}]}}
{"type":"message_end","message":{"role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"toolCall","id":"call_1","name":"read","arguments":{"path":"notes.txt"}}],"stopReason":"toolUse","usage":{"input":3941,"output":108,"cacheRead":0,"cacheWrite":0,"totalTokens":4049,"cost":{"total":0.00397}}}}
{"type":"message_end","message":{"role":"toolResult","toolCallId":"call_1","toolName":"read","content":[{"type":"text","text":"hello\n"}],"isError":false}}
{"type":"message_end","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"400: {...not a valid model ID...}","usage":{...}}}
```

Rules:

- Handle only `type == "message_end"`. Ignore every other event type, including
  `message_update`, which carries all-zero `usage` objects, and `turn_end` /
  `agent_end`, which repeat message content.
- `role == "assistant"`: display `thinking`, `text` (signal-eligible) and `toolCall`
  (`name`, `arguments`) blocks. If `stopReason == "error"`: `is_error = true`,
  `error = errorMessage`, emit `[error] <errorMessage>`. If any assistant message ends
  without an error and none has errored, `is_error = false`.
- `role == "toolResult"`: emit a tool result using `toolName`, `content`, `isError`.
- `role == "user"` / `"system"`: ignore (echoed prompt and system prompt).
- `cost` = sum of `usage.cost.total` over assistant messages (cost accrues per call).
  `context_used` = `usage.totalTokens` of the last assistant message (context size of
  the final call). `context_max` = `null`: pi's stream does not expose the window
  (`specs/tech-debt.md` item 5). `cost`/`context_used` are `null` only when no assistant
  usage was seen.

## Phases

Phase 1 must come first. Phases 2 and 3 depend only on Phase 1 and are independent of
each other.

### Phase 1: Core processor, `text` format, test harness

Work:

1. Create `lib/format_output.py` with the base class, the CLI, the summary writer, the
   robustness behavior above, and the `text` format.
2. Create `tests/test_format_output.py` using stdlib `unittest` (pytest is not stdlib and
   is not installed on the maintainer's machine). Tests run the processor as a
   subprocess (`sys.executable lib/format_output.py ...`) and assert on stdout, the
   summary JSON, and the exit code.
3. Add a `format_output` group to `tests/test_ralph.sh` that runs
   `python3 -m unittest discover -s tests -p 'test_format_output.py'` from the project
   root and records pass/fail with the existing assertion helpers. Include it in the
   default all-groups run and in the "Available groups" error message.

Tests (all through the CLI, `text` format unless noted):

- Empty stdin: exit 0, summary has `signal: null`, `response_chars: 0`, every
  usage/error field `null`, `malformed_lines: 0`.
- A line with REPLAN followed by a line with COMPLETE gives `signal: "COMPLETE"`. A line
  with only REPLAN gives `"REPLAN"`. No signal gives `null` with `response_chars > 0`.
- Invalid UTF-8 bytes in the input do not crash: exit 0, summary written.
- `--format bogus`: exit 2, stderr names the valid formats.
- `--summary` inside a nonexistent directory: exit 1.
- `--log` appends: a log file that already contains `PRE-EXISTING` still starts with it
  afterwards, followed by the processed lines.
- `--log` inside a nonexistent directory: exit 1.
- Streaming: write one line to the processor's stdin **without closing it** and read the
  formatted line from stdout within 5 seconds. This fails if output is buffered.
- Broken pipe: feed 10,000 lines with `--log` while the reader closes stdout after the
  first line. The processor exits 0, the summary records the signal on the last input
  line, and the log contains all 10,000 lines.

Validation: `./tests/test_ralph.sh format_output` passes, and `./tests/test_ralph.sh` (all
groups) still passes.

### Phase 2: `stream-json`

Work: implement `stream-json` per the rules above. Add tests.

Tests with `amp.ndjson` (expected values were derived with `jq` from the fixture, not
from the implementation):

- Summary: `signal: "COMPLETE"`, `response_chars: 2082`, `is_error: false`,
  `error: null`, `context_used: 130615` (1 + 297 + 130234 + 83), `context_max: 300000`,
  `context_pct: 44`, `cost: null`, `malformed_lines: 0`.
- Screen contains `[thinking] Let me start by reading the key files` and
  `[tool] Read: /home/mjeffe/src/mrj/ralph-loop/AGENTS.md`.
- Screen has no lines starting with `[tool result] ` or `[tool error] `. The log (via
  `--log`) has exactly 56 lines starting with `[tool result] ` and none starting with
  `[tool error] `.
- Neither output contains the echoed prompt's opening line
  `You are an expert software architect and planner working in Ralph plan mode.`
- `All other specs are satisfied.` appears exactly once on the screen (the `result`
  line is not re-printed).
- False-positive guard: the fixture minus its last `assistant` line and its `result` line
  gives `signal: null` and `response_chars > 0`. The echoed prompt and 10 tool results
  in the remaining input still contain the signal string.

Tests with inline lines (claude shapes from the docs):

- A successful `tool_result` whose `content` is a list of text blocks appears in the log
  with its text, and not on the screen. The same result with `is_error: true` produces
  a `[tool error] ` line on the screen.
- A failed `tool_result` with 30 non-blank lines (`line 1` .. `line 30`): the screen line
  ends with `(+29 more lines)`. The log has that line followed by indented `line 2` ..
  `line 6`, `... (9 lines omitted)`, then `line 16` .. `line 30` (29 remaining lines:
  first 5 + last 15, 9 omitted). The screen has none of
  the indented lines.
- An assistant message with usage lacking `max_tokens`, followed by a `result` with
  `total_cost_usd: 0.0123` and `modelUsage: {"m": {"contextWindow": 200000}}`, gives
  `cost: 0.0123`, `context_max: 200000`, and a computed `context_pct`.
- A `result` with `is_error: true`, `subtype: "error_max_turns"`,
  `errors: ["Reached maximum number of turns"]` gives `is_error: true`, `error`
  containing that message, and an `[error] ` display line.
- An assistant message with `parent_tool_use_id: "toolu_x"` whose text contains
  `<promise>COMPLETE</promise>` is displayed, but gives `signal: null`.
- A non-JSON line between two valid lines is displayed raw and gives
  `malformed_lines: 1`. Both valid lines are still displayed.

### Phase 3: `pi-json`

Work: implement `pi-json` per the rules above. Add tests.

Tests with `pi.ndjson` (values derived with `jq`):

- Summary: `signal: "COMPLETE"`, `is_error: false`, `context_used: 4241`,
  `context_max: null`, `context_pct: null`, `cost` approximately `0.00517305132`
  (sum of 0.00397101582, 0.00068396616, 0.00051806934; compare with a tolerance).
- Screen contains `[thinking] The user wants me to follow three steps`,
  `[tool] read: notes.txt`, `[tool] bash: ls does-not-exist`, and
  `[tool error] bash: ls: cannot access 'does-not-exist': No such file or directory (+1 more lines)`.
  It contains no `[tool result] ` line.
- Log contains everything above, plus
  `[tool result] read: hello from notes.txt (+1 more lines)` and, directly after the
  tool error line, the indented line `    Command exited with code 2`. Blank lines in the
  raw result are dropped.
- Neither output contains `This is a test of your tool output` (echoed prompt).
- False-positive guard: the fixture minus only its last assistant `message_end` line gives
  `signal: null`. The echoed user prompt and the `turn_end` line still contain the signal.

Tests with `pi-error.ndjson`:

- Summary: `is_error: true`, `error` contains `not a valid model ID`, `signal: null`,
  `response_chars: 0`. Screen contains an `[error] ` line.

## What This Spec Does NOT Cover

Done afterwards in one supervised commit (prompt: `integrate-output-pipeline-prompt.md`):

- Wiring the processor into `run_iteration` in `ralph` (with `--log "$SESSION_LOG"`
  replacing `| tee -a "$SESSION_LOG"`), reading the summary, and
  empty-response detection based on `response_chars` / `is_error`.
- `AGENT_OUTPUT_FORMAT` in every agent script. Removing `agent_format_display` and
  `agent_extract_response`. Keeping `agent_pre_iteration` / `agent_post_iteration` as stock
  hooks in every agent script.
- Keeping `tee "$RALPH_DIR/last_agent_output"` as the raw debug record.
- Declaring `python3` in `dependencies` and `prompts/templates/Dockerfile.base`.
- `install.sh` / `update.sh` `MANAGED_FILES`, and updates to `specs/loop-behavior.md`,
  `specs/agent-scripts.md`, `specs/project-structure.md`, `README.md`, and
  `specs/tech-debt.md`.
- Bash loop tests and stub agent changes.

Do not modify any of those files while building this spec.

## Success Criteria (for the COMPLETE signal)

All of:

1. `lib/format_output.py` exists and registers exactly `text`, `stream-json` and `pi-json`.
2. `tests/test_format_output.py` covers every test listed in the completed phases.
3. `./tests/test_ralph.sh format_output` and `./tests/test_ralph.sh` both pass.
4. `python3 lib/format_output.py --format pi-json --summary /tmp/s.json <
   tests/fixtures/format_output/pi.ndjson` prints readable output, and `/tmp/s.json`
   matches the Phase 3 expectations.
5. No file listed under "What This Spec Does NOT Cover" was modified.
