---
name: genie
title: Genie
version: 1.0.0
category: software-development
description: One-command multi-agent pipeline. Idea or ticket → working codebase → PR. Unified genie × SAFe — 15 roles, 8 phases, independence gates, Zettelkasten compounding.
author: Hermes Agent
tags: [claude-code, tmux, obsidian, multi-agent, orchestration, genie, safe]
---

# Genie v1 — Unified Pipeline (genie × SAFe)

One command turns an idea or ticket into a working codebase with PR, using orchestrated Claude Code agents in tmux sessions with Obsidian knowledge capture.

## Usage

```bash
# Greenfield — idea has no ticket/spec (BSA creates spec first)
genie "Build a real-time collaborative whiteboard"

# Ticket mode — skips BSA, uses ticket AC/DoD
genie "9R-456"

# Custom critic count (must be odd, default 3)
genie "Add OAuth2 middleware" 5

# Skip preflight checks
genie "Write a CLI tool" 3 --skip-preflight

# Specify project directory
genie "Fix login bug" --project-dir=/home/ram/myproject
```

## What It Does — 8 Phases

| Phase | Action |
|-------|--------|
| 0 | 23-point infrastructure preflight + merge-queue readiness gate |
| 0.5 | Skill scan (auto-inject Hermes skills) + pattern discovery (specs+code+Zettelkasten) |
| 1a | BSA creates spec with AC/DoD (greenfield only — stop-the-line gate) |
| 1b | N critics (parallel) → synthesizer → architect writes plan |
| 2 | Implementor builds (reads plan, plays specialist roles) — in git worktree |
| 3 | QAS gate (independence gate — NOT collapsible, bounce-back authority) |
| 4 | Security Engineer (if security-sensitive) + System Architect (if complexity-triggered, budget auto +25%) |
| 5 | Final critique (N critics, holistic post-build review) |
| 6 | RTE creates PR (or collapsed into implementer for simple work) |
| 7 | Post-hoc merge to Obsidian + Zettelkasten learning extraction |

## 15-Role Roster

| # | Role | Model | Effort | Origin | Collapsible? |
|---|------|-------|--------|--------|--------------|
| 1 | BSA | Sonnet | High | SAFe | n/a |
| 2 | System Architect | Opus | Max | SAFe | n/a |
| 3 | BE Developer | Sonnet | High | SAFe | n/a |
| 4 | FE Developer | Sonnet | High | SAFe | n/a |
| 5 | Data Engineer | Sonnet | High | SAFe | n/a |
| 6 | DPE | Haiku | Low | SAFe | n/a |
| 7 | Tech Writer | Sonnet | High | SAFe | n/a |
| 8 | QAS | Opus | High | SAFe | **NEVER** |
| 9 | Security Engineer | Opus | High | SAFe | **NEVER** |
| 10 | RTE | Haiku | Low | SAFe | YES |
| 11 | TDM | Sonnet | High | SAFe | n/a |
| 12 | Critic ×N | Sonnet | High | genie | n/a |
| 13 | Synthesizer | Sonnet | High | genie | n/a |
| 14 | Tiebreaker | Sonnet | High | genie | n/a |
| 15 | Learn-extract | Sonnet | High | genie | n/a |

## Key Innovations (neither parent had)

- **Spec-creation before critics** — BSA fills AC/DoD gap in greenfield mode
- **Pattern discovery searches Zettelkasten** — cross-session compounding knowledge base
- **Complexity-triggered review auto-escalates budget** — SysArch trigger raises ceiling +25%
- **Three-way reviewer split** — QAS (AC gate) + SysArch (complexity) + Critic (holistic)
- **Manifest drives both skill injection AND role config** — single project identity source

## Independence Gates (never collapsed)

- **QAS** — cannot be same session as implementer (self-review bias)
- **Security Engineer** — cannot be same session as implementer (security blindness)

## Two Modes

### One-Shot Pipeline (default)

```bash
genie "<idea|TICKET-ID>" [critic_count] [--skip-preflight] [--project-dir=.]
```

Runs 8 phases sequentially — idea → spec → build → QAS gate → PR → learnings. Done when PR is ready.

### Dark Factory (24/7 persistent team)

```bash
# One-time setup (merge-queue readiness gate)
genie factory setup [--project-dir=.]

# Launch persistent team (runs until stopped)
genie factory start <story|feature|epic> [ticket-id] [--attach]

# Monitor all sessions
genie factory status

# Attach to live session
genie factory attach <session-name>

# Graceful stop (Ctrl-C → wait → kill → cleanup worktrees → archive logs)
genie factory stop [session-name]
```

| Team Size | Panes | Roles |
|-----------|-------|-------|
| story | 3 | TDM + BE Developer + QAS |
| feature | 5 | TDM + BE + FE + QAS + RTE |
| epic | 9 | TDM + BE + FE + DE + DPE + TW + QAS + SecEng + RTE |

Dark factory features:
- Per-agent git worktrees (isolated branches)
- Per-agent log files (archived on stop)
- TDM acts as team lead, orchestrates other agents
- Merge queue + squash enforced (setup gate blocks without it)
- 24/7 — runs until explicitly stopped

## Commands

```bash
# Full pipeline (one-shot)
genie "<idea|TICKET-ID>" [critic_count] [--skip-preflight] [--project-dir=.]

# Dark factory
genie factory setup [--project-dir=.]
genie factory start <story|feature|epic> [ticket-id] [--attach]
genie factory status
genie factory attach <session>
genie factory stop [session]

# Check infrastructure
~/.hermes/scripts/hermes-preflight.sh [project_dir]

# View budget
python3 ~/.hermes/scripts/budget_tracker.py report <goal_id>

# Raise budget ceiling (complexity-triggered)
python3 ~/.hermes/scripts/budget_tracker.py raise-ceiling <goal_id> --pct 25.0 --reason complexity

# Pattern discovery (standalone)
~/.hermes/scripts/pattern_discovery.sh "<goal>" <goal_dir> [project_dir]
```

## Files

| Path | Description |
|------|-------------|
| `~/.hermes/scripts/genie.sh` | Main orchestrator (one-shot + factory dispatch) |
| `~/.hermes/scripts/factory-setup.sh` | One-time factory setup + merge-queue gate |
| `~/.hermes/scripts/factory-start.sh` | Launch persistent team session |
| `~/.hermes/scripts/factory-stop.sh` | Graceful stop + worktree cleanup + log archive |
| `~/.hermes/scripts/factory-status.sh` | Dashboard (active/idle/dead per pane) |
| `~/.hermes/scripts/hermes-spawn.sh` | Agent launcher (role prompts, worktrees) |
| `~/.hermes/scripts/skill_scan.sh` | Skill matching + safety |
| `~/.hermes/scripts/pattern_discovery.sh` | Specs + code + Zettelkasten search |
| `~/.hermes/scripts/merge_goal.sh` | Post-hoc mtime-safe merger |
| `~/.hermes/scripts/budget_tracker.py` | $50 gate + raise-ceiling + tracking |
| `~/.hermes/scripts/priority_queue.py` | Two-queue scheduler |
| `~/.hermes/scripts/filter.sh` | ANSI stripper |
| `~/.hermes/scripts/filter_daemon.py` | Async filter daemon |
| `~/.hermes/scripts/hermes-preflight.sh` | 23-point check + merge-queue gate |
| `~/.hermes/scripts/claude-recovery.sh` | Session diagnostics |
| `~/.hermes/scripts/tmux_watchdog.sh` | Event-driven monitor |
| `~/.hermes/scripts/zettelkasten.sh` | Learning extraction |
| `~/.hermes/scripts/lib/_roles.sh` | 15-role config (models/effort/tools) |
| `~/.hermes/scripts/lib/roles/*.md` | 11 SAFe role prompts (generalized) |
| `~/.hermes/scripts/lib/team-layouts/` | Story (3), Feature (5), Epic (9) pane layouts |
| `~/.hermes/scripts/lib/factory-env.template` | Dark factory config template |

## Vault Structure

```
~/Documents/Obsidian Vault/
├── 00-staging/          (active goals)
├── 10-goals/            (merged output)
├── 11-sessions/         (live session logs)
├── 20-learnings/        (Zettelkasten — feeds pattern discovery)
├── 30-templates/        (goal, session, learning)
├── 40-meta/             (MOC index)
└── 99-archive/          (completed)
```

## Recovery

| Situation | Behavior |
|-----------|----------|
| Agent timeout | TTL expires, proceed with partial |
| Agent crash | Capture saved to raw-logs/, retry |
| Budget exhausted | Pre-spawn gate blocks |
| Complexity trigger | Budget auto-raised +25%, SysArch review |
| Security block | All work halts until resolved |
| Max 3 rebuild cycles | Proceed best-effort, flag in learnings |
