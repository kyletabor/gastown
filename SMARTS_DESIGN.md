# Adding Smarts to Gastown: Design Document v2

> Updated after feedback: Focus on discoverability, custom formulas, and
> what can be fixed via formulas alone vs Go code changes.

---

## Problem Statement

Kyle has identified several issues:

1. **No enforcement** - Formulas exist but agents don't automatically use them
2. **Not discoverable** - Unclear how to tell Mayor to use formulas
3. **Custom formula location** - Where to store private formulas without polluting gastown repo?
4. **Revision loops needed at EVERY stage** - Not just PR review, but design review, spec review, etc.
5. **Validation at every step** - "If step says create a file, validate it created the file"

---

## Formula Search Paths (Where Custom Formulas Go)

Formulas are discovered from these paths **in order**:

```
1. .beads/formulas/           # Project-level (current rig's worktree)
2. ~/.beads/formulas/         # User-level (private custom formulas)
3. $GT_ROOT/.beads/formulas/  # Town-level (shared across all rigs)
```

**For Kyle's private formulas:** Use `~/.beads/formulas/` or `/home/orangepi/gt/.beads/formulas/`

Current formula locations:
| Location | Count | Purpose |
|----------|-------|---------|
| `/home/orangepi/gt/.beads/formulas/` | 35 | Town-level shared formulas |
| `/home/orangepi/gt/gastown/refinery/rig/.beads/formulas/` | 32 | Gastown rig formulas (synced from internal/) |
| `/home/orangepi/gt/gastown/refinery/rig/internal/formula/formulas/` | 32 | Source formulas (compiled into Go) |

**Custom formula workflow:**
```bash
# Create custom formula in user directory
gt formula create my-workflow          # Creates in .beads/formulas/ (project)

# Or manually create in user-level (private, not in any repo):
touch ~/.beads/formulas/kyle-review.formula.toml

# List all formulas (shows search path order)
bd formula list
```

---

## Available Formulas (32 total)

### Workflow Formulas (Sequential Steps)
| Formula | Description | Vars |
|---------|-------------|------|
| `shiny` | Engineer in a Box: design → implement → review → test → submit | feature, assignee |
| `shiny-enterprise` | Shiny + rule-of-five expansion on implement | - |
| `shiny-secure` | Shiny + security-audit aspect | - |
| `beads-release` | Release workflow for beads | version |
| `gastown-release` | Release workflow for gastown | version |
| `mol-polecat-work` | Full polecat lifecycle from assignment to completion | issue |

### Convoy Formulas (Parallel Legs)
| Formula | Description | Legs |
|---------|-------------|------|
| `code-review` | Parallel code review (10 legs) | correctness, performance, security, elegance, resilience, style, smells, wiring, commit-discipline, test-quality |
| `design` | Parallel design exploration (6 legs) | api, data, ux, scale, security, integration |

### Expansion Formulas (Step Templates)
| Formula | Description |
|---------|-------------|
| `rule-of-five` | 4-5 iterative refinements: draft → correctness → clarity → edge cases → excellence |

### Aspect Formulas (Cross-cutting Concerns)
| Formula | Description |
|---------|-------------|
| `security-audit` | Security scanning aspect applied to workflows |

### Molecule Formulas (Daemon Patrols)
| Formula | Purpose |
|---------|---------|
| `mol-deacon-patrol` | Mayor's daemon patrol loop |
| `mol-witness-patrol` | Per-rig worker monitor |
| `mol-refinery-patrol` | Merge queue processor patrol |
| `mol-polecat-code-review` | Code review for polecats |
| `mol-polecat-conflict-resolve` | Conflict resolution workflow |
| `mol-polecat-review-pr` | PR review workflow |

---

## Mapping: Kyle's claude-life-dev → Gastown Formulas

| Kyle's Command | Gastown Equivalent | Gap |
|----------------|-------------------|-----|
| `/prd-jam` | `design` convoy (parallel exploration) | PRD format not in formula |
| `/eng-spec` | `shiny.design` step + worktree setup | Worktree creation not in formula |
| `/execute` | `shiny.implement` + `rule-of-five` | Ralph loop not in formula |
| PR Review | `code-review` convoy | ✅ Already exists |
| PR Revision | `mol-polecat-review-pr` | Revision limits not enforced |

### Behavioral Instructions to Extract into Formulas

From Kyle's commands, these behavioral patterns need formula representation:

**1. Investigate-First Principle** (from prd-jam)
```toml
# Before asking questions, explore the codebase
# If you can investigate, do it. Don't ask for permission.
```

**2. Role Division** (from eng-spec)
```toml
# Claude handles: architecture, patterns, file structure, tests
# PM handles: user impact, UX decisions, priority trade-offs
# Rule: Never ask the user a technical question. Make the decision.
```

**3. Quality Gates** (from execute)
```toml
# PRD is ready when:
# - Problem is clear (from your investigation)
# - Scope has boundaries
# - Requirements have acceptance criteria

# PRD is NOT ready if:
# - You haven't looked at the codebase
# - You asked more than 2-3 questions
```

**4. Validation Protocol** (from execute)
```toml
# HARD FAIL: Cannot execute on main/master branch
# HARD FAIL: Must be in a worktree (not the main checkout)
# Check plan exists: SPEC.md, TODO.md, PROMPT.md
```

---

## Gap Analysis: What Can Be Fixed via Formulas vs Go Code

### ✅ Can Be Fixed with Formulas Alone

| Issue | Formula Solution |
|-------|------------------|
| Design review before implement | Add `design-review` step with human gate after `design` |
| Spec review before implement | Add `spec-review` step that runs parallel review |
| Code review before submit | Already exists: `code-review` convoy |
| Security audit on sensitive code | Already exists: `shiny-secure` |
| Rule-of-five refinement | Already exists: `shiny-enterprise` |

**Example: Design Review Formula**
```toml
# kyle-design-review.formula.toml
formula = "kyle-design-review"
type = "workflow"
extends = ["shiny"]

[[steps]]
id = "design"
title = "Create design spec"
description = "Create engineering specification"

[[steps]]
id = "design-review"
title = "Review design with second agent"
needs = ["design"]
gate = { type = "human" }  # Or spawn a review convoy
description = """
Before implementing, have another agent review the design.
Run: gt formula run code-review --preset=gate --files=<spec-files>
Review findings. Address P0/P1 issues before proceeding.
"""

[[steps]]
id = "implement"
title = "Implement (with rule-of-five)"
needs = ["design-review"]
# ... rest of shiny steps
```

### ❌ Cannot Be Fixed with Formulas - Needs Go Code

| Issue | Why Formulas Can't Fix | Go Change Needed |
|-------|------------------------|------------------|
| **Discoverability**: How to tell Mayor to use formulas | No command to set default formula | Add `gt config set default-formula <name>` |
| **Enforcement**: Polecats don't auto-use formulas | Witness dispatches without formula | Witness assigns formula with issue |
| **Validation at every step**: "Check file was created" | No step validator in formula spec | Add `[steps.validate]` section to formula schema |
| **Revision limits**: Max 3 revisions then escalate | No revision counter in MR processing | Add `revision_count` tracking + escalation in Refinery |
| **Pre-submit validation**: Tests/lint before `gt done` | `gt done` has no validation hooks | Add `gt validate` command + hook in `done.go` |

---

## What Needs to Change in Go Code

### 1. Formula Enforcement (Witness Integration)

**File**: `internal/cmd/sling.go` or `internal/protocol/witness.go`

When Witness dispatches work:
```go
// Current: Just slings the issue
gt sling <issue> <polecat>

// Needed: Sling with formula
gt sling <issue> <polecat> --formula shiny
// Or: Check rig config for default formula
```

### 2. Step Validation (Formula Schema Extension)

**File**: `internal/formula/types.go`

Add validation section to steps:
```toml
[[steps]]
id = "implement"
title = "Implement feature"
[steps.validate]
files_created = ["src/new-feature.ts"]
files_modified = ["src/index.ts"]
command = "go build ./..."
exit_on_fail = true
escalate_to = "witness"
```

### 3. Revision Limits (Refinery Enhancement)

**File**: `internal/refinery/engineer.go`

```go
type MRInfo struct {
    // ... existing fields
    RevisionCount  int    // Track revisions
    MaxRevisions   int    // Default: 3
    EscalatedAt    *time.Time
    EscalatedTo    string
}

func (e *Engineer) HandleMRInfoFailure(mr *MRInfo, result ProcessResult) {
    mr.RevisionCount++
    if mr.RevisionCount >= mr.MaxRevisions {
        e.escalateToHuman(mr, "Max revisions exceeded")
        return
    }
    // ... normal failure handling
}
```

### 4. Pre-Submit Validation (`gt validate`)

**File**: `internal/cmd/validate.go` (new) + `internal/cmd/done.go`

```go
// gt validate --check=lint --check=test
func runValidate(checks []string) error {
    for _, check := range checks {
        if err := runCheck(check); err != nil {
            return fmt.Errorf("%s failed: %w", check, err)
        }
    }
    return nil
}

// In done.go:
func runDone() error {
    // Run validation before MR creation
    if err := runValidate(rigConfig.RequiredChecks); err != nil {
        return fmt.Errorf("validation failed: %w\n\nRun `gt validate` to see details")
    }
    // ... proceed with MR creation
}
```

### 5. Default Formula Config

**File**: `internal/rig/config.go`

```go
type RigConfig struct {
    // ... existing fields
    DefaultFormula string `json:"default_formula"` // e.g., "shiny"
    RequiredChecks []string `json:"required_checks"` // e.g., ["lint", "test"]
}
```

---

## Recommended Action Plan

### Phase 1: Formula-Only Improvements (No Go Changes)

1. **Create custom formulas** in `~/.beads/formulas/`:
   - `kyle-prd-jam.formula.toml` - PRD creation workflow
   - `kyle-eng-spec.formula.toml` - Engineering spec + review
   - `kyle-execute.formula.toml` - Implementation + Ralph loop

2. **Document the workflow**:
   ```bash
   # Example: Run a formula-driven workflow
   gt formula run shiny --var feature="Add notification system" gastown
   ```

### Phase 2: Discoverability Fixes (Go Changes)

1. Add `gt config set default-formula <name>` command
2. Update Witness to check default formula when dispatching
3. Add `gt formula --help` improvements showing workflow examples

### Phase 3: Validation Infrastructure (Go Changes)

1. Add `[steps.validate]` to formula schema
2. Implement step validator in formula runner
3. Add `gt validate` command with pluggable checks
4. Integrate validation into `gt done`

### Phase 4: Revision Limits (Go Changes)

1. Add `revision_count` to MR beads
2. Track revisions in Refinery failure handling
3. Implement escalation logic (mail human, spawn senior agent)

---

## Open Questions

1. **Where should default formula be configured?**
   - Per-rig in `config.json`?
   - Per-user in `~/.beads/config.yaml`?
   - Per-issue via labels?

2. **What triggers formula usage?**
   - `gt sling --formula <name>` (explicit)
   - Auto-detect from issue type/labels (implicit)
   - Always use rig default (enforced)

3. **Step validation failure actions:**
   - Stop work entirely?
   - Mail Witness and wait?
   - Create a sub-task and block?

4. **Revision escalation targets:**
   - Human (Kyle)
   - Mayor
   - Senior polecat (if such concept exists)
   - External system (GitHub issue, etc.)
