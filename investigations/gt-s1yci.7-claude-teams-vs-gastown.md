# Research: Claude Opus 4.6 Agent Teams vs Gastown Orchestration
**Bead:** gt-s1yci.7 | **Date:** 2026-02-06 | **Status:** Complete

## Executive Summary

Claude Opus 4.6 introduces built-in multi-agent team orchestration within Claude Code sessions. After deep research, the key finding is: **Claude Teams are intra-session orchestration; Gastown is inter-session orchestration. They are complementary, not competing.**

Claude Teams could simplify our code review gate architecture (gt-s1yci.6 legs 3-7) by providing native spawning, messaging, and plan approval gates within a session, while Gastown continues to handle persistence, cross-machine coordination, and session lifecycle.

## What Claude Agent Teams Are

### Core Components
1. **TeamCreate** - Creates a team with shared task list at `~/.claude/teams/{name}/`
2. **Team Lead** - The session that creates and manages the team
3. **Teammates** - Independent Claude Code instances with isolated context windows
4. **Shared Task List** - `~/.claude/tasks/{name}/` with pending/in_progress/completed + blockedBy deps
5. **SendMessage** - Direct peer-to-peer messaging (unicast + broadcast)

### How It Works
- Lead spawns teammates via Task tool with `team_name` parameter
- Teammates get fresh context (project CLAUDE.md, MCP servers, skills) but NOT lead's conversation history
- Teammates self-claim tasks from shared list or get assigned by lead
- Plan approval gates: teammates propose plans, lead approves/rejects before implementation
- Automatic idle notifications when teammates finish turns
- Shutdown protocol: lead requests, teammate approves/rejects

### Agent Types Available
- `general-purpose` - Full tools including file editing, writing, bash
- `Explore` - Read-only, fast codebase exploration
- `Plan` - Read-only, architecture and planning
- `Bash` - Command execution specialist
- Custom agents from `.claude/agents/`

### Proven Scale
- 16 agents built 100K-line C compiler (~2000 sessions, ~$20K total cost)
- Opus 4.6 autonomously managed ~50-person org across 6 repos
- Parallel code review pattern: 3+ reviewers examine different aspects simultaneously

## Critical Limitations

| Limitation | Impact on Gastown |
|---|---|
| **Session-scoped only** - teams die on crash/restart | Gastown MUST handle persistence |
| **No nested teams** - 2-level hierarchy max | Can't have refinery spawn team leads who spawn sub-teams |
| **File write conflicts** - concurrent edits silently overwrite | Must partition file ownership |
| **One team per session** | Each Gastown role can run one team at a time |
| **Fixed leadership** - can't transfer lead | Lead session must stay alive |
| **Shared filesystem required** | No cross-machine teams (Gastown handles this) |
| **~7x token cost** vs single session | Cost-effective only for genuinely parallel work |
| **Task status can lag** | Need verification layer |

## Gastown vs Claude Teams: Detailed Comparison

| Capability | Gastown | Claude Teams |
|---|---|---|
| Agent spawning | `gt sling` (tmux-based, durable) | TeamCreate + Task tool (in-process, ephemeral) |
| Work assignment | Molecules + hooks + formulas | Shared task list + self-claiming |
| Communication | `gt mail` (persistent, cross-session) | SendMessage (session-scoped) |
| Persistence | Beads in git, survives everything | Session-scoped, lost on crash |
| Cross-machine | Yes (git sync + SSH) | No (shared filesystem only) |
| Process lifecycle | tmux sessions, watchdog, restart | In-process, dies with lead |
| Task tracking | Beads (JSONL in git, forever) | TaskList (ephemeral, session only) |
| Orchestration | Mayor/Refinery/Formulas (persistent) | Team Lead (session-scoped) |
| Review gates | Proposed (gt-s1yci.6) | Plan approval built-in |
| Code review | Formula-based (manual trigger) | Competing agents pattern (native) |
| Cost model | tmux sessions (cheap) | Token-based (~7x multiplier) |

## Impact on Architecture (gt-s1yci.6)

### Legs That Could Be Simplified

**Legs 3-7 are the review/revision cycle.** Claude Teams has native primitives for most of this:

- **Leg 3 (Refinery Review Gate):** Instead of building custom gate logic in Go, the Refinery could become a Team Lead, spawn a reviewer teammate, and use the plan approval response as the gate decision.

- **Leg 4 (Reviewer Polecat Spawning):** Team Lead spawns reviewer as teammate with `subagent_type: "general-purpose"`. No custom spawning code needed.

- **Leg 5 (Gate Decision Logic):** Plan approval response IS the gate. Lead examines review findings, approves (merge) or rejects (needs revision) with feedback.

- **Leg 6 (Revision Polecat Spawning):** On rejection, Lead spawns reviser teammate with the review feedback in the spawn prompt.

- **Leg 7 (Escalation):** Lead counts cycles. After 3 rejections, sends message to human instead of spawning another teammate.

**Potential reduction: 5 legs → 1-2 legs** (one for "Refinery as Team Lead" wrapper, one for cycle counting/escalation).

### Legs That Stay the Same

- **Leg 1 (MR Schema):** Still need review_status/review_cycle fields in beads for persistence
- **Leg 2 (Review Findings):** Still need finding beads - Claude TaskList is ephemeral, findings must persist in git
- **Leg 8 (Feature Branch):** Branch targeting is git-level, independent of orchestration
- **Leg 9 (Code Review Formula):** Still need the formula, but it becomes the teammate's task prompt
- **Leg 10 (Human UAT):** Still need human gate for feature→main

### Revised Architecture Sketch

```
CURRENT PLAN (10 legs, custom everything):
  Refinery → custom gate → custom spawn → custom review → custom decision → custom revision → custom escalation

REVISED PLAN (leveraging Claude Teams):
  Refinery enters Team Lead mode
    → TeamCreate("review-{mr-id}")
    → Spawn reviewer teammate (runs code review formula as task)
    → Reviewer files findings as beads (persistent)
    → Lead examines findings, makes gate decision (plan approval pattern)
    → If P0/P1: spawn reviser teammate with feedback
    → Track cycle count in MR bead fields
    → After 3 cycles: escalate to human via gt mail
    → If clean: merge to feature branch
    → TeamDelete (cleanup)
  Beads record everything for posterity
```

## Open Questions

1. **Can a Gastown polecat session become a Team Lead?** Polecats are tmux-based Claude Code sessions. In theory, any Claude Code session can use TeamCreate. Need to verify this works with Gastown's tmux management.

2. **Token cost impact:** If every MR triggers a team (lead + reviewer + maybe reviser), that's 2-3x sessions per MR. At ~7x token cost per teammate, this could get expensive. Need cost modeling.

3. **Race conditions:** If Refinery is running as a Team Lead for one MR, can it handle another MR simultaneously? (One team per session limitation.)

4. **Failure recovery:** If the Refinery session crashes mid-review, the Claude Team dies. Gastown's molecule/hook system would need to detect this and restart the review cycle.

5. **Plan approval vs custom gate:** The plan approval pattern assumes the Lead reads code and decides. Can we make it examine bead-recorded findings instead? Or does the reviewer teammate just message the lead with a summary?

## Recommendation

**Keep the hybrid architecture, but swap the implementation mechanism for legs 3-7.**

Instead of building custom Go code for spawning/gating/messaging:
1. Refinery patrol detects pending MRs (existing behavior, Leg 3 simplified)
2. Refinery becomes Team Lead, spawns reviewer teammate (replaces Legs 4)
3. Reviewer runs code review, files findings as beads (Leg 9, existing formula)
4. Lead examines findings, makes gate decision (replaces Leg 5)
5. If blocked: spawn reviser teammate with feedback (replaces Leg 6)
6. Count cycles in MR bead, escalate after 3 (replaces Leg 7)
7. Beads persist everything, gt mail for cross-session comms (unchanged)

**Net effect:** Reduce custom Go implementation by ~60%. Leverage Claude's native team primitives. Keep Gastown for what it's good at: persistence, cross-session coordination, process lifecycle.

## Next Steps

1. Kyle reviews this analysis and decides whether to revise the architecture
2. If yes: create revised leg beads (probably 5-6 legs instead of 10)
3. Prototype: have a Refinery session use TeamCreate manually to validate the pattern
4. Cost modeling: estimate token cost per MR review cycle

## Sources
- https://code.claude.com/docs/en/agent-teams
- https://www.anthropic.com/news/claude-opus-4-6
- https://www.anthropic.com/engineering/building-c-compiler
- https://claudefa.st/blog/guide/agents/agent-teams
