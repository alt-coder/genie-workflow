#!/usr/bin/env bash
# Epic Team Layout: TDM + BE + FE + Data Eng + DPE + Tech Writer + QAS + SecEng + RTE
# 9 panes — full SAFe team for epic-level work
# Sourced by factory-start.sh (SESSION_NAME must be set)
set -euo pipefail

# Layout: 9 panes arranged in tiled grid by tmux
# ┌──────────────────────────────┐
# │         TDM (lead)           │
# ├────────┬─────────┬───────────┤
# │   BE   │   FE    │ Data Eng  │
# ├────────┼─────────┼───────────┤
# │  DPE   │TechWrit │    QAS    │
# ├────────┼─────────┼───────────┤
# │ SecEng │   RTE   │  (spare)  │
# └────────┴─────────┴───────────┘

# Enable pane renumbering so indices stay sequential after splits
tmux set-option -t "${SESSION_NAME}" renumber-panes on

# Pane 1 exists (TDM). Create 8 more.
for i in $(seq 2 9); do
    tmux split-window -t "${SESSION_NAME}:1" -v
    tmux select-layout -t "${SESSION_NAME}:1" tiled >/dev/null 2>&1
done

# Arrange in a grid
tmux select-layout -t "${SESSION_NAME}:1" tiled

# Label and start agents — panes 1-9 in reading order
start_factory_agent 1 "tdm"
start_factory_agent 2 "be-developer"
start_factory_agent 3 "fe-developer"
start_factory_agent 4 "data-engineer"
start_factory_agent 5 "dpe"
start_factory_agent 6 "tech-writer"
start_factory_agent 7 "qas"
start_factory_agent 8 "security-engineer"
start_factory_agent 9 "rte"

# Select TDM pane
tmux select-pane -t "${SESSION_NAME}:1.1"
