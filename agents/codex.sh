#!/bin/bash
# Agent script for OpenAI Codex CLI (https://github.com/openai/codex)
#
# Not yet supported: agent_invoke is a stub, and lib/format_output.py has no parser for the
# `codex exec --json` stream, so AGENT_OUTPUT_FORMAT is deliberately unset and ralph refuses
# to run this agent. See specs/tech-debt.md item 7 (researched schema, and how to add a
# format from a real capture) and specs/agent-scripts.md.

# shellcheck disable=SC2034  # read by ralph after sourcing
AGENT_CLI="codex"
# Command to install the agent CLI in the sandbox base image (see Dockerfile.base
# AGENT_INSTALL build arg, injected by sandbox_build_base in lib/sandbox.sh).
AGENT_INSTALL="npm install -g @openai/codex"
# Environment variable(s) holding this agent's API credentials. Ralph forwards
# these into the sandbox (docker-compose env pass-through + .env.example) so the
# agent can authenticate inside the container. Space-separated if more than one.
AGENT_ENV_KEYS="OPENAI_API_KEY"

# Invoke the agent CLI with a prompt file; must stream raw output to stdout.
agent_invoke() {
    echo "Error: Codex agent is not yet implemented." >&2
    return 1
}

# Hook: runs before each agent invocation. Capture out-of-band state here (e.g. account balance).
agent_pre_iteration() { :; }

# Hook: runs after each invocation, after ralph logs stream usage. $RALPH_ITER_SUMMARY is the
# summary JSON and $RALPH_DIR/last_agent_output the raw stream. May log, and may set
# _ITER_CONTEXT_USED/_ITER_CONTEXT_MAX/_ITER_CONTEXT_PCT to override stream values.
agent_post_iteration() { :; }
