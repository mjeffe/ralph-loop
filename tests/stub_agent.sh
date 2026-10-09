#!/bin/bash
# Stub agent for loop tests — lets the real ralph loop run without an LLM.
# Installed as agents/stub.sh in a throwaway project by tests/test_loop.sh; never shipped.
#
# Each invocation N (retries count as invocations):
#   - saves the rendered prompt to $STUB_DIR/prompt-N.md
#   - performs the action on line N of $STUB_DIR/actions (missing line = noop):
#       noop               respond without changing anything
#       mark-selected <S>  set the status of the prompt's selected task (first "### Task" line)
#                          from planned to S (e.g. complete, blocked, or an invalid value)
#       signal <NAME>      respond with <promise>NAME</promise>
#       empty              exit 0 with no response
#       fail               exit 1

AGENT_CLI="true"

agent_invoke() {
    local prompt_file="$1" n action heading
    n=$(( $(cat "$STUB_DIR/count" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$STUB_DIR/count"
    cp "$prompt_file" "$STUB_DIR/prompt-$n.md"
    action=$(sed -n "${n}p" "$STUB_DIR/actions" 2>/dev/null)
    heading=$(grep -m1 '^### Task' "$prompt_file" || true)

    case "$action" in
        mark-selected\ *)
            [[ -n "$heading" ]] || { echo "stub: no selected task in prompt"; return 0; }
            local plan="$RALPH_DIR/implementation_plan.md" status="${action#mark-selected }"
            awk -v h="$heading" -v s="$status" \
                '$0 == h { f = 1 } f && /Status:/ { sub(/planned/, s); f = 0 } { print }' \
                "$plan" > "$plan.tmp" && mv "$plan.tmp" "$plan"
            echo "stub: ${status} ${heading}" ;;
        signal\ *) echo "stub: <promise>${action#signal }</promise>" ;;
        empty) ;;
        fail) return 1 ;;
        *) echo "stub: noop" ;;
    esac
}

agent_extract_response() { cat "$1"; }
agent_format_display() { cat; }
