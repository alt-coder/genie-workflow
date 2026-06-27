---
name: genie-pipeline
title: Genie Pipeline
version: 2.0.0
category: software-development
description: Manager-orchestrated multi-agent pipeline — idea/ticket to codebase to PR via Claude Code + tmux + Obsidian. 15 roles, 8 phases, clarification, interactive monitoring, human-agent bridge, vision delegation, enhanced gating, Zettelkasten compounding.
author: Hermes Agent
tags: [claude-code, tmux, obsidian, multi-agent, orchestration, safe, manager, bridge]
---

# Genie Pipeline v2 — Manager-Orchestrator (genie × SAFe)

One command turns an idea or ticket into a working codebase with PR, using **managed** Claude Code agents — not fire-and-forget, but actively monitored, bridged, and gated.

## What Changed (v1 → v2)

| Feature | v1 (fire-and-forget) | v2 (manager-orchestrator) |
|---------|---------------------|--------------------------|
| Spawn | `--bare --print` (one-shot) | `--dangerously-skip-permissions --brief` (interactive) |
| Monitoring | Blind `waitfor_with_ttl` | `session_monitor_loop` — detect questions, errors, idle |
| Questions | Undetected, agent blocks | Bridge: trivial→answer, critical→ask user, expert→spawn |
| Clarification | None | Phase 0.5b: ask user before BSA |
| Prompt | Static role template | Dynamic enrichment (model + image + clarification + skills) |
| Vision | "Do NOT use images" | Positive delegation: `@vision-analyst` subagent |
| Gating | Marker file exists | Output quality verified (AC/DoD, verdict, length) |
| Image | Unsupported | Three flows (direct, subagent, separate session) |
| Resume | None | `--resume` flag (skip completed phases) |

## Lineage

Fuses `genie` v7 (one-command build pipeline) with `safe-agentic-workflow` v2.10 (SAFe 11-role ship harness). v2 adds manager-orchestrator pattern from user requirements.

## Quick Start

```bash
# One-shot pipeline (manager-orchestrated)
genie "Build a real-time collaborative whiteboard"
genie "9R-456" 3

# With image (user sends screenshot via Telegram)
GENIE_HAS_IMAGE=true GENIE_IMAGE_PATH=/tmp/genie-images/ui.png genie "implement this UI"

# Resume after crash
genie "Add OAuth middleware" --resume

# Dark factory (24/7 persistent team)
genie factory setup
genie factory start feature 9R-123 --attach
genie factory status
genie factory stop factory-9R-123

# Skip preflight
genie "Write a CLI tool" --skip-preflight
```

**Important:** For clarification and bridge to work, run `genie` in **background** mode (terminal `background=true`) so the Hermes agent can poll for `NEEDS_USER_INPUT` signals and handle them via the `clarify` tool.

## Phases

| Phase | Action |
|-------|--------|
| 0 | Preflight (23 checks) + Plane MCP + merge-queue gate |
| 0.5a | Skill scan + pattern discovery (specs + code + Zettelkasten + Plane) |
| 0.5b | **Clarification** — ask user 1-3 questions before BSA (NEW) |
| 1a | BSA spec gate (greenfield — stop-the-line if no AC/DoD). Ticket: fetch from Plane. |
| 1b | N critics (parallel) → synthesizer → architect plan |
| 2 | Implementor builds in git worktree |
| 3 | QAS gate (independence — NOT collapsible, bounce-back) |
| 4 | SecEng (if security-sensitive) + SysArch (if complexity-triggered, budget +25%) |
| 5 | Final critique (N critics, holistic) |
| 6 | RTE PR creation. Updates Plane work item status + links PR. |
| 7 | Merge to Obsidian + Zettelkasten learning extraction |

## Manager Protocol

Hermes is NOT a bystander. It actively manages every session.

```
After spawning each agent:
  1. session_monitor_loop polls every 10s via session_read
  2. Detects: question | error | done | idle | working
  3. On question → genie_bridge (classify + handle)
  4. On error → assess severity (retry/escalate/abort)
  5. On idle >60s → session_nudge
  6. On done → session_verify_output (quality gate)
  7. NEVER advance phase on marker-only. Always verify output.
```

## Bridge Decision Tree

When an agent asks a question during its work:

```
session_detect_question fires
  │
  ├─ trivial (which file? what format?)
  │    → derive_answer_from_context (spec, plan, clarification)
  │    → session_send answer → agent continues
  │
  ├─ critical (REST vs GraphQL? which DB?)
  │    → write_pending_question
  │    → print NEEDS_USER_INPUT:{role}:{question}
  │    → Hermes agent picks up via process(poll)
  │    → Hermes calls clarify tool → user answers
  │    → write_pending_answer → agent receives answer
  │
  └─ expert (which crypto library? GDPR compliance?)
       → spawn_expert (separate claude session with expert model)
       → expert writes answer to file
       → session_send expert recommendation → agent continues
```

## Enrichment Protocol

Before every spawn, `_enrichment.sh` builds a dynamic prompt:

```
genie_enrich_prompt(role, goal_desc, goal_dir, user_msg, has_image, image_path)
  │
  ├─ 1. Run model decision tree (dual output)
  │     ├─ Main model → --model flag (command level)
  │     └─ Subtask models → prompt text (vision, review, security)
  │
  ├─ 2. Load role prompt from lib/roles/*.md
  │
  ├─ 3. Add clarification answers (if Phase 0.5b ran)
  │
  ├─ 4. Add model capability notes
  │     ├─ Has vision → "Analyze image at {path}"
  │     └─ Lacks vision → "Use @vision-analyst (model: {vision_model})"
  │
  ├─ 5. Add image path (if image present)
  │
  ├─ 6. Add user message enrichment (if different from goal_desc)
  │
  ├─ 7. Add skill summaries
  │
  ├─ 8. Add worktree info
  │
  └─ 9. Write to .prompt-{role}.md → send via tmux paste-buffer
```

## Vision Delegation

```
Main model HAS vision:
  → "Analyze image at /path/img.png" in prompt
  → Agent reads file directly via Read tool

Main model LACKS vision + simple image task:
  → "Use @vision-analyst subagent (model: {vision_model}) to analyze"
  → Agent spawns subagent internally, gets text description, proceeds

Main model LACKS vision + complex image task:
  → Hermes spawns separate vision session with vision model
  → Gets text description back
  → Embeds description in main agent's prompt
  → Main agent proceeds with text description
```

## Image Handling

```
User sends image via Telegram → Hermes saves to /tmp/genie-images/
Enrichment checks: main model vision capability
  ├─ Flow A: main model has vision → pass path, agent reads directly
  ├─ Flow B: lacks vision → @vision-analyst subagent (agent spawns internally)
  └─ Flow C: lacks vision, complex → Hermes spawns separate vision session
```

Environment variables for image support:
- `GENIE_HAS_IMAGE=true` — flag that image is present
- `GENIE_IMAGE_PATH=/path/to/image.png` — path to saved image

## Enhanced Gating

```
session_verify_output(goal_dir, role)
  │
  ├─ BSA: check for acceptance criteria + requirements
  ├─ Architect: check for implementation steps
  ├─ Critic: check word count (≥50)
  ├─ Implementor: check no TODO/stub/placeholder
  ├─ QAS: check for APPROVED/CHANGES_NEEDED verdict
  ├─ SecEng: check for SECURITY_BLOCKED/PASSED verdict
  └─ Generic: check non-empty + reasonable length (≥20 words)

If quality insufficient:
  → session_send "Output needs revision: {specific issues}"
  → Re-monitor until fixed or timeout
```

## Architecture

- **Interactive sessions** — `claude --dangerously-skip-permissions --brief` in tmux, not one-shot `--print`
- **Per-agent files** — no shared mutable state during work
- **Git worktrees** — code isolation per agent
- **Post-hoc merge** — mtime-safe concatenation into goal note
- **Budget gate** — $50/goal, per-phase tracking, +25% on complexity
- **Independence gates** — QAS + SecEng never same session as implementor
- **Pattern discovery** — specs + code + Zettelkasten cross-session
- **Completion markers** — JSON signals for done detection
- **Session monitoring** — `session_monitor_loop` replaces blind `waitfor_with_ttl`
- **Bridge** — `genie_bridge` classifies and handles agent questions
- **Enrichment** — `genie_enrich_prompt` builds dynamic context-aware prompts
- **Subagents** — `@vision-analyst`, `@security-advisor`, `@domain-expert` via `--agents` flag
- **Resume** — `--resume` flag skips completed phases via marker check

## Scripts

### Core (v2)

| Script | Purpose |
|--------|---------|
| `genie.sh` | Main orchestrator (8 phases + clarification + manager loop + resume) |
| `hermes-spawn.sh` | Interactive agent launcher (enrichment + paste-buffer) |
| `lib/_sessions.sh` | **NEW** — tmux session helpers (send, read, detect, monitor) |
| `lib/_enrichment.sh` | **NEW** — prompt enrichment + model decision tree + image routing |
| `lib/_bridge.sh` | **NEW** — question classification + answer/escalate/expert |
| `lib/agents/` | **NEW** — subagent definitions (vision-analyst, security-advisor, domain-expert) |
| `hermes-preflight.sh` | 23-point check + merge-queue gate |
| `skill_scan.sh` | Keyword matching + safety scoring |
| `pattern_discovery.sh` | Specs + code + Zettelkasten search |
| `merge_goal.sh` | Post-hoc mtime-safe merger |
| `budget_tracker.py` | $50 gate + raise-ceiling + tracking |
| `filter.sh` | ANSI stripping (pipe-pane) |
| `zettelkasten.sh` | Learning extraction |

### Dark Factory (v1 active)

| Script | Purpose |
|--------|---------|
| `factory-setup.sh` | One-time setup + merge-queue gate |
| `factory-start.sh` | Launch persistent tmux team |
| `factory-stop.sh` | Graceful stop + worktree cleanup |
| `factory-status.sh` | Dashboard (active/idle/dead per pane) |

## Model Selection (v3 + v2 enrichment)

**Source of truth:** `~/.claude/settings.json` env vars.

```
genie_model_decision_tree(role, goal_desc, has_image, goal_dir)
  │
  ├─ Main model: genie_select_model (role floor × complexity × budget)
  │    → --model flag (command level)
  │
  └─ Subtask models:
       ├─ Vision model (if image + main lacks vision)
       │    → prompt text: "Use @vision-analyst (model: {vision_model})"
       │    → --agents JSON: {"vision-analyst": {...}}
       ├─ Review model (if critic role)
       └─ Security model (if security-sensitive goal)
```

**Positive enrichment** (v2 change):
```
Before: "Model lacks vision — do NOT use image analysis"
After:  "You lack vision. Use @vision-analyst (model: sonnet) to analyze images.
         Pass the image file path. Wait for text description, then proceed."
```

## Session Library (`_sessions.sh`)

| Function | Purpose |
|----------|---------|
| `session_send` | Type text into tmux session (send-keys) |
| `session_read` | Read last N lines from session (capture-pane) |
| `session_wait_ready` | Poll for claude prompt indicator |
| `session_detect_question` | Detect if agent is asking a question |
| `session_detect_error` | Detect errors in session output |
| `session_detect_done` | Check completion marker + output file |
| `session_is_idle` | Detect idle (prompt showing or claude exited) |
| `session_nudge` | Send "Status?" to idle session |
| `session_monitor` | Single-pass: returns working/question/error/done/idle |
| `session_monitor_loop` | Full loop with bridge + nudge + TTL |
| `session_verify_output` | Phase-specific quality check (enhanced gating) |

## Related Skills

- `multi-agent-orchestration` — Class-level patterns this pipeline implements
- `autonomous-coding-agents` — Delegating to external AI coding agent CLIs
- `genie` — Quick reference + launcher for this pipeline
- `plane-project-management` — Plane MCP setup, self-hosting, workflow integration

## Pitfalls

- **Run in background**: For clarification and bridge to work, run `genie` via terminal `background=true` so Hermes can poll for `NEEDS_USER_INPUT` signals. Foreground blocks the agent.
- **Paste-buffer for multi-line**: Interactive claude needs paste-buffer (not send-keys -l) for multi-line prompts. `hermes-spawn.sh` uses `tmux load-buffer` + `paste-buffer` + Enter.
- **Dual-consumer tool integration**: Configure BOTH Hermes (`config.yaml` → `mcp_servers`) and Claude Code (`settings.json` or `.mcp.json`) for external services.
- **Bash pitfalls**: `declare -A` without explicit init → unbound variable. `readonly` conflicts if re-sourcing `_common.sh`.
- **Vision model mismatch**: `find_vision_model` scans `model-capabilities.json` for `has_vision=true`. If no vision model cached, falls back to `sonnet`.
- **Agent question detection**: Uses pattern matching (question phrases, `?` at end of line, `SendUserMessage`). May miss unusual phrasings. `--brief` flag enables structured `SendUserMessage` for more reliable detection.

## What Makes It Different

- **Manager, not bystander** — Hermes actively monitors, bridges, and gates every session
- **Interactive, not one-shot** — agents run in interactive mode, Hermes types instructions
- **Clarification before work** — Phase 0.5b asks user questions before BSA creates spec
- **Positive vision delegation** — tells agent HOW to handle images (subagent), not just "don't"
- **Image support** — three flows for handling user-sent images
- **Enhanced gating** — output quality verified, not just marker existence
- **Resume support** — crash-safe via `--resume` flag + completion markers
- **Not a framework** — actual shell scripts orchestrating real Claude Code agents in tmux
- **Spec-first** — BSA creates AC/DoD before any implementation (greenfield mode)
- **Plane-native ticket flow** — fetch work items from Plane MCP instead of placeholder specs
- **Zettelkasten compounding** — learnings written AND read back by future goals
- **Three-way review** — QAS (AC gate) + SysArch (complexity) + Critic (holistic)
- **Cost-gated complexity** — SysArch review auto-raises budget ceiling +25%
- **Full paper trail** — every decision, critique, and learning preserved in Obsidian

*Pipeline built on Hermes Agent. All scripts at `~/.hermes/scripts/`.*
