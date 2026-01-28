---
name: gastown
description: >
  Multi-agent orchestration system for coordinating Claude Code instances across projects.
  Use when working in a Gas Town environment, managing polecats/crew, using gt/bd commands,
  understanding convoys, molecules, or the propulsion principle.
allowed-tools: "Bash(gt:*),Bash(bd:*)"
version: "1.0.0"
author: "Gas Town"
license: "MIT"
---

# Gas Town - Multi-Agent Orchestration for Claude Code

Gas Town coordinates multiple Claude Code instances across projects using `gt` (agent operations) and `bd` (beads/data operations).

## Core Principles

| Principle | Meaning |
|-----------|---------|
| **GUPP** | "If there is work on your Hook, YOU MUST RUN IT." No waiting for confirmation. |
| **MEOW** | Break large goals into atomic, trackable units (beads/molecules). |
| **NDI** | Eventual completion despite unreliable individual operations. |

**The Hook Contract**: When you find work on your hook, EXECUTE IMMEDIATELY. The hook IS your assignment.

## Quick Orientation

```bash
gt hook              # What's on my hook?
bd mol current       # Where am I in the molecule?
bd ready             # What step is next?
bd show <step-id>    # What does this step require?
```

## The Propulsion Loop

```
1. gt hook                    # What's hooked?
2. bd mol current             # Where am I?
3. Execute step
4. bd close <step> --continue # Close and auto-advance
5. GOTO 2
```

## Role Quick Reference

| Role | Purpose | Lifecycle |
|------|---------|-----------|
| **Mayor** | Town coordinator, initiates convoys | Persistent, town-level |
| **Deacon** | Background supervisor, health checks | Persistent, daemon |
| **Witness** | Monitors polecats per rig | Persistent, per-rig |
| **Refinery** | Merge queue processor | Persistent, per-rig |
| **Polecat** | Ephemeral worker with worktree | Transient, Witness-managed |
| **Crew** | Persistent human workspace | Long-lived, user-managed |

See [references/roles.md](references/roles.md) for detailed role documentation.

## Essential Commands

### Agent Operations (gt)

```bash
gt hook                      # What's on my hook
gt convoy list               # Active work batches
gt convoy create "name" <ids> # Create work batch
gt sling <bead> <rig>        # Assign work to agent
gt handoff                   # Session cycling
gt mail inbox                # Check messages
gt escalate "topic"          # Escalate issue
```

### Beads Operations (bd)

```bash
bd ready                     # Unblocked work
bd show <id>                 # Issue details
bd create --title="..."      # Create issue
bd update <id> --status=...  # Update status
bd close <id> --continue     # Close and advance
bd sync                      # Push/pull to git
```

See [references/commands.md](references/commands.md) for full CLI reference.

## Work Units

| Type | Persistence | Purpose |
|------|-------------|---------|
| **Bead** | Git-backed | Atomic work unit (issue/task) |
| **Formula** | TOML source | Reusable workflow template |
| **Molecule** | Persistent | Multi-step workflow instance |
| **Wisp** | Ephemeral | Lightweight transient work |
| **Hook** | Pinned | Agent's primary work queue |
| **Convoy** | Tracking | Batch of related beads |

See [references/molecules.md](references/molecules.md) for workflow details.

## Directory Structure

```
~/gt/                           Town root
├── .beads/                     Town-level beads (hq-* prefix)
├── mayor/                      Mayor agent home
├── deacon/                     Deacon daemon home
└── <rig>/                      Project container (NOT a clone)
    ├── .repo.git/              Bare repo (shared by worktrees)
    ├── mayor/rig/              Canonical clone (beads live here)
    ├── refinery/rig/           Worktree on main
    ├── witness/                Monitor (no clone)
    ├── crew/<name>/rig/        Human workspaces
    └── polecats/<name>/rig/    Worker worktrees
```

## Startup Behavior

1. Check hook (`gt hook`)
2. Work hooked -> EXECUTE immediately
3. Hook empty -> Check mail for attached work
4. Nothing anywhere -> ERROR: escalate to Witness

## Session Cycling

When context fills or you finish a chunk:

```bash
/handoff                    # Or gt handoff
```

**What persists**: Hooked molecule, beads state, git state
**What resets**: Conversation context, TodoWrite items, in-memory state

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `GT_ROLE` | Agent role (mayor, witness, polecat, crew) |
| `GT_ROOT` | Town root directory |
| `GT_RIG` | Current rig name |
| `BD_ACTOR` | Agent identity for attribution |

## Resources

| Resource | Content |
|----------|---------|
| [roles.md](references/roles.md) | Detailed role documentation |
| [convoys.md](references/convoys.md) | Work tracking and assignment |
| [molecules.md](references/molecules.md) | Formulas and workflow lifecycle |
| [propulsion.md](references/propulsion.md) | The propulsion principle deep dive |
| [commands.md](references/commands.md) | Full CLI reference |

## Full Documentation

- **gt --help**: Command overview
- **bd prime**: AI-optimized workflow context
- **GitHub**: [github.com/steveyegge/gastown](https://github.com/steveyegge/gastown)
