#!/bin/bash
# Agent script for Pi (https://pi.dev)
#
# Pi is a minimal terminal coding harness with native OpenRouter support, making
# it a good fit for running cheaper models on low-value loop iterations.
#
# Headless invocation:
#   --mode json   : emit every session event as one JSON object per line (NDJSON)
#   --approve     : trust project-local files (.pi/settings.json, resources) for this run
#   --no-session  : ephemeral; do not persist a session file
#   --model       : provider/id (with optional :<thinking>), e.g. openrouter/anthropic/claude-3.5-haiku
#
# Pi has no per-tool permission prompts by design, so there is no
# --dangerously-allow-all equivalent — built-in tools (read, bash, edit, write,
# grep, find, ls) are available unless restricted with --tools/--no-tools.
#
# JSON event shape (see https://pi.dev/docs/latest/programmatic-usage/json-event-stream-mode):
#   {"type":"message_end","message":{"role":"assistant","content":[...],"usage":{...}}}
# Each assistant message's content[] holds text / thinking / toolCall blocks, and
# usage carries token counts and cost.total. lib/format_output.py (pi-json) keys
# parsing off message_end so it reads complete blocks rather than streamed deltas.

# shellcheck disable=SC2034  # AGENT_INSTALL, AGENT_ENV_KEYS, AGENT_OUTPUT_FORMAT: read by ralph after sourcing
AGENT_CLI="pi"
# Command to install the agent CLI in the sandbox base image (see Dockerfile.base
# AGENT_INSTALL build arg, injected by sandbox_build_base in lib/sandbox.sh).
# Uses the project's custom pi installer (subagent extension, agent definitions, skills,
# keybindings). Changes to the nix-profile pi config require a base-image rebuild:
#   docker rmi ralph-sandbox-base && ralph sandbox setup
AGENT_INSTALL="curl -fsSL https://raw.githubusercontent.com/mjeffe/nix-profile/master/coding-agents/pi/install.sh | bash"

# Model is configurable via PI_MODEL in config (sourced before this script).
# Format: provider/id with optional :<thinking> level, e.g.
#   openrouter/anthropic/claude-3.5-haiku        (cheap, default)
#   openrouter/google/gemini-2.0-flash-001:low
# Run `pi --list-models openrouter` to see what your account can reach.
#
# FUTURE (out of scope for now): per-task model selection. ralph exports MODE
# (plan|build|...) before invoking the agent, so a later enhancement could map
# task type -> model here (e.g. a cheap model for `build`, a stronger one for
# `plan`) instead of a single PI_MODEL. Keep this single-model for now.
PI_MODEL="${PI_MODEL:-openrouter/anthropic/claude-3.5-haiku}"

# Derive the credential env var from the model's provider (first path segment),
# e.g. openrouter/... -> OPENROUTER_API_KEY, anthropic/... -> ANTHROPIC_API_KEY.
# This is the variable ralph forwards into the sandbox so pi can authenticate
# inside the container (docker-compose env pass-through + .env.example).
PI_PROVIDER="${PI_MODEL%%/*}"
AGENT_ENV_KEYS="$(printf '%s' "$PI_PROVIDER" | tr '[:lower:]-' '[:upper:]_')_API_KEY"

AGENT_ARGS="--mode json --approve --no-session --model $PI_MODEL"
# Stream schema of agent_invoke's stdout, parsed by lib/format_output.py --format.
AGENT_OUTPUT_FORMAT="pi-json"

# Invoke the agent CLI with a prompt file; must stream raw NDJSON to stdout.
agent_invoke() {
    local prompt_file="$1"

    # Pre-flight: fail with a clear message instead of an opaque provider error
    # if the provider has no credentials. The key var derived from the provider
    # (AGENT_ENV_KEYS, via indirect expansion) is enough; otherwise ask pi, which
    # also knows about ~/.pi/agent/auth.json and OAuth logins.
    if [[ -z "${!AGENT_ENV_KEYS:-}" ]] && ! $AGENT_CLI auth check --provider "$PI_PROVIDER" &>/dev/null; then
        echo "Error: PI_MODEL is '$PI_MODEL' (provider '$PI_PROVIDER') but $AGENT_ENV_KEYS is not set" \
            "and 'pi auth check --provider $PI_PROVIDER' is not ready." >&2
        echo "Export $AGENT_ENV_KEYS or add a '$PI_PROVIDER' key to ~/.pi/agent/auth.json." >&2
        return 1
    fi

    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Hook: runs before each agent invocation. Capture out-of-band state here (e.g. account balance).
agent_pre_iteration() { :; }

# Hook: runs after each invocation, after ralph logs stream usage (cost and context tokens come
# from the stream). $RALPH_ITER_SUMMARY is the summary JSON and $RALPH_DIR/last_agent_output the
# raw stream. May log, and may set _ITER_CONTEXT_USED/_ITER_CONTEXT_MAX/_ITER_CONTEXT_PCT to
# override stream values.
agent_post_iteration() {
    log "Model: ${PI_MODEL}"
}
