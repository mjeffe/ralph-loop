#!/bin/bash
# Agent script for Amp (https://ampcode.com)

AGENT_CLI="amp"
AGENT_ARGS="-x --dangerously-allow-all --stream-json-thinking"

agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] | select(.type=="text") | .text' 2>/dev/null || true
    done < "$output_file"
}

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

agent_pre_iteration() {
    _BALANCE_BEFORE=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
}

agent_post_iteration() {
    local balance_after
    balance_after=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
    if [[ -n "${_BALANCE_BEFORE:-}" && -n "$balance_after" ]]; then
        local cost
        cost=$(awk "BEGIN {printf \"%.2f\", $_BALANCE_BEFORE - $balance_after}" 2>/dev/null || true)
        log "Iteration Cost: \$${cost}  Balance: \$${balance_after}"
    fi
}
