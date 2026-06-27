# Unified Agentic Workflow v1 — Genie × SAFe

**Lineage**: Fuses `genie` v7 (Hermes one-command build pipeline) with `safe-agentic-workflow` v2.10 (SAFe 11-role ship harness). Each parent strong where the other weak. v1 = union minus overlap.

| Parent | Keeps | Drops |
|--------|-------|-------|
| Genie v7 | one-command entry, N-critic→synth divergence, skill auto-injection, budget gate, per-agent files, post-hoc merge, Zettelkasten, priority queue, event-driven watchdog, JSON completion markers, ANSI filter, 23-pt preflight | generic-role-only roster (no specialists), no HITL gate, no PR/CI phase, no spec-first planning |
|| SAFe v2.10 | 11 specialized roles, specs-driven (Epic→Feature→Story→Enabler), MANDATORY pattern discovery, stop-the-line gate, independence gates (QAS+SecEng), role collapsing, 3-stage PR review, evidence→Linear/Plane, complexity-triggered SysArch review, dark-factory tmux layouts, harness manifest, merge-queue enforcement | manual method-1..4 selection (replaced by auto mode-detect), per-project isolated skills (replaced by central Hermes skill lib) |

---

## 1. Two Entry Modes (auto-detected)

```bash
genie "<idea>"                       # greenfield — idea has no ticket/spec
genie "<TICKET-ID>"                  # ticket — Linear/Plane already has AC/DoD
genie "<idea>" --critics 5           # explicit critic count (must be odd)
genie "<TICKET-ID>" --skip-preflight # bypass infra check (CI-known-good hosts)
```

**Mode detect**:
- Input matches `^[A-Z]+-\d+$` (e.g. `9R-456`, `REN-12`) → **ticket mode**. Pull AC/DoD from Linear/Plane MCP. If AC/DoD missing → STOP-THE-LINE, escalate to BSA. Skip Phase 1a.
- Otherwise → **greenfield mode**. Phase 1a runs BSA to create spec before any critics.

---

## 2. Pipeline Phases

### Phase 0 — Preflight + Readiness (genie preflight + SAFe readiness gate)

1. 23-point infra preflight (genie `hermes-preflight.sh`): tmux ≥3.0, claude CLI, gh, git, inotify-tools, Obsidian vault dirs, budget_tracker.py importable.
2. **Readiness gate (SAFe)**: verify merge-queue enforcement on target branch (squash, no direct push). If fail → hard stop. Set up `~/.dark-factory/env` if dark-factory mode.
3. Load harness manifest (SAFe): `~/.hermes/manifests/<project>.yml` — identity, protected files, substitutions, ticket prefix, main branch, MCP servers. Manifest drives both skill injection (Phase 0.5) AND role config (Phase 2).
4. Init budget: `budget_tracker.py init <goal_id> --budget <ceiling>` (default $50, manifest can override).

### Phase 0.5 — Skill Scan + Pattern Discovery (genie scan + SAFe discovery, **extended**)

Two passes, both write to `staging/<goal_id>/context/`:

**Pass A — Skill scan (genie)**:
- Keyword-match goal desc against all `~/.hermes/skills/*/SKILL.md` frontmatter `triggers`.
- Score by `occurrence_count × safety_score`. Safety score flags eval/exec/pipe-to-shell/subprocess-shell=True patterns; unsafe skills excluded.
- Inject top 3 relevant skill **summaries** (<200 tokens each) into every spawned agent's `--append-system-prompt`. Never full markdown.

**Pass B — Pattern discovery (SAFe, extended)**:
- Search `specs/` dir for similar past specs (SAFe).
- Search codebase for existing helpers/patterns (SAFe).
- Search `~/.claude/todos/` and `~/.hermes/sessions/` for recent session patterns (SAFe).
- **NEW**: Search `Obsidian Vault/20-learnings/` (Zettelkasten) for atomic learnings matching goal keywords. Cross-session pattern compounding — neither parent did this.
- Write ranked hits to `context/pattern-discovery.md`. Every downstream agent reads this.

### Phase 1 — Spec & Plan

#### 1a. BSA spec gate (greenfield only)

Stop-the-line gate (SAFe v1.4): if no AC/DoD exists for the goal, **BSA** spawns first to create spec from idea:

```text
idea → BSA (Sonnet/High, Read+Linear/Plane) → spec.md
  spec contains: user story, acceptance criteria, DoD, demo script, low-level tasks
```

BSA exit state: `"Spec ready — AC/DoD defined"`. Gate blocks Phase 1b until spec written.

In ticket mode: pull existing AC/DoD from Linear/Plane, write to `staging/<goal_id>/spec.md`, skip 1a.

#### 1b. Critique + Synthesize + Architect plan (genie's deliberate divergence)

```text
spec.md ─┬─→ Critic 1 (Sonnet/High, Read-only) ─→ critique-1.md
         ├─→ Critic 2 (Sonnet/High, Read-only) ─→ critique-2.md
         └─→ Critic N (Sonnet/High, Read-only) ─→ critique-N.md   [N odd, default 3]
                                                                ↓
         all critiques ─→ Synthesizer (Sonnet/High) ─→ decisions.md
                                                                ↓
         spec + decisions ─→ Architect (Opus/Max, Read+Bash) ─→ plan.md
```

- **N must be odd** — majority always possible (multi-agent-orchestration skill pitfall).
- Critics read `context/pattern-discovery.md` + Zettelkasten learnings (NEW) for prior-pattern cross-check.
- Synthesizer writes `## Decisions` section, resolves critique conflicts.
- **Tiebreaker** (Sonnet/High) spawned only if no majority after synth — binary decision, Opus overkill.
- Architect's `plan.md` contains: role roster (which specialists), dependency graph (parallel vs sequential), file ownership map, test strategy, complexity-classification per deliverable (triggers SysArch review thresholds).

Architect exit state: `"Plan ready — roles assigned"`.

### Phase 2 — Build (SAFe role-specialized + genie isolation)

Spawn specialists per `plan.md`. Specialist = SAFe role (FE/BE/DE/DPE/TW) — NOT genie's generic "implementor".

**Parallel/sequential** per dependency graph:
- Independent work (e.g. FE + BE + Docs) → parallel tmux sessions.
- Dependent (e.g. DE schema → BE API) → sequential with `wait-for` channel sync.

**Per-agent isolation (both)**:
- Each agent writes to `staging/<goal_id>/agent-<role>.md` (genie per-agent files — no shared mutable state during work).
- Each agent works in its own **git worktree** `~/.dark-factory/worktrees/<session>/agent-<N>/` (SAFe — code isolation). Both: files for logs/decisions, worktrees for code.
- `--append-system-prompt` injects: goal desc + spec + plan + pattern-discovery + skill summaries (genie).
- Tool restrictions per role (SAFe `AGENT_CONFIGURATION_SOP`): implementers get Read/Write/Edit/Bash; reviewers Read-only; SecEng RLS scripts only.

**Budget gate per spawn** (genie):
```bash
est=$(genie_estimate_cost "$role" 8000)
budget_tracker.py check "$goal_id" --estimate "$est" || exit 1   # pre-spawn block
# ... after spawn ...
budget_tracker.py record "$goal_id" --cost "$actual" --phase "$role"
```

**Completion markers** (genie, not pane-exit): each agent writes `staging/<goal_id>/completion-markers/<role>.done.json`:
```json
{"status":"done","exit_code":0,"role":"be-developer","timestamp":"..."}
```

Implementer exit state (SAFe): `"Ready for QAS"`.

### Phase 3 — QAS Gate (SAFe, NOT COLLAPSIBLE)

QAS is a **gate owner**, not a report producer. Replaces genie's "implementor→tester→reviewer" loop with proper gate semantics.

```text
implementer(s) done → QAS (Opus/High, Read+Bash(test)+Linear/Plane) → verdict
                                                          │
                                                          ├─ PASS  → "Approved for RTE" → Phase 4
                                                          └─ FAIL  → bounce-back to implementer (no retry cap on bounces, but total Phase 2+3 cycle capped at 3 full iterations)
```

- QAS verifies **all ACs** from spec, runs tests, posts evidence to Linear/Plane (`mcp__linear__create_comment` or `mcp__plane__add_work_item_comment`).
- QAS is an **independence gate** — never the same model session as implementer, never collapsible (SAFe 9R-499). Rationale: self-review bias.
- Bounce-back re-runs Phase 2 only for failed specialists, not full rebuild.

### Phase 4 — Independence Gates + Complexity Review (SAFe)

After QAS approves, two more gates fire **only if triggered**:

#### 4a. Security Engineer (independence gate, NOT collapsible)

Triggers: RLS policy changes, auth logic, secret handling, SSH/remote exec, security-critical code.
SecEng (Opus/High, RLS scripts+security tools) audits independently. Exit: `"Security audit passed"` or block.

#### 4b. System Architect (complexity-triggered, MANDATORY if triggered)

Triggers (SAFe v1.1, from 9R-321 lesson):
- Bash script >100 lines
- CI/CD workflow creation/modification
- Infrastructure-as-code (Terraform, CloudFormation)
- TypeScript/JavaScript >200 lines
- Database migration automation
- Security-critical code (overlaps 4a — both fire)

SysArch (Opus/Max, Read+Grep+ADR templates) reviews. If `REQUIRES_FIXES` → re-invoke specialist with feedback → re-review. Loop until `APPROVED`.

**NEW**: complexity-triggered review **auto-escalates budget ceiling**. If any 4b trigger fires, `budget_tracker.py raise-ceiling <goal_id> --reason complexity --by 25%`. Cost awareness tied to governance — neither parent had this.

#### 4c. Role collapsing (SAFe 9R-499)

For simple PRs (single-agent, no complex triggers, no security triggers):
- **RTE collapsible** → implementer handles PR creation. QAS gate still required before PR.
- **QAS NOT collapsible** — always independent.
- **SecEng NOT collapsible** — always independent.

```text
Standard:  Implementer → QAS → RTE → HITL
Collapsed: Implementer → QAS → [Implementer handles PR] → HITL
                       └─ QAS "Approved for RTE" still required
```

### Phase 5 — Final Critique (genie, post-build divergence)

After all gates pass, N parallel critics (same N as Phase 1b) review **built output**:

```text
built codebase + all agent files ─→ N Critics (Sonnet/High, Read-only) ─→ final-critiques/
                                                                       ↓
                                                  if any CRITICAL issue found → escalate to SysArch (Phase 4b)
                                                  else → Phase 6
```

Catches what gate-based review missed (gates are AC-focused; critics are holistic). Critics read Zettelkasten for prior failure patterns (NEW).

### Phase 6 — PR + 3-Stage Review (SAFe)

#### 6a. RTE PR shepherd (or collapsed implementer)

RTE (Haiku/Low, Git+gh+CI tools) — **no code, no merge**:
- Creates PR from spec/template
- Monitors CI/CD
- Assembles evidence
- Edits PR metadata
- Exit: `"Ready for HITL Review"`

#### 6b. 3-Stage PR Review

```text
Stage 1: System Architect  — pattern validation, technical review
         Exit: "Stage 1 Approved — Ready for ARCHitect"
Stage 2: ARCHitect-in-CLI   — architectural alignment, cross-cutting concerns
Stage 3: HITL (human)       — final merge authority
         Exit: MERGED
```

**Merge queue enforced** — no direct push to main. `gh pr merge --auto --squash` only. Queue is single entry point to trunk (SAFe dark-factory policy).

### Phase 7 — Merge + Learn (genie + SAFe evidence)

#### 7a. Post-hoc merge (genie)

`merge_goal.sh <goal_dir> <goal_id>`:
- Concatenates all `agent-*.md` files into single goal note `Obsidian Vault/10-goals/<goal_id>.md`.
- **mtime-safe**: skips if merged file newer than all sources.
- Strips ANSI (filter_daemon.py) — raw output kept in `raw-logs/`.

#### 7b. Zettelkasten learning extraction (genie)

`zettelkasten.sh <goal_id> <goal_dir>` spawns learn-extract (Sonnet/High, Read-only):
- Reads all agent output files.
- Extracts 1-3 **atomic insights** (one concept per learning).
- Writes to `Obsidian Vault/20-learnings/<id>-<slug>.md` with frontmatter + wikilinks.
- Updates `40-meta/moc-sessions.md` (Map of Content).
- Budget: ~$0.50/goal.

These learnings feed **Phase 0.5 Pass B** for future goals — compounding knowledge base. Neither parent closed this loop fully (genie wrote learnings but didn't read them; SAFe had no Zettelkasten).

#### 7c. Evidence + reconciliation

- Linear/Plane work item updated with QAS verdict, SysArch approval, PR link (`mcp__linear__update_issue` or `mcp__plane__update_work_item`).
- Budget reconciliation report: `budget_tracker.py report <goal_id>` — estimate vs actual per phase.
- Goal marked `completed`, moved to `99-archive/` after cooldown.

---

## 3. Unified Role Roster (15 roles)

| # | Role | Origin | Model | Effort | Tools | Collapsible? |
|---|------|--------|-------|--------|-------|--------------|
| 1 | BSA | SAFe | Sonnet | High | Read, Linear/Plane, Confluence | n/a (planning) |
| 2 | System Architect | SAFe | Opus | Max | Read, Grep, ADR | n/a (review) |
| 3 | BE Developer | SAFe | Sonnet | High | Read, Write, Edit, Bash | n/a |
| 4 | FE Developer | SAFe | Sonnet | High | Read, Write, Edit, Bash | n/a |
| 5 | Data Engineer | SAFe | Sonnet | High | Prisma, SQL, migration | n/a |
| 6 | DPE | SAFe | Haiku | Low | SQL, Prisma Studio | n/a |
| 7 | Tech Writer | SAFe | Sonnet | High | Read, Write, Edit, Grep, Glob | n/a |
| 8 | QAS | SAFe | Opus | High | Read, Bash(test), Linear/Plane | **NEVER** (independence) |
| 9 | Security Engineer | SAFe | Opus | High | RLS scripts, security tools | **NEVER** (independence) |
| 10 | RTE | SAFe | Haiku | Low | Git, gh, CI tools | YES (simple PRs) |
| 11 | TDM | SAFe | Sonnet | High | Linear/Plane, Confluence | n/a (reactive) |
| 12 | Critic ×N | genie | Sonnet | High | Read-only | n/a |
| 13 | Synthesizer | genie | Sonnet | High | Read-only | n/a |
| 14 | Tiebreaker | genie | Sonnet | High | Read-only | n/a (only if no majority) |
| 15 | Learn-extract | genie | Sonnet | High | Read-only | n/a |

**Role mapping** (genie generic → SAFe specific):
- genie `architect` → SAFe `System Architect` (Phase 1b plan) + `System Architect` (Phase 4b review) — same role, two invocation points.
- genie `implementor` → SAFe `BE/FE/DE/DPE/TW` per plan — multi-specialist, not one generic.
- genie `tester` → absorbed into `QAS` (QAS supersedes; tester was a sub-function).
- genie `reviewer` → absorbed into `QAS` (gate) + `System Architect` (complexity) + `Critic` (holistic) — three-way split, each with different lens.

---

## 4. Cross-Cutting (always-on)

### Budget gate (genie, extended)
- Default $50/goal, manifest-configurable.
- Pre-spawn check blocks if estimate > remaining.
- **NEW**: complexity-triggered review (Phase 4b) auto-raises ceiling +25% with `--reason complexity` audit trail.
- Per-phase tracking + post-hoc reconciliation.
- Dark-factory sessions (see §5) get per-session budget cap with **auto-shutdown on overspend** (NEW — genie tracked per-goal, SAFe dark-factory had no cost control).

### Priority queue (genie)
Two-queue weighted round-robin (3 high : 1 low) for multi-goal scheduling:
```python
urgency = priority * freshness * (1.0 + min(blocked_minutes,120)/60.0)
```
Caps `blocked_minutes` at 120 to prevent unbounded queue growth.

### Event-driven watchdog (genie)
1s `tmux_watchdog.sh` loop, silent when idle. Fires on:
- JSON completion marker written → advance phase.
- Pane-died (no claude process) → capture last 200 lines to `raw-logs/`, mark CRASHED.
- Idle >10min → inject nudge or spawn helper.
- inotify overflow → backstop polling reconciliation.

### Completion markers (genie, not pane-exit)
JSON signals unambiguous — `pane-exited` fires identically for exit 0, OOM, SIGKILL, accidental close. Markers are the source of truth.

### ANSI filter (genie)
`filter_daemon.py` (async) strips ANSI + control chars before writing to Obsidian. Raw kept in `raw-logs/`. Debounces rapid writes, handles SIGPIPE.

### Harness manifest (SAFe, unified)
`~/.hermes/manifests/<project>.yml` — single source of project identity:
```yaml
identity:
  PROJECT_NAME, PROJECT_REPO, PROJECT_SHORT, PROJECT_DOMAIN
  GITHUB_ORG, COMPANY_NAME, AUTHOR_*, SECURITY_EMAIL
  ARCHITECT_GITHUB_HANDLE, TICKET_PREFIX, LINEAR_WORKSPACE
  MAIN_BRANCH, MCP_LINEAR_SERVER, MCP_CONFLUENCE_SERVER
  # Plane — open-source Jira/Linear alternative (preferred)
  MCP_PLANE_SERVER, PLANE_WORKSPACE_SLUG, PLANE_API_URL
  DB_USER, DB_PASSWORD, DB_NAME, DB_CONTAINER
  DEV_CONTAINER, STAGING_CONTAINER, CONTAINER_REGISTRY
substitutions: {}        # derived from identity, override if needed
renames: {}              # file rename map (upstream → project)
protected: [...]         # never overwritten by sync
replaced: [...]          # project rewrote from upstream
sync:
  auto_substitute: true
  backup: true
  conflict_strategy: prompt
  substitution_extensions: [.md, .json, .yml, .yaml, .sh, .py, .ts, .mjs, .txt, .toml]
budget:                  # NEW — manifest-driven budget
  default_ceiling: 50.0
  complexity_escalation_pct: 25
  dark_factory_session_cap: 200.0
```

Manifest drives: skill injection filter (Phase 0.5), role config (Phase 2), budget ceiling, dark-factory env, merge-queue target branch.

---

## 5. Dark Factory Mode (SAFe, budget-extended)

Persistent 24/7 tmux teams on remote headless machine. Scope-driven team layouts:

```text
story  (3 panes): TDM + BE + QAS
feature(5 panes): TDM + BE + FE + QAS + RTE
epic   (9 panes): TDM + BSA + ARCH + SecEng + BE + FE + DE + QAS + RTE
```

- Per-agent git worktrees at `~/.dark-factory/worktrees/<session>/agent-N/`, branch `<session>-agent-N`.
- Per-agent logs via `tmux pipe-pane` → `~/.dark-factory/logs/<session>/<role>.log`.
- **NEW**: per-session budget cap (manifest `dark_factory_session_cap`). Auto-shutdown when cap hit — `factory-stop.sh` triggered by watchdog. Work persists in git branches/PRs (session state lost, but commits/PRs survive).
- Merge queue enforcement is a **readiness gate** — `factory-setup.sh` blocks if main branch lacks queue.
- `factory-status.sh` dashboard: green=active, yellow=idle>5min, red=dead (no claude process).

---

## 6. Vault Structure (genie Obsidian)

```text
~/Documents/Obsidian Vault/
├── 00-staging/          ← active goals, excluded from sync
│   └── <goal_id>/
│       ├── spec.md                  (Phase 1a, BSA)
│       ├── plan.md                  (Phase 1b, Architect)
│       ├── decisions.md             (Phase 1b, Synthesizer)
│       ├── context/
│       │   ├── pattern-discovery.md (Phase 0.5)
│       │   └── skill-summaries/     (Phase 0.5)
│       ├── agent-<role>.md          (Phase 2, per-agent files)
│       ├── critique-{1..N}.md      (Phase 1b + 5)
│       ├── completion-markers/      (JSON done signals)
│       └── raw-logs/                (crash dumps, unfiltered)
├── 10-goals/           ← merged output (read-only during work)
├── 11-sessions/        ← live session logs (pipe-pane output)
├── 20-learnings/       ← Zettelkasten atomic notes (feeds Phase 0.5)
├── 30-templates/       ← goal, session, learning templates
├── 40-meta/            ← MOC index (moc-sessions.md)
└── 99-archive/         ← completed goals (after cooldown)
```

---

## 7. Recovery Matrix

| Situation | Behavior |
|-----------|----------|
| Agent timeout (TTL) | Proceed with partial input, mark `timeout` in marker |
| Agent crash | Save last 200 lines to `raw-logs/`, retry same session-id |
| Budget exhausted | Pre-spawn gate blocks; dark-factory auto-shutdown |
| Complexity trigger | Auto-raise budget ceiling +25%, audit-trail logged |
| Model unavailable | Tiered fallback: primary → fallback → emergency |
| inotify overflow | Backstop polling reconciliation |
| Stuck agent (>10min) | Watchdog injects nudge or spawns helper |
| Session crash (dark-factory) | Work persists in git branches/worktrees/PRs; restart with same ticket |
| No majority after synth | Tiebreaker spawned (Sonnet/High) |
| Max 3 rebuild cycles | Proceed with best effort, flag in learnings |

---

## 8. What's NEW (neither parent had)

1. **Spec-creation phase before critics** — BSA fills AC/DoD gap in greenfield mode. Genie skipped this (idea→architect directly). SAFe assumed spec exists (ticket mode). v1 unifies: greenfield gets BSA, ticket mode skips.
2. **Pattern discovery searches Zettelkasten** — `20-learnings/` queried in Phase 0.5. Cross-session compounding. Genie wrote learnings but never read them; SAFe had no Zettelkasten.
3. **Complexity-triggered review auto-escalates budget** — SysArch trigger (bash>100, TS>200, CI/CD, security) raises ceiling +25% with audit trail. Ties cost awareness to governance.
4. **Dark-factory per-session budget cap + auto-shutdown** — genie tracked per-goal; SAFe dark-factory had no cost control. v1: dark-factory sessions get caps, watchdog auto-stops on overspend.
5. **Critic panel reads Zettelkasten** — critics cross-check against prior failure patterns. Catches recurring anti-patterns across goals.
6. **Manifest drives both skill injection AND role config** — single source of project identity (SAFe manifest only drove sync; genie had no manifest).
7. **Three-way reviewer split** — genie's single `reviewer` → QAS (AC gate) + SysArch (complexity gate) + Critic (holistic). Each lens independent, no single point of review failure.
8. **Plane MCP as preferred project backend** — open-source Jira/Linear alternative. 55+ MCP tools (work items, cycles, modules, epics, intake). Hermes orchestrator uses native `mcp_plane_*`, Claude Code agents use `mcp__plane__*`. Setup: `bash ~/.hermes/scripts/hermes-plane-setup.sh`. Self-hosted or cloud.
9. **Intelligent model selection (v3)** — reads tier→model mapping from `~/.claude/settings.json` (`ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL` env vars). Probes each model for capabilities (vision, tools, context window) via API call → cached in `~/.hermes/model-capabilities.json` (1h TTL). Selection: role_min_tier × complexity keywords × budget remaining. Spawn enrichment: warns Claude Code agent if model lacks vision/limited tools/context. Supports custom model providers (9router, OpenRouter, self-hosted).

---

## 9. Implementation Map

| Component | Source | Path |
|-----------|--------|------|
| Orchestrator | genie | `~/.hermes/scripts/genie.sh` (extended: mode-detect, BSA phase, gate phases) |
| Agent launcher | genie | `~/.hermes/scripts/hermes-spawn.sh` (extended: SAFe role roster, worktree creation) |
| Skill scan | genie | `~/.hermes/scripts/skill_scan.sh` (unchanged) |
| Pattern discovery | SAFe + NEW | `~/.hermes/scripts/pattern_discovery.sh` (NEW — merges SAFe search + Zettelkasten query) |
| Budget tracker | genie | `~/.hermes/scripts/budget_tracker.py` (extended: raise-ceiling, dark-factory session cap) |
| Priority queue | genie | `~/.hermes/scripts/priority_queue.py` (unchanged) |
| Watchdog | genie | `~/.hermes/scripts/tmux_watchdog.sh` (extended: dark-factory auto-shutdown) |
| Filter | genie | `~/.hermes/scripts/filter.sh` + `filter_daemon.py` (unchanged) |
| Merge | genie | `~/.hermes/scripts/merge_goal.sh` (unchanged) |
| Zettelkasten | genie | `~/.hermes/scripts/zettelkasten.sh` (unchanged) |
| Preflight | genie | `~/.hermes/scripts/hermes-preflight.sh` (extended: merge-queue readiness gate) |
| Recovery | genie | `~/.hermes/scripts/claude-recovery.sh` (unchanged) |
| Dark factory | SAFe | `~/.hermes/scripts/factory-{setup,start,stop,status,attach}.sh` (NEW Hermes port of SAFe dark-factory/) |
| Manifest | SAFe | `~/.hermes/manifests/<project>.yml` (NEW — SAFe manifest format, Hermes-resident) |
| Role prompts | SAFe | `~/.hermes/scripts/lib/roles/<role>.md` (NEW — port of SAFe `agent_providers/claude_code/prompts/*.md`) |
| Role config | SAFe | `~/.hermes/scripts/lib/_roles.sh` (NEW — model/effort/tools/permission per role, sourced by hermes-spawn.sh) |

**Implementation order** (lazy, minimum-viable):
1. Extend `genie.sh` with mode-detect + BSA phase + gate phases (Phase 1a, 3, 4, 5, 6).
2. Port SAFe role prompts + role config to `~/.hermes/scripts/lib/roles/` + `_roles.sh`.
3. New `pattern_discovery.sh` (Zettelkasten query is ~20 lines of grep against `20-learnings/`).
4. Extend `budget_tracker.py` with `raise-ceiling` + dark-factory session cap.
5. Port dark-factory scripts (deferred — only needed for 24/7 mode, not one-shot).
6. Harness manifest schema + loader (deferred — only needed for multi-project, not single).

---

## 10. Comparison: genie vs SAFe vs v1

| Dimension | genie v7 | SAFe v2.10 | **v1 (unified)** |
|-----------|----------|-------------|-------------------|
| Entry | one-command, idea only | manual method 1-4 selection | one-command, mode-auto-detected |
| Roles | 4 generic | 11 specialized | 15 (11 SAFe + 4 genie) |
| Planning | architect direct | specs-driven (assumes spec) | BSA spec gate → critics → architect |
| Divergence | N critics → synth | none (QAS iteration) | N critics → synth (Phase 1b + 5) |
| Pattern discovery | none | MANDATORY (specs+code+sessions) | MANDATORY (+ Zettelkasten) |
| Stop-the-line | none | AC/DoD gate | AC/DoD gate (BSA fills if missing) |
| Independence gates | none | QAS + SecEng | QAS + SecEng |
| Complexity review | none | SysArch (bash>100 etc) | SysArch (+ budget auto-escalate) |
| Role collapsing | none | RTE collapsible | RTE collapsible |
| Build isolation | per-agent files | git worktrees | **both** (files for logs, worktrees for code) |
| Cost control | $50 budget gate | none | $50 + complexity escalation + dark-factory cap |
| Multi-goal scheduling | priority queue | none | priority queue |
| Monitoring | event-driven watchdog | factory-status dashboard | both (watchdog drives dashboard) |
| Completion signal | JSON markers | pane-state | JSON markers |
| Knowledge capture | Zettelkasten (write-only) | none | **Zettelkasten (read+write, compounding)** |
| Evidence system | filesystem (Obsidian) | Linear | Linear/Plane + Obsidian (linked) |
| PR/CI phase | none (produces codebase) | RTE + 3-stage review + merge queue | RTE + 3-stage review + merge queue |
| HITL merge | none | Stage 3 | Stage 3 |
| Persistent 24/7 | none | dark factory | dark factory (budget-capped) |
| Multi-project sync | none | harness manifest | harness manifest (drives skill+role+budget) |
| Multi-provider | none (Hermes/Claude) | Claude+Gemini+Codex+Cursor | Hermes-native (Claude primary, extensible) |
| Skills | central Hermes lib (auto-inject) | per-project `.claude/skills` | central Hermes lib (auto-inject, manifest-filtered) |
| Three-layer arch | none | Hooks→Commands→Skills | Hooks→Commands→Skills (Hermes-native) |
| Recovery | TTL+retry+fallback | git persistence | TTL+retry+fallback+git persistence |

---

## 11. Open Questions (decide before implementation)

1. **Plane MCP (or Linear) available in Hermes?** If not, evidence → Obsidian only (drop SAFe integration, keep filesystem as system of record). Manifest field `MCP_PLANE_SERVER` (or `MCP_LINEAR_SERVER`) becomes optional. **Plane is preferred** — open-source, self-hostable, 55+ MCP tools vs Linear's REST API.
2. **Multi-provider scope for v1?** v1 ships Hermes+Claude only (simplest). SAFe's Gemini/Codex/Cursor support deferred to v2 unless manifest explicitly configures.
3. **Dark factory in v1?** Defer to v1.1 — one-shot pipeline (genie-style) is MVP. Dark factory adds 5 scripts + remote-machine setup; ship after one-shot validated.
4. **Critic count default?** 3 (genie default). Manifest can override. N must be odd.
5. **Budget default?** $50 (genie default). Manifest can override per project.
6. **Zettelkasten query mechanism?** v1 uses grep against `20-learnings/` frontmatter `tags:` + content. v2 may upgrade to FTS5 (session_search already has FTS5 infra).

---

*v1 spec. Markdown at `/home/ram/unified-agentic-workflow-v1.md`. Implementation deferred pending §11 decisions.*
