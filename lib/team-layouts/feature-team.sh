#!/usr/bin/env bash
# Feature Team Layout: TDM + BE Developer + FE Developer + QAS + RTE
# 5 panes — full feature team
# Sourced by factory-start.sh (SESSION_NAME must be set)
set -euo pipefail

# Layout:
# ┌──────────────────────────────┐
# │         TDM (lead)           │
# ├──────────────┬───────────────┤
# │  BE Developer│  FE Developer  │
# ├──────────────┼───────────────┤
# │     QAS      │     RTE        │
# └──────────────┴───────────────┘

# Pane 1: TDM — already exists
tmux select-pane -t "${SESSION_NAME}:1.1" -T "tdm"

# Split for bottom two-thirds
tmux split-window -t "${SESSION_NAME}:1" -v
# Split BE row horizontally for FE
tmux split-window -t "${SESSION_NAME}:1.2" -h
# Split BE pane vertically for QAS row
tmux split-window -t "${SESSION_NAME}:1.2" -v
# Split QAS horizontally for RTE
tmux split-window -t "${SESSION_NAME}:1.3" -h

# Re-label panes (indices shift during splits)
tmux select-pane -t "${SESSION_NAME}:1.1" -T "tdm"
tmux select-pane -t "${SESSION_NAME}:1.2" -T "be-developer"
tmux select-pane -t "${SESSION_NAME}:1.3" -T "qas"
tmux select-pane -t "${SESSION_NAME}:1.4" -T "fe-developer"
tmux select-pane -t "${SESSION_NAME}:1.5" -T "rte"

# Start agents
start_factory_agent 1 "tdm"
start_factory_agent 2 "be-developer"
start_factory_agent 3 "qas"
start_factory_agent 4 "fe-developer"
start_factory_agent 5 "rte"

# Select TDM pane
tmux select-pane -t "${SESSION_NAME}:1.1"
