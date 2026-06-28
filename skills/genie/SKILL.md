---
name: genie
title: Genie
version: 2.1.0
category: software-development
description: Manager-orchestrated multi-agent pipeline. Idea or ticket → working codebase → PR. Claude Code + tmux + Obsidian. 15 roles, 8 phases, clarification, bridge, vision delegation, enhanced gating, resume, Zettelkasten compounding.
author: Hermes Agent
tags: [claude-code, tmux, obsidian, multi-agent, orchestration, genie, safe, manager, bridge]
---

# Genie v2 — Manager-Orchestrated Pipeline (genie × SAFe)

One command turns an idea or ticket into a working codebase with PR, using **managed** Claude Code agents — actively monitored, bridged, and gated. Not fire-and-forget.

**Lineage:** Fuses `genie` v7 (one-command build pipeline) with `safe-agentic-workflow` v2.10 (SAFe 11-role ship harness). v2 adds manager-orchestrator pattern.

## Usage

```bash
# Greenfield — idea has no ticket/spec (BSA creates spec first)
genie "Build a real-time collaborative whiteboard"

# Ticket mode — fetches from Plane, uses ticket AC/DoD
genie "9R-456"

# Custom critic count (must be odd, default 3)
genie "Add OAuth2 middleware" 5

# With image (user sends screenshot via Telegram)
GENIE_HAS_IMAGE=true GENIE_IMAGE_PATH=/tmp/genie-images/ui.png genie "implement this UI"

# Resume after crash (skips completed phases)
genie "Add OAuth middleware" --resume

# Skip preflight checks
genie "Write a CLI tool" 3 --skip-preflight

# Force run despite active lock (recovery/debugging only)
genie "Fix login bug" --force

# Specify project directory
genie "Fix login bug" --project-dir=/home/ram/myproject
```

**Important:** Run `genie` in **background** mode (terminal `background=true`) so Hermes can poll for `NEEDS_USER_INPUT` signals and handle clarification/bridge via the `clarify` tool.

## v1 → v2 Changes

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

## 8 Phases

| Phase | Action |
|-------|--------|
| 0 | 23-point infrastructure preflight + Plane MCP connectivity + merge-queue readiness gate |
| 0.5a | Skill scan (auto-inject Hermes skills) + pattern discovery (specs+code+Zettelkasten + Plane work items) |
| 0.5b | **Clarification** — ask user 1-3 questions before BSA (NEW in v2) |
| 1a | BSA creates spec with AC/DoD (greenfield — stop-the-line gate). Ticket mode: fetches from Plane. |
| 1b | N critics (parallel) → synthesizer → architect writes plan |
| 2 | Implementor builds (reads plan, plays specialist roles) — in git worktree |
| 3 | QAS gate (independence — NOT collapsible, bounce-back authority) |
| 4 | Security Engineer (if security-sensitive) + System Architect (if complexity-triggered, budget auto +25%) |
| 5 | Final critique (N critics, holistic post-build review) |
| 6 | RTE creates PR (or collapsed into implementer). Updates Plane work item status + links PR. |
| 7 | **MANDATORY** — 7a: Merge to `10-goals/` (verified) → 7b: Zettelkasten to `20-learnings/` (verified) → 7c: MOC update |

## 15-Role Roster

| # | Role | Model | Effort | Collapsible? |
|---|------|-------|--------|--------------|
| 1 | BSA | Sonnet | High | n/a |
| 2 | System Architect | Opus | Max | n/a |
| 3 | BE Developer | Sonnet | High | n/a |
| 4 | FE Developer | Sonnet | High | n/a |
| 5 | Data Engineer | Sonnet | High | n/a |
| 6 | DPE | Haiku | Low | n/a |
| 7 | Tech Writer | Sonnet | High | n/a |
| 8 | QAS | Opus | High | **NEVER** |
| 9 | Security Engineer | Opus | High | **NEVER** |
| 10 | RTE | Haiku | Low | YES |
| 11 | TDM | Sonnet | High | n/a |
| 12 | Critic ×N | Sonnet | High | n/a |
| 13 | Synthesizer | Sonnet | High | n/a |
| 14 | Tiebreaker | Sonnet | High | n/a |
| 15 | Learn-extract | Sonnet | High | n/a |

## Independence Gates (never collapsed)

- **QAS** — cannot be same session as implementer (self-review bias)
- **Security Engineer** — cannot be same session as implementer (security blindness)

## Manager Protocol

Hermes is NOT a bystander. After spawning each agent:

```
1. session_monitor_loop polls every 10s via session_read
2. Detects: question | error | done | idle | working
3. On question → genie_bridge (classify + handle)
4. On error → assess severity (retry/escalate/abort)
5. On idle >60s → session_nudge
6. On done → session_verify_output (quality gate)
7. NEVER advance phase on marker-only. Always verify output.
```

## Bridge Decision Tree

```
Agent asks question:
  ├─ trivial (which file? format?)
  │    → derive_answer_from_context (spec, plan, clarification)
  │    → session_send answer → agent continues
  ├─ critical (REST vs GraphQL? which DB?)
  │    → write_pending_question
  │    → print NEEDS_USER_INPUT:{role}:{question}
  │    → Hermes picks up via process(poll) → clarify tool → user answers
  │    → write_pending_answer → agent receives answer
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
  ├─ 2. Load role prompt from lib/roles/*.md
  ├─ 3. Add clarification answers (if Phase 0.5b ran)
  ├─ 4. Add model capability notes
  │     ├─ Has vision → "Analyze image at {path}"
  │     └─ Lacks vision → "Use @vision-analyst (model: {vision_model})"
  ├─ 5. Add image path (if image present)
  ├─ 6. Add user message enrichment (if different from goal_desc)
  ├─ 7. Add skill summaries
  ├─ 8. Add worktree info
  └─ 9. Write to .prompt-{role}.md → send via tmux paste-buffer
```

## Vision Delegation + Image Handling

```
User sends image via Telegram → Hermes saves to /tmp/genie-images/
Enrichment checks: main model vision capability
  ├─ Flow A: main model has vision → pass path, agent reads directly
  ├─ Flow B: lacks vision + simple → @vision-analyst subagent (agent spawns internally)
  └─ Flow C: lacks vision + complex → Hermes spawns separate vision session
```

Image env vars: `GENIE_HAS_IMAGE=true`, `GENIE_IMAGE_PATH=/path/to/image.png`

**Positive enrichment** (v2): tells agent HOW to handle images, not just "don't":
```
"You lack vision. Use @vision-analyst (model: sonnet) to analyze images.
 Pass the image file path. Wait for text description, then proceed."
```

## Enhanced Gating

```
session_verify_output(goal_dir, role)
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

## Phase 7 — Merge + Learn (MANDATORY)

**This phase is NOT optional. It MUST run after every goal, even if earlier phases had warnings.**

```
7a: merge_goal.sh → 10-goals/{goal_id}.md
    ├─ Concatenates ALL agent-*.md files in phase order:
    │   BSA Spec → Critics → Synthesis → Architect Plan →
    │   Implementation → QAS Verdict → SysArch Review →
    │   Security Review → Final Critique → PR Creation
    ├─ Mtime-safe: skips if merged file newer than all sources
    └─ VERIFIED: file must exist AND be non-empty. If not → ERROR logged.

7b: zettelkasten.sh → 20-learnings/{date}-{title}.md
    ├─ Only runs if 7a succeeded (needs merged output)
    ├─ Reads FULL agent files (not truncated)
    ├─ Extracts 1-3 atomic learnings via Claude
    ├─ JSON parsed with fallback (handles markdown fences, prose)
    ├─ Deduplicates: skips if learning file already exists
    └─ VERIFIED: counts new .md files in 20-learnings/. Warns if 0.

7c: MOC Update → 40-meta/moc-sessions.md
    ├─ Appends goal ID + date + description to Map of Content
    └─ VERIFIED: grep checks goal_id already present
```

**File naming** (critical for merge): see `references/agent-file-naming.md` for full mapping.
- Phase 1b critics: `agent-critic-1.md`, `agent-critic-2.md`, ...
- Phase 5 critics: `agent-critic-final-1.md`, `agent-critic-final-2.md`, ...
- Phase 5 uses `critic-final` prefix (NOT `critic`) to avoid overwriting Phase 1b

**If merge fails:** ERROR logged, learning extraction + MOC skipped. Goal still marked complete (code on branch). Manual re-run: `bash ~/.hermes/scripts/merge_goal.sh <goal_dir> <goal_id>`

**If learning extraction fails:** WARN (non-fatal). Raw output saved to `raw-logs/`. Manual re-run: `bash ~/.hermes/scripts/zettelkasten.sh <goal_id> <goal_dir>`

## Model Selection (v3 + v2 enrichment)

**Source of truth:** `~/.claude/settings.json` env vars.

```
genie_model_decision_tree(role, goal_desc, has_image, goal_dir)
  │
  ├─ Main model: genie_select_model (role floor × complexity × budget)
  │    → --model flag (command level)
  └─ Subtask models:
       ├─ Vision model (if image + main lacks vision)
       │    → prompt text: "Use @vision-analyst (model: {vision_model})"
       │    → --agents JSON: {"vision-analyst": {...}}
       ├─ Review model (if critic role)
       └─ Security model (if security-sensitive goal)
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

## Two Modes

### One-Shot Pipeline (default — manager-orchestrated)

```bash
genie "<idea|TICKET-ID>" [critic_count] [--skip-preflight] [--resume] [--project-dir=.] [--force]
```

Runs 8 phases sequentially with active monitoring — idea → clarify → spec → build → QAS gate → PR → learnings.

### Dark Factory (24/7 persistent team)

```bash
genie factory setup [--project-dir=.]
genie factory start <story|feature|epic> [ticket-id] [--attach]
genie factory status
genie factory attach <session-name>
genie factory stop [session-name]
```

| Team Size | Panes | Roles |
|-----------|-------|-------|
| story | 3 | TDM + BE Developer + QAS |
| feature | 5 | TDM + BE + FE + QAS + RTE |
| epic | 9 | TDM + BE + FE + DE + DPE + TW + QAS + SecEng + RTE |

## Plane Integration (Project Management Backend)

Genie natively integrates with [Plane](https://plane.so). See `plane-project-management` skill for setup.

```bash
# One-command setup
bash ~/.hermes/scripts/hermes-plane-setup.sh
```

| Phase | Without Plane | With Plane |
|-------|--------------|------------|
| 0 (Preflight) | Infrastructure only | + Plane MCP reachable check |
| 0.5 (Discovery) | Specs + code + Zettelkasten | + Related work items, active cycles |
| 1a (Ticket) | Placeholder spec | Real work item via MCP (title, desc, AC, labels) |
| 6 (PR) | PR created | + Work item status → "In Review", PR link added |

## Research with opencode (Free Models)

For research-heavy phases (BSA, pattern discovery, critic research), use **opencode** instead of Claude Code to save API costs. opencode is a harness like Claude Code (TUI, tools, agents) with free model access.

### Setup

```bash
# opencode installed at ~/.opencode/bin/opencode (v1.17+)
# Auth: opencode-go provider (auto-configured)
# Config: ~/.config/opencode/opencode.jsonc
```

### Free models

| Model ID | Use Case |
|----------|----------|
| `opencode/big-pickle` | General research, web search |
| `opencode/deepseek-v4-flash-free` | Fast code analysis |
| `opencode/mimo-v2.5-free` | Lightweight tasks |
| `opencode/nemotron-3-ultra-free` | Heavy reasoning |
| `opencode/north-mini-code-free` | Code-specific research |

### Workflow (research in tmux)

```bash
# 1. Launch opencode in tmux
tmux new-session -d -s research "opencode /home/ram/projects/myproject"

# 2. Wait for TUI (~3s), then select free model
tmux send-keys -t research "/model" Enter
# → arrow keys to select opencode/big-pickle, Enter

# 3. Type research query
tmux send-keys -t research "Research existing GitHub workflows for video generation with Gita API. Star counts, architecture patterns, gaps." Enter

# 4. Monitor output
tmux capture-pane -t research -p -S -50

# 5. When done, kill session
tmux kill-session -t research
```

### Integration with genie

When genie needs research (BSA pre-spec, pattern discovery, critic context):
1. Hermes launches opencode in tmux with a free model
2. Types the research query
3. Captures output
4. Feeds research context into the Claude Code agent prompt

This saves paid API calls — research uses free models, implementation uses Claude Code.

## Architecture

- **Interactive sessions** — `claude --dangerously-skip-permissions --brief` in tmux, not one-shot `--print`
- **Research sessions** — `opencode` in tmux with free models (big-pickle, deepseek-v4-flash-free)
- **Per-agent files** — no shared mutable state during work
- **Git worktrees** — code isolation per agent
- **Post-hoc merge** — mtime-safe concatenation into goal note (Phase 7a, MANDATORY)
- **Zettelkasten** — atomic learning extraction, cross-session compounding (Phase 7b)
- **MOC** — Map of Content index for goals + learnings (Phase 7c)
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
| `lib/_sessions.sh` | tmux session helpers (send, read, detect, monitor) |
| `lib/_enrichment.sh` | Prompt enrichment + model decision tree + image routing |
| `lib/_bridge.sh` | Question classification + answer/escalate/expert |
| `lib/agents/` | Subagent definitions (vision-analyst, security-advisor, domain-expert) |
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

## Vault Structure

```
~/Documents/Obsidian Vault/
├── 00-staging/          (active goals)
├── 10-goals/            (merged output — Phase 7a)
├── 11-sessions/         (live session logs)
├── 20-learnings/        (Zettelkasten — Phase 7b, feeds pattern discovery)
├── 30-templates/        (goal, session, learning)
├── 40-meta/             (MOC index — Phase 7c)
└── 99-archive/          (completed)
```

## Recovery

| Situation | Behavior |
|-----------|----------|
| Agent timeout | TTL expires, proceed with partial |
| Agent crash | Capture saved to raw-logs/, retry |
| Budget exhausted | Pre-spawn gate blocks |
| Budget race condition | **FIXED** — flock lock prevents concurrent runs; EXIT trap cleans up |
| Complexity trigger | Budget auto-raised +25%, SysArch review |
| Security block | All work halts until resolved |
| Max 3 rebuild cycles | Proceed best-effort, flag in learnings |
| Crash mid-pipeline | `--resume` flag skips completed phases via marker check |

### Skipping PR creation

If user says "no PR" or "no need to raise a PR", let the pipeline complete through Phase 5 (final critique) but skip Phase 6 (RTE/PR). The code changes are already committed on the working branch — push the branch manually if the user wants it on a remote. Do not force the RTE phase if the user declined it.

## Pitfalls

- **Repo sync after skill updates**: When the `genie` skill is updated in Hermes (`~/.hermes/skills/genie/`), changes must be manually synced to the git repo (`~/genie-workflow/skills/genie/`) and pushed. Copy `SKILL.md` + `references/`, delete any removed sub-skills, then `git add -A && git commit && git push`. Hermes-local skills and repo skills are NOT auto-linked.
- **safe-agentic-workflow is read-only**: The skill lineage references `safe-agentic-workflow` v2.10 as an origin, but that repo must NOT be modified. All genie updates go to `~/genie-workflow/` only.
- **Run in background**: For clarification and bridge to work, run `genie` via terminal `background=true` so Hermes can poll for `NEEDS_USER_INPUT` signals. Foreground blocks the agent.
- **Paste-buffer for multi-line**: Interactive claude needs paste-buffer (not send-keys -l) for multi-line prompts. `hermes-spawn.sh` uses `tmux load-buffer` + `paste-buffer` + Enter.
- **Dual-consumer tool integration**: Configure BOTH Hermes (`config.yaml` → `mcp_servers`) and Claude Code (`settings.json` or `.mcp.json`) for external services.
- **Bash pitfalls**: `declare -A` without explicit init → unbound variable. `readonly` conflicts if re-sourcing `_common.sh`. `set -e` from sourced libs overrides `set +e` — re-assert after sourcing. `grep -qi 'a|b'` silently matches nothing — use `grep -qiE 'a|b'` (extended regex) for `|` alternation. See `references/bash-pitfalls.md`.
- **Patch tool backslash doubling**: when using the Hermes `patch` tool to edit Python code embedded in bash heredocs, backslashes get doubled. Workaround: use `python3 -c` in terminal instead. See `references/claude-cli-spawn.md`.
- **Vision model mismatch**: `find_vision_model` scans `model-capabilities.json` for `has_vision=true`. If no vision model cached, falls back to `sonnet`.
- **Agent question detection**: Uses pattern matching (question phrases, `?` at end of line, `SendUserMessage`). May miss unusual phrasings. `--brief` flag enables structured `SendUserMessage` for more reliable detection.
- **`set -e` + echo-based verification functions**: Functions like `session_verify_output` echo an issues string and callers check that string — but if the function returns non-zero, `set -e` (inherited from sourced libs or `genie.sh`) kills the pipeline silently before the caller ever sees the output. Fix: these functions must **always `return 0`**. Callers branch on the echoed string, not the return code. See `references/orchestration-debugging.md` §1.
- **Model quirk — `ocg/glm-5.2` empty tool_use**: This model emits `tool_use` blocks with an **empty `name` field** (e.g., two tool_use blocks, one named `get_time`, one with `name: ""`). Claude Code rejects with "No such tool available" and the agent stalls. Fix: use `syn/hf:zai-org/GLM-5.2` (same model, syn HuggingFace provider route — emits proper tool_use names) for the Opus tier in `~/.claude/settings.json` (`ANTHROPIC_DEFAULT_OPUS_MODEL`). `ds/deepseek-v4-pro-max` is an alternative. Sonnet (`ocg/minimax-m3`) and Haiku (`ds/deepseek-v4-flash`) are unaffected. See `references/orchestration-debugging.md` §2.
- **TUI readiness — wait for `❯`, not banner**: `session_wait_ready` must poll for the actual input prompt `❯` (or `for agents|/help|/exit`), NOT the `Claude Code` banner which appears ~2-3s early. Claude Code TUI accepts paste at **~8s** after spawn. Pasting before readiness silently swallows the prompt. See `references/orchestration-debugging.md` §3.
- **Paste verification — detect real work, not pasted text**: After pasting a prompt via tmux `paste-buffer`, verify the agent is actually working by grepping for real-work indicators (`thinking for|reading [0-9]+ files?|↓ [0-9]+ tokens|wibbling|crunched|shenanigan|fiddle|baked|✻ [a-z]`), NOT pasted prompt text or input-activity markers (`●`, `/effort`). Send `Ctrl-U` before each retry to clear stale input. Retry up to 8×. See `references/orchestration-debugging.md` §4.
- **`pattern_discovery.sh` SIGPIPE**: `set -euo pipefail` + `| head` causes intermittent SIGPIPE → non-zero exit → `set -e` death in `genie.sh`. Wrap the call with `2>/dev/null || log_warn "Pattern discovery failed (non-fatal)"`.
- **BSA timeout too short**: BSA with heavy tool use (Read+Bash) needs **600s**, not the default 300s. If `spawn_and_monitor` returns 1 on timeout, `set -e` at the call site kills the pipeline. Add `|| true` at the call site — the stop-the-line `spec.md` existence check still gates the phase.
- **`budget_tracker.py` stdout leakage**: `budget_tracker.py check` and `record` print `[BUDGET] OK: ...` to **stdout**. When `session_name=$(bash hermes-spawn.sh ...)` captures stdout, these lines merge into `session_name` → monitor can't find the tmux session → timeout. Fix: redirect budget_tracker.py stdout to stderr in `hermes-spawn.sh` — `1>&2` for the `check` command, `&>/dev/null` for `record`. `log_info`/`log_warn` already go to `&2` — only `budget_tracker.py` prints to stdout. See `references/orchestration-debugging.md` §7.
- **All roles need explicit TTLs**: The default `WAITFOR_TTL=300` is too short for ANY complex agent work. BSA=600s, synthesizer=900s, architect=600s, implementor=1200s, system-architect/security-engineer/QAS/RTE=600s. Without explicit TTLs, `spawn_and_monitor` times out, returns 1, and `set -e` may kill the pipeline. See `references/orchestration-debugging.md` §8.
- **Check tmux before declaring timeout failure**: When `session_monitor_loop` times out, the tmux session may **still be alive and actively coding**. Always check `tmux has-session -t "$session_name"` and `tmux capture-pane` before discarding output. The monitor timeout is a polling deadline, not an agent death. If the agent is still working (spinner active, files being edited), wait for it to finish or increase TTL. Code produced during a "timed out" phase can still be valid and usable. See `references/orchestration-debugging.md` §9.
- **`--resume` glob doesn't slugify**: `gen_goal_id()` slugifies `goal_desc` to lowercase+hyphens (e.g. `"Build a video"` → `"build-a-video"`), but `--resume` matched raw `goal_desc:0:20` (original case+spaces) against staging dir names. Glob never matched → `--resume` always started fresh. Fix: apply the same `tr/sed` slug transform before globbing. Rule: any code that searches for an identifier created by a transform function must apply the same transform. See `references/orchestration-debugging.md` §10.
- **Harvesting code from timed-out runs**: When genie exits after a phase timeout, the project directory may already contain a complete, tested codebase. Don't restart from scratch — kill the stale tmux session, install deps, run tests, implement any stubs, commit. Faster than a full `--resume`. See `references/orchestration-debugging.md` §11.

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

## Related Skills

- `multi-agent-orchestration` — Class-level patterns this pipeline implements
- `autonomous-coding-agents` — Delegating to external AI coding agent CLIs
- `plane-project-management` — Plane MCP setup, self-hosting, ticket integration

*Pipeline built on Hermes Agent. All scripts at `~/.hermes/scripts/`.*
