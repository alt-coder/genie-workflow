# 🧞 Genie Workflow v1

> One-command agentic build pipeline + 24/7 dark factory. Fuses **genie v7** (Hermes one-command build) × **SAFe v2.10** (11-role ship harness).

## What it does

**One-shot mode:** Idea or ticket → spec → N-critique → architect plan → implement → QAS gate → security audit → final critique → PR → Zettelkasten learnings.

**Dark factory mode:** Persistent tmux team (3/5/9 agents), 24/7, TDM lead, per-agent git worktrees, merge-queue gate enforced.

## Quick start

```bash
# Clone + install
git clone https://github.com/alt-coder/genie-workflow.git
cd genie-workflow
./install.sh

# One-shot build
genie "Build a real-time collaborative whiteboard"

# Dark factory (24/7 team)
genie factory setup                    # one-time
genie factory start feature 9R-123     # launch 5-agent team
genie factory status                    # monitor
genie factory attach factory-9R-123    # jump in
genie factory stop factory-9R-123      # graceful shutdown
```

## Requirements

- [Hermes Agent](https://hermes-agent.nousresearch.com/docs) — orchestrator + CLI
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — agent runtime (`~/.local/bin/claude`)
- `tmux` — terminal multiplexer (factory mode)
- `inotify-tools` — filesystem watcher (preflight check)
- `gh` CLI — GitHub PR creation
- `python3` — budget tracker

## Architecture

### 15 Roles

| # | Role | Model | Purpose |
|---|------|-------|---------|
| 1 | BSA | sonnet | Business Systems Analyst — spec from idea |
| 2 | Critic | haiku | Divergent critique (N parallel) |
| 3 | Synthesizer | sonnet | Merge critiques → consensus |
| 4 | SysArch | opus | Architecture plan + complexity review |
| 5 | BE Developer | sonnet | Backend implementation |
| 6 | FE Developer | sonnet | Frontend implementation |
| 7 | Data Engineer | sonnet | Data pipelines |
| 8 | DPE | sonnet | DevOps/platform engineering |
| 9 | Tech Writer | haiku | Documentation |
| 10 | QAS | sonnet | QA Specialist — stop-the-line gate |
| 11 | Security Engineer | opus | Independent security audit |
| 12 | RTE | sonnet | Release Train Engineer — PR shepherd |
| 13 | TDM | sonnet | Tech Delivery Manager — blocker resolver |
| 14 | Architect | opus | Legacy genie architect (greenfield) |
| 15 | Implementor | sonnet | Legacy genie implementor (greenfield) |

### 8 Phases (one-shot)

| Phase | Name | Gate |
|-------|------|------|
| 0 | Preflight | 23 checks (deps, git, models) |
| 0.5 | Skill + Pattern Discovery | Cross-session search |
| 1 | Spec + Plan | BSA spec → critics → synth → architect |
| 2 | Build | Specialist agents implement |
| 3 | QAS Gate | Stop-the-line quality gate |
| 4 | Independence + Complexity | Security audit + budget escalation |
| 5 | Final Critique | N-critic holistic review |
| 6 | PR + 3-stage Review | RTE shepherds PR |
| 7 | Merge + Learn | Merge-queue → Zettelkasten |

### Dark Factory Team Sizes

| Size | Panes | Roles |
|------|-------|-------|
| story | 3 | TDM + BE + QAS |
| feature | 5 | TDM + BE + FE + QAS + RTE |
| epic | 9 | TDM + BE + FE + DE + DPE + TW + QAS + SecEng + RTE |

## File structure

```
genie-workflow/
├── genie.sh                  # Main pipeline + factory dispatch
├── hermes-spawn.sh           # Agent spawner (worktree isolation)
├── hermes-preflight.sh       # 23-check preflight
├── pattern_discovery.sh      # Cross-session pattern search
├── budget_tracker.py         # Cost tracking + raise-ceiling (+25%)
├── skill_scan.sh             # Skill keyword matching
├── merge_goal.sh             # Post-hoc goal merger
├── zettelkasten.sh           # Learn extraction → Obsidian
├── filter.sh                 # ANSI stripping for pipe-pane
├── factory-setup.sh          # One-time factory setup + merge-queue gate
├── factory-start.sh          # Launch persistent tmux team
├── factory-stop.sh           # Graceful shutdown + cleanup
├── factory-status.sh         # Factory dashboard
├── install.sh                # Deploy to ~/.hermes/scripts/
├── lib/
│   ├── _common.sh            # Shared functions (GENIE_DIR, logging)
│   ├── _models.sh            # Model/token/cost config
│   ├── _roles.sh             # 15-role config (models/effort/tools)
│   ├── factory-env.template  # Factory config template
│   ├── roles/               # 11 SAFe role prompts (.md)
│   └── team-layouts/        # 3 tmux layouts (story/feature/epic)
├── docs/
│   └── SPEC.md              # Full unified spec (464 lines)
└── skills/
    ├── genie/SKILL.md       # Quick reference skill
    └── genie-pipeline/SKILL.md  # Full technical docs
```

## Budget

Default $50 per goal. Complexity review auto-escalates +25% via `budget_tracker.py raise-ceiling`.

## Lineage

- **genie v7** — one-command build pipeline (Hermes Agent)
- **SAFe v2.10** — 11-role ship harness ([safe-agentic-workflow](https://github.com/bybren-llc/safe-agentic-workflow))
- **v1** — unified: genie's build engine + SAFe's ship discipline

## License

MIT
