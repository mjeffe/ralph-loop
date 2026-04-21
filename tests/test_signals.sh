#!/bin/bash
# Signal detection and display filter tests.

test_signal_detection_complete() {
    echo "--- Signal detection: COMPLETE ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/complete_output.json"
    cat > "$output_file" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"prompt text with <promise>COMPLETE</promise>"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"All done. <promise>COMPLETE</promise>"}]}}
EOF
    # Source check_signals from ralph context
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "detects COMPLETE signal" "2" "$rc"
}

test_signal_detection_replan() {
    echo "--- Signal detection: REPLAN ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/replan_output.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Plan needs work. <promise>REPLAN</promise>"}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "detects REPLAN signal" "3" "$rc"
}

test_signal_detection_no_signal() {
    echo "--- Signal detection: no signal ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/nosignal_output.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Still working on things."}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "no signal returns 0" "0" "$rc"
}

test_signal_ignores_user_messages() {
    echo "--- Signal detection: ignores user messages ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/user_signal.json"
    # Prompt (user message) contains the signal, but agent response does not
    cat > "$output_file" <<'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"When done output: <promise>COMPLETE</promise>"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will keep working."}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "ignores COMPLETE in user message" "0" "$rc"
}

test_signal_survives_malformed_json() {
    echo "--- Signal detection: survives malformed JSON ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/malformed_output.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Working..."}]}}
THIS IS NOT JSON
{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>COMPLETE</promise>"}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "detects signal despite malformed lines" "2" "$rc"
}

test_signal_both_complete_and_replan() {
    echo "--- Signal detection: COMPLETE wins when both present ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/both_signals.json"
    cat > "$output_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"<promise>COMPLETE</promise> and also <promise>REPLAN</promise>"}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "COMPLETE wins over REPLAN" "2" "$rc"
}

test_signal_in_long_response() {
    echo "--- Signal detection: finds signal in long response ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/long_response.json"
    # Generate a response with lots of filler text before the signal
    local filler
    filler=$(printf 'x%.0s' {1..500})
    cat > "$output_file" <<EOF
{"type":"assistant","message":{"content":[{"type":"text","text":"${filler} <promise>COMPLETE</promise>"}]}}
EOF
    check_signals() {
        local response
        response=$(agent_extract_response "$1")
        if echo "$response" | grep -qF '<promise>COMPLETE</promise>'; then return 2; fi
        if echo "$response" | grep -qF '<promise>REPLAN</promise>'; then return 3; fi
        return 0
    }
    local rc=0
    check_signals "$output_file" || rc=$?
    assert_eq "finds signal in long response" "2" "$rc"
}

test_empty_response_detected() {
    echo "--- Empty response: no assistant messages produces empty extract ---"
    source "$RALPH_DIR/agents/amp.sh"
    local output_file="$TMP_DIR/empty_response.json"
    # Simulate budget exhaustion: system init and user prompt echo, but no assistant response
    cat > "$output_file" <<'EOF'
{"type":"system","subtype":"init","cwd":"/tmp","session_id":"T-test"}
{"type":"user","message":{"content":[{"type":"text","text":"Do some work"}]}}
EOF
    local response
    response=$(agent_extract_response "$output_file")
    assert_eq "empty response from no assistant messages" "" "$response"

    # Also test truly empty file
    > "$TMP_DIR/truly_empty.json"
    response=$(agent_extract_response "$TMP_DIR/truly_empty.json")
    assert_eq "empty response from empty file" "" "$response"
}

test_display_filter_survives_malformed_json() {
    echo "--- Display filter: survives malformed JSON ---"
    source "$RALPH_DIR/agents/amp.sh"
    local input_file="$TMP_DIR/display_input.json"
    cat > "$input_file" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"line 1"}]}}
NOT JSON
{"type":"assistant","message":{"content":[{"type":"text","text":"line 3"}]}}
EOF
    local output
    output=$(agent_format_display < "$input_file")
    assert_contains "displays line 1" "line 1" "$output"
    assert_contains "displays line 3" "line 3" "$output"
}
