#!/bin/bash
# Plan filter — extracts plan slices for build prompt injection.
#
# Usage:
#   lib/plan-filter.sh header   <plan_file>
#   lib/plan-filter.sh overview <plan_file>
#   lib/plan-filter.sh select   <plan_file>
#
# Modes:
#   header   — emit everything above the first ### Task heading
#   overview — emit smart task overview (summarized complete sections,
#              expanded incomplete sections with line numbers)
#   select   — emit the deterministically selected next task block
#              plus adjacent context (process plans only)
#
# Exit codes:
#   0 — success
#   1 — usage error or parse failure (zero tasks found)

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Match a task heading line: ### Task N — Title  or  ### Task N: Title
is_task_heading() {
    [[ "$1" =~ ^###[[:space:]]+Task[[:space:]] ]]
}

# Match a section heading: ## ...
is_section_heading() {
    [[ "$1" =~ ^##[[:space:]] && ! "$1" =~ ^###[[:space:]] ]]
}

# Extract status value from a status line (bold, bare, or backtick format)
# Returns: planned, blocked, complete, or empty
extract_status() {
    local line="$1"
    if [[ "$line" =~ ^\*?\*?Status:\*?\*?[[:space:]]*(.*) ]]; then
        local val="${BASH_REMATCH[1]}"
        # Strip bold markers, backticks, and whitespace
        val="${val%%\*\*}"
        val="${val#\`}"
        val="${val%%\`*}"
        val="${val%% *}"
        echo "$val"
    fi
}

# Check if a line is a Depends on: field
is_depends_line() {
    [[ "$1" =~ ^\*?\*?Depends[[:space:]]+on:\*?\*? ]]
}

# ---------------------------------------------------------------------------
# Mode: header
# ---------------------------------------------------------------------------
# Emit everything from the top of the plan down to (but not including) the
# first ### Task heading.
mode_header() {
    local plan_file="$1"
    local found_task=0
    while IFS= read -r line; do
        if is_task_heading "$line"; then
            found_task=1
            break
        fi
        echo "$line"
    done < "$plan_file"

    # Strip trailing blank lines from output
    return 0
}

# ---------------------------------------------------------------------------
# Mode: overview
# ---------------------------------------------------------------------------
# Emit a smart structural overview:
# - Completed sections → single summary line
# - Incomplete sections → task headings, statuses, depends-on with line numbers
# - Progressive disclosure: if >30 incomplete tasks, limit to first 3
#   incomplete sections + summary of remaining
mode_overview() {
    local plan_file="$1"

    # First pass: parse all sections and tasks
    local -a section_names=()
    local -a section_start_lines=()
    local -a section_total=()
    local -a section_complete=()
    # For each section, store task info as newline-separated records
    local -a section_task_data=()

    local current_section=-1
    local in_header=1
    local line_num=0
    local current_task_line=0
    local current_task_heading=""
    local current_task_status=""
    local current_task_depends=""
    local total_tasks=0

    local RS=$'\x1f'  # unit separator — won't appear in plan text

    flush_task() {
        if [[ -n "$current_task_heading" && $current_section -ge 0 ]]; then
            section_task_data[$current_section]+="${current_task_line}${RS}${current_task_status}${RS}${current_task_depends}${RS}${current_task_heading}"$'\n'
            section_total[$current_section]=$(( ${section_total[$current_section]} + 1 ))
            if [[ "$current_task_status" == "complete" ]]; then
                section_complete[$current_section]=$(( ${section_complete[$current_section]} + 1 ))
            fi
            total_tasks=$(( total_tasks + 1 ))
        fi
        current_task_heading=""
        current_task_status=""
        current_task_depends=""
        current_task_line=0
    }

    while IFS= read -r line; do
        line_num=$(( line_num + 1 ))

        if is_task_heading "$line"; then
            in_header=0
            flush_task
            # If no section exists yet, create an implicit one
            if [[ $current_section -lt 0 ]]; then
                current_section=0
                section_names+=("")
                section_start_lines+=(0)
                section_total+=(0)
                section_complete+=(0)
                section_task_data+=("")
            fi
            current_task_line=$line_num
            current_task_heading="$line"
            continue
        fi

        if is_section_heading "$line"; then
            in_header=0
            flush_task
            current_section=$(( ${#section_names[@]} ))
            section_names+=("$line")
            section_start_lines+=("$line_num")
            section_total+=(0)
            section_complete+=(0)
            section_task_data+=("")
            continue
        fi

        if [[ $in_header -eq 1 ]]; then
            continue
        fi

        # Inside a task block — capture status and depends
        if [[ -n "$current_task_heading" ]]; then
            local status_val
            status_val=$(extract_status "$line")
            if [[ -n "$status_val" ]]; then
                current_task_status="$status_val"
            fi
            if is_depends_line "$line"; then
                current_task_depends="$line"
            fi
        fi
    done < "$plan_file"

    flush_task

    if [[ $total_tasks -eq 0 ]]; then
        return 1
    fi

    # Count incomplete tasks across all sections
    local incomplete_tasks=0
    for i in "${!section_names[@]}"; do
        incomplete_tasks=$(( incomplete_tasks + ${section_total[$i]} - ${section_complete[$i]} ))
    done

    # Determine if progressive disclosure is needed (>30 incomplete tasks)
    local progressive=0
    local max_incomplete_sections=999
    if [[ $incomplete_tasks -gt 30 ]]; then
        progressive=1
        max_incomplete_sections=3
    fi

    # Second pass: emit overview
    local incomplete_sections_shown=0
    local remaining_sections=0
    local remaining_tasks=0

    for i in "${!section_names[@]}"; do
        local name="${section_names[$i]}"
        local total="${section_total[$i]}"
        local complete="${section_complete[$i]}"

        if [[ $total -eq 0 ]]; then
            # Context-only section (no tasks) — emit heading, don't count for progressive disclosure
            if [[ -n "$name" ]]; then
                echo "$name"
            fi
        elif [[ $total -eq $complete ]]; then
            # All tasks complete — summary line
            if [[ -n "$name" ]]; then
                echo "$name ($complete/$total complete)"
            fi
        else
            # Incomplete section with tasks
            if [[ $progressive -eq 1 && $incomplete_sections_shown -ge $max_incomplete_sections ]]; then
                remaining_sections=$(( remaining_sections + 1 ))
                remaining_tasks=$(( remaining_tasks + total - complete ))
                continue
            fi

            if [[ -n "$name" ]]; then
                echo "$name"
            fi

            # Emit task details with line numbers
            while IFS="$RS" read -r task_line task_status task_depends task_heading; do
                [[ -z "$task_heading" ]] && continue
                echo "  ${task_line}:${task_heading}"
                if [[ -n "$task_status" ]]; then
                    echo "  $(( task_line + 1 )):**Status:** ${task_status}"
                fi
                if [[ -n "$task_depends" ]]; then
                    echo "  $(( task_line + 2 )):${task_depends}"
                fi
            done <<< "${section_task_data[$i]}"

            incomplete_sections_shown=$(( incomplete_sections_shown + 1 ))
        fi
    done

    if [[ $remaining_sections -gt 0 ]]; then
        echo "(+${remaining_sections} more sections with ${remaining_tasks} planned tasks)"
    fi
}

# ---------------------------------------------------------------------------
# Mode: select
# ---------------------------------------------------------------------------
# Deterministic task selection for process plans.
# Finds the earliest incomplete section, then the first planned task with
# resolved dependencies. Emits SELECTED_TASK and ADJACENT_CONTEXT.
mode_select() {
    local plan_file="$1"

    # Parse all tasks with their full blocks
    local -a task_lines=()
    local -a task_headings=()
    local -a task_statuses=()
    local -a task_depends=()
    local -a task_sections=()
    local -a task_blocks=()

    local -a section_names=()

    local current_section=-1
    local in_header=1
    local line_num=0
    local current_task_idx=-1
    local block=""
    local total_tasks=0

    flush_select_task() {
        if [[ $current_task_idx -ge 0 && -n "$block" ]]; then
            task_blocks[$current_task_idx]="$block"
        fi
        block=""
    }

    while IFS= read -r line; do
        line_num=$(( line_num + 1 ))

        if is_task_heading "$line"; then
            in_header=0
            flush_select_task

            current_task_idx=$total_tasks
            task_lines+=("$line_num")
            task_headings+=("$line")
            task_statuses+=("")
            task_depends+=("")
            task_sections+=("$current_section")
            task_blocks+=("")
            block="$line"
            total_tasks=$(( total_tasks + 1 ))
            continue
        fi

        if is_section_heading "$line"; then
            in_header=0
            flush_select_task
            current_section=$(( ${#section_names[@]} ))
            section_names+=("$line")
            current_task_idx=-1
            continue
        fi

        if [[ $in_header -eq 1 ]]; then
            continue
        fi

        if [[ $current_task_idx -ge 0 ]]; then
            block+=$'\n'"$line"
            local status_val
            status_val=$(extract_status "$line")
            if [[ -n "$status_val" ]]; then
                task_statuses[$current_task_idx]="$status_val"
            fi
            if is_depends_line "$line"; then
                task_depends[$current_task_idx]="$line"
            fi
        fi
    done < "$plan_file"

    flush_select_task

    if [[ $total_tasks -eq 0 ]]; then
        return 1
    fi

    # Find the earliest incomplete section with a planned task
    # For plans without sections, treat all tasks as section -1
    local selected=-1

    # Build a set of complete task numbers for dependency resolution
    local -A complete_tasks=()
    for i in $(seq 0 $(( total_tasks - 1 ))); do
        if [[ "${task_statuses[$i]}" == "complete" ]]; then
            # Extract task number from heading
            local heading="${task_headings[$i]}"
            if [[ "$heading" =~ Task[[:space:]]+([0-9]+) ]]; then
                complete_tasks["${BASH_REMATCH[1]}"]=1
            fi
        fi
    done

    # Check if a task's dependencies are resolved
    deps_resolved() {
        local dep_line="$1"
        [[ -z "$dep_line" ]] && return 0

        # Extract task numbers from depends line
        local dep_nums
        dep_nums=$(echo "$dep_line" | grep -oP 'Task\s+\K[0-9]+' || true)
        [[ -z "$dep_nums" ]] && return 0

        local num
        while read -r num; do
            [[ -z "$num" ]] && continue
            if [[ -z "${complete_tasks[$num]:-}" ]]; then
                return 1
            fi
        done <<< "$dep_nums"
        return 0
    }

    # Iterate sections in order to find earliest incomplete one
    # Get unique sections in order
    local -a unique_sections=()
    local -A seen_sections=()
    for i in $(seq 0 $(( total_tasks - 1 ))); do
        local sec="${task_sections[$i]}"
        if [[ -z "${seen_sections[$sec]:-}" ]]; then
            unique_sections+=("$sec")
            seen_sections[$sec]=1
        fi
    done

    for sec in "${unique_sections[@]}"; do
        # Check if this section has any incomplete tasks
        local has_incomplete=0
        for i in $(seq 0 $(( total_tasks - 1 ))); do
            if [[ "${task_sections[$i]}" == "$sec" && "${task_statuses[$i]}" != "complete" ]]; then
                has_incomplete=1
                break
            fi
        done

        [[ $has_incomplete -eq 0 ]] && continue

        # Find the first planned task with resolved deps in this section
        for i in $(seq 0 $(( total_tasks - 1 ))); do
            if [[ "${task_sections[$i]}" == "$sec" && "${task_statuses[$i]}" == "planned" ]]; then
                if deps_resolved "${task_depends[$i]}"; then
                    selected=$i
                    break 2
                fi
            fi
        done

        # If this section has incomplete tasks but none are ready, keep searching
        # (the spec says: find earliest section where not all tasks are complete,
        # then find first planned task with resolved deps)
        break
    done

    if [[ $selected -lt 0 ]]; then
        # No eligible task found — either all done or all remaining are blocked
        # Exit with 0 but emit nothing — let ralph handle this case
        echo "NO_ELIGIBLE_TASK"
        return 0
    fi

    # Emit SELECTED_TASK marker and full task block
    echo "---SELECTED_TASK---"
    echo "${task_blocks[$selected]}"
    echo "---END_SELECTED_TASK---"

    # Emit ADJACENT_CONTEXT — 1-2 tasks before and after, headings + status + depends only
    echo "---ADJACENT_CONTEXT---"
    local adj_start=$(( selected - 2 ))
    local adj_end=$(( selected + 2 ))
    [[ $adj_start -lt 0 ]] && adj_start=0
    [[ $adj_end -ge $total_tasks ]] && adj_end=$(( total_tasks - 1 ))

    for i in $(seq $adj_start $adj_end); do
        [[ $i -eq $selected ]] && continue
        echo "${task_headings[$i]}"
        if [[ -n "${task_statuses[$i]}" ]]; then
            echo "**Status:** ${task_statuses[$i]}"
        fi
        if [[ -n "${task_depends[$i]}" ]]; then
            echo "${task_depends[$i]}"
        fi
        echo ""
    done
    echo "---END_ADJACENT_CONTEXT---"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <header|overview|select> <plan_file>" >&2
    exit 1
fi

mode="$1"
plan_file="$2"

if [[ ! -f "$plan_file" ]]; then
    echo "Error: plan file not found: $plan_file" >&2
    exit 1
fi

case "$mode" in
    header)   mode_header "$plan_file" ;;
    overview) mode_overview "$plan_file" ;;
    select)   mode_select "$plan_file" ;;
    *)
        echo "Error: unknown mode: $mode (expected: header, overview, select)" >&2
        exit 1
        ;;
esac
