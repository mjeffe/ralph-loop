#!/bin/bash
# Agent script for Cline (https://github.com/cline/cline)
#
# Cline CLI supports headless mode via -y (yolo) and --json flags.
# When stdin is piped, Cline automatically enters headless mode.
#
# Not yet supported: lib/format_output.py has no parser for the cline 3.x --json stream, so
# AGENT_OUTPUT_FORMAT is deliberately unset and ralph refuses to run this agent. See
# specs/tech-debt.md item 7 (researched schema, and how to add a format from a real capture).

# shellcheck disable=SC2034  # AGENT_INSTALL, AGENT_ENV_KEYS: read by ralph after sourcing
AGENT_CLI="cline"
# Command to install the agent CLI in the sandbox base image (see Dockerfile.base
# AGENT_INSTALL build arg, injected by sandbox_build_base in lib/sandbox.sh).
AGENT_INSTALL="npm install -g cline"
# Cline has no single API-key env var: it is configured interactively via
# `cline auth`, which persists provider/model state to ~/.cline/data. There is
# therefore nothing for ralph to forward into the sandbox, so AGENT_ENV_KEYS is
# empty. (Running cline in the sandbox additionally requires persisting that
# config dir, which is out of scope here.)
AGENT_ENV_KEYS=""
# -y: yolo mode (auto-approve all actions, exit when complete)
# --json: output messages as JSON (one object per line), forces plain text mode
AGENT_ARGS="-y --json"

# Invoke the agent CLI with a prompt file; must stream raw output to stdout.
agent_invoke() {
    local prompt_file="$1"

    # Pre-flight check: verify Cline has been configured with a provider and model.
    local state_dir="${CLINE_DIR:-$HOME/.cline/data}"
    if [[ ! -f "$state_dir/globalState.json" ]]; then
        echo "Error: Cline is not configured." >&2
        echo "Run 'cline auth' to set up your API provider and model." >&2
        return 1
    fi

    # Check that a provider is configured (actModeApiProvider or planModeApiProvider)
    local has_provider
    has_provider=$(jq -r '.actModeApiProvider // .planModeApiProvider // empty' "$state_dir/globalState.json" 2>/dev/null || true)
    if [[ -z "$has_provider" ]]; then
        echo "Error: Cline is not configured — no API provider set." >&2
        echo "Run 'cline auth' to set up your API provider and model." >&2
        return 1
    fi

    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Hook: runs before each agent invocation. Capture out-of-band state here (e.g. account balance).
agent_pre_iteration() { :; }

# Hook: runs after each invocation, after ralph logs stream usage. $RALPH_ITER_SUMMARY is the
# summary JSON and $RALPH_DIR/last_agent_output the raw stream. May log, and may set
# _ITER_CONTEXT_USED/_ITER_CONTEXT_MAX/_ITER_CONTEXT_PCT to override stream values.
agent_post_iteration() { :; }
