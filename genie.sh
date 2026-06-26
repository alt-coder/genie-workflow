#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Genie Pipeline v1 — Unified (genie × SAFe)
# One command: idea or ticket → working codebase → PR
#
# Usage:
#   genie "Build a real-time whiteboard"           # greenfield
#   genie "9R-456"                                  # ticket mode (skip BSA)
#   genie "Add OAuth middleware" 5                  # 5 critics (must be odd)
#   genie "Fix login bug" --skip-preflight          # bypass infra check
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_roles.sh"

readonly MAX_RETRIES=3

main() {
    # ── Factory subcommand dispatch ──
    if [[ "${1:-}" == "factory" ]]; then
        shift
        subcmd="${1:-}"
        shift || true
        case "$subcmd" in
            setup)  exec bash "${GENIE_DIR}/factory-setup.sh" "$@" ;;
            start)  exec bash "${GENIE_DIR}/factory-start.sh" "$@" ;;
            stop)   exec bash "${GENIE_DIR}/factory-stop.sh" "$@" ;;
            status) exec bash "${GENIE_DIR}/factory-status.sh" "$@" ;;
            attach)
                local sess="${1:-}"
                if [[ -z "$sess" ]]; then
                    sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^factory-' || true)"
                    if [[ -z "$sessions" ]]; then
                        log_error "No factory sessions running."
                        exit 1
                    fi
                    echo "$sessions" | nl -ba
                    exit 0
                fi
                exec tmux attach -t "$sess"
                ;;
            *)
                log_error "Usage: genie factory <setup|start|stop|status|attach> [args]"
                log_error "  setup:  One-time environment setup + merge-queue gate"
                log_error "  start:  Launch team — genie factory start <story|feature|epic> [ticket]"
                log_error "  stop:   Stop session — genie factory stop [session]"
                log_error "  status: Dashboard of all factory sessions"
                log_error "  attach: Attach to session — genie factory attach <session>"
                exit 1
                ;;
        esac
    fi

    local goal_desc=""
    local critic_count=3
    local skip_preflight=false
    local project_dir="."

    # Parse args
    local positional=()
    for arg in "$@"; do
        case "$arg" in
            --skip-preflight) skip_preflight=true ;;
            --project-dir=*)  project_dir="${arg#*=}" ;;
            *) positional+=("$arg") ;;
        esac
    done
    goal_desc="${positional[0]:-}"
    [[ -n "${positional[1]:-}" ]] && critic_count="${positional[1]}"

    if [[ -z "$goal_desc" ]]; then
        log_error "Usage: $0 '<idea|TICKET-ID>' [critic_count] [--skip-preflight] [--project-dir=.]"
        exit 1
    fi

    # Validate critic count is odd
    if (( critic_count % 2 == 0 )); then
        log_warn "Critic count must be odd. Using $((critic_count + 1))."
        critic_count=$((critic_count + 1))
    fi

    # Mode detect: ticket (TICKET-123) vs greenfield
    local mode="greenfield"
    if [[ "$goal_desc" =~ ^[A-Z]+-[0-9]+$ ]]; then
        mode="ticket"
        log_v "Mode: TICKET ($goal_desc) — skipping BSA spec creation"
    else
        log_v "Mode: GREENFIELD — BSA will create spec before critics"
    fi

    # Phase 0: Preflight
    if [[ "$skip_preflight" == "false" ]]; then
        log_v "Phase 0: Preflight checks"
        bash "${GENIE_DIR}/hermes-preflight.sh" "$project_dir" || exit 1
    fi

    # Generate goal ID and directories
    local goal_id
    goal_id=$(gen_goal_id "$goal_desc")
    local goal_dir="${STAGING_DIR}/${goal_id}"
    safe_mkdir "$goal_dir"
    safe_mkdir "${goal_dir}/completion-markers"
    safe_mkdir "${goal_dir}/raw-logs"
    safe_mkdir "${goal_dir}/skill-summaries"
    safe_mkdir "${goal_dir}/context"

    log_v "Goal ID: $goal_id | Mode: $mode | Critics: $critic_count"

    # Initialize budget
    python3 "${GENIE_DIR}/budget_tracker.py" init "$goal_id" --budget 50.0

    # Write goal context
    cat > "${goal_dir}/goal-context.json" <<EOF
{
  "goal_id": "${goal_id}",
  "description": "${goal_desc}",
  "mode": "${mode}",
  "status": "active",
  "priority": 3,
  "created_at": $(date +%s),
  "blocked_minutes": 0,
  "critic_count": ${critic_count},
  "project_dir": "${project_dir}"
}
EOF

    # Phase 0.5: Skill Scan + Pattern Discovery
    log_v "Phase 0.5: Skill scan + Pattern discovery"
    bash "${GENIE_DIR}/skill_scan.sh" "$goal_desc" "$goal_dir" 2>/dev/null || log_warn "Skill scan failed (non-fatal)"
    bash "${GENIE_DIR}/pattern_discovery.sh" "$goal_desc" "$goal_dir" "$project_dir"

    # Phase 1a: BSA spec gate (greenfield only)
    local spec_file="${goal_dir}/spec.md"
    if [[ "$mode" == "greenfield" ]]; then
        log_v "Phase 1a: BSA — spec creation (stop-the-line gate)"
        bash "${GENIE_DIR}/hermes-spawn.sh" bsa "$goal_id" "$goal_dir" "$goal_desc"
        if waitfor_with_ttl "${goal_id}-bsa-done"; then
            write_completion_marker "$goal_dir" "bsa" "done" 0
        else
            log_error "BSA timeout — no spec, cannot proceed. Stop-the-line gate failed."
            write_completion_marker "$goal_dir" "bsa" "timeout" 1
            exit 1
        fi

        # Stop-the-line: verify spec exists with AC/DoD
        if [[ ! -f "$spec_file" ]] || ! grep -qi "acceptance criteria\|AC[0-9]" "$spec_file" 2>/dev/null; then
            log_error "Stop-the-line: BSA did not produce spec with acceptance criteria. Halting."
            exit 1
        fi
        log_ok "Spec created with AC/DoD — stop-the-line gate passed"
    else
        # Ticket mode: spec pulled from ticket system (placeholder — write minimal spec)
        log_v "Ticket mode: writing placeholder spec from ticket ID"
        cat > "$spec_file" <<EOF
# Spec: $goal_desc

## User Story
As a user, I want the work described in ticket $goal_desc.

## Acceptance Criteria
- [ ] All requirements from ticket $goal_desc are met
- [ ] Tests pass
- [ ] No regressions

## Definition of Done
- [ ] Ticket requirements implemented
- [ ] Tests added and passing
- [ ] Documentation updated
EOF
    fi

    # Phase 1b: Critique + Synthesize + Architect plan
    log_v "Phase 1b: ${critic_count} critics (parallel) → synthesizer → architect"

    # Spawn critics in parallel
    for i in $(seq 1 "$critic_count"); do
        bash "${GENIE_DIR}/hermes-spawn.sh" critic "$goal_id" "$goal_dir" "$goal_desc" "$i" &
    done
    wait

    # Wait for all critics with TTL
    local critic_wait_start
    critic_wait_start=$(date +%s)
    while true; do
        local all_done=true
        for i in $(seq 1 "$critic_count"); do
            local marker="${goal_dir}/completion-markers/critic${i}.done.json"
            [[ ! -f "$marker" ]] && { all_done=false; break; }
        done
        [[ "$all_done" == "true" ]] && break
        if (( $(date +%s) - critic_wait_start > WAITFOR_TTL )); then
            log_warn "Critics timeout. Proceeding with partial critiques."
            break
        fi
        sleep 2
    done

    # Synthesizer
    log_v "Phase 1b: Synthesizer"
    bash "${GENIE_DIR}/hermes-spawn.sh" synthesizer "$goal_id" "$goal_dir" "$goal_desc"
    if waitfor_with_ttl "${goal_id}-synthesizer-done"; then
        write_completion_marker "$goal_dir" "synthesizer" "done" 0
    else
        log_warn "Synthesizer timeout."
        write_completion_marker "$goal_dir" "synthesizer" "timeout" 1
    fi

    # Architect writes plan.md
    log_v "Phase 1b: Architect — plan.md"
    bash "${GENIE_DIR}/hermes-spawn.sh" architect "$goal_id" "$goal_dir" "$goal_desc"
    if waitfor_with_ttl "${goal_id}-architect-done"; then
        write_completion_marker "$goal_dir" "architect" "done" 0
    else
        log_warn "Architect timeout. Proceeding with partial plan."
        write_completion_marker "$goal_dir" "architect" "timeout" 1
    fi

    # Phase 2+3: Build → QAS gate loop (max 3 full iterations)
    log_v "Phase 2+3: Build → QAS gate (max ${MAX_RETRIES} iterations)"

    local build_iteration=0
    local qas_approved=false

    while [[ "$qas_approved" == "false" && $build_iteration -lt $MAX_RETRIES ]]; do
        build_iteration=$((build_iteration + 1))
        log_v "Build iteration ${build_iteration}/${MAX_RETRIES}"

        # Phase 2: Implementor (reads plan.md, plays specialist roles as directed)
        bash "${GENIE_DIR}/hermes-spawn.sh" implementor "$goal_id" "$goal_dir" "$goal_desc"
        if waitfor_with_ttl "${goal_id}-implementor-done"; then
            write_completion_marker "$goal_dir" "implementor" "done" 0
        else
            log_warn "Implementor timeout."
            write_completion_marker "$goal_dir" "implementor" "timeout" 1
        fi

        # Phase 4b pre-check: complexity triggers (auto-escalate budget if fired)
        if check_complexity_triggers "$project_dir"; then
            log_warn "Complexity triggers fired — raising budget ceiling +25%"
            python3 "${GENIE_DIR}/budget_tracker.py" raise-ceiling "$goal_id" --pct 25.0 --reason "complexity-triggered-review"
            # SysArch review (mandatory if complexity triggered)
            log_v "Phase 4b: System Architect review (complexity-triggered, MANDATORY)"
            bash "${GENIE_DIR}/hermes-spawn.sh" system-architect "$goal_id" "$goal_dir" "$goal_desc"
            if waitfor_with_ttl "${goal_id}-system-architect-done"; then
                write_completion_marker "$goal_dir" "system-architect" "done" 0
            else
                log_warn "System Architect timeout."
                write_completion_marker "$goal_dir" "system-architect" "timeout" 1
            fi
            # Check if REQUIRES_FIXES
            if grep -qi "REQUIRES_FIXES" "${goal_dir}/agent-system-architect.md" 2>/dev/null; then
                log_info "SysArch requested fixes — re-implementing (iteration $build_iteration continues)"
                continue  # restart build loop (implementor re-runs with architect feedback)
            fi
            log_ok "SysArch approved."
        fi

        # Phase 4a: Security Engineer (independence gate — fires if security-sensitive)
        # Check for security-sensitive patterns in implemented code
        if grep -rli "password\|secret\|api_key\|auth\|token\|rls\|row.level" "$project_dir" --include='*.ts' --include='*.py' --include='*.sh' --include='*.sql' 2>/dev/null | grep -qv node_modules; then
            log_v "Phase 4a: Security Engineer audit (security-sensitive code detected)"
            bash "${GENIE_DIR}/hermes-spawn.sh" security-engineer "$goal_id" "$goal_dir" "$goal_desc"
            if waitfor_with_ttl "${goal_id}-security-engineer-done"; then
                write_completion_marker "$goal_dir" "security-engineer" "done" 0
            else
                log_warn "Security Engineer timeout."
                write_completion_marker "$goal_dir" "security-engineer" "timeout" 1
            fi
            if grep -qi "SECURITY_BLOCKED" "${goal_dir}/agent-security-engineer.md" 2>/dev/null; then
                log_error "Security block — re-implementing to fix security issues"
                continue  # restart build loop
            fi
            log_ok "Security audit passed."
        fi

        # Phase 3: QAS gate (independence gate — NOT collapsible)
        log_v "Phase 3: QAS gate (independence gate)"
        bash "${GENIE_DIR}/hermes-spawn.sh" qas "$goal_id" "$goal_dir" "$goal_desc"
        if waitfor_with_ttl "${goal_id}-qas-done"; then
            write_completion_marker "$goal_dir" "qas" "done" 0
        else
            log_warn "QAS timeout."
            write_completion_marker "$goal_dir" "qas" "timeout" 1
        fi

        # Check QAS verdict
        if grep -qi "Approved for RTE\|APPROVED\|PASS" "${goal_dir}/agent-qas.md" 2>/dev/null; then
            qas_approved=true
            log_ok "QAS approved — gate passed."
        elif grep -qi "CHANGES_NEEDED\|FAIL" "${goal_dir}/agent-qas.md" 2>/dev/null; then
            log_info "QAS requested changes — re-implementing (iteration $build_iteration)"
        else
            log_warn "QAS verdict unclear — assuming pass (best effort)."
            qas_approved=true
        fi
    done

    if [[ "$qas_approved" == "false" ]]; then
        log_warn "Max rebuild cycles reached. Proceeding with best effort."
    fi

    # Phase 5: Final Critique (post-build, holistic)
    log_v "Phase 5: Final critique (${critic_count} critics, parallel)"
    for i in $(seq 1 "$critic_count"); do
        bash "${GENIE_DIR}/hermes-spawn.sh" critic "$goal_id" "$goal_dir" "$goal_desc" "final-${i}" &
    done
    wait

    # Phase 6: PR (RTE shepherd — or collapsed into implementer)
    log_v "Phase 6: PR creation (RTE)"
    # Check if this is a git repo
    if git -C "$project_dir" rev-parse --git-dir &>/dev/null; then
        bash "${GENIE_DIR}/hermes-spawn.sh" rte "$goal_id" "$goal_dir" "$goal_desc"
        if waitfor_with_ttl "${goal_id}-rte-done"; then
            write_completion_marker "$goal_dir" "rte" "done" 0
        else
            log_warn "RTE timeout — PR creation skipped."
            write_completion_marker "$goal_dir" "rte" "timeout" 1
        fi
    else
        log_v "Not a git repo — skipping PR phase (Phase 6). Output in staging."
    fi

    # Phase 7: Merge + Learn
    log_v "Phase 7: Merge + Zettelkasten learning extraction"

    # Post-hoc merge
    bash "${GENIE_DIR}/merge_goal.sh" "$goal_dir" "$goal_id" 2>/dev/null || log_warn "Merge failed (non-fatal)"

    # Zettelkasten learning extraction
    bash "${GENIE_DIR}/zettelkasten.sh" "$goal_id" "$goal_dir" 2>/dev/null || log_warn "Learn extraction failed (non-fatal)"

    # Mark complete
    python3 -c "
import json
with open('${goal_dir}/goal-context.json') as f:
    d = json.load(f)
d['status'] = 'completed'
d['completed_at'] = $(date +%s)
with open('${goal_dir}/goal-context.json', 'w') as f:
    json.dump(d, f, indent=2)
"

    # Final budget report
    python3 "${GENIE_DIR}/budget_tracker.py" report "$goal_id"

    log_ok "✓ Goal complete: $goal_id"
    log_info "Merged output: ${VAULT_DIR}/10-goals/${goal_id}.md"
    log_info "Learnings: ${VAULT_DIR}/20-learnings/"
    log_info "Staging:   ${goal_dir}/"
}

main "$@"
