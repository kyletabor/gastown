#!/bin/bash
# Reproduction script for gt handoff timeout bug
# Tests whether exec.Command("kill") kills the caller

set -e

echo "=== Testing Process Group Behavior ==="
echo ""

# Get our own PID and PGID
MY_PID=$$
MY_PGID=$(ps -o pgid= -p $MY_PID | tr -d ' ')
echo "Test script PID: $MY_PID"
echo "Test script PGID: $MY_PGID"
echo ""

# Test 1: Check if we're in our own process group
if [ "$MY_PID" = "$MY_PGID" ]; then
    echo "✓ We are our own process group leader"
else
    echo "✗ We are NOT our own process group leader"
fi
echo ""

# Test 2: What happens when we call kill on our own PGID?
echo "=== Test: Calling kill on our own PGID ==="
echo "About to run: kill -0 -$MY_PGID (signal 0 = check if we can send)"

# Signal 0 doesn't actually send a signal, just checks permissions
if kill -0 -$MY_PGID 2>/dev/null; then
    echo "✓ We CAN send signals to our own process group"
else
    echo "✗ We CANNOT send signals to our own process group"
fi
echo ""

# Test 3: Create a child process and check its PGID
echo "=== Test: Child process PGID ==="
CHILD_PGID=$(bash -c 'ps -o pgid= -p $$ | tr -d " "')
echo "Child bash PGID: $CHILD_PGID"
if [ "$CHILD_PGID" = "$MY_PGID" ]; then
    echo "✓ Child inherits parent's PGID (same group)"
else
    echo "✗ Child has different PGID: $CHILD_PGID vs $MY_PGID"
fi
echo ""

# Test 4: Simulate what gt handoff does - get "pane PID" and its PGID
echo "=== Test: Simulating KillPaneProcesses flow ==="
# In the real case, this would be the Claude process
# For testing, we use our own parent (the shell that ran this script)
TARGET_PID=$PPID
TARGET_PGID=$(ps -o pgid= -p $TARGET_PID 2>/dev/null | tr -d ' ')
echo "Target (parent) PID: $TARGET_PID"
echo "Target (parent) PGID: $TARGET_PGID"
echo "Our PGID: $MY_PGID"
echo ""

if [ "$TARGET_PGID" = "$MY_PGID" ]; then
    echo "⚠️  WARNING: Target and us share the same PGID!"
    echo "   Killing -PGID would kill us too!"
else
    echo "✓ Target has different PGID - we would survive the kill"
fi
echo ""

# Test 5: Check what happens with a Go program using exec.Command
echo "=== Test: Go exec.Command behavior ==="
# Create a small Go program to test signal behavior
cat > /tmp/test_kill_pgid.go << 'GOEOF'
package main

import (
    "fmt"
    "os"
    "os/exec"
    "syscall"
    "time"
)

func main() {
    pid := os.Getpid()
    pgid, _ := syscall.Getpgid(pid)
    ppid := os.Getppid()
    ppgid, _ := syscall.Getpgid(ppid)

    fmt.Printf("Go process PID: %d\n", pid)
    fmt.Printf("Go process PGID: %d\n", pgid)
    fmt.Printf("Parent PID: %d\n", ppid)
    fmt.Printf("Parent PGID: %d\n", ppgid)
    fmt.Println()

    if pgid == ppgid {
        fmt.Println("⚠️  Go process and parent share PGID")
    } else {
        fmt.Println("✓ Go process has different PGID from parent")
    }
    fmt.Println()

    // Test exec.Command behavior
    fmt.Println("Testing exec.Command(\"ps\")...")
    cmd := exec.Command("ps", "-o", "pid,pgid", "-p", fmt.Sprintf("%d", pid))
    out, err := cmd.Output()
    if err != nil {
        fmt.Printf("Error: %v\n", err)
    } else {
        fmt.Printf("Output:\n%s\n", out)
    }

    // Check if we would survive a PGID kill
    if pgid == ppgid {
        fmt.Println("THEORY A: If we kill -9 -PGID, we would die too!")
    } else {
        fmt.Println("THEORY A INVALID: We have our own PGID, we would survive")
    }

    // Small delay to allow output to flush
    time.Sleep(100 * time.Millisecond)
}
GOEOF

if command -v go &> /dev/null; then
    echo "Compiling and running Go test program..."
    go run /tmp/test_kill_pgid.go
else
    echo "Go not available, skipping Go test"
fi
echo ""

echo "=== Summary ==="
echo "If Claude Code spawns bash commands in their own process group,"
echo "then Theory A (self-kill) is INVALID because gt handoff would have"
echo "a different PGID from Claude and would survive the kill."
echo ""
echo "To verify in real environment, run 'gt handoff --dry-run' and check"
echo "the PGIDs of Claude and the gt process."
