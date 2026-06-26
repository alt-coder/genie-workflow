#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# factory-status.sh — Dark Factory dashboard
# Shows all factory sessions, pane status (active/idle/dead), aggregate stats
# Usage: genie factory status
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Find all factory sessions
sessions="$(tmux list-sessions -F '#{session_name}|#{session_created}' 2>/dev/null | grep '^factory-' || true)"

if [[ -z "$sessions" ]]; then
    echo "No dark factory sessions running."
    echo ""
    echo "Start one: genie factory start <story|feature|epic> [ticket-id]"
    exit 0
fi

echo ""
echo -e "${BOLD}========================================"
echo "  Dark Factory Status Dashboard"
echo -e "========================================${RESET}"
echo ""

total_sessions=0
total_agents=0
total_active=0
total_idle=0
total_dead=0

while IFS='|' read -r session_name session_created; do
    total_sessions=$((total_sessions + 1))

    created_time="$(date -d "@${session_created}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "${session_created}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"

    echo -e "${BOLD}Session: ${session_name}${RESET}"
    echo "  Created: ${created_time}"
    echo "  Panes:"

    pane_info="$(tmux list-panes -t "$session_name" \
        -F '#{pane_index}|#{pane_title}|#{pane_pid}|#{pane_current_command}|#{pane_last_activity}' 2>/dev/null || true)"

    if [[ -z "$pane_info" ]]; then
        echo "    (no panes)"
        continue
    fi

    now="$(date +%s)"

    while IFS='|' read -r pane_index pane_title pane_pid _pane_cmd last_activity; do
        total_agents=$((total_agents + 1))
        label="${pane_title:-pane-${pane_index}}"

        has_claude=false
        if [[ -n "$pane_pid" ]] && pgrep -P "$pane_pid" -f "claude" &>/dev/null; then
            has_claude=true
        fi

        idle_seconds=0
        if [[ -n "$last_activity" ]] && [[ "$last_activity" =~ ^[0-9]+$ ]]; then
            idle_seconds=$((now - last_activity))
        fi

        if [[ "$has_claude" == true ]]; then
            if [[ $idle_seconds -gt 300 ]]; then
                status_color="${YELLOW}"
                status_label="idle (${idle_seconds}s)"
                total_idle=$((total_idle + 1))
            else
                status_color="${GREEN}"
                status_label="active"
                total_active=$((total_active + 1))
            fi
        else
            status_color="${RED}"
            status_label="dead"
            total_dead=$((total_dead + 1))
        fi

        printf "    [%s] %-20s %b%s%b\n" \
            "$pane_index" "$label" "$status_color" "$status_label" "$RESET"
    done <<< "$pane_info"
    echo ""
done <<< "$sessions"

# Aggregate stats
echo -e "${BOLD}Aggregate Stats${RESET}"
echo "  Sessions:  $total_sessions"
echo "  Agents:    $total_agents (${total_active} active, ${total_idle} idle, ${total_dead} dead)"

# Resource usage
claude_procs="$(pgrep -f 'claude' 2>/dev/null | wc -l || echo "0")"
if [[ "$claude_procs" -gt 0 ]]; then
    rss_total="$(ps -C claude -o rss= 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum/1024}' || echo "0")"
    echo "  Processes: ${claude_procs} claude process(es), ~${rss_total}MB RSS"
else
    echo "  Processes: 0 claude processes"
fi

echo ""
echo "Commands:"
echo "  Attach:  genie factory attach <session>"
echo "  Stop:    genie factory stop <session>"
echo ""
