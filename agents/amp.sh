#!/bin/bash
# Agent script for Amp (https://ampcode.com)

# shellcheck disable=SC2034  # AGENT_INSTALL, AGENT_ENV_KEYS, AGENT_OUTPUT_FORMAT: read by ralph after sourcing
AGENT_CLI="amp"
# Command to install the agent CLI in the sandbox base image (see Dockerfile.base
# AGENT_INSTALL build arg, injected by sandbox_build_base in lib/sandbox.sh).
AGENT_INSTALL="npm install -g @sourcegraph/amp"
# Environment variable(s) holding this agent's API credentials. Ralph forwards
# these into the sandbox (docker-compose env pass-through + .env.example) so the
# agent can authenticate inside the container. Space-separated if more than one.
AGENT_ENV_KEYS="AMP_API_KEY"
# -x: non-interactive (exit after response, no follow-up prompt)
# --dangerously-allow-all: skip tool-use confirmation prompts
# --stream-json-thinking: emit one JSON object per line, including thinking blocks
AGENT_ARGS="-x --dangerously-allow-all --stream-json-thinking"
# Stream schema of agent_invoke's stdout, parsed by lib/format_output.py --format.
AGENT_OUTPUT_FORMAT="stream-json"

# Pipes the prompt file to the amp CLI and streams JSON output to stdout.
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
