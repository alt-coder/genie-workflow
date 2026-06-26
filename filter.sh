#!/usr/bin/env bash
# filter.sh v7 — ANSI stripping for pipe-pane (simple wrapper)
# Usage: pipe-pane -O 'bash ~/.hermes/scripts/filter.sh >> agent-log.md'

exec sed -u 's/\x1b\[[0-9;]*m//g; s/\x1b\[[?]//g; s/\r$//'
