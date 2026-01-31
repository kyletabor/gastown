#!/bin/bash
# Trace script to identify where gt handoff hangs
# Run this INSIDE the mayor session to test handoff behavior

set -x  # Enable command tracing

echo "=== Tracing gt handoff operations ==="
echo "Time: $(date)"
echo ""

# Get pane info
PANE="${TMUX_PANE:-unknown}"
echo "[TRACE] TMUX_PANE=$PANE"

if [ "$PANE" = "unknown" ]; then
    echo "[ERROR] Not in tmux!"
    exit 1
fi

# Step 1: Test tmux list-panes (used by GetPanePID)
echo "[TRACE] Step 1: Testing tmux list-panes..."
echo "[TRACE] Running: tmux list-panes -t $PANE -F '#{pane_pid}'"
START=$(date +%s%3N)
PANE_PID=$(tmux list-panes -t "$PANE" -F '#{pane_pid}' 2>&1)
END=$(date +%s%3N)
ELAPSED=$((END - START))
echo "[TRACE] Result: $PANE_PID (${ELAPSED}ms)"

if [ -z "$PANE_PID" ]; then
    echo "[ERROR] Failed to get pane PID"
    exit 1
fi

# Step 2: Test ps (used by getProcessGroupID)
echo ""
echo "[TRACE] Step 2: Testing ps for PGID..."
echo "[TRACE] Running: ps -o pgid= -p $PANE_PID"
START=$(date +%s%3N)
PGID=$(ps -o pgid= -p "$PANE_PID" 2>&1 | tr -d ' ')
END=$(date +%s%3N)
ELAPSED=$((END - START))
echo "[TRACE] Result: PGID=$PGID (${ELAPSED}ms)"

# Step 3: Test pgrep (used by getAllDescendants)
echo ""
echo "[TRACE] Step 3: Testing pgrep for descendants..."
echo "[TRACE] Running: pgrep -P $PANE_PID"
START=$(date +%s%3N)
DESCENDANTS=$(pgrep -P "$PANE_PID" 2>&1 || true)
END=$(date +%s%3N)
ELAPSED=$((END - START))
echo "[TRACE] Result: descendants='$DESCENDANTS' (${ELAPSED}ms)"

# Step 4: Test tmux clear-history
echo ""
echo "[TRACE] Step 4: Testing tmux clear-history..."
echo "[TRACE] Running: tmux clear-history -t $PANE"
START=$(date +%s%3N)
CLEAR_RESULT=$(tmux clear-history -t "$PANE" 2>&1)
END=$(date +%s%3N)
ELAPSED=$((END - START))
echo "[TRACE] Result: '$CLEAR_RESULT' (${ELAPSED}ms)"

# Step 5: Test kill with signal 0 (doesn't actually kill)
echo ""
echo "[TRACE] Step 5: Testing kill -0 (permission check)..."
echo "[TRACE] Running: kill -0 $PANE_PID"
START=$(date +%s%3N)
KILL_RESULT=$(kill -0 "$PANE_PID" 2>&1 && echo "OK" || echo "FAILED")
END=$(date +%s%3N)
ELAPSED=$((END - START))
echo "[TRACE] Result: $KILL_RESULT (${ELAPSED}ms)"

# Step 6: Test process group kill with signal 0
echo ""
echo "[TRACE] Step 6: Testing process group kill -0..."
if [ -n "$PGID" ] && [ "$PGID" != "0" ] && [ "$PGID" != "1" ]; then
    echo "[TRACE] Running: kill -0 -$PGID"
    START=$(date +%s%3N)
    PG_KILL_RESULT=$(kill -0 -"$PGID" 2>&1 && echo "OK" || echo "FAILED")
    END=$(date +%s%3N)
    ELAPSED=$((END - START))
    echo "[TRACE] Result: $PG_KILL_RESULT (${ELAPSED}ms)"
else
    echo "[TRACE] Skipped: PGID is empty, 0, or 1"
fi

echo ""
echo "[TRACE] All steps completed successfully!"
echo "[TRACE] If gt handoff hangs, compare which step is last to appear"
echo ""
echo "=== Summary ==="
echo "Pane: $PANE"
echo "Pane PID: $PANE_PID"
echo "Pane PGID: $PGID"
echo "Descendants: ${DESCENDANTS:-none}"
