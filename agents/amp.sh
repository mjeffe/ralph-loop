#!/bin/bash
# Agent script for Amp (https://ampcode.com)

AGENT_CLI="amp"
# -x: non-interactive (exit after response, no follow-up prompt)
# --dangerously-allow-all: skip tool-use confirmation prompts
# --stream-json-thinking: emit one JSON object per line, including thinking blocks
AGENT_ARGS="-x --dangerously-allow-all --stream-json-thinking"

# Pipes the prompt file to the amp CLI and streams JSON output to stdout.
agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Extracts only the plain text responses from amp's streaming JSON output,
# filtering for assistant messages and selecting text content blocks.
# Called by check_signals() to scan the response for loop-control signals
# (<promise>COMPLETE</promise> and <promise>REPLAN</promise>).
# Processes line-by-line so malformed lines (stderr leakage, partial writes)
# are skipped rather than aborting the entire parse.
agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] | select(.type=="text") | .text' 2>/dev/null || true
    done < "$output_file"
}

# Formats amp's streaming JSON into human-readable output for the live display.
# Reads from stdin (piped from agent_invoke via tee in run_iteration).
# Extracts three content types from assistant messages:
#   - thinking blocks:  prefixed with [thinking]
#   - text blocks:      displayed as-is
#   - tool_use blocks:  prefixed with [tool], showing the tool name and the first
#                        relevant input field (path, cmd, query, etc.) truncated to 200 chars
agent_format_display() {
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] |
            if .type == "thinking" then "[thinking] " + .thinking
            elif .type == "text" then .text
            elif .type == "tool_use" then "[tool] " + .name + ": " +
                ((.input | (.path // .cmd // .filePattern // .pattern // .query // .url //
                .description // .prompt // (tostring)) | tostring | .[0:200]))
            else empty end' 2>/dev/null || true
    done
}

# Captures the current account balance before an iteration so we can calculate cost.
agent_pre_iteration() {
    _BALANCE_BEFORE=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
}

# Compares the account balance after an iteration to _BALANCE_BEFORE to compute
# and log the iteration cost. Also extracts context window usage from the raw
# NDJSON output — each assistant message includes a usage object with token
# counts and the model's max context window size.
agent_post_iteration() {
    local balance_after
    balance_after=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
    if [[ -n "${_BALANCE_BEFORE:-}" && -n "$balance_after" ]]; then
        local cost
        cost=$(awk "BEGIN {printf \"%.2f\", $_BALANCE_BEFORE - $balance_after}" 2>/dev/null || true)
        log "Iteration Cost: \$${cost}  Balance: \$${balance_after}"
    fi

    local usage_line
    usage_line=$(grep -o '"usage":{[^}]*}' "$RALPH_DIR/last_agent_output" 2>/dev/null | tail -1)
    if [[ -n "$usage_line" ]]; then
        local input cache_create cache_read output_tok total max_tok pct
        input=$(echo "$usage_line" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*')
        cache_create=$(echo "$usage_line" | grep -o '"cache_creation_input_tokens":[0-9]*' | grep -o '[0-9]*')
        cache_read=$(echo "$usage_line" | grep -o '"cache_read_input_tokens":[0-9]*' | grep -o '[0-9]*')
        output_tok=$(echo "$usage_line" | grep -o '"output_tokens":[0-9]*' | grep -o '[0-9]*')
        max_tok=$(echo "$usage_line" | grep -o '"max_tokens":[0-9]*' | grep -o '[0-9]*')
        total=$(( ${input:-0} + ${cache_create:-0} + ${cache_read:-0} + ${output_tok:-0} ))
        if [[ "${max_tok:-0}" -gt 0 ]]; then
            pct=$(awk "BEGIN {printf \"%.0f\", ($total / $max_tok) * 100}" 2>/dev/null || true)
            log "Context: ${total}/${max_tok} tokens (${pct}%)"
        fi
    fi
}
