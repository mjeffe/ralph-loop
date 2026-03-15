#!/bin/bash
# Agent script for Cline (https://github.com/cline/cline)
#
# Not yet implemented — Cline does not currently have a headless CLI.
# Each function below is a stub that errors out. To implement, replace with
# real invocation/parsing logic following the interface defined in specs/agent-scripts.md.

AGENT_CLI="cline"

# Invoke the agent CLI with a prompt file; must stream raw output to stdout.
agent_invoke() {
    echo "Error: Cline agent is not yet implemented." >&2
    return 1
}

# Extract plain text response from saved output; used by check_signals() for loop control.
agent_extract_response() {
    echo "Error: Cline agent is not yet implemented." >&2
    return 1
}

# Filter stdin into human-readable live display; piped from agent_invoke in run_iteration.
agent_format_display() {
    echo "Error: Cline agent is not yet implemented." >&2
    return 1
}
