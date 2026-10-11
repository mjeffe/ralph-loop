# Implementation Plan

Plan Type: process
Plan Command: ralph plan --process
Primary Process Specs: specs/process/output-pipeline-python.md

## Summary

Build `lib/format_output.py`, a single-pass, stdlib-only Python processor that turns an
agent CLI's NDJSON stream into readable screen/log lines plus a summary JSON file, along
with its unittest suite and a `format_output` group in `tests/test_ralph.sh`. The work is
purely additive: nothing in `ralph` or `agents/*.sh` calls the processor yet. Integration
is a separate supervised step (`integrate-output-pipeline-prompt.md`) and is out of scope.

Phase order (from the spec, "Phases"): Phase 1 first. Phases 2 and 3 depend only on
Phase 1 and are independent of each other.

Planning survey (2026-10-11, at commit d3f118e):

- `lib/format_output.py` and `tests/test_format_output.py` do not exist. `lib/` holds
  `help/`, `plan-filter.sh`, `sandbox.sh`.
- Fixtures already exist and must not be regenerated: `tests/fixtures/format_output/`
  `amp.ndjson` (36 lines), `pi.ndjson` (34 lines), `pi-error.ndjson` (12 lines), `README.md`.
- Spot-checked spec expectations against fixtures with `jq`: amp has 56 `tool_result`
  blocks, 0 with `is_error: true`; top-level assistant text totals 2082 chars; last
  top-level usage is 1 + 297 + 130234 + 83 = 130615 with `max_tokens` 300000. pi assistant
  `message_end` lines have totalTokens 4049, 4152, 4241 and cost.total 0.00397101582,
  0.00068396616, 0.00051806934. All match the spec.
- `python3 --version` is 3.10.12 locally; the spec targets 3.9+.
- Baseline: `./tests/test_ralph.sh` passes, 367 passed / 0 failed.
- Test groups live in `tests/test_ralph.sh` `main()`: a `case` per group and an
  "Available groups: cli, signals, core, install_update, plan_filter, sandbox, loop" error
  line. Assertion helpers (`assert_eq`, `assert_contains`, `assert_exit_code`, ...) are in
  `tests/test_helpers.sh` and update the `PASS`/`FAIL`/`TESTS` counters.
- `test_shellcheck_shipped_scripts` (`tests/test_core.sh:443`) lints `lib/*.sh` only, so a
  `.py` file in `lib/` is not linted. No test requires every `lib/` file to be in
  `MANAGED_FILES` (`tests/test_core.sh:456` only compares installer vs updater arrays).

Destructive-change analysis: none. Every task creates new files or extends
`tests/test_ralph.sh`. No pre-existing shared artifact is removed, so no `Pre-check:`
blocks are needed.

Previous plan: the prior gap-driven plan (help extraction, `lib/sandbox.sh` extraction,
`wait-for-db` refresh, installer/updater MANAGED_FILES; Tasks 1-4, all complete) is
superseded by this process plan. Its outcomes still exist (`lib/help/*.txt`,
`lib/sandbox.sh`) and are recorded in git history.

## Cross-cutting constraints

- Do NOT modify any file the spec lists under "What This Spec Does NOT Cover": `ralph`,
  `agents/*.sh`, `dependencies`, `prompts/templates/Dockerfile.base`, `install.sh`,
  `update.sh`, `specs/loop-behavior.md`, `specs/agent-scripts.md`,
  `specs/project-structure.md`, `README.md`, `specs/tech-debt.md`, `tests/stub_agent.sh`,
  and the bash loop tests (`tests/test_loop.sh`). `tests/test_ralph.sh` is allowed (Task 2).
- Do not regenerate or edit the existing fixtures in `tests/fixtures/format_output/`. Tests
  that need a truncated fixture (false-positive guards) build the reduced input in the test
  from the fixture lines. If a synthesized fixture file is ever added, record it in the
  fixtures `README.md` table as the README requires.
- `lib/format_output.py`: one file, Python 3.9+, stdlib only (`argparse`, `json`, `os`,
  `sys`). Use `from __future__ import annotations` if using `X | None` hints. Keep the
  underscore file name.
- Tests use stdlib `unittest` only (pytest is not installed). Every test drives the CLI as
  a subprocess via `sys.executable lib/format_output.py ...` and asserts on stdout, the
  summary JSON, the log file, and the exit code. Paths resolve relative to the project root.
- Expected values in fixture tests come from the spec (derived with `jq`), never from
  running the implementation.
- Signal invariant (must not regress): signals are detected only in assistant-authored,
  top-level response text emitted through the `text` helper. Never in echoed prompts,
  tool results, thinking, subagent output, `result` lines, or malformed (non-JSON) lines.
  COMPLETE wins when both COMPLETE and REPLAN appear.
- Display limits (200 chars; 20 / 5 / 15 lines) are module constants.
- Repository style (AGENTS.md): ASCII only, no em dashes, 4-space indent, 120-char max
  lines, snake_case, conventional commit prefixes, no agent attribution.
- `tests/test_format_output.py` has module-level `FIXTURES` / `read_fixture(name)` and
  `ndjson(*objs)` helpers (added in Task 3); reuse them for fixture and inline-line tests.
- The worktree has untracked `integrate-output-pipeline-prompt.md` and
  `pi-deepseek-guide.md`. Leave them alone and do not commit them.

## Phase 1: Core processor, `text` format, test harness

Source: `specs/process/output-pipeline-python.md` - Phase 1 (Work steps 1-3, Tests,
Validation), plus "Interface", "Display conventions", "Robustness", "Implementation shape",
and "Formats / text".

### Task 1: Core processor with `text` format and its unittest suite (Phase 1, steps 1-2)
**Status:** complete

Notes (completed 2026-10-11):
- Added `lib/format_output.py` (base `Processor`, `TextProcessor`, `FORMATS` dict, `main()`)
  and `tests/test_format_output.py` (11 tests, all passing; full suite still 367/0).
- Helper API for Tasks 3/4: `self.text(s)`, `self.thinking(s)`,
  `self.tool(name, input, call_id=None)` (records `call_id -> name`),
  `self.tool_result(content, is_error, call_id=None, name=None)` (name falls back to the
  recorded id mapping, then `?`), `self.error(msg)`. Formats set `self.is_error`,
  `self.error_message`, `self.context_used`, `self.context_max`, `self.cost` directly and
  define `name` plus `handle(obj)`; register in `FORMATS`. Base `process_line` already does
  the JSON parse / raw-line / `malformed_lines` path.
- Scratch-checked the not-yet-exercised helpers: tool summary key priority, newline
  replacement, compact JSON fallback, `(no output)`, `(+N more lines)`, and the 30-line
  error detail block (`line 2`..`line 6`, `... (9 lines omitted)`, `line 16`..`line 30`).
- Mutation-checked the tests: removing the stdout flush fails the streaming test; removing
  the `os.dup2` fails the broken-pipe test.
- Discovered: running the unittest suite leaves an untracked `tests/__pycache__/`. Fixed by
  adding `__pycache__/` to `.gitignore` (not on the spec's do-not-modify list).
- Assumption / Spec gap: error detail lines are not truncated to 200 chars (spec only
  truncates `<first line>` and tool summaries); `malformed_lines` line numbers in the stderr
  message count physical input lines including blank ones.

Create the processor base and the `text` format, plus the unittest file covering every
Phase 1 test.

Files to create:
- `lib/format_output.py`
- `tests/test_format_output.py`

Read first: the spec sections "Interface" (Invocation, Summary file), "Display
conventions", "Robustness", "Implementation shape", "Formats / text", and "Phase 1".

End state of `lib/format_output.py`:
- CLI: `--format` (required, argparse `choices` from a module-level dict mapping format
  name -> class; for now only `text`), `--summary PATH` (required), `--log PATH`
  (optional, opened in append mode before reading stdin; failure -> exit 1).
- Exit codes: 0 when the stream was processed (including empty or malformed input); 1 when
  the log cannot be opened or the summary cannot be written; 2 on usage errors (argparse).
- Base class owns: reading `sys.stdin.buffer` line by line, UTF-8 decode with
  `errors="replace"`, stdout reconfigured to UTF-8 `errors="replace"`, skipping blank lines,
  JSON parsing for JSON formats (non-object or unparseable line -> written raw to stdout,
  counted in `malformed_lines`, never signal-eligible, no stderr warning), per-line
  exception recovery (count in `malformed_lines`, one stderr line
  `format_output: skipped line N: <exception>`), signal scanning, summary accumulation,
  and the summary writer (written once in a `finally` block; every key always present:
  `format`, `signal`, `response_chars`, `is_error`, `error`, `context_used`, `context_max`,
  `context_pct`, `cost`, `malformed_lines`; `context_pct` computed only when both context
  values are known and `context_max > 0`).
- Emit helpers on the base class: `text` (the only signal-eligible helper; adds `len()` to
  `response_chars`), `thinking` (`[thinking] <text>`), `tool` (`[tool] <name>: <summary>`
  using the input-key priority list, newlines -> spaces, 200-char truncation, compact JSON
  fallback), `tool_result` (screen vs log split, first line with ` (+N more lines)`,
  `(no output)`, log-only error detail block indented 4 spaces with the 20 / 5 / 15 rule,
  content as string or list of text blocks), `error` (`[error] <message>`). One underlying
  writer method takes a `log_only` flag. All of these follow "Display conventions" even
  though only `text` and the raw-line path are exercised in this phase.
- Every write flushes stdout and the log. On `BrokenPipeError` writing stdout: stop writing
  stdout, `os.dup2` stdout onto `os.devnull`, keep reading stdin to EOF, keep writing the
  log, still write the summary, exit 0.
- `text` format: overrides per-line handling (input is not JSON); every non-blank line is
  displayed as-is and is signal-eligible; all usage fields, `is_error`, `error` stay `null`.

End state of `tests/test_format_output.py` (all `text` format unless noted), one test per
Phase 1 bullet:
- Empty stdin -> exit 0, `signal: null`, `response_chars: 0`, all usage/error fields
  `null`, `malformed_lines: 0`.
- REPLAN line then COMPLETE line -> `"COMPLETE"`; only REPLAN -> `"REPLAN"`; no signal ->
  `null` with `response_chars > 0`.
- Invalid UTF-8 bytes -> exit 0, summary written.
- `--format bogus` -> exit 2, stderr names the valid formats.
- `--summary` in a nonexistent directory -> exit 1.
- `--log` appends: file pre-seeded with `PRE-EXISTING` still starts with it, followed by
  the processed lines.
- `--log` in a nonexistent directory -> exit 1.
- Streaming: write one line without closing stdin; the formatted line is readable from
  stdout within 5 seconds (use `select` or a reader thread with a timeout; then close
  stdin and reap the process).
- Broken pipe: 10,000 lines with `--log`, reader closes stdout after the first line ->
  exit 0, summary records the signal on the last input line, log has all 10,000 lines.

Verify:
- `python3 -m unittest discover -s tests -p 'test_format_output.py'` (from the project
  root) -> all tests pass, 9+ tests run.
- `printf 'hello\n<promise>COMPLETE</promise>\n' | python3 lib/format_output.py --format text --summary /tmp/fo_s.json; echo $?`
  -> prints both lines, exit 0; `/tmp/fo_s.json` has `"signal": "COMPLETE"` and
  `"response_chars"` > 0.
- `grep -E '^import|^from' lib/format_output.py` -> only stdlib modules
  (`__future__`, `argparse`, `json`, `os`, `sys`).
- `./tests/test_ralph.sh` still reports 0 failed.

<!-- Sizing: files=2, refs=1 (spec only; no existing code to study), subsystems=[python CLI/stream processor, python unittest], independent_components=1. Signals fired: 0/4. Decision: keep. The streaming and broken-pipe behavior are the riskiest parts; the tests listed above are the acceptance gate for them. -->

### Task 2: Add `format_output` group to tests/test_ralph.sh (Phase 1, step 3)
**Status:** complete
**Depends on:** Task 1

Notes (complete): Added `run_format_output_tests` to `tests/test_ralph.sh`. It runs the
unittest discover command from `$RALPH_DIR` inside `$(...) || rc=$?`, records one
`assert_eq` on the exit code, and echoes the captured unittest output on failure. Wired into
the all-groups run and the `format_output` case; the "Available groups" line now ends with
`format_output`. Verified: group alone -> 1 passed, exit 0; full suite -> 368 passed,
0 failed; a temporarily broken assertion -> group reports 1 failed with the traceback, exit 1
(reverted). Future tasks add tests to `tests/test_format_output.py` only; the bash group
count stays at one assertion regardless of how many unittest cases exist.

Hook the unittest suite into the bash test runner.

Files to change:
- `tests/test_ralph.sh` (`main()` group dispatch, the all-groups block, the
  "Available groups" error message, and a new `run_format_output_tests` function in the
  "Test groups" section)

Reference: `tests/test_helpers.sh` assertion helpers (`assert_eq`, `assert_exit_code`)
and the existing `run_*_tests` functions for style.

End state:
- A `run_format_output_tests` function runs
  `python3 -m unittest discover -s tests -p 'test_format_output.py'` from the project root
  (`$RALPH_DIR`), captures its exit code without tripping `set -euo pipefail`, and records
  pass/fail through an existing assertion helper. On failure, print the unittest output so
  the cause is visible.
- `./tests/test_ralph.sh format_output` runs only this group.
- The no-argument (all groups) run includes it.
- The unknown-group error message lists `format_output` among the available groups.
- No other test file or shipped script changes.

Verify:
- `./tests/test_ralph.sh format_output` -> group runs, 0 failed, exit 0.
- `./tests/test_ralph.sh` -> 0 failed; total is the 367 baseline plus the new assertion(s).
- `./tests/test_ralph.sh bogus 2>&1 | grep 'Available groups'` -> the line includes
  `format_output`.
- Temporarily break one assertion in `tests/test_format_output.py` (do not commit) and
  confirm `./tests/test_ralph.sh format_output` reports a failure and exits 1; then revert.

<!-- Sizing: files=1, refs=2 (test_ralph.sh, test_helpers.sh), subsystems=[bash test harness], independent_components=1. Signals fired: 0/4. Decision: keep. Separate from Task 1 because it has a distinct verification surface (bash harness wiring) and is spec step 3 in an explicit numbered sequence. -->

## Phase 2: `stream-json` format

Source: `specs/process/output-pipeline-python.md` - Phase 2, plus "Formats / stream-json"
and "Display conventions".
Depends on: Phase 1. Independent of Phase 3.

### Task 3: Implement `stream-json` format with amp-fixture and claude-shape tests (Phase 2)
**Status:** complete
**Depends on:** Task 2

Notes (complete): Added `StreamJsonProcessor` (registered as `stream-json`) to
`lib/format_output.py`; the base `tool_result` helper already matched the spec and was not
changed. Subagent text (`parent_tool_use_id` set) is written via the plain writer so it is
displayed but not counted or scanned. Added `TestStreamJsonAmpFixture` (summary, display,
false-positive guard built in-test from fixture lines) and `TestStreamJsonShapes` (inline
claude shapes, 30-line error detail block, cost/modelUsage context window, error result,
subagent text, malformed line, plus unknown tool id -> `?` and no-result -> `is_error: null`).
Verified: amp fixture summary matches the spec; mutating the handler to scan tool results
makes the guard test fail (reverted); full suite 368 passed, 0 failed.
Assumption / Spec gap: a `result` line without a boolean `is_error` leaves `is_error`
unchanged (null); when `is_error` is true but `errors`, `error`, and `subtype` are all
absent, `error` is `"unknown error"`. Only usage of top-level assistant messages updates
context; `context_max` keeps the last seen `usage.max_tokens`.

Add the `stream-json` subclass (amp, claude) and its tests.

Files to change:
- `lib/format_output.py` (new subclass with `handle(obj)`, register `stream-json` in the
  format dict)
- `tests/test_format_output.py` (new test class)

Read first: spec "Formats / stream-json" rules and Phase 2 tests;
`tests/fixtures/format_output/amp.ndjson` (inspect with `jq`, the file is large per line).

End state (handler rules):
- `assistant`: display `thinking`, `text`, `tool_use` blocks in order; `text` is
  signal-eligible only when `parent_tool_use_id` is absent or null (subagent text is
  displayed but not scanned). Context from the `usage` of the last top-level assistant
  message: `context_used` = input + cache_creation_input + cache_read_input + output
  tokens (missing keys = 0); `context_max = usage.max_tokens` when present.
- `user`: `tool_result` blocks -> `tool_result` helper (`is_error: true` -> failed result),
  matched to the tool name by `tool_use_id` (use `?` if unknown). `text` blocks (echoed
  prompt) are neither displayed nor scanned.
- `result`: not displayed, not scanned. Sets `is_error`; when true, `error` = `errors`
  joined with `"; "`, else `error`, else `subtype`, and emits `[error] <error>`. Sets
  `cost` from `total_cost_usd`; sets `context_max` from the largest
  `modelUsage.*.contextWindow` only if not already set from `usage.max_tokens`.
- Without a `result` line `is_error` stays `null`; amp `cost` stays `null`.
- If Task 1's shared `tool_result` helper does not match the expectations below, fix it in
  the base class (not in the subclass).

Tests (exact values from the spec):
- amp summary: `signal: "COMPLETE"`, `response_chars: 2082`, `is_error: false`,
  `error: null`, `context_used: 130615`, `context_max: 300000`, `context_pct: 44`,
  `cost: null`, `malformed_lines: 0`.
- amp screen contains `[thinking] Let me start by reading the key files` and
  `[tool] Read: /home/mjeffe/src/mrj/ralph-loop/AGENTS.md`.
- amp screen has no lines starting `[tool result] ` or `[tool error] `; log has exactly 56
  lines starting `[tool result] ` and none starting `[tool error] `.
- Neither output contains
  `You are an expert software architect and planner working in Ralph plan mode.`
- `All other specs are satisfied.` appears exactly once on the screen.
- False-positive guard: fixture minus its last `assistant` line and its `result` line ->
  `signal: null`, `response_chars > 0` (build the reduced input in the test).
- Inline claude shapes: list-of-text-blocks `tool_result` in log not screen; same with
  `is_error: true` -> `[tool error] ` on screen.
- Failed result with `line 1` .. `line 30`: screen line ends `(+29 more lines)`; log has
  indented `line 2` .. `line 6`, `... (9 lines omitted)`, `line 16` .. `line 30`; screen has
  none of the indented lines.
- Usage without `max_tokens` + `result` with `total_cost_usd: 0.0123` and
  `modelUsage: {"m": {"contextWindow": 200000}}` -> `cost: 0.0123`, `context_max: 200000`,
  computed `context_pct`.
- `result` with `is_error: true`, `subtype: "error_max_turns"`,
  `errors: ["Reached maximum number of turns"]` -> `is_error: true`, `error` contains the
  message, `[error] ` line displayed.
- Assistant with `parent_tool_use_id: "toolu_x"` containing `<promise>COMPLETE</promise>`
  -> displayed, `signal: null`.
- Non-JSON line between two valid lines -> displayed raw, `malformed_lines: 1`, both valid
  lines still displayed.

Verify:
- `./tests/test_ralph.sh format_output` -> 0 failed.
- `python3 lib/format_output.py --format stream-json --summary /tmp/fo_amp.json < tests/fixtures/format_output/amp.ndjson`
  -> readable output; `jq -c '{signal,response_chars,context_used,context_max,context_pct}' /tmp/fo_amp.json`
  -> `{"signal":"COMPLETE","response_chars":2082,"context_used":130615,"context_max":300000,"context_pct":44}`.
- `./tests/test_ralph.sh` -> 0 failed.
- `git diff --name-only d3f118e..HEAD` plus `git status --short` -> no file from the
  Cross-cutting "Do NOT modify" list appears.

<!-- Sizing: files=2, refs=2 (spec, amp.ndjson; plus the Task 1 module being extended), subsystems=[python stream processor, python unittest], independent_components=1. Signals fired: 0/4. Decision: keep. amp and claude shapes share one handler, so splitting them would duplicate setup without separating concerns. -->

## Phase 3: `pi-json` format

Source: `specs/process/output-pipeline-python.md` - Phase 3, plus "Formats / pi-json" and
"Success Criteria".
Depends on: Phase 1. Independent of Phase 2 (may be built before or after it).

### Task 4: Implement `pi-json` format with pi fixture tests (Phase 3)
**Status:** complete
**Depends on:** Task 2

Notes (complete): Added `PiJsonProcessor` (registered as `pi-json`) to
`lib/format_output.py`; it reuses the base emit helpers unchanged. Added
`TestPiJsonFixtures` (summary, display, false-positive guard built in-test by dropping the
last assistant `message_end` line, and the `pi-error.ndjson` case). `--help` now lists
exactly `pi-json`, `stream-json`, `text`. `./tests/test_ralph.sh` -> 368 passed, 0 failed.
Assumption / Spec gap: an assistant `usage` object without `cost.total` or `totalTokens`
counts as 0 (so `pi-error.ndjson` yields `cost: 0`, `context_used: 0`); both stay `null`
only when no assistant `usage` was seen, as the spec states.

Add the `pi-json` subclass and its tests.

Files to change:
- `lib/format_output.py` (new subclass with `handle(obj)`, register `pi-json`)
- `tests/test_format_output.py` (new test class)

Read first: spec "Formats / pi-json" rules and Phase 3 tests;
`tests/fixtures/format_output/pi.ndjson` and `pi-error.ndjson`.

End state (handler rules):
- Handle only `type == "message_end"`; ignore all other event types (`message_update`
  carries all-zero usage; `turn_end` / `agent_end` repeat content).
- `role == "assistant"`: display `thinking`, `text` (signal-eligible), and `toolCall`
  (`name`, `arguments`) blocks. `stopReason == "error"` -> `is_error = true`,
  `error = errorMessage`, emit `[error] <errorMessage>`. If any assistant message ends
  without error and none has errored -> `is_error = false`.
- `role == "toolResult"`: `tool_result` helper with `toolName`, `content`, `isError`.
- `role == "user"` / `"system"`: ignored.
- `cost` = sum of `usage.cost.total` over assistant messages; `context_used` =
  `usage.totalTokens` of the last assistant message; `context_max` = `null`. `cost` and
  `context_used` are `null` only when no assistant usage was seen.

Tests (exact values from the spec):
- pi summary: `signal: "COMPLETE"`, `is_error: false`, `context_used: 4241`,
  `context_max: null`, `context_pct: null`, `cost` approximately `0.00517305132`
  (`assertAlmostEqual` with a tolerance).
- Screen contains `[thinking] The user wants me to follow three steps`,
  `[tool] read: notes.txt`, `[tool] bash: ls does-not-exist`, and
  `[tool error] bash: ls: cannot access 'does-not-exist': No such file or directory (+1 more lines)`;
  no `[tool result] ` line.
- Log contains the above plus `[tool result] read: hello from notes.txt (+1 more lines)`
  and, directly after the tool error line, `    Command exited with code 2` (blank lines in
  the raw result dropped).
- Neither output contains `This is a test of your tool output`.
- False-positive guard: fixture minus only its last assistant `message_end` line ->
  `signal: null`.
- `pi-error.ndjson`: `is_error: true`, `error` contains `not a valid model ID`,
  `signal: null`, `response_chars: 0`, screen has an `[error] ` line.

Verify:
- `./tests/test_ralph.sh format_output` -> 0 failed.
- Success criterion 4: `python3 lib/format_output.py --format pi-json --summary /tmp/s.json < tests/fixtures/format_output/pi.ndjson`
  prints readable output and `/tmp/s.json` matches the Phase 3 summary expectations.
- `./tests/test_ralph.sh` -> 0 failed.
- `git diff --name-only d3f118e..HEAD` plus `git status --short` -> no file from the
  Cross-cutting "Do NOT modify" list appears (success criterion 5).
- If Phase 2 (Task 3) is also complete: `python3 lib/format_output.py --help` lists exactly
  `text`, `stream-json`, `pi-json` (success criterion 1).

<!-- Sizing: files=2, refs=3 (spec, pi.ndjson, pi-error.ndjson; plus the Task 1 module being extended), subsystems=[python stream processor, python unittest], independent_components=1. Signals fired: 0/4. Decision: keep. -->

## Ancillary / Follow-up Work

- Integration cutover (wiring into `ralph`, `AGENT_OUTPUT_FORMAT` in agent scripts,
  dependency declarations, installer/updater `MANAGED_FILES`, spec and README updates,
  loop tests). Explicitly out of scope per the spec's "What This Spec Does NOT Cover"; done
  afterwards in a supervised session using `integrate-output-pipeline-prompt.md`. Note
  that this prompt file is currently untracked in the worktree.
- After all four tasks are complete, consider moving
  `specs/process/output-pipeline-python.md` to `specs/process/archive/` once integration
  lands, per the spec lifecycle.
