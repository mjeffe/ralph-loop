#!/bin/bash
# Agent script for Cline (https://github.com/cline/cline)
#
# Cline CLI supports headless mode via -y (yolo) and --json flags.
# When stdin is piped, Cline automatically enters headless mode.
# JSON output format: {"type": "ask"|"say", "text": "...", "ts": <ms>, "reasoning"?: "...", "partial"?: bool}

AGENT_CLI="cline"
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

# Extract plain text response from saved output; used by check_signals() for loop control.
# Processes line-by-line to handle malformed lines gracefully.
# Cline's JSON format: {"type": "ask"|"say", "text": "...", ...}
# We extract text from both "ask" and "say" message types.
agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="ask" or .type=="say") | select(.text != null) | .text' 2>/dev/null || true
    done < "$output_file"
}

# Filter stdin into human-readable live display; piped from agent_invoke in run_iteration.
# Extracts text and optional reasoning from Cline's JSON messages.
agent_format_display() {
    while IFS= read -r line; do
        echo "$line" | jq -r '
            select(.type=="ask" or .type=="say") |
            if .reasoning and .reasoning != "" then
                "[reasoning] " + .reasoning + "\n" + .text
            elif .text then
                .text
            else
                empty
            end
        ' 2>/dev/null || true
    done
}

# Cline stores cumulative usage/cost data in taskHistory.json.
# Each headless invocation creates a new task entry. We capture totals before
# and after each iteration to compute per-iteration deltas.
# Schema: { tokensIn, tokensOut, cacheWrites, cacheReads, totalCost, modelId, ... }

_CLINE_TASK_HISTORY="${CLINE_DIR:-$HOME/.cline/data/state/taskHistory.json}"

# Captures cumulative usage totals from taskHistory.json before an iteration.
agent_pre_iteration() {
    if [[ ! -f "$_CLINE_TASK_HISTORY" ]]; then
        return 0
    fi
    # Read the first (most recent) entry's cumulative totals
    local entry
    entry=$(jq -c '.[0] // empty' "$_CLINE_TASK_HISTORY" 2>/dev/null || true)
    if [[ -n "$entry" ]]; then
        _CLINE_PRE_IN=$(echo "$entry" | jq -r '.tokensIn // 0' 2>/dev/null || echo 0)
        _CLINE_PRE_OUT=$(echo "$entry" | jq -r '.tokensOut // 0' 2>/dev/null || echo 0)
        _CLINE_PRE_CACHE_W=$(echo "$entry" | jq -r '.cacheWrites // 0' 2>/dev/null || echo 0)
        _CLINE_PRE_CACHE_R=$(echo "$entry" | jq -r '.cacheReads // 0' 2>/dev/null || echo 0)
        _CLINE_PRE_COST=$(echo "$entry" | jq -r '.totalCost // 0' 2>/dev/null || echo 0)
        _CLINE_PRE_MODEL=$(echo "$entry" | jq -r '.modelId // "unknown"' 2>/dev/null || echo "unknown")
    fi
}

# Compares cumulative totals after an iteration to pre-iteration totals to compute
# per-iteration usage and cost deltas. Also extracts context window info from the
# model metadata to enable context usage percentage tracking.
agent_post_iteration() {
    if [[ ! -f "$_CLINE_TASK_HISTORY" ]]; then
        return 0
    fi
    local entry
    entry=$(jq -c '.[0] // empty' "$_CLINE_TASK_HISTORY" 2>/dev/null || true)
    if [[ -z "$entry" ]]; then
        return 0
    fi

    local post_in post_out post_cache_w post_cache_r post_cost
    post_in=$(echo "$entry" | jq -r '.tokensIn // 0' 2>/dev/null || echo 0)
    post_out=$(echo "$entry" | jq -r '.tokensOut // 0' 2>/dev/null || echo 0)
    post_cache_w=$(echo "$entry" | jq -r '.cacheWrites // 0' 2>/dev/null || echo 0)
    post_cache_r=$(echo "$entry" | jq -r '.cacheReads // 0' 2>/dev/null || echo 0)
    post_cost=$(echo "$entry" | jq -r '.totalCost // 0' 2>/dev/null || echo 0)

    local delta_in delta_out delta_cache_w delta_cache_r delta_cost total
    delta_in=$(( ${post_in:-0} - ${_CLINE_PRE_IN:-0} ))
    delta_out=$(( ${post_out:-0} - ${_CLINE_PRE_OUT:-0} ))
    delta_cache_w=$(( ${post_cache_w:-0} - ${_CLINE_PRE_CACHE_W:-0} ))
    delta_cache_r=$(( ${post_cache_r:-0} - ${_CLINE_PRE_CACHE_R:-0} ))
    delta_cost=$(awk "BEGIN {printf \"%.4f\", $post_cost - ${_CLINE_PRE_COST:-0}}" 2>/dev/null || echo "0")
    total=$(( ${delta_in:-0} + ${delta_out:-0} + ${delta_cache_w:-0} + ${delta_cache_r:-0} ))

    # Log per-iteration usage
    if [[ "$total" -gt 0 ]]; then
        log "Tokens: ${total} (in:${delta_in:-0} out:${delta_out:-0} cache_w:${delta_cache_w:-0} cache_r:${delta_cache_r:-0})"
    fi
    local cost_fmt
    cost_fmt=$(awk "BEGIN {printf \"%.4f\", $delta_cost}" 2>/dev/null || echo "0")
    if [[ "$cost_fmt" != "0.0000" ]]; then
        log "Iteration Cost: \$${cost_fmt}  Total: \$${post_cost:-0}"
    fi

    # Attempt to get context window size from the model info in globalState.json
    # This is needed for context usage percentage tracking
    local model_id max_tok
    model_id=$(echo "$entry" | jq -r '.modelId // "unknown"' 2>/dev/null || echo "unknown")
    max_tok=""
    if [[ -f "${CLINE_DIR:-$HOME/.cline/data}/globalState.json" ]]; then
        # Check actMode or planMode model info for context window
        max_tok=$(jq -r --arg mid "$model_id" '
            [.actModeOpenRouterModelInfo, .planModeOpenRouterModelInfo] |
            map(select(. != null)) |
            map(select(.id == $mid) | .context_length // empty) |
            first // empty
        ' "${CLINE_DIR:-$HOME/.cline/data}/globalState.json" 2>/dev/null || true)
    fi
    if [[ -n "$max_tok" && "$max_tok" != "null" && "$max_tok" -gt 0 ]]; then
        local pct
        pct=$(awk "BEGIN {printf \"%.0f\", ($total / $max_tok) * 100}" 2>/dev/null || true)
        log "Context: ${total}/${max_tok} tokens (${pct}%)"
        if [[ "${pct:-0}" -ge "${CONTEXT_WARN_PCT:-80}" ]]; then
            log "⚠ Context usage high — agent quality may degrade"
        fi
        _ITER_CONTEXT_USED=$total
        _ITER_CONTEXT_MAX=$max_tok
        _ITER_CONTEXT_PCT=$pct
    fi
}
