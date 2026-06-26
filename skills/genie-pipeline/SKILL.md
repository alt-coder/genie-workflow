---
name: genie-pipeline
title: Genie Pipeline
version: 1.0.0
category: software-development
description: Unified multi-agent pipeline — idea/ticket to codebase to PR via Claude Code + tmux + Obsidian. 15 roles, 8 phases, independence gates, Zettelkasten compounding.
author: Hermes Agent
tags: [claude-code, tmux, obsidian, multi-agent, orchestration, safe]
---

# Genie Pipeline v1 — Unified (genie × SAFe)

One command turns an idea or ticket into a working codebase with PR, using orchestrated Claude Code agents.

## Lineage

Fuses `genie` v7 (one-command build pipeline) with `safe-agentic-workflow` v2.10 (SAFe 11-role ship harness). Each parent strong where the other weak.

## Quick Start

```bash
# One-shot pipeline (one-shot mode)
genie "Build a real-time collaborative whiteboard"
genie "9R-456" 3

# Dark factory (24/7 persistent team)
genie factory setup                          # one-time: merge-queue gate
genie factory start feature 9R-123 --attach  # launch team, attach
genie factory status                          # dashboard
genie factory stop factory-9R-123             # graceful stop + cleanup

# Skip preflight (one-shot)
genie "Write a CLI tool" --skip-preflight
```

## 8 Phases

| Phase | Action |
|-------|--------|
| 0 | Preflight (23 checks) + merge-queue readiness gate |
| 0.5 | Skill scan + pattern discovery (specs + code + Zettelkasten) |
| 1a | BSA spec gate (greenfield only — stop-the-line if no AC/DoD) |
| 1b | N critics (parallel) → synthesizer → architect plan |
| 2 | Implementor builds in git worktree |
| 3 | QAS gate (independence — NOT collapsible, bounce-back) |
| 4 | SecEng (if security-sensitive) + SysArch (if complexity-triggered, budget +25%) |
| 5 | Final critique (N critics, holistic) |
| 6 | RTE PR creation (or collapsed into implementer) |
| 7 | Merge to Obsidian + Zettelkasten learning extraction |

## Architecture

- **Per-agent files** — no shared mutable state during work (genie)
- **Git worktrees** — code isolation per agent (SAFe)
- **Post-hoc merge** — mtime-safe concatenation into goal note (genie)
- **Budget gate** — $50/goal, per-phase tracking, +25% on complexity (genie + NEW)
- **Independence gates** — QAS + SecEng never same session as implementer (SAFe)
- **Pattern discovery** — specs + code + Zettelkasten cross-session (SAFe + NEW)
- **Event-driven watchdog** — 1s loop, silent when idle (genie)
- **Completion markers** — JSON signals, not tmux pane-exited ambiguity (genie)
- **Skill summaries** — top 3 relevant skills, <200 tokens each (genie)
- **Complexity triggers** — bash>100, TS>200, CI/CD, IaC, security → mandatory SysArch (SAFe)

## Scripts

| Script | Purpose |
|--------|---------|
| `genie.sh` | Main orchestrator (8 phases) |
| `hermes-spawn.sh` | Agent launcher (role prompts, worktrees) |
| `skill_scan.sh` | Keyword matching + safety scoring |
| `pattern_discovery.sh` | Specs + code + Zettelkasten search |
| `merge_goal.sh` | Post-hoc mtime-safe merger |
| `budget_tracker.py` | $50 gate + raise-ceiling + tracking |
| `priority_queue.py` | Two-queue scheduler |
| `filter.sh` / `filter_daemon.py` | ANSI stripping |
| `hermes-preflight.sh` | 23-point check + merge-queue gate |
| `claude-recovery.sh` | Session diagnostics |
| `tmux_watchdog.sh` | Event-driven monitor |
| `zettelkasten.sh` | Learning extraction |
| `lib/_roles.sh` | 15-role config |
| `lib/roles/*.md` | 11 SAFe role prompts |

## Model Map

| Role | Model | Effort | Tools |
|------|-------|--------|-------|
| BSA | Sonnet | High | Read, Bash |
| System Architect | Opus | Max | Read, Bash |
| BE/FE/Data Developer | Sonnet | High | ALL |
| DPE | Haiku | Low | Read, Bash |
| Tech Writer | Sonnet | High | Read, Write, Edit, Bash |
| QAS | Opus | High | Read, Bash |
| Security Engineer | Opus | High | Read, Bash |
| RTE | Haiku | Low | Read, Bash |
| TDM | Sonnet | High | Read, Bash |
| Critic (×N) | Sonnet | High | Read only |
| Synthesizer | Sonnet | High | Read only |
| Tiebreaker | Sonnet | High | Read only |
| Learn-extract | Sonnet | High | Read only |

## Related Skills

- `multi-agent-orchestration` — Class-level patterns this pipeline implements
- `autonomous-coding-agents` — Delegating to external AI coding agent CLIs

## What Makes It Different

- **Not a framework** — actual shell scripts orchestrating real Claude Code agents in tmux
- **Both file AND worktree isolation** — logs in per-agent files, code in per-agent worktrees
- **Spec-first** — BSA creates AC/DoD before any implementation (greenfield mode)
- **Zettelkasten compounding** — learnings written AND read back by future goals
- **Three-way review** — QAS (AC gate) + SysArch (complexity) + Critic (holistic)
- **Cost-gated complexity** — SysArch review auto-raises budget ceiling +25%
- **Full paper trail** — every decision, critique, and learning preserved in Obsidian

*Pipeline built on Hermes Agent. All scripts at `~/.hermes/scripts/`.*
