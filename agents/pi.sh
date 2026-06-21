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
# usage carries token counts and cost.total. We key parsing off message_end so we
# read complete blocks rather than reassembling streamed deltas.

AGENT_CLI="pi"
# Command to install the agent CLI in the sandbox base image (see Dockerfile.base
# AGENT_INSTALL build arg, injected by sandbox_build_base in lib/sandbox.sh).
# --ignore-scripts matches pi's documented npm install (no lifecycle scripts needed).
AGENT_INSTALL="npm install -g --ignore-scripts @earendil-works/pi-coding-agent"

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

AGENT_ARGS="--mode json --approve --no-session --model $PI_MODEL"

# Invoke the agent CLI with a prompt file; must stream raw NDJSON to stdout.
agent_invoke() {
    local prompt_file="$1"

    # Pre-flight: when targeting OpenRouter, fail with a clear message instead of
    # an opaque provider error if the API key is missing.
    if [[ "$PI_MODEL" == openrouter/* && -z "${OPENROUTER_API_KEY:-}" ]]; then
        echo "Error: PI_MODEL targets OpenRouter ($PI_MODEL) but OPENROUTER_API_KEY is not set." >&2
        echo "Export OPENROUTER_API_KEY or add an 'openrouter' key to ~/.pi/agent/auth.json." >&2
        return 1
    fi

    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Extract plain text response from saved output; used by check_signals() for loop
# control. Processes line-by-line so malformed lines are skipped, not fatal.
# Pi emits the final assistant text in message_end.message.content[] text blocks.
agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="message_end") | .message.content[] | select(.type=="text") | .text' 2>/dev/null || true
    done < "$output_file"
}

# Filter stdin into human-readable live display; piped from agent_invoke in
# run_iteration. Per-line processing keeps output line-buffered and robust.
# Shows thinking, text, and tool calls from each completed assistant message.
agent_format_display() {
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="message_end") | .message.content[] |
            if .type == "thinking" then "[thinking] " + .thinking
            elif .type == "text" then .text
            elif .type == "toolCall" then "[tool] " + .name + ": " +
                ((.arguments | (.command // .cmd // .path // .file_path // .pattern //
                .query // .url // .description // .prompt // (tostring)) | tostring | .[0:200]))
            else empty end' 2>/dev/null || true
    done
}

# Compute and log per-iteration cost and token usage from the raw NDJSON.
# Pi reports usage per assistant message, so cost is summed across all
# message_end events; the final message's totalTokens approximates the context
# sent on the last turn. Pi's stream does not expose the model's max context
# window, so a context-usage percentage (and CONTEXT_WARN_PCT warning) is not
# available for this agent.
agent_post_iteration() {
    local out="$RALPH_DIR/last_agent_output"
    [[ -f "$out" ]] || return 0

    local summary
    summary=$(
        while IFS= read -r line; do
            echo "$line" | jq -r 'select(.type=="message_end") |
                [(.message.usage.cost.total // 0), (.message.usage.totalTokens // 0)] | @tsv' 2>/dev/null || true
        done < "$out" | awk -F'\t' '
            { cost += $1; tokens = $2 }
            END { if (NR > 0) printf "%.4f %d", cost, tokens }'
    )

    if [[ -n "$summary" ]]; then
        local cost tokens
        cost=$(echo "$summary" | awk '{print $1}')
        tokens=$(echo "$summary" | awk '{print $2}')
        log "Iteration Cost: \$${cost}  Tokens: ${tokens}  Model: ${PI_MODEL}"
    fi
}
