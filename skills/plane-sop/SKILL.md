---
name: plane-sop
description: Plane work item management via MCP. Use when creating issues, updating status, attaching evidence, or managing cycles/modules. Plane is the open-source Jira/Linear alternative with 55+ MCP tools.
allowed-tools: Read, Grep
---

# Plane SOP Skill

## Purpose

Guide consistent Plane work item management via MCP. Plane replaces Linear/Jira as the project management backend — self-hostable or cloud, with 55+ MCP tools for work items, cycles, modules, epics, and intake.

## Setup

### One-command setup

```bash
bash ~/.hermes/scripts/hermes-plane-setup.sh
```

### Per-project Claude Code MCP (recommended)

```bash
# From repo root — creates .mcp.json (commit to git)
claude mcp add --scope project plane \
  --transport http \
  --url https://mcp.plane.so/http/api-key/mcp \
  --header "x-api-key: your_key" \
  --header "x-workspace-slug: your-workspace-slug"
```

Tools appear as `mcp_plane_*` (Hermes) or `mcp__plane__*` (Claude Code).

## When This Skill Applies

Invoke when:
- Creating new work items
- Updating work item status
- Attaching evidence to work items
- Managing cycles (sprints)
- Creating modules
- Triage/intake of new issues
- Searching across projects
- Working with both UUIDs and human-readable IDs (PROJ-42)

## Plane MCP Tools (Key Operations)

### Reading Work Items

```text
# Get work item by human-readable identifier
mcp__plane__get_work_item({ identifier: "9R-459" })

# List work items in a project with filters
mcp__plane__list_work_items({
  project_id: "uuid-of-project",
  state: "In Progress",
  assignee: "me"
})

# Search across workspace
mcp__plane__search_work_items({ query: "authentication" })
```

### Creating Work Items

```text
mcp__plane__create_work_item({
  project_id: "project-uuid",
  name: "feat(scope): description",
  description: "## Summary\n\n...",
  priority: "high",
  assignee: "user-uuid",
  labels: ["feature", "sprint-1"]
})
```

### Updating Work Items

```text
mcp__plane__update_work_item({
  work_item_id: "uuid",
  state: "Done"
})
```

### Adding Comments

```text
mcp__plane__add_work_item_comment({
  work_item_id: "uuid",
  comment: "**Dev Evidence**\n\nPR: https://github.com/...\n..."
})
```

### Managing Cycles (Sprints)

```text
# Create a cycle
mcp__plane__create_cycle({
  project_id: "uuid",
  name: "Sprint 24",
  start_date: "2025-01-13",
  end_date: "2025-01-27"
})

# Add work items to cycle
mcp__plane__add_work_items_to_cycle({
  cycle_id: "uuid",
  work_items: ["uuid-1", "uuid-2"]
})

# Transfer incomplete items between cycles
mcp__plane__transfer_cycle_work_items({
  source_cycle_id: "uuid",
  target_cycle_id: "uuid"
})
```

### Triage / Intake

```text
# List intake items
mcp__plane__list_intake_work_items({ project_id: "uuid" })

# Accept/reject intake
mcp__plane__update_intake_work_item({
  intake_work_item_id: "uuid",
  state: "accepted"
})
```

## Evidence Policy (MUST)

Every work item requires evidence at each phase:

| Phase | Required? | Content |
|-------|-----------|---------|
| **Dev** | MUST | Implementation proof, PR link |
| **Staging** | MUST | UAT validation (or N/A) |
| **Done** | MUST | Final verification, merge commit |

## Evidence Templates

### Dev Evidence Template

```markdown
**Dev Evidence**

**PR**: https://github.com/{{GITHUB_ORG}}/{{PROJECT_REPO}}/pull/XXX
**Commit**: [short-hash]
**Branch**: 9R-XXX-description

**Implementation:**
- [x] Feature implemented
- [x] Tests passing
- [x] Lint passing

**Verification:**
\`\`\`bash
yarn ci:validate
# Output: All checks passed
\`\`\`
```

### Staging/UAT Evidence Template

```markdown
**Staging Evidence**

**Environment**: Pop OS dev server
**URL**: http://pop-os:3000

**Validation Steps:**
1. Deployed to staging: [timestamp]
2. Smoke test passed: [yes/no]
3. Feature verified: [description]

**UAT Status:** [Passed/Pending/N/A]
If N/A, reason: [e.g., "Dev tooling only - no user-facing changes"]
```

### Done Evidence Template

```markdown
**Done Evidence**

**PR Merged**: https://github.com/{{GITHUB_ORG}}/{{PROJECT_REPO}}/pull/XXX
**Merge Commit**: [hash]

**Final Checklist:**
- [x] All acceptance criteria met
- [x] Documentation updated (if applicable)
- [x] No regressions detected
```

## Acceptance Criteria Parsing

When reading work item descriptions, extract ACs:

```markdown
## Acceptance Criteria
- [ ] User can perform action X
- [ ] System responds with Y
- [ ] Error handling for Z
```

Convert to testable checklist:

```typescript
const acceptanceCriteria = [
  { criterion: "User can perform action X", verified: false },
  { criterion: "System responds with Y", verified: false },
  { criterion: "Error handling for Z", verified: false },
];
```

## Status Workflow

```
Backlog → Ready → In Progress → In Review → Done
```

### Plane-GitHub Integration

Work items can be linked to PRs via comments. Use the `[9R-XXX]` prefix in commit messages and PR titles for tracking. After PR merge, update work item status:

```text
mcp__plane__update_work_item({ work_item_id: "uuid", state: "Done" })
mcp__plane__add_work_item_comment({
  work_item_id: "uuid",
  comment: "PR merged: https://github.com/..."  
})
```

### Status Update Guidelines

| From | To | When |
|------|----|------|
| Backlog | Ready | Sprint planning |
| Ready | In Progress | Work starts |
| In Progress | In Review | PR created |
| In Review | Done | PR merged, evidence posted |

## UUID Handling

Plane uses TWO identifier types:

```typescript
// Human-readable (for users, URLs, communication)
const identifier = "9R-459";

// UUID (for API operations)
const uuid = "3fa85f64-5717-4562-b3fc-2c963f66afa6";

// Get UUID from human-readable identifier
// mcp__plane__get_work_item({ identifier: "9R-459" })
// Returns work item with .id property containing UUID
```

## Common Operations

### Link PR to Work Item

Post a comment on the work item with the PR link:

```text
mcp__plane__add_work_item_comment({
  work_item_id: "uuid",
  comment: "PR: https://github.com/{{GITHUB_ORG}}/{{PROJECT_REPO}}/pull/123"
})
```

### Create Sub-Issue

Plane doesn't have explicit sub-issues, but you can link work items:

```text
mcp__plane__add_work_item_link({
  work_item_id: "parent-uuid",
  link_id: "child-uuid",
  relation: "blocks"
})
```

### Query by Label

```text
mcp__plane__list_work_items({
  project_id: "uuid",
  labels: ["sprint-1"]
})
```

### Get Project Overview

```text
mcp__plane__retrieve_project({ project_id: "uuid" })
mcp__plane__list_cycles({ project_id: "uuid" })
mcp__plane__get_project_members({ project_id: "uuid" })
```

## Authoritative References

- **Plane MCP Docs**: https://developers.plane.so/dev-tools/mcp-server
- **Hermes Plane Setup**: `bash ~/.hermes/scripts/hermes-plane-setup.sh`
- **Hermes Skill**: `plane-project-management` (full setup + architecture docs)
- **Agent Workflow SOP**: `docs/sop/AGENT_WORKFLOW_SOP.md`
- **CONTRIBUTING.md**: Workflow documentation
