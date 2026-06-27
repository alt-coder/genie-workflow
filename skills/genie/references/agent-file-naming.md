# Agent File Naming Convention

Root cause of 3 bugs found in Phase 7 scripts (fixed 2026-06-27).

## Convention

`hermes-spawn.sh` names output files: `agent-${role}${suffix}.md`

- `${role}` — the role slug passed to `spawn_parallel_critics` (or `hermes_spawn`)
- `${suffix}` — `-${N}` for parallel critics, empty for single agents

## Actual filenames by phase

| Phase | Role slug | Suffix | Filename pattern | Merge section |
|-------|-----------|--------|-------------------|---------------|
| 1a | `bsa` | — | `agent-bsa.md` | BSA Spec |
| 1b | `critic` | `-1`, `-2`, ... | `agent-critic-1.md` | Critics |
| 1b | `synthesizer` | — | `agent-synthesizer.md` | Synthesis |
| 1b | `architect` | — | `agent-architect.md` | Architect Plan |
| 2 | `implementor` | — | `agent-implementor.md` | Implementation |
| 3 | `qas` | — | `agent-qas.md` | QAS Verdict |
| 4 | `seceng` | — | `agent-seceng.md` | Security Review |
| 4 | `sysarch` | — | `agent-sysarch.md` | SysArch Review |
| 5 | `critic-final` | `-1`, `-2`, ... | `agent-critic-final-1.md` | Final Critique |
| 6 | `rte` | — | `agent-rte.md` | PR Creation |

## Bugs fixed

1. **`critique` vs `critic`** — merge_goal.sh globbed `agent-critique-*.md` but files are `agent-critic-*.md`. Fix: use correct role slug.
2. **`final-critique` vs `critic-final`** — merge_goal.sh globbed `agent-final-critique-*.md` but files are `agent-critic-final-*.md`. Fix: prefix param `critic-final` passed to `spawn_parallel_critics`.
3. **Phase 1b/5 collision** — both phases used prefix `critic`, so Phase 5 `agent-critic-1.md` overwrote Phase 1b's. Fix: `spawn_parallel_critics` accepts `$5=prefix` (default `critic`), Phase 5 passes `critic-final`.

## Debugging tip

When merge_goal.sh produces empty or partial output:
1. `ls agent-*.md` in goal dir — see actual filenames
2. Compare against the table above
3. Check `spawn_parallel_critics` call in genie.sh — verify prefix arg matches
