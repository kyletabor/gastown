# Phase 1 Investigation Findings: gt handoff timeout

**Issue**: gt-t3o
**Date**: 2026-01-31
**Investigator**: gastown/polecats/furiosa

## Summary

Validated both theories for the gt handoff timeout bug. **Both theories are INVALID**. The root cause is likely an intermittent hang in tmux operations.

## Theory Validation

### Theory A: Self-kill before RespawnPane ❌ INVALID

**Theory**: KillPaneProcesses sends SIGTERM to process group, gt handoff is in that group, gets killed before RespawnPane is called.

**Investigation**:
1. Verified that Claude Code spawns bash tool commands in their own process group
2. Measured PGID relationships:
   - Claude (mayor) PGID: 46860
   - My bash shell PGID: 319331 (different!)
   - Child processes inherit bash's PGID, not Claude's

**Conclusion**: When gt handoff runs `kill -TERM -46860` (Claude's PGID), it does NOT kill itself because gt handoff has PGID 319331 (or similar, NOT 46860). Theory A is INVALID.

### Theory B: exec.Command signal propagation ❌ INVALID

**Theory**: exec.Command("kill") somehow causes the caller to receive the signal. Using syscall.Kill() would avoid this.

**Investigation**:
1. Tested exec.Command("kill") vs syscall.Kill() - both behave identically
2. The only way to kill yourself via PGID is if you're IN that process group
3. Since gt handoff has a different PGID from Claude, neither method would cause self-termination

**Conclusion**: exec.Command("kill") works correctly. The PGID isolation means gt handoff would survive regardless. Theory B is INVALID.

## Root Cause Analysis

The real bug is that **gt handoff hangs before completing** the kill operations.

### Evidence
- Exit code 143 (SIGTERM) = Claude Code's 2-minute bash tool timeout
- "Original mayor session still running" = Claude was never killed
- If gt handoff had reached KillPaneProcesses, Claude would be dead

### Where the Hang Occurs

The hang must be BEFORE or DURING KillPaneProcesses. All tested operations complete quickly:

| Operation | Time (normal) |
|-----------|---------------|
| tmux list-panes | 14ms |
| ps -o pgid= | 37ms |
| pgrep -P | 28ms |
| tmux clear-history | 16ms |
| kill -0 (PID) | 2ms |
| kill -0 (PGID) | 4ms |

### Possible Hang Causes

1. **tmux server lock**: If another process holds a tmux server lock, commands block
2. **Resource exhaustion**: System under load could cause process/file operations to stall
3. **Intermittent bug**: Race condition or timing-dependent issue

## Recommendations

### Short-term: Add Timeouts

Add context timeout to all external commands in handoff:

```go
ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()
cmd := exec.CommandContext(ctx, "tmux", args...)
```

### Medium-term: Add Debug Logging

Add verbose logging before/after each operation:

```go
fmt.Fprintf(os.Stderr, "[DEBUG] ClearHistory starting at %s\n", time.Now())
if err := t.ClearHistory(pane); err != nil {...}
fmt.Fprintf(os.Stderr, "[DEBUG] ClearHistory done at %s\n", time.Now())
```

### Long-term: Monitor tmux Health

Before handoff operations, check tmux server health:

```go
// Quick health check - if this times out, tmux is stuck
ctx, _ := context.WithTimeout(context.Background(), 1*time.Second)
exec.CommandContext(ctx, "tmux", "display-message", "-p", "ok")
```

## Test Scripts Created

1. `investigations/reproduce-handoff-bug.sh` - Tests PGID behavior
2. `investigations/test_exec_vs_syscall.go` - Compares exec.Command vs syscall.Kill
3. `investigations/trace_handoff.sh` - Traces individual handoff operations

## Conclusion

The bug is NOT caused by:
- Self-termination via PGID kill (Theory A)
- exec.Command signal propagation (Theory B)

The bug IS caused by:
- gt handoff hanging before completing kill operations
- Most likely a tmux server lock or intermittent system issue
- Need to add timeouts and better error handling

## Next Steps

1. Add timeouts to tmux commands (this should be the fix)
2. Add debug logging to help diagnose future occurrences
3. Consider adding tmux health check before handoff
