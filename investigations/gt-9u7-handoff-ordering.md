# Investigation: gt handoff mail ordering bug

**Issue**: gt-9u7
**Date**: 2026-02-01
**Investigator**: gastown/polecats/nux

## Summary

Investigation into why `gt handoff` allegedly kills the session before sending handoff mail.

**Key Finding**: The bug report describes expected behavior. Mail is only sent when explicitly requested via flags (`-s`, `-m`, or `-c`). The code order IS correct: mail is sent BEFORE kill. However, there IS a code inconsistency that should be fixed.

## Root Cause Analysis

### Primary Finding: Mail is Conditional (Not a Bug)

The code at `internal/cmd/handoff.go:177-185`:

```go
// Lines 175-185: Mail is ONLY sent if subject or message is provided
if handoffSubject != "" || handoffMessage != "" {
    beadID, err := sendHandoffMail(handoffSubject, handoffMessage)
    if err != nil {
        style.PrintWarning("could not send handoff mail: %v", err)
        // Continue anyway - the respawn is more important
    } else {
        fmt.Printf("... Sent handoff mail %s (auto-hooked)\n", beadID)
    }
}
```

**When no flags are used** (`gt handoff` alone):
- `handoffSubject = ""` (default)
- `handoffMessage = ""` (default)
- `handoffCollect = false` (default)

Result: The condition `handoffSubject != "" || handoffMessage != ""` is FALSE, so **no mail is sent by design**.

### Code Order is Correct

Tracing `runHandoff()` execution:

| Line | Operation | Notes |
|------|-----------|-------|
| 152 | Print "Handing off..." | User sees this |
| 154-163 | Log handoff event | File I/O |
| 165-173 | DRY RUN check | Returns early if `--dry-run` |
| **175-185** | **Send mail** | **ONLY if subject/message provided** |
| 191-195 | Clear history | tmux command |
| 197-205 | Write handoff marker | File I/O |
| **207-213** | **Kill pane processes** | **AFTER mail** |
| 216 | RespawnPane | Final step |

**The order is: mail → kill → respawn** (correct)

### Secondary Finding: Code Inconsistency in KillPaneProcessesExcluding

`internal/tmux/tmux.go:456-528` uses `exec.Command("kill", ...)` while other kill functions use `syscall.Kill()`:

```go
// KillPaneProcessesExcluding uses exec.Command (INCONSISTENT)
for _, dpid := range killList {
    _ = exec.Command("kill", "-TERM", dpid).Run()  // Line 507
}
...
for _, dpid := range killList {
    _ = exec.Command("kill", "-KILL", dpid).Run()  // Line 515
}
```

Compare with `KillPaneProcesses` at lines 426-444 which correctly uses:

```go
_ = killPID(dpid, syscall.SIGTERM)  // Uses syscall.Kill
_ = killPID(dpid, syscall.SIGKILL)
```

**Root cause**: Commit `6218177f` added `KillPaneProcessesExcluding` but used `exec.Command` pattern, while commit `0c0a22cf` (which came chronologically first but on a different branch) converted other functions to use `syscall.Kill`.

**Impact**: While Phase 1 investigation concluded that exec.Command vs syscall.Kill doesn't cause the timeout issue, maintaining consistency is important. The code should be unified.

## Execution Flow Diagram

```
gt handoff [args]
      │
      ▼
┌─────────────────────────────┐
│ Check if polecat            │
│ → Yes: delegate to gt done  │
└─────────────────────────────┘
      │ No
      ▼
┌─────────────────────────────┐
│ Process --collect flag      │
│ → Yes: auto-collect state   │
│   into handoffMessage       │
└─────────────────────────────┘
      │
      ▼
┌─────────────────────────────┐
│ Check for bead/role arg     │
│ → Bead: hook it first       │
│ → Role: resolve session     │
└─────────────────────────────┘
      │
      ▼
┌─────────────────────────────┐
│ Remote handoff?             │
│ (targetSession != current)  │
│ → Yes: handoffRemoteSession │
└─────────────────────────────┘
      │ No (self handoff)
      ▼
┌─────────────────────────────┐
│ Print feedback              │
│ Log handoff event           │
└─────────────────────────────┘
      │
      ▼
┌─────────────────────────────┐
│ DRY RUN?                    │─── Yes ──► return
└─────────────────────────────┘
      │ No
      ▼
┌─────────────────────────────────────────────┐
│ MAIL SEND (if subject/message provided)     │◄── HAPPENS FIRST
│   - sendHandoffMail()                       │
│   - Creates bead via bd create              │
│   - Auto-hooks bead                         │
└─────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────┐
│ ClearHistory                │
│ Write handoff marker        │
└─────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────┐
│ KILL PANE PROCESSES (excluding self)        │◄── HAPPENS SECOND
│   - KillPaneProcessesExcluding()            │
│   - Sends SIGTERM, waits 2s, SIGKILL        │
└─────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────┐
│ RespawnPane                 │
│ → Kills pane, starts new    │
└─────────────────────────────┘
```

## Proposed Fixes

### Fix 1: Clarify Expected Behavior (Documentation)

The current behavior is intentional - mail is only sent when flags are used. Update documentation to clarify:

```markdown
## gt handoff

Ends the current session and starts a fresh one.

### Mail/Context Options

By default, no handoff mail is sent. To include context for the next session:

- `gt handoff -c` - Auto-collect current state (hooked work, inbox, ready beads)
- `gt handoff -s "subject"` - Send mail with custom subject
- `gt handoff -m "message"` - Send mail with custom message body
```

### Fix 2: Consider Default Mail Behavior (Design Decision)

If the expectation is that mail SHOULD always be sent, consider making `-c` the default:

```go
// Option A: Default collect to true
handoffCmd.Flags().BoolVarP(&handoffCollect, "collect", "c", true, ...)

// Option B: Always send minimal mail
if handoffSubject == "" && handoffMessage == "" {
    handoffSubject = "Session handoff"
    handoffMessage = "Context cycling to fresh session."
}
```

**Trade-off**: More mail noise vs better context continuity.

### Fix 3: Unify Kill Function Implementations (Technical Debt)

Update `KillPaneProcessesExcluding` to use `syscall.Kill` instead of `exec.Command`:

```go
// internal/tmux/tmux.go:507-508, 515-516, 522-524
// Change FROM:
_ = exec.Command("kill", "-TERM", dpid).Run()
_ = exec.Command("kill", "-KILL", dpid).Run()

// Change TO:
_ = killPID(dpid, syscall.SIGTERM)
_ = killPID(dpid, syscall.SIGKILL)
```

This aligns with the fix in commit `0c0a22cf` which changed other functions for consistency.

## Edge Cases and Risks

### Risk 1: Mail Sending Failure

If `sendHandoffMail` fails (e.g., `bd create` fails), the handoff continues without mail:

```go
if err != nil {
    style.PrintWarning("could not send handoff mail: %v", err)
    // Continue anyway - the respawn is more important
}
```

This is intentional - mail is nice-to-have, respawn is critical.

### Risk 2: Remote Handoff Mail Ordering

For remote handoff (`gt handoff witness`), mail is sent BEFORE `handoffRemoteSession` is called (line 147). The order is still correct.

### Risk 3: Polecat Delegation

Polecats delegate to `gt done` (lines 74-82), which has its own mail handling. This path doesn't use the main handoff mail logic.

## Files Analyzed

| File | Lines | Key Functions |
|------|-------|---------------|
| `internal/cmd/handoff.go` | 1-826 | `runHandoff`, `sendHandoffMail`, `handoffRemoteSession` |
| `internal/tmux/tmux.go` | 1-1623 | `KillPaneProcesses`, `KillPaneProcessesExcluding`, `RespawnPane` |

## Related Issues/Commits

| Reference | Description |
|-----------|-------------|
| gt-9u7 | This bug: handoff mail ordering |
| hq-qkk | Self-kill bug (caller killed before respawn) |
| gt-019 | Same as hq-qkk (alternate ID) |
| 6218177f | Added KillPaneProcessesExcluding |
| 0c0a22cf | Changed to syscall.Kill |
| 04b7e8b6 | Alternate version on different branch |

## Conclusion

1. **The bug report describes expected behavior**: Mail is only sent when flags (`-s`, `-m`, `-c`) are provided.

2. **The code order IS correct**: Mail send (line 175) comes before kill (line 207).

3. **There IS a code inconsistency**: `KillPaneProcessesExcluding` uses `exec.Command` while other kill functions use `syscall.Kill`. This should be unified for consistency.

4. **Design decision needed**: Should mail be sent by default? Currently it requires explicit flags.

## Recommendations

1. **If current behavior is correct**: Update documentation to clarify that `-c` flag is needed for automatic context.

2. **If mail should be default**: Change `handoffCollect` default to `true` or add minimal default mail.

3. **Regardless**: Fix `KillPaneProcessesExcluding` to use `syscall.Kill` for consistency with other functions.
