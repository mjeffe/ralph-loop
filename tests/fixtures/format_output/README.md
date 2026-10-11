# format_output fixtures

NDJSON samples used by `tests/test_format_output.py`. Each file records where it came
from, because real captures and synthesized samples deserve different levels of trust.

| File | Source | Notes |
|---|---|---|
| `amp.ndjson` | Real capture: `amp -x --dangerously-allow-all --stream-json-thinking`, one `ralph plan` iteration in this repo | Long `tool_result` contents and `create_file` input trimmed to keep the file small. Results that contained `<promise>COMPLETE</promise>` keep a window around the signal. Assistant messages, usage, and the `result` line are unmodified. |
| `pi.ndjson` | Real capture: `pi --mode json --approve --no-session --model openrouter/deepseek/deepseek-v4-pro` (pi 1.1.0, 2026-10-10) | Prompt: read a file, run a failing command, reply with the signal. Kept 3 of 54 `message_update` lines; system message `sections`/`toolsAdded`, `agent_end.messages`, `turn_end` thinking signatures, and `cwd` trimmed. Assistant, user, and toolResult `message_end` lines are unmodified. |
| `pi-error.ndjson` | Real capture: same pi command with an invalid model id | Shows the error path: assistant `message_end` with `stopReason: "error"` and `errorMessage`, exit code 0. Same trimming as `pi.ndjson`. |

Synthesized fixtures (if any) must say so in this table and cite the documentation or
source file their shapes were taken from. Replace them with real captures when the agent
is available.

To capture a new sample, run the agent CLI with the same arguments as `agents/<name>.sh`
and save stdout; `last_agent_output` in a ralph project holds the raw stream of the most
recent iteration.
