#!/usr/bin/env bash
# Story Team Layout: TDM (lead) + BE Developer + QAS
# 3 panes — minimal team for ticket-level work
# Sourced by factory-start.sh (SESSION_NAME must be set)
set -euo pipefail

# Layout:
# ┌──────────────────────────────┐
# │         TDM (lead)           │
# ├──────────────┬───────────────┤
# │  BE Developer│     QAS        │
# └──────────────┴───────────────┘

# Pane 1: TDM (team lead) — already exists from new-session
tmux select-pane -t "${SESSION_NAME}:1.1" -T "tdm"

# Split for bottom half
tmux split-window -t "${SESSION_NAME}:1" -v
# Split bottom horizontally
tmux split-window -t "${SESSION_NAME}:1.2" -h

# Start agents
start_factory_agent 1 "tdm"
start_factory_agent 2 "be-developer"
start_factory_agent 3 "qas"

# Select TDM pane
tmux select-pane -t "${SESSION_NAME}:1.1"
