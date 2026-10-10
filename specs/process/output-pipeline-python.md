# Agent Output Pipeline — Python Extraction

## Purpose

Extract the agent output processing pipeline from bash into a shared Python module
(`lib/format-output.py`) with per-agent subclasses. This is Phase 1 of the two-phase
remediation described in `specs/tech-debt.md` item 3 (Agent Output Pipeline).

This spec covers only the Python module and its tests — purely additive files that
nothing references yet. The integration (modifying `ralph` and `agents/*.sh`) is done
separately in an interactive session to keep the cutover atomic and human-supervised.

## Context

The current output pipeline has three independent parsing passes in bash (display,
signal detection, usage extraction) that share no code and can silently drift apart.
46% of content blocks never reach the session log. Signal detection misses the
`result` message type. Usage extraction uses fragile grep-on-JSON. Per-agent
implementation quality varies widely. See `specs/tech-debt.md` for full details.

## End State

- `lib/format-output.py` — shared `OutputProcessor` base class (~150-200 lines)
- `lib/format-output/amp.py` — amp agent subclass (~30 lines)
- `lib/format-output/claude.py` — claude agent subclass (~30 lines, shares schema with amp)
- `lib/format-output/pi.py` — pi agent subclass (~40 lines, unique message_end schema)
- `lib/format-output/cline.py` — cline agent subclass (~40 lines, unique flat schema)
- `lib/format-output/codex.py` — codex stub (~20 lines, schema TBD)
- `tests/test_format_output.py` — pytest suite (~100-150 lines)
- `tests/fixtures/` — real NDJSON sample files from each agent for reproducible tests
- All tests pass. The module is callable as:
  ```bash
  agent_invoke "$prompt" \
      | python3 "$RALPH_DIR/lib/format-output.py" --agent "$AGENT" --summary "$summary_file" \
      | tee -a "$SESSION_LOG"
  ```
  but nothing calls it yet — that's the integration phase.

## Design Decisions

### Single-pass processing

The Python script reads stdin exactly once and produces all outputs in a single pass:
- Formatted human-readable text to stdout (replaces `agent_format_display`)
- Summary JSON to `--summary` file (replaces `agent_extract_response` for signal
  detection and `agent_post_iteration` for usage extraction)

No re-reading files. No multiple passes over the same data.

### Summary file format

Written at end of stream. Always valid JSON, even on error:

```json
{
  "signal": "COMPLETE" | "REPLAN" | null,
  "context_used": 12345,
  "context_max": 200000,
  "context_pct": 6,
  "cost": 0.0234,
  "tokens": 12345
}
```

When data is unavailable, fields are `null` rather than omitted or zeroed. Bash
callers test with `jq -r '.signal // empty'` and skip null-valued fields. The file
is always written, even on empty input or processing errors, so bash callers never
wait on a missing file.

### Signal detection scope

Signals (`<promise>COMPLETE</promise>`, `<promise>REPLAN</promise>`) are detected in
text content from ALL message types — including `user` (tool results), `result`
(final message), `message_end` (pi), `ask`/`say` (cline) — not just `assistant`
text blocks. This fixes the current bug where signals in result messages are missed.

Signal detection uses substring matching (`in`), not regex. The signal strings are
exact, well-known, and contain XML-like delimiters — regex offers no benefit.

The first signal seen wins. If COMPLETE appears in message 3 and REPLAN in message 5,
the summary reports COMPLETE. Both appearing in the same stream is a degenerate case
that should not happen with well-behaved agents; if it does, first-wins is unambiguous.

### Tool result visibility

`tool_result` blocks (in `user` messages from amp/claude) and tool results in other
schemas are displayed in the formatted output. This fixes the "46% of content blocks
never reach the log" gap:

```
[tool result] Read: specs/foo.md
...content truncated to 500 chars...
```

Truncation limit is a class constant (`TOOL_RESULT_MAX_CHARS = 500`), overridable
per subclass. A `--tool-result-limit N` CLI flag overrides at runtime. Pass 0 to
suppress tool results entirely.

Tool result blocks with error content (non-zero `is_error` in amp/claude) are always
shown regardless of truncation.

### Usage extraction

Uses `json.loads()` dictionary access with `.get()` defaults — never grep or regex.
Handles nested fields, missing keys, and unexpected shapes gracefully. The base class
provides a default `extract_usage(obj)` that works for the Anthropic stream-json
schema (amp/claude); subclasses override it for different schemas.

### Robustness

- Malformed JSON lines are skipped with a one-line warning to stderr. Processing
  continues with the next line.
- Empty lines are skipped silently.
- Lines that parse as valid JSON but lack expected fields use `.get()` defaults.
- The summary file is written even if the entire input was malformed (all nulls).
- Exit code is always 0 unless the input stream itself is unreadable (broken pipe
  before any data) or the summary file cannot be written.

### Stdlib only

No pip dependencies. Uses `json`, `sys`, `argparse`, `dataclasses`, `pathlib`,
`textwrap`, `re` (for COMPLETE/REPLAN detection in block text — actually, wait;
substring matching is simpler and sufficient for exact signal strings). All stdlib
modules available in Python 3.9+.

### Per-agent dispatch

The `--agent` CLI argument selects the subclass. The base class maintains a registry
dict mapping agent names to classes. Subclasses register themselves via a decorator
or explicit dict entry. Unknown agent names exit with a clear error message listing
known agents.

### Display formatting conventions

Consistent across all agents:

| Content type | Format |
|---|---|
| Thinking / reasoning | `[thinking] text here` |
| Text | `text here` (no prefix) |
| Tool call | `[tool] name: args_summary` (first relevant arg, truncated to 200 chars) |
| Tool result | `[tool result] name: content` (content truncated to TOOL_RESULT_MAX_CHARS) |
| Error / failure | `[error] message` |

## Agent NDJSON Schemas (Reference)

### amp / claude (Anthropic stream-json)

```json
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"..."},{"type":"tool_use","id":"...","name":"read","input":{"path":"..."}}],"usage":{"input_tokens":100,"output_tokens":50,"max_tokens":200000}}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"...","content":"...","is_error":false}]}}
{"type":"result","message":{"content":[{"type":"text","text":"completed message"}]}}
```

### pi (message_end)

```json
{"type":"message_end","message":{"role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"..."},{"type":"toolCall","name":"read","arguments":{"path":"..."}}],"usage":{"totalTokens":100,"cost":{"total":0.001}}}}
```

The `role` field in `message.content[]` is `"assistant"` for output. System/user
role messages also appear in the stream; the pi subclass filters to
`role == "assistant"`.

Note: pi's stream does NOT expose `max_tokens` / context window size. The pi
subclass sets `context_max` to `null` in the summary. See `specs/tech-debt.md`
item 5 for the broader context-window gap.

### cline (flat ask/say)

```json
{"type":"ask","text":"...","reasoning":"...","ts":123,"partial":true}
{"type":"ask","text":"...","reasoning":"...","ts":124,"partial":false}
{"type":"say","text":"...","ts":125}
```

`partial: true` messages are intermediate streaming chunks and should be suppressed
(only emit complete messages). `reasoning` is optional and maps to `[thinking]`.
There are no tool_use/tool_result blocks in the stream — cline's tool calls appear
inline in `say` text.

cline's usage data is NOT in the NDJSON stream. It lives in
`taskHistory.json` on disk, which is handled by `agent_pre_iteration` and
`agent_post_iteration` as a pre/post hook pattern. The cline subclass sets all
usage fields to `null` in the summary — the existing hooks in `agents/cline.sh`
remain responsible for usage tracking until the integration phase.

### codex (TBD)

Schema unknown. The codex subclass is a stub that passes through raw text and sets
all summary fields to `null`. This is an improvement over the current stub which
errors out — at least codex can be used with the loop, even if output is unformatted.

## Phases

### Phase 1: Base class + amp implementation + test fixtures

**Order:** 1 of 5. Must complete before Phase 2-5 (other subclasses depend on the
base class interface).

**Work:**
1. Create `lib/format-output.py` with the `OutputProcessor` base class.
2. Create `lib/format-output/__init__.py` (empty).
3. Create `lib/format-output/amp.py` with the `AmpProcessor` subclass.
4. Create `tests/fixtures/` directory.
5. Capture real NDJSON samples from amp, claude, pi, and cline (one sample per
   agent, covering all content block types + a COMPLETE signal). Write each as a
   `.ndjson` fixture file plus a `.expected` file with the expected formatted output
   and expected summary JSON.
6. Create `tests/test_format_output.py` with pytest tests for the base class and
   amp subclass, driven by fixtures.

**Key design work in this phase:**

The base class must define the interface that subclasses implement. Based on the
schema analysis, the minimal per-subclass interface is:

```python
class OutputProcessor:
    agent_name: str  # set by subclass

    def get_message_type(self, obj: dict) -> str | None:
        """Return the message type string for dispatch, or None to skip."""

    def get_content_blocks(self, obj: dict) -> list[dict]:
        """Return content blocks from a parsed JSON object."""

    def format_block(self, block: dict, msg_type: str) -> str | None:
        """Format a single content block for display, or None to skip."""

    def extract_usage(self, obj: dict) -> dict | None:
        """Extract usage data, or None if not present."""
```

Each subclass overrides these four methods (plus `agent_name`). The base class
handles: line reading, JSON parsing, error recovery, signal scanning,
summary accumulation, stdout writing, stderr warnings, and summary file output.

Signal detection is built into the base class's text-emitting method. Every time
a text block is emitted, the base scans it for signal strings and records the
first match.

**Edge cases to handle in Phase 1:**
- Empty input (no lines): write summary with all nulls, exit 0
- Every line malformed: write summary with all nulls, warnings to stderr, exit 0
- Stream with no usage data: summary has null usage fields
- Stream with no signals: summary has null signal
- Very long text blocks: no truncation for text/thinking blocks (only tool results)
- Unicode content: handled by Python's default UTF-8 I/O
- Multiple content blocks in one message: all formatted in order
- Unknown block types: skipped with a one-line stderr warning

**Validation (Phase 1):**
- `python3 -m pytest tests/test_format_output.py -v` — all tests pass
- Pipe each fixture through the processor and diff against `.expected`:
  ```bash
  for agent in amp claude pi cline; do
      python3 lib/format-output.py --agent "$agent" --summary /tmp/summary.json \
          < tests/fixtures/${agent}.ndjson > /tmp/out.txt
      diff tests/fixtures/${agent}.expected /tmp/out.txt
  done
  ```
- Manual inspection: output is human-readable and matches the formatting conventions

### Phase 2: claude implementation

**Order:** 2 of 5. Depends on Phase 1 (base class interface stable).

**Work:**
1. Create `lib/format-output/claude.py` with `ClaudeProcessor(AmpProcessor)`.
   Since claude uses the same stream-json schema as amp, `ClaudeProcessor` should
   inherit from `AmpProcessor` — it may need zero overrides. If claude's tool_use
   or tool_result shapes differ, override the relevant methods.
2. Add claude-specific tests to the pytest suite.

**Validation:**
- `python3 -m pytest tests/test_format_output.py -v` — all tests pass including claude
- Diff against claude fixture `.expected`

### Phase 3: pi implementation

**Order:** 3 of 5. Depends on Phase 1. Independent of Phase 2.

**Work:**
1. Create `lib/format-output/pi.py` with `PiProcessor(OutputProcessor)`.
   pi's unique characteristics:
   - All content arrives in `message_end` events, not streamed per-block
   - Filter to `message.role == "assistant"` to skip system/user echoes
   - Content block type is `toolCall` (not `tool_use`) with `arguments` (not `input`)
   - Usage is at `message.usage.totalTokens` with `cost.total` — no `max_tokens`
   - `max_tokens` is unavailable → set `context_max` to `null`
2. Add pi-specific tests.

**Edge cases specific to pi:**
- `message_end` events with `role != "assistant"` (system/user): skip entirely
- `message_end` events with empty content array: skip
- No `message_end` events at all: write summary with all nulls
- Multiple `message_end` events: sum cost across all, use last event's totalTokens

**Validation:**
- `python3 -m pytest tests/test_format_output.py -v` — all tests pass including pi
- Diff against pi fixture `.expected`

### Phase 4: cline implementation

**Order:** 4 of 5. Depends on Phase 1. Independent of Phases 2-3.

**Work:**
1. Create `lib/format-output/cline.py` with `ClineProcessor(OutputProcessor)`.
   cline's unique characteristics:
   - Flat `ask`/`say` message types (no nested content blocks)
   - `partial: true` messages must be suppressed (streaming chunks)
   - `reasoning` field maps to `[thinking]` display
   - No tool_use/tool_result blocks in stream (tool calls are inline in `say` text)
   - No usage data in stream (set all usage fields to `null` in summary)
2. Add cline-specific tests.

**Edge cases specific to cline:**
- `partial: true` messages: skip (do not emit to stdout)
- `partial` field absent: treat as `false` (complete message)
- `reasoning` present but empty string: skip thinking prefix
- Mixed ask/say messages: both are formatted the same way

**Validation:**
- `python3 -m pytest tests/test_format_output.py -v` — all tests pass including cline
- Diff against cline fixture `.expected`

### Phase 5: codex stub + final integration test

**Order:** 5 of 5. Depends on Phases 1-4 complete.

**Work:**
1. Create `lib/format-output/codex.py` with `CodexProcessor(OutputProcessor)`.
   This is a stub — codex's NDJSON schema is unknown. It should:
   - Pass through raw lines as-is (or attempt to pretty-print JSON)
   - Set all summary fields to `null`
   - Not error out (unlike the current bash stub)
   - Log a warning on first line: "codex output format unknown — displaying raw output"
2. Add a codex smoke test (pipes one line through, verifies no crash).
3. Run the full test suite one final time.
4. Verify all fixtures produce matching output.

**Validation:**
- `python3 -m pytest tests/test_format_output.py -v` — all tests pass
- All five agent fixtures diff cleanly against their `.expected` files
- `python3 lib/format-output.py --agent unknown 2>&1` prints a clear error listing known agents

## Dependencies Between Phases

```
Phase 1 (Base + amp)
  ├── Phase 2 (claude — inherits from AmpProcessor)
  ├── Phase 3 (pi — independent, unique schema)
  ├── Phase 4 (cline — independent, unique schema)
  └── Phase 5 (codex stub + final integration)
```

Phases 2, 3, and 4 are independent of each other and can be built in any order.
Phase 5 requires all four agent implementations to exist.

## What This Spec Does NOT Cover

- **Modifying `ralph`** to use the Python callout instead of the three bash functions
- **Modifying `agents/*.sh`** to remove `agent_format_display`, `agent_extract_response`,
  `agent_post_iteration`
- **Updating `install.sh` / `update.sh`** `MANAGED_FILES` for the new Python files
- **Updating `specs/agent-scripts.md`** for the new contract

These integration steps are done interactively after this spec is built, in a single
atomic commit. See the rationale in `specs/tech-debt.md` item 3.

## Config Changes Required

To run this spec through ralph, set `PROCESS_DIR` in `config`:

```bash
PROCESS_DIR="specs/process"
```

Restore to empty after the build completes (or leave set if you expect more process
specs in the future).

Run as:
```bash
ralph plan --process
ralph build
```

## Test Suite Requirements

- Uses pytest (available as `python3 -m pytest` with no additional install on most systems)
- Test fixtures are real NDJSON captured from actual agent runs
- Tests validate: correct block types emitted, correct signal detection, correct
  usage extraction, correct summary JSON, graceful handling of malformed input,
  empty input, and partial messages (cline)
- The existing bash test suite (`./tests/test_ralph.sh`) is unaffected — these are
  new, independent tests

## Success Criteria (for COMPLETE signal)

All of:
1. `lib/format-output.py` exists with `OutputProcessor` base class
2. `lib/format-output/{amp,claude,pi,cline,codex}.py` all exist
3. `tests/test_format_output.py` exists with tests covering all agents
4. `tests/fixtures/` contains real NDJSON samples and `.expected` files for each agent
5. `python3 -m pytest tests/test_format_output.py -v` passes with zero failures
6. All fixture diffs are clean