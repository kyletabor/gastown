# Investigation: gt handoff timeout - Exit 143 SIGTERM

**Issue**: cc-yx4y
**Investigator**: gastown/polecats/furiosa
**Date**: 2026-01-31

## Summary

The `gt handoff` command hangs for 2 minutes when run by the mayor, then gets killed by Claude Code's bash tool timeout (SIGTERM, exit code 143).

## Environment Analysis

### Process Group Isolation
- Claude Code spawns bash commands in their own session/process group
- Verified: current shell PGID (248514) != Claude PGID (46860)
- When `gt handoff` kills Claude's process group, it survives (different PGID)

### Mayor State at Time of Investigation
- Session: hq-mayor
- PID: 46860
- Command: claude --dangerously-skip-permissions
- PGID: 46860 (process group leader)
- Pane: alive (pane_dead=0)

## Code Flow Analysis

From `handoff.go` lines 152-215:

1. **Line 152**: Print "🤝 Handing off hq-mayor..." ← Issue reports this happened
2. **Lines 155-163**: Log to townlog/events (file I/O - fast)
3. **Line 192**: `t.ClearHistory(pane)` - tmux command
4. **Lines 200-205**: Write handoff marker to `.runtime/handoff_to_successor`
5. **Lines 209-212**: `t.KillPaneProcesses(pane)` - kills Claude's process group
6. **Line 215**: `t.RespawnPane(pane, command)` - calls `tmux respawn-pane -k`

### KillPaneProcesses Timing (tmux.go lines 362-419)
- 100ms sleep after process group SIGTERM
- 2s sleep after descendant SIGTERM
- 2s sleep after pane PID SIGTERM
- **Total: ~4.2 seconds**

### Observed vs Expected
- **Expected**: ~4.2 seconds (KillPaneProcesses) + fast tmux commands
- **Observed**: 2 minutes (120 seconds) - Claude Code's bash tool timeout
- **Unaccounted**: ~116 seconds of hanging

## Key Insight

The issue description states: "Original mayor session still running"

This means **Claude was NOT killed** by `KillPaneProcesses`. If the function had completed:
1. SIGKILL would have been sent to PGID 46860
2. Claude would be dead
3. The pane would be in dead state

Since Claude was still running, the hang must occur **before or during** `KillPaneProcesses`.

## Possible Root Causes

### Theory 1: tmux Command Blocking
One of these tmux commands could be hanging:
- `tmux list-panes` in `GetPanePID()`
- `tmux clear-history` in `ClearHistory()`

Possible causes:
- tmux server lock/deadlock
- Socket permission issues
- Server busy with another operation

### Theory 2: Process Lookup Hanging
- `ps -o pgid=` hanging
- `pgrep -P` hanging (recursive calls)

### Theory 3: Process Group Kill Skipped
If `getProcessGroupID()` returns "", "0", or "1", the process group kill is skipped entirely:
```go
if pgid != "" && pgid != "0" && pgid != "1" {
    // Kill is only executed if this condition is true
    _ = exec.Command("kill", "-TERM", "-"+pgid).Run()
    ...
}
```

## Reproduction Steps

1. Attach to mayor session
2. Run `gt handoff` while monitoring:
   - `strace -f -p <gt_handoff_pid>` to see blocking syscalls
   - `tmux list-sessions` in another terminal to verify tmux responsiveness
   - Process state with `ps auxf | grep -E "gt|claude"` before/during/after

## Recommended Fixes

### Fix 1: Add Timeouts to External Commands
```go
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()
cmd := exec.CommandContext(ctx, "tmux", args...)
```

### Fix 2: Add Debug Logging
Add verbose output before each operation in `runHandoff`:
```go
fmt.Printf("[DEBUG] ClearHistory starting...\n")
if err := t.ClearHistory(pane); err != nil {...}
fmt.Printf("[DEBUG] ClearHistory done\n")

fmt.Printf("[DEBUG] KillPaneProcesses starting...\n")
if err := t.KillPaneProcesses(pane); err != nil {...}
fmt.Printf("[DEBUG] KillPaneProcesses done\n")
```

### Fix 3: Validate PGID Before Kill
```go
pgid := getProcessGroupID(pid)
if pgid == "" {
    return fmt.Errorf("failed to get PGID for PID %s", pid)
}
```

## Next Steps

1. Add debug logging to `gt handoff` to identify exact blocking point
2. Test with `--dry-run` doesn't exercise KillPaneProcesses (returns early)
3. Create a test script that simulates the handoff flow step-by-step
4. Consider adding health check for tmux server before handoff operations
