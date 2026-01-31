// Test program to compare exec.Command("kill") vs syscall.Kill()
// This tests Theory B: exec.Command signal propagation issues
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

	fmt.Println("=== Theory B: exec.Command vs syscall.Kill Test ===")
	fmt.Printf("Test process PID: %d\n", pid)
	fmt.Printf("Test process PGID: %d\n", pgid)
	fmt.Println()

	// Spawn a child process that we can kill
	fmt.Println("Spawning child process to kill...")
	child := exec.Command("sleep", "60")
	if err := child.Start(); err != nil {
		fmt.Printf("Failed to start child: %v\n", err)
		return
	}
	childPID := child.Process.Pid
	childPGID, _ := syscall.Getpgid(childPID)

	fmt.Printf("Child PID: %d\n", childPID)
	fmt.Printf("Child PGID: %d\n", childPGID)
	fmt.Println()

	// Wait a moment for child to settle
	time.Sleep(100 * time.Millisecond)

	// Test 1: Use exec.Command("kill")
	fmt.Println("=== Test 1: exec.Command(\"kill\") ===")
	fmt.Printf("Running: kill -TERM %d\n", childPID)

	// Check if child is running
	if err := syscall.Kill(childPID, 0); err != nil {
		fmt.Printf("Child not running before kill: %v\n", err)
	} else {
		fmt.Println("Child is running before kill")
	}

	// Kill using exec.Command
	killCmd := exec.Command("kill", "-TERM", fmt.Sprintf("%d", childPID))
	killOut, killErr := killCmd.CombinedOutput()
	fmt.Printf("kill command returned: out=%q err=%v\n", string(killOut), killErr)

	// Wait and check
	time.Sleep(100 * time.Millisecond)
	if err := syscall.Kill(childPID, 0); err != nil {
		fmt.Println("✓ Child is dead after exec.Command kill")
	} else {
		fmt.Println("✗ Child is STILL RUNNING after exec.Command kill!")
	}
	fmt.Println()

	// Spawn another child for second test
	fmt.Println("Spawning second child for syscall test...")
	child2 := exec.Command("sleep", "60")
	if err := child2.Start(); err != nil {
		fmt.Printf("Failed to start child2: %v\n", err)
		return
	}
	child2PID := child2.Process.Pid
	fmt.Printf("Child2 PID: %d\n", child2PID)

	time.Sleep(100 * time.Millisecond)

	// Test 2: Use syscall.Kill()
	fmt.Println("=== Test 2: syscall.Kill() ===")
	fmt.Printf("Running: syscall.Kill(%d, syscall.SIGTERM)\n", child2PID)

	if err := syscall.Kill(child2PID, 0); err != nil {
		fmt.Printf("Child2 not running before kill: %v\n", err)
	} else {
		fmt.Println("Child2 is running before kill")
	}

	if err := syscall.Kill(child2PID, syscall.SIGTERM); err != nil {
		fmt.Printf("syscall.Kill failed: %v\n", err)
	} else {
		fmt.Println("syscall.Kill returned successfully")
	}

	time.Sleep(100 * time.Millisecond)
	if err := syscall.Kill(child2PID, 0); err != nil {
		fmt.Println("✓ Child2 is dead after syscall.Kill")
	} else {
		fmt.Println("✗ Child2 is STILL RUNNING after syscall.Kill!")
	}
	fmt.Println()

	// Test 3: Test killing by PGID (the real scenario)
	fmt.Println("=== Test 3: Kill by PGID using exec.Command ===")
	child3 := exec.Command("sleep", "60")
	if err := child3.Start(); err != nil {
		fmt.Printf("Failed to start child3: %v\n", err)
		return
	}
	child3PID := child3.Process.Pid
	child3PGID, _ := syscall.Getpgid(child3PID)
	fmt.Printf("Child3 PID: %d, PGID: %d\n", child3PID, child3PGID)

	time.Sleep(100 * time.Millisecond)

	fmt.Printf("Running: kill -TERM -%d (negative = PGID)\n", child3PGID)
	killCmd3 := exec.Command("kill", "-TERM", fmt.Sprintf("-%d", child3PGID))
	killOut3, killErr3 := killCmd3.CombinedOutput()
	fmt.Printf("kill command returned: out=%q err=%v\n", string(killOut3), killErr3)

	time.Sleep(100 * time.Millisecond)

	// Did WE survive?
	fmt.Println()
	fmt.Println("=== Survival Check ===")
	fmt.Println("If you can read this, the test process survived the PGID kill!")
	fmt.Printf("Our PID: %d, Our PGID: %d, Child3 PGID we killed: %d\n", pid, pgid, child3PGID)

	if pgid == child3PGID {
		fmt.Println("⚠️ We share PGID with child - we SHOULD have died!")
	} else {
		fmt.Println("✓ We have different PGID from child - survival expected")
	}

	// Cleanup
	child.Wait()
	child2.Wait()
	child3.Wait()

	fmt.Println()
	fmt.Println("=== Conclusion ===")
	fmt.Println("Both exec.Command(\"kill\") and syscall.Kill() should work the same")
	fmt.Println("for sending signals. The key factor is the PGID relationship.")
}
