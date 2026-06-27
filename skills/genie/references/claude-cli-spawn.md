# Claude Code CLI Spawn Pitfalls

Pitfalls encountered when spawning Claude Code agents via `hermes-spawn.sh` in tmux sessions. These are durable CLI integration facts, not environment-specific transient errors.

## 1. `--permission-mode` Valid Values

Claude Code CLI (v2.1.193+) accepts ONLY these values for `--permission-mode`:

```
acceptEdits, auto, bypassPermissions, default, dontAsk, plan
```

**`"Read"` is NOT a valid permission mode.** The genie infrastructure (`_roles.sh` ROLE_PERMISSIONS array and `_models.sh` `genie_get_permission()` fallback) historically used `"Read"` for read-only roles (critic, reviewer, synthesizer, security-engineer, etc.). This causes agents to fail immediately with:

```
Error: Invalid value for --permission-mode: Read
Valid choices: acceptEdits, auto, bypassPermissions, default, dontAsk, plan
```

**Mapping (read-only roles → valid mode):**

| Old (invalid) | New (valid) | Behavior |
|---------------|-------------|----------|
| `"Read"` | `"default"` | Read-only with prompts — closest to intended read-only behavior |
| `"Read"` | `"plan"` | Plan-only mode (no edits) — alternative for pure analysis roles |

**Fix locations:**
- `~/.hermes/scripts/lib/_roles.sh` — `ROLE_PERMISSIONS` associative array (7+ entries)
- `~/.hermes/scripts/lib/_models.sh` — `genie_get_permission()` fallback return value

## 2. Prompt Argument Required When Stdout is Piped

When spawning `claude` in a tmux session with `| tee` for log capture:

```bash
# BROKEN — claude detects non-interactive (piped stdout), enters print mode,
#          but no prompt is provided
tmux new-session -d -s "$session" "claude --model '...' --effort '...' 2>&1 | tee '$log'"
# Error: "Input must be provided either through stdin or as a prompt argument when using --print"
```

The `| tee` pipe causes Claude CLI to detect non-interactive mode and switch to `--print` behavior, which requires input via stdin or a positional prompt argument.

**Fix — pass a prompt argument:**

```bash
tmux new-session -d -s "$session" \
    "claude --name '${session}' \
    --model '${model}' \
    --effort '${effort}' \
    --append-system-prompt '${sys_prompt}' \
    --permission-mode '${permission}' \
    'Begin your role as ${role} for goal: ${goal_desc}. Read the goal context, spec, and any existing plans in ${goal_dir}. Write your output to ${agent_file}. When done, write the JSON completion marker to ${goal_dir}/completion-markers/${role}${idx:+-${idx}}.done.json' \
    2>&1 | tee '${agent_file}'"
```

The prompt must be the **last positional argument** (not a flag). It should instruct the agent to:
1. Read context files in the goal staging directory
2. Write output to its designated agent file
3. Write a JSON completion marker when done

## 3. `--effort` Levels

Valid `--effort` values for Claude Code CLI:

```
low, medium, high, xhigh, max
```

## 4. Valid Flags Checklist

| Flag | Example | Notes |
|------|---------|-------|
| `--model` | `--model 'opencode-go/glm-5.2'` | Provider/model format |
| `--effort` | `--effort 'high'` | Reasoning depth |
| `--name` | `--name 'critic-1'` | Session label |
| `--permission-mode` | `--permission-mode 'default'` | See valid values above |
| `--append-system-prompt` | `--append-system-prompt '...'` | Role-specific instructions |
| (positional) | `'Begin your role...'` | Required when stdout piped |

## Debugging Spawn Failures

When agents fail silently or immediately:

1. **Check agent log files** in staging dir — `cat staging/{goal_id}/raw-logs/*.log`
2. **Check `bash -n` syntax** of spawn script — `bash -n ~/.hermes/scripts/hermes-spawn.sh`
3. **Check tmux sessions** — `tmux ls` (dead sessions = crash)
4. **Check for completion markers** — `ls staging/{goal_id}/completion-markers/` (empty = agents never ran)
5. **pstree** to find stuck processes — `pstree -p $(pgrep -f genie)`
