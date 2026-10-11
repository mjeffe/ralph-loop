#!/bin/bash
# Agent script for Claude Code (https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)

# shellcheck disable=SC2034  # AGENT_INSTALL, AGENT_ENV_KEYS, AGENT_OUTPUT_FORMAT: read by ralph after sourcing
AGENT_CLI="claude"
# Command to install the agent CLI in the sandbox base image (see Dockerfile.base
# AGENT_INSTALL build arg, injected by sandbox_build_base in lib/sandbox.sh).
AGENT_INSTALL="npm install -g @anthropic-ai/claude-code"
# Environment variable(s) holding this agent's API credentials. Ralph forwards
# these into the sandbox (docker-compose env pass-through + .env.example) so the
# agent can authenticate inside the container. Space-separated if more than one.
AGENT_ENV_KEYS="ANTHROPIC_API_KEY"
# --output-format stream-json: emit one JSON object per line (same schema as amp)
# --verbose: required by Claude Code with -p --output-format stream-json
# -p: read prompt from stdin (piped mode)
AGENT_ARGS="--output-format stream-json --verbose -p"
# Stream schema of agent_invoke's stdout, parsed by lib/format_output.py --format.
AGENT_OUTPUT_FORMAT="stream-json"

# Pipes the prompt file to the claude CLI and streams JSON output to stdout.
agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Hook: runs before each agent invocation. Capture out-of-band state here (e.g. account balance).
agent_pre_iteration() { :; }

# Hook: runs after each invocation, after ralph logs stream usage. $RALPH_ITER_SUMMARY is the
# summary JSON and $RALPH_DIR/last_agent_output the raw stream. May log, and may set
# _ITER_CONTEXT_USED/_ITER_CONTEXT_MAX/_ITER_CONTEXT_PCT to override stream values.
agent_post_iteration() { :; }
