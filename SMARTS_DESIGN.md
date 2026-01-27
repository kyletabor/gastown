# Adding Smarts to Gastown: Design Document

> Research findings and implementation proposal for adding review loops,
> quality gates, and revision limits to Gastown.

## Executive Summary

Gastown already has significant infrastructure for "smarts" that Kyle may not be aware of. The key gap is **not** the primitives (formulas, gates, validation) but their **integration and activation**. This document proposes leveraging existing infrastructure with targeted enhancements.

---

## Current Infrastructure (Already Exists!)

### 1. Formula System (`internal/formula/`)

Gastown already has sophisticated workflow templates:

| Formula | Type | Purpose |
|---------|------|---------|
| `shiny.formula.toml` | workflow | design → implement → review → test → submit |
| `shiny-enterprise.formula.toml` | workflow | extends shiny with rule-of-five refinements |
| `code-review.formula.toml` | convoy | 10-leg parallel review (correctness, security, performance, etc.) |
| `rule-of-five.formula.toml` | expansion | 4-5 iterative refinement passes |

**Key insight**: The `shiny` formula IS Kyle's `/prd-jam → /eng-spec → /execute` pattern!
- `design` step = `/prd-jam` + `/eng-spec`
- `implement` step = `/execute`
- `review` step = revision check
- `test` step = validation
- `submit` step = `gt done`

### 2. Gate System (`internal/cmd/gate.go`)

Gates enable async coordination between workflow steps:

```bash
bd gate create --type=timer --duration=1h     # Timer gate
bd gate create --type=gh:run --ref=main       # GitHub Actions gate
bd gate create --type=human --approver=kyle   # Human approval gate
bd gate create --type=mail --waiting=agent    # Mail notification gate
```

**Features**:
- Waiter registration (agents wait for gate)
- Wake notifications (`gt gate wake`)
- Integration with Deacon patrol

### 3. Refinery Validation (`internal/refinery/engineer.go`)

The merge queue already supports:
- Conflict detection and resolution workflow
- Test execution (`RunTests` + `TestCommand` in config)
- Retry for flaky tests (`RetryFlakyTests`)
- Branch cleanup

**Configuration** in `<rig>/config.json`:
```json
{
  "merge_queue": {
    "enabled": true,
    "run_tests": true,
    "test_command": "make test",
    "retry_flaky_tests": 2
  }
}
```

### 4. Pre-Submission Validation (`internal/cmd/done.go`)

`gt done` already validates before MR submission:
- ✅ Uncommitted changes check
- ✅ Branch pushed to origin
- ✅ Work exists (commits ahead of main)
- ✅ Role guard (polecats only)

---

## What's Missing (The Gaps)

### Gap 1: No Automated Review Loop Before Submit

The `review` step in `shiny.formula.toml` is just instructions - it doesn't actually run the `code-review` convoy.

**Fix**: Connect `review` step to actually execute `code-review.formula.toml` (gate preset).

### Gap 2: No Revision Limits with Escalation

Kyle's claude-life-dev has "max 3 revisions before escalation". Gastown has no such mechanism.

**Fix**: Add revision tracking to MR beads, gate after N cycles, auto-escalate.

### Gap 3: Quality Checks Are Optional and External

Tests run only if configured. No lint, type check, security scan integration.

**Fix**: Create `gt validate` command with pluggable checks, integrate into `gt done`.

### Gap 4: No Human-in-the-Loop for Critical Work

Polecats run autonomously. No approval gates for high-risk changes.

**Fix**: Use existing `human` gate type, add to enterprise workflow formulas.

---

## Design Proposal

### Phase 1: Pre-Submission Validation Framework

**New command**: `gt validate`

```bash
gt validate                    # Run all configured validators
gt validate --check=lint       # Run specific check
gt validate --list             # List available validators
```

**Validators** (pluggable via rig config):
- `lint` - Run linter (golangci-lint, eslint, etc.)
- `typecheck` - Run type checker
- `test` - Run test suite
- `coverage` - Check test coverage threshold
- `security` - Run security scanner (gosec, npm audit, etc.)
- `size` - Check PR size limits

**Config** (`<rig>/config.json`):
```json
{
  "validators": {
    "lint": {
      "command": "golangci-lint run",
      "required": true
    },
    "test": {
      "command": "go test ./...",
      "required": true
    },
    "coverage": {
      "command": "go test -coverprofile=c.out && go tool cover -func=c.out",
      "threshold": 80,
      "required": false
    }
  }
}
```

**Integration with `gt done`**:
```go
// In runDone(), before MR creation:
if err := runValidators(cwd); err != nil {
    return fmt.Errorf("validation failed: %w\n\nFix issues and retry, or use --skip-validate to bypass")
}
```

### Phase 2: Review Gate Integration

**Enhanced `shiny-review.formula.toml`**:
```toml
formula = "shiny-review"
type = "workflow"
extends = ["shiny"]

# Override review step to run actual code review
[[steps]]
id = "review"
title = "Automated Code Review"
needs = ["implement"]
description = """
Run the code-review convoy (gate preset) on your changes.
This produces a review summary at .reviews/<review-id>/review-summary.md

Steps:
1. Create review: gt formula run code-review --preset=gate --files="$(git diff --name-only main)"
2. Wait for review completion
3. Address any P0/P1 issues before proceeding
4. If issues found, return to 'implement' step
"""

[[steps]]
id = "review-gate"
title = "Review Approval Gate"
needs = ["review"]
gate = { type = "human", approver = "self" }
description = """
Confirm you've addressed review findings.
Close this gate when ready to proceed to testing.
"""
```

### Phase 3: Revision Limits with Escalation

**MR Bead Enhancement**:
```
# In MR description (already tracked):
retry_count: 0
last_conflict_sha: null
conflict_task_id: null

# New fields:
revision_count: 0
max_revisions: 3
escalated_at: null
escalated_to: null
```

**Refinery Logic** (`engineer.go`):
```go
func (e *Engineer) HandleMRInfoFailure(mr *MRInfo, result ProcessResult) {
    // Increment revision count
    mr.RevisionCount++

    // Check escalation threshold
    if mr.RevisionCount >= mr.MaxRevisions {
        // Create escalation
        e.escalateToHuman(mr, fmt.Sprintf(
            "MR has been revised %d times. Review needed.",
            mr.RevisionCount))
        return
    }

    // Normal failure handling...
}
```

### Phase 4: Enterprise Workflow Template

**`shiny-enterprise-reviewed.formula.toml`**:
```toml
description = "Full enterprise workflow with automated review and human gates"
formula = "shiny-enterprise-reviewed"
type = "workflow"
version = 1
extends = ["shiny"]

# Expand implement with rule-of-five
[compose]
[[compose.expand]]
target = "implement"
with = "rule-of-five"

# Add review convoy after implementation
[[steps]]
id = "code-review"
title = "Automated Code Review"
needs = ["implement.refine-4"]  # After rule-of-five completion
convoy = "code-review"
preset = "gate"

# Add human gate for review approval
[[steps]]
id = "review-approval"
title = "Review Approval"
needs = ["code-review"]
gate = { type = "human" }

# Test after review approved
[[steps]]
id = "test"
title = "Test {{feature}}"
needs = ["review-approval"]

# Final submit
[[steps]]
id = "submit"
title = "Submit for merge"
needs = ["test"]
```

---

## Integration Points Summary

| Hook Point | File | Purpose |
|------------|------|---------|
| Pre-MR validation | `cmd/done.go` | Run `gt validate` before MR creation |
| Molecule step | `formula/` | Connect review step to code-review convoy |
| MR bead metadata | `beads.MRFields` | Track revision count |
| Refinery failure | `refinery/engineer.go` | Check revision limit, escalate |
| Gate system | `cmd/gate.go` | Human approval for review findings |

---

## Kyle's claude-life-dev Mapping

| Kyle's Process | Gastown Equivalent |
|----------------|-------------------|
| `/prd-jam` | Formula `design` step with human gate |
| `/eng-spec` | Formula `design` step output (design doc) |
| `/execute` | Formula `implement` step (with rule-of-five) |
| Memory MCP | Beads (persistent state) + hooks (session context) |
| Triple redundancy | Beads + role templates + git |
| PR Review Cycle | `code-review` convoy + revision limits |
| Max 3 revisions | `max_revisions` field + escalation logic |

---

## Recommended Next Steps

1. **Quick Win**: Configure `test_command` in gastown's rig config to enable test validation in Refinery

2. **Phase 1** (1-2 days): Implement `gt validate` command with pluggable validators

3. **Phase 2** (1 day): Create `shiny-review.formula.toml` that integrates code-review convoy

4. **Phase 3** (1 day): Add revision tracking to MR beads, escalation in Refinery

5. **Phase 4** (1 day): Create comprehensive enterprise template combining all features

---

## Files to Modify

| File | Changes |
|------|---------|
| `internal/cmd/validate.go` | New command (create) |
| `internal/cmd/done.go` | Add validation gate |
| `internal/refinery/engineer.go` | Add revision tracking + escalation |
| `internal/formula/formulas/shiny-review.formula.toml` | New formula (create) |
| `internal/beads/types.go` | Add revision fields to MRFields |

---

## Open Questions for Kyle

1. **Validation strictness**: Should validators block `gt done` by default, or warn-only?

2. **Escalation target**: When revision limit hit, escalate to human, Mayor, or specific agent?

3. **Review coverage**: Should `gate` preset (4 legs) be default, or `full` preset (10 legs)?

4. **Human gates**: Where in the workflow should human approval be required?
   - After design?
   - After review findings?
   - Before merge?
   - All of the above?

5. **Formula activation**: Should `shiny-review` be the default for `gt sling`, or opt-in?
