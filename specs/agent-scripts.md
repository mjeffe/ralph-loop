# Agent Scripts

## Overview

Agent scripts encapsulate agent-specific logic (CLI invocation, credentials, the stream
schema of the CLI's output, and out-of-band usage tracking) behind a few known variables and
functions. Output parsing is shared: `lib/format_output.py` (see `output-pipeline.md`)
parses every supported stream schema, and each agent script only names the schema its CLI
emits. This keeps the ralph controller agent-agnostic and makes adding or swapping agents a
matter of writing one short shell script.

## Location and Naming

Agent scripts live in the `agents/` directory (relative to the ralph script directory) and are
named `{agent_name}.sh`:

```
agents/
  amp.sh
  claude.sh
  cline.sh
  codex.sh
  pi.sh
```

The active agent is selected by the `AGENT` variable in `config`:

```bash
AGENT="amp"
```

Ralph sources the agent script at startup:

```bash
source "$RALPH_DIR/agents/${AGENT}.sh"
```

If the script does not exist, ralph exits with an error.

### Supported Agents

| Script | `AGENT_OUTPUT_FORMAT` | Status |
|---|---|---|
| `amp.sh` | `stream-json` | supported |
| `claude.sh` | `stream-json` | supported |
| `pi.sh` | `pi-json` | supported |
| `cline.sh` | unset | **not yet supported**: no parser for the cline 3.x `--json` stream (`tech-debt.md` item 7) |
| `codex.sh` | unset | **not yet supported**: `agent_invoke` is a stub and there is no parser for `codex exec --json` (`tech-debt.md` item 7) |

Ralph refuses to run an agent whose script leaves `AGENT_OUTPUT_FORMAT` unset, with an error
naming the script and saying its output parser is not implemented yet.

## Contract

An agent script **must** set `AGENT_CLI`, `AGENT_INSTALL`, `AGENT_ENV_KEYS`, and
`AGENT_OUTPUT_FORMAT`, and define `agent_invoke`. Every shipped script also defines the two
stock hooks, `agent_pre_iteration` and `agent_post_iteration`.

### Required Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `AGENT_CLI` | The CLI command name | `amp` |
| `AGENT_INSTALL` | Command to install the agent CLI in the sandbox base image | `npm install -g @sourcegraph/amp` |
| `AGENT_ENV_KEYS` | API-credential env var(s) ralph forwards into the sandbox (space-separated; may be empty) | `AMP_API_KEY` |
| `AGENT_OUTPUT_FORMAT` | Stream schema of `agent_invoke`'s stdout, passed to `lib/format_output.py --format` | `stream-json` |

Ralph uses `AGENT_CLI` to validate that the agent is installed (via `command -v`).

`AGENT_OUTPUT_FORMAT` names a format registered in `lib/format_output.py` (`FORMATS`):
`stream-json` (amp, claude), `pi-json` (pi), or `text` (plain-text output, used by the test
stub agent). The format describes a stream schema, not an agent, so a new agent whose CLI
emits an existing schema needs no Python changes. Leaving it unset marks the agent as not
yet supported: ralph exits before the agent CLI check (and `ralph sandbox setup` does the
same). `text` is not a safe fallback for an agent that emits JSON or echoes its prompt,
because every line would be scanned for signals.

`AGENT_INSTALL` is injected as the `AGENT_INSTALL` Docker build arg when building
the sandbox base image (see `sandbox_build_base()` in the sandbox spec). This
makes the base image agent-configurable: switching `AGENT` and rebuilding installs
the matching CLI. If an agent script omits `AGENT_INSTALL`, the base image falls
back to its Dockerfile default (Amp).

`AGENT_ENV_KEYS` lists the environment variable(s) holding the agent's API
credentials. Installing an agent's CLI is only half of running it in the sandbox —
it must also authenticate. Ralph exports `AGENT_ENV_KEYS` when rendering the
sandbox so the generated `docker-compose.yml` forwards (pass-through) the right
key(s) into the container and `.env.example` documents them. This makes
authentication agent-configurable the same way `AGENT_INSTALL` makes installation
configurable. The value may be:
- a single var (`AMP_API_KEY` for amp, `ANTHROPIC_API_KEY` for claude),
- derived dynamically (pi derives `<PROVIDER>_API_KEY` from `PI_MODEL`, e.g.
  `OPENROUTER_API_KEY`), or
- empty when the agent authenticates out-of-band (cline, configured via
  `cline auth`); ralph then forwards no agent key.

### Required Function: `agent_invoke <prompt_file>`

Invokes the agent CLI with the given prompt file. The CLI's output, in the schema named by
`AGENT_OUTPUT_FORMAT`, must be written to stdout. Ralph tees it to `last_agent_output` and
pipes it through `lib/format_output.py`, which produces the screen display, the session log
lines, and the summary (signal, response size, error state, context, cost).

Agent stderr is **not redirected by ralph** — it flows directly to the user's terminal. This
ensures that CLI errors (authentication failures, network errors, crashes) are immediately
visible to the human operator. Agent scripts should not suppress stderr unless they have a
specific reason to filter it (e.g., removing known cosmetic noise while preserving real errors).

```bash
agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}
```

### Stock Hooks

Every shipped agent script defines both hooks, with a no-op body and the comment below
when there is nothing to do, so the extension point is visible to anyone copying a script.
Ralph calls them only if they exist (`type ... &>/dev/null &&`), so user-written agents
without hooks still work.

```bash
# Hook: runs before each agent invocation. Capture out-of-band state here (e.g. account balance).
agent_pre_iteration() { :; }

# Hook: runs after each invocation, after ralph logs stream usage. $RALPH_ITER_SUMMARY is the
# summary JSON and $RALPH_DIR/last_agent_output the raw stream. May log, and may set
# _ITER_CONTEXT_USED/_ITER_CONTEXT_MAX/_ITER_CONTEXT_PCT to override stream values.
agent_post_iteration() { :; }
```

#### `agent_pre_iteration`

Called before each agent invocation (including retries). Use it to capture out-of-band state
that the stream does not report, such as an account balance.

#### `agent_post_iteration`

Called after each agent invocation, regardless of success or failure, inside the iteration
footer. By then ralph has already logged the `Context:` and `Iteration Cost:` lines from the
stream (when available). The hook can use:

- `$RALPH_ITER_SUMMARY`: path to the summary JSON written by `lib/format_output.py` (keys
  `signal`, `response_chars`, `is_error`, `error`, `context_used`, `context_max`,
  `context_pct`, `cost`, `malformed_lines`; see "Summary File" in `output-pipeline.md`).
  Read it with `jq`. The file is deleted after the hook returns.
- `$RALPH_DIR/last_agent_output`: the raw stream of this invocation.
- `log`: ralph's logging function (terminal and session log).

It may set `_ITER_CONTEXT_USED`, `_ITER_CONTEXT_MAX`, and `_ITER_CONTEXT_PCT` (integer
percentage) to override the stream values, for example when the window is known from
elsewhere. Ralph checks `CONTEXT_WARN_PCT` and aggregates session context after the hook, so
overrides are honored. Do not re-log values ralph already logged from the stream.

Shipped hooks:
- `amp.sh`: amp's stream carries no cost, so the hooks compute it from the account balance
  (the example below).
- `pi.sh`: `agent_post_iteration` logs `Model: ${PI_MODEL}`; cost and tokens come from the
  stream.
- `claude.sh`, `cline.sh`, `codex.sh`: no-ops.

### Agent-Specific Configuration

Ralph sources `config` **before** the agent script, so agent scripts may read
agent-specific variables defined in `config`. For example, `pi.sh` reads `PI_MODEL`
to select the model passed to the `pi` CLI (e.g. `openrouter/anthropic/claude-3.5-haiku`),
falling back to a built-in default when unset. This keeps model selection in `config`
(versioned with the project and preserved across `ralph update`) rather than
hard-coded in the managed agent script. (A future enhancement could select a
different model per task by keying off the exported `MODE`; the current contract is a
single model per agent.)

**Convention.** Agent-specific config keys are named `<AGENT>_<SETTING>` (e.g.
`PI_MODEL`) and are **shipped commented-out** in `config`, with the real default
living in the agent script's fallback (`PI_MODEL="${PI_MODEL:-...}"`). This keeps
the shared `config` uncluttered for projects that use a different agent, while the
commented line documents the key and makes overriding a one-line edit. Each agent
script owns reading its own keys — no central registry or per-agent config files.
(If a future agent needs several settings, or 3+ agents each carry their own keys,
revisit with a per-agent config section or file; the flat convention is sufficient
until then.)

## Adding a New Agent

To add support for a new agent:

1. Create `agents/{name}.sh`
2. Set `AGENT_CLI` to the CLI command name
3. Set `AGENT_INSTALL` to the command that installs the CLI (for sandbox builds)
4. Set `AGENT_ENV_KEYS` to the agent's API-credential env var(s), or `""` if the
   agent authenticates out-of-band (so the sandbox forwards the right key)
5. Implement `agent_invoke`
6. Set `AGENT_OUTPUT_FORMAT`:
   - If the CLI emits a schema `lib/format_output.py` already parses (e.g. Claude Code's
     `stream-json`), reuse that format.
   - Otherwise capture a real stream with the script's arguments, save it as
     `tests/fixtures/format_output/<name>.ndjson`, and add a `Processor` subclass to
     `lib/format_output.py` with fixture tests (see "Adding a Format" in
     `output-pipeline.md`). Signals must come only from assistant-authored response text.
7. Define the two stock hooks (no-ops unless the agent has out-of-band usage to track)
8. Set `AGENT="{name}"` in config
9. Test with `ralph plan`

The agent CLI must:
- Accept a prompt via stdin
- Produce structured output (typically NDJSON) on stdout
- Run in a non-interactive, auto-approve mode (no human confirmation prompts)

## Example: amp.sh

```bash
AGENT_CLI="amp"
AGENT_INSTALL="npm install -g @sourcegraph/amp"
AGENT_ENV_KEYS="AMP_API_KEY"
AGENT_ARGS="-x --dangerously-allow-all --stream-json-thinking"
# Stream schema of agent_invoke's stdout, parsed by lib/format_output.py --format.
AGENT_OUTPUT_FORMAT="stream-json"

agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Hook: runs before each agent invocation. Captures the account balance so the post hook can
# compute the iteration cost.
agent_pre_iteration() {
    _BALANCE_BEFORE=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
}

# Hook: runs after each invocation, after ralph logs stream usage (context). amp's stream
# carries no cost, so log the balance delta instead.
agent_post_iteration() {
    local balance_after
    balance_after=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
    if [[ -n "${_BALANCE_BEFORE:-}" && -n "$balance_after" ]]; then
        local cost
        cost=$(awk "BEGIN {printf \"%.2f\", $_BALANCE_BEFORE - $balance_after}" 2>/dev/null || true)
        log "Iteration Cost: \$${cost}  Balance: \$${balance_after}"
    fi
}
```

## Switching Agents on an Existing Sandbox

The sandbox base image and docker-compose.yml are built against the agent
configured at `sandbox setup` time. To switch agents on an existing sandbox:

1. Change `AGENT` in config
2. Run `ralph sandbox setup --render-only --force` — this rebuilds the base
   image with the new agent's CLI and re-renders docker-compose.yml with the
   new agent's env keys, without re-analyzing the project.

Note: this is a workaround for the current single-agent architecture. Multi-agent
support (installing all CLIs and forwarding all keys at build time, so switching
agents requires no rebuild or re-render) is tracked separately.
