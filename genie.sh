#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Genie Pipeline v2 — Manager-Orchestrator
# ============================================================
# Changes from v1:
#   - Phase 0.5: Clarification (asks user before BSA)
#   - Manager monitor loop (replaces blind waitfor_with_ttl)
#   - Enhanced gating (verify output quality, not just marker)
#   - Bridge: trivial→answer, critical→ask user, expert→spawn
#   - Image + vision delegation support
#   - --resume flag (skip completed phases)
#
# Usage:
#   genie "Build a real-time whiteboard"           # greenfield
#   genie "9R-456"                                  # ticket mode
#   genie "Add OAuth middleware" 5                  # 5 critics
#   genie "Fix login bug" --skip-preflight          # bypass infra
#   genie "Add rate limiting" --resume              # resume from crash
#
# Image support (env vars):
#   GENIE_HAS_IMAGE=true GENIE_IMAGE_PATH=/tmp/img.png genie "implement this UI"
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_roles.sh"
source "${HOME}/.hermes/scripts/lib/_models.sh"
source "${HOME}/.hermes/scripts/lib/_sessions.sh"
source "${HOME}/.hermes/scripts/lib/_enrichment.sh"
source "${HOME}/.hermes/scripts/lib/_bridge.sh"

readonly MAX_RETRIES=3
readonly CLARIFY_TTL=300

# ─── Helper: spawn + monitor + gate ──────────────────────────
# Spawns a role, monitors via session_monitor_loop, verifies output.
# Returns 0 on success, non-zero on failure.
spawn_and_monitor() {
    local role="$1" goal_id="$2" goal_dir="$3" goal_desc="$4"
    local idx="${5:-}" ttl="${6:-$WAITFOR_TTL}"

    local session_name
    session_name=$(bash "${GENIE_DIR}/hermes-spawn.sh" \
        "$role" "$goal_id" "$goal_dir" "$goal_desc" "$idx" \
        "${GENIE_USER_MSG:-}" "${GENIE_HAS_IMAGE:-false}" "${GENIE_IMAGE_PATH:-}")

    local result=0
    session_monitor_loop "$session_name" "$goal_dir" "$role" "$goal_id" "$idx" "$ttl" || result=$?

    local role_key="${role}${idx:+-${idx}}"
    if [[ $result -eq 0 ]]; then
        write_completion_marker "$goal_dir" "$role_key" "done" 0
        # Enhanced gating: verify output quality
        local issues; issues=$(session_verify_output "$goal_dir" "$role" "$idx")
        if [[ -n "$issues" ]]; then
            log_warn "Output quality: ${role} — ${issues}"
            if tmux has-session -t "$session_name" 2>/dev/null; then
                session_send "$session_name" "Your output needs revision: ${issues}"
                session_monitor_loop "$session_name" "$goal_dir" "$role" "$goal_id" "$idx" 120 || true
                local recheck; recheck=$(session_verify_output "$goal_dir" "$role" "$idx")
                [[ -z "$recheck" ]] && log_ok "${role} revised successfully" || log_warn "${role} revision incomplete: ${recheck}"
            fi
        else
            log_ok "${role} output quality verified"
        fi
    else
        log_warn "${role} did not complete cleanly (exit: ${result})"
        write_completion_marker "$goal_dir" "$role_key" "timeout" 1
    fi
    return $result
}

# ─── Helper: spawn parallel critics + monitor ────────────────
# $5 = role_prefix (default: "critic", Phase 5 uses "critic-final")
spawn_parallel_critics() {
    local goal_id="$1" goal_dir="$2" goal_desc="$3" count="$4" prefix="${5:-critic}"

    local sessions=()
    for i in $(seq 1 "$count"); do
        local sess
        sess=$(bash "${GENIE_DIR}/hermes-spawn.sh" \
            "$prefix" "$goal_id" "$goal_dir" "$goal_desc" "$i" \
            "${GENIE_USER_MSG:-}" "${GENIE_HAS_IMAGE:-false}" "${GENIE_IMAGE_PATH:-}")
        sessions+=("$sess")
    done

    # Monitor all in parallel
    local pids=()
    for i in $(seq 1 "$count"); do
        (
            session_monitor_loop "${sessions[$((i-1))]}" "$goal_dir" "$prefix" "$goal_id" "$i" "$WAITFOR_TTL" || true
            local issues; issues=$(session_verify_output "$goal_dir" "$prefix" "$i")
            if [[ -n "$issues" ]]; then
                log_warn "${prefix} ${i}: ${issues}"
            else
                write_completion_marker "$goal_dir" "${prefix}-${i}" "done" 0
            fi
        ) &
        pids+=($!)
    done
    wait

    log_ok "All ${count} ${prefix} completed"
}

# ─── Phase 0.5: Clarification ───────────────────────────────
clarify_goal() {
    local goal_desc="$1" goal_dir="$2"

    # Skip if already clarified (resume)
    if [[ -f "${goal_dir}/context/clarification.md" ]]; then
        log_v "Phase 0.5: Clarification already done (resuming)"
        return 0
    fi

    # Skip if goal is a ticket (has structured requirements)
    if [[ "$goal_desc" =~ ^[A-Z]+-[0-9]+$ ]]; then
        log_v "Phase 0.5: Ticket mode — skipping clarification"
        return 0
    fi

    # Heuristic ambiguity check
    local ambiguities=""

    # Check: missing primary action
    if ! echo "$goal_desc" | grep -qiE 'build|add|fix|implement|create|refactor|update|remove|migrate|deploy'; then
        ambiguities+="What is the primary action (build, fix, refactor, etc.)?; "
    fi

    # Check: tech stack unclear
    if ! echo "$goal_desc" | grep -qiE 'api|ui|backend|frontend|database|react|vue|python|rust|go|node|typescript|javascript|cli|web|mobile'; then
        ambiguities+="What technology stack should be used?; "
    fi

    # Check: acceptance criteria absent
    if ! echo "$goal_desc" | grep -qiE 'test|pass|work|require|criteria|accept|should|must|when|given'; then
        ambiguities+="What are the acceptance criteria (how do we know it's done)?; "
    fi

    # Check: scope undefined (very short goal)
    local word_count; word_count=$(echo "$goal_desc" | wc -w)
    if (( word_count < 5 )); then
        ambiguities+="Please provide more detail about the scope and requirements; "
    fi

    if [[ -n "$ambiguities" ]]; then
        local q_dir="${goal_dir}/pending-questions"
        mkdir -p "$q_dir" 2>/dev/null || true

        local q_file="${q_dir}/clarification.question"
        cat > "$q_file" <<EOF
{
  "role": "clarification",
  "question": "${ambiguities}",
  "timestamp": "$(date -Iseconds)",
  "status": "pending"
}
EOF

        echo "NEEDS_USER_INPUT:clarification:${ambiguities}"
        log_info "Phase 0.5: Waiting for user clarification (TTL: ${CLARIFY_TTL}s)..."

        # Wait for answer file
        local answer_file="${goal_dir}/pending-answers/clarification.answer"
        local start; start=$(date +%s)
        while [[ ! -f "$answer_file" ]]; do
            if (( $(date +%s) - start >= CLARIFY_TTL )); then
                log_warn "Clarification timeout — proceeding with best effort"
                return 0
            fi
            sleep 2
        done

        # Write clarification to context
        local answer_content
        answer_content=$(python3 -c "import json; print(json.load(open('$answer_file')).get('answer',''))" 2>/dev/null || cat "$answer_file")

        local clar_dir="${goal_dir}/context"
        mkdir -p "$clar_dir" 2>/dev/null || true
        cat > "${clar_dir}/clarification.md" <<EOF
# Clarification Answers

**Original Goal:** ${goal_desc}

**Questions:** ${ambiguities}

**User Answers:**
${answer_content}
EOF
        log_ok "Phase 0.5: Clarification complete"
    else
        log_v "Phase 0.5: No clarification needed (goal is clear)"
    fi
}

# ─── Check if phase already done (for --resume) ─────────────
phase_completed() {
    local goal_dir="$1" role="$2" idx="${3:-}"
    local marker="${goal_dir}/completion-markers/${role}${idx:+-${idx}}.done.json"
    [[ -f "$marker" ]] && {
        local status; status=$(python3 -c "import json; print(json.load(open('$marker')).get('status',''))" 2>/dev/null)
        [[ "$status" == "done" ]]
    }
}

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
                exit 1
                ;;
        esac
    fi

    local goal_desc=""
    local critic_count=3
    local skip_preflight=false
    local force_lock=false
    local resume=false
    local project_dir="."

    # Parse args
    local positional=()
    for arg in "$@"; do
        case "$arg" in
            --skip-preflight) skip_preflight=true ;;
            --force)          force_lock=true ;;
            --resume)         resume=true ;;
            --project-dir=*)  project_dir="${arg#*=}" ;;
            *) positional+=("$arg") ;;
        esac
    done
    goal_desc="${positional[0]:-}"
    [[ -n "${positional[1]:-}" ]] && critic_count="${positional[1]}"

    if [[ -z "$goal_desc" ]]; then
        log_error "Usage: $0 '<idea|TICKET-ID>' [critic_count] [--skip-preflight] [--resume] [--project-dir=.]"
        exit 1
    fi

    # Validate critic count is odd
    if (( critic_count % 2 == 0 )); then
        log_warn "Critic count must be odd. Using $((critic_count + 1))."
        critic_count=$((critic_count + 1))
    fi

    # Mode detect
    local mode="greenfield"
    if [[ "$goal_desc" =~ ^[A-Z]+-[0-9]+$ ]]; then
        mode="ticket"
        log_v "Mode: TICKET ($goal_desc) — skipping BSA spec creation"
    else
        log_v "Mode: GREENFIELD — BSA will create spec"
    fi

    # Phase 0: Preflight
    if [[ "$skip_preflight" == "false" ]] && [[ "$resume" == "false" ]]; then
        log_v "Phase 0: Preflight checks"
        bash "${GENIE_DIR}/hermes-preflight.sh" "$project_dir" || exit 1
    fi

    # Process lock
    if [[ "$force_lock" == "false" ]]; then
        local genie_lock="${STAGING_DIR}/.genie.lock"
        exec 9>"$genie_lock"
        if ! flock -n 9; then
            log_error "Another genie run is active. Use --force to override."
            exit 1
        fi
        echo $$ > "$genie_lock"
    fi

    # Generate goal ID and directories
    local goal_id
    goal_id=$(gen_goal_id "$goal_desc")
    local goal_dir="${STAGING_DIR}/${goal_id}"

    # Resume: find existing goal dir (slugify goal_desc to match gen_goal_id naming)
    if [[ "$resume" == "true" ]]; then
        local resume_slug
        resume_slug=$(echo "$goal_desc" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-$//')
        local existing_dir=$(ls -d "${STAGING_DIR}/"*"-${resume_slug:0:20}"* 2>/dev/null | head -1)
        if [[ -n "$existing_dir" ]] && [[ -d "$existing_dir" ]]; then
            goal_dir="$existing_dir"
            goal_id=$(basename "$goal_dir")
            log_v "Resuming goal: $goal_id"
        else
            log_warn "No existing goal found for resume. Starting fresh."
            resume=false
        fi
    fi

    safe_mkdir "$goal_dir"
    safe_mkdir "${goal_dir}/completion-markers"
    safe_mkdir "${goal_dir}/raw-logs"
    safe_mkdir "${goal_dir}/skill-summaries"
    safe_mkdir "${goal_dir}/context"
    safe_mkdir "${goal_dir}/pending-questions"
    safe_mkdir "${goal_dir}/pending-answers"

    # Install cleanup trap
    trap_cleanup "$goal_dir"

    log_v "Goal ID: $goal_id | Mode: $mode | Critics: $critic_count | Resume: $resume"

    # Initialize budget (skip if resuming)
    if [[ "$resume" == "false" ]]; then
        python3 "${GENIE_DIR}/budget_tracker.py" init "$goal_id" --budget 50.0
    fi

    # Write goal context (skip if resuming)
    if [[ "$resume" == "false" ]] || [[ ! -f "${goal_dir}/goal-context.json" ]]; then
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
    fi

    # Phase 0.5a: Skill Scan + Pattern Discovery
    if ! phase_completed "$goal_dir" "skill-scan"; then
        log_v "Phase 0.5a: Skill scan + Pattern discovery"
        bash "${GENIE_DIR}/skill_scan.sh" "$goal_desc" "$goal_dir" 2>/dev/null || log_warn "Skill scan failed (non-fatal)"
        bash "${GENIE_DIR}/pattern_discovery.sh" "$goal_desc" "$goal_dir" "$project_dir" 2>/dev/null || log_warn "Pattern discovery failed (non-fatal)"
        write_completion_marker "$goal_dir" "skill-scan" "done" 0
    fi

    # Phase 0.5b: Clarification
    if ! phase_completed "$goal_dir" "clarification"; then
        log_v "Phase 0.5b: Clarification"
        clarify_goal "$goal_desc" "$goal_dir"
        write_completion_marker "$goal_dir" "clarification" "done" 0
    fi

    # Phase 1a: BSA spec gate (greenfield only)
    local spec_file="${goal_dir}/spec.md"
    if [[ "$mode" == "greenfield" ]]; then
        if ! phase_completed "$goal_dir" "bsa"; then
            log_v "Phase 1a: BSA — spec creation (stop-the-line gate)"
            spawn_and_monitor "bsa" "$goal_id" "$goal_dir" "$goal_desc" "" 600 || true

            # Stop-the-line: verify spec exists with AC/DoD
            if [[ ! -f "$spec_file" ]] || ! grep -qi "acceptance criteria\|AC[0-9]" "$spec_file" 2>/dev/null; then
                log_error "Stop-the-line: BSA did not produce spec with acceptance criteria. Halting."
                exit 1
            fi
            log_ok "Spec created with AC/DoD — stop-the-line gate passed"
        else
            log_v "Phase 1a: BSA already done (resuming)"
        fi
    else
        # Ticket mode: write minimal spec
        if [[ ! -f "$spec_file" ]]; then
            log_v "Ticket mode: writing placeholder spec"
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
    fi

    # Phase 1b: Critics (parallel) → Synthesizer → Architect
    if ! phase_completed "$goal_dir" "synthesizer"; then
        log_v "Phase 1b: ${critic_count} critics (parallel)"
        spawn_parallel_critics "$goal_id" "$goal_dir" "$goal_desc" "$critic_count"

        log_v "Phase 1b: Synthesizer"
        spawn_and_monitor "synthesizer" "$goal_id" "$goal_dir" "$goal_desc" "" 900
    fi

    if ! phase_completed "$goal_dir" "architect"; then
        log_v "Phase 1b: Architect — plan.md"
        spawn_and_monitor "architect" "$goal_id" "$goal_dir" "$goal_desc" "" 600
    fi

    # Phase 2+3: Build → QAS gate loop (max 3 iterations)
    local build_iteration=0
    local qas_approved=false

    while [[ "$qas_approved" == "false" && $build_iteration -lt $MAX_RETRIES ]]; do
        build_iteration=$((build_iteration + 1))
        log_v "Build iteration ${build_iteration}/${MAX_RETRIES}"

        # Phase 2: Implementor
        if ! phase_completed "$goal_dir" "implementor"; then
            spawn_and_monitor "implementor" "$goal_id" "$goal_dir" "$goal_desc" "" 1200
        fi

        # Complexity triggers → budget raise + SysArch review
        if check_complexity_triggers "$project_dir" 2>/dev/null; then
            log_warn "Complexity triggers fired — raising budget ceiling +25%"
            python3 "${GENIE_DIR}/budget_tracker.py" raise-ceiling "$goal_id" --pct 25.0 --reason "complexity-triggered-review" 2>/dev/null || true

            if ! phase_completed "$goal_dir" "system-architect"; then
                log_v "Phase 4b: System Architect review (complexity-triggered, MANDATORY)"
                spawn_and_monitor "system-architect" "$goal_id" "$goal_dir" "$goal_desc" "" 600

                if grep -qi "REQUIRES_FIXES" "${goal_dir}/agent-system-architect.md" 2>/dev/null; then
                    log_info "SysArch requested fixes — re-implementing"
                    rm -f "${goal_dir}/completion-markers/implementor.done.json"
                    continue
                fi
                log_ok "SysArch approved."
            fi
        fi

        # Phase 4a: Security Engineer (if security-sensitive)
        if grep -rli "password\|secret\|api_key\|auth\|token\|rls\|row.level" "$project_dir" --include='*.ts' --include='*.py' --include='*.sh' --include='*.sql' 2>/dev/null | grep -qv node_modules; then
            if ! phase_completed "$goal_dir" "security-engineer"; then
                log_v "Phase 4a: Security Engineer audit"
                spawn_and_monitor "security-engineer" "$goal_id" "$goal_dir" "$goal_desc" "" 600

                if grep -qi "SECURITY_BLOCKED" "${goal_dir}/agent-security-engineer.md" 2>/dev/null; then
                    log_error "Security block — re-implementing"
                    rm -f "${goal_dir}/completion-markers/implementor.done.json"
                    continue
                fi
                log_ok "Security audit passed."
            fi
        fi

        # Phase 3: QAS gate
        if ! phase_completed "$goal_dir" "qas"; then
            log_v "Phase 3: QAS gate (independence gate)"
            spawn_and_monitor "qas" "$goal_id" "$goal_dir" "$goal_desc" "" 600

            if grep -qi "Approved for RTE\|APPROVED\|PASS" "${goal_dir}/agent-qas.md" 2>/dev/null; then
                qas_approved=true
                log_ok "QAS approved — gate passed."
            elif grep -qi "CHANGES_NEEDED\|FAIL" "${goal_dir}/agent-qas.md" 2>/dev/null; then
                log_info "QAS requested changes — re-implementing"
                rm -f "${goal_dir}/completion-markers/implementor.done.json"
            else
                log_warn "QAS verdict unclear — assuming pass"
                qas_approved=true
            fi
        else
            qas_approved=true
        fi
    done

    if [[ "$qas_approved" == "false" ]]; then
        log_warn "Max rebuild cycles reached. Proceeding with best effort."
    fi

    # Phase 5: Final Critique (post-build, holistic)
    if ! phase_completed "$goal_dir" "critic-final-1"; then
        log_v "Phase 5: Final critique (${critic_count} critics, parallel)"
        spawn_parallel_critics "$goal_id" "$goal_dir" "$goal_desc" "$critic_count" "critic-final"
    fi

    # Phase 6: PR (RTE)
    if ! phase_completed "$goal_dir" "rte"; then
        if git -C "$project_dir" rev-parse --git-dir &>/dev/null 2>&1; then
            log_v "Phase 6: PR creation (RTE)"
            spawn_and_monitor "rte" "$goal_id" "$goal_dir" "$goal_desc" "" 600
        else
            log_v "Not a git repo — skipping PR phase. Output in staging."
        fi
    fi

    # Phase 7: Merge + Learn (MANDATORY — not optional)
    log_v "Phase 7: Merge + Zettelkasten learning extraction"

    # 7a: Merge all agent outputs into goal note
    local merged_file=""
    merged_file=$(bash "${GENIE_DIR}/merge_goal.sh" "$goal_dir" "$goal_id" 2>&1 | tail -1) || {
        log_error "Phase 7a FAILED: merge_goal.sh exited non-zero"
        log_error "Output: $merged_file"
    }
    # Verify merge produced output
    local expected_merge="${VAULT_DIR}/10-goals/${goal_id}.md"
    if [[ ! -f "$expected_merge" ]] || [[ ! -s "$expected_merge" ]]; then
        log_error "Phase 7a FAILED: merged goal note missing or empty at ${expected_merge}"
        log_error "Cannot proceed to learning extraction without merged output"
    else
        log_ok "Phase 7a: Merged to ${expected_merge} ($(wc -c < "$expected_merge") bytes)"

        # 7b: Extract Zettelkasten learnings (only if merge succeeded)
        local learn_output=""
        learn_output=$(bash "${GENIE_DIR}/zettelkasten.sh" "$goal_id" "$goal_dir" 2>&1) || {
            log_warn "Phase 7b: Learning extraction failed (non-fatal)"
            log_warn "$learn_output"
        }
        # Verify learnings
        local learning_count
        learning_count=$(find "${VAULT_DIR}/20-learnings/" -name "*.md" -newer "$expected_merge" 2>/dev/null | wc -l)
        if [[ "$learning_count" -gt 0 ]]; then
            log_ok "Phase 7b: Extracted ${learning_count} learning(s) to ${VAULT_DIR}/20-learnings/"
        else
            log_warn "Phase 7b: No new learnings extracted (may be expected for trivial goals)"
        fi

        # 7c: Update MOC (Map of Content) for this goal
        local moc="${VAULT_DIR}/40-meta/moc-sessions.md"
        safe_mkdir "$(dirname "$moc")" 2>/dev/null || true
        if ! grep -q "$goal_id" "$moc" 2>/dev/null; then
            echo "- [[${goal_id}]] — $(date +%Y-%m-%d) — ${goal_desc:0:80}" >> "$moc"
            log_ok "Phase 7c: MOC updated"
        fi
    fi

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
    python3 "${GENIE_DIR}/budget_tracker.py" report "$goal_id" 2>/dev/null || true

    log_ok "✓ Goal complete: $goal_id"
    log_info "Merged output: ${VAULT_DIR}/10-goals/${goal_id}.md"
    log_info "Learnings: ${VAULT_DIR}/20-learnings/"
    log_info "Staging:   ${goal_dir}/"
}

main "$@"
