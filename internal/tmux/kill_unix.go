//go:build !windows

package tmux

import (
	"strconv"
	"strings"
	"syscall"
)

// killPID sends a signal to a specific process ID.
// Uses syscall.Kill directly instead of exec.Command("kill", ...) to avoid
// unexpected signal delivery issues that can cause the caller to be killed.
// Returns nil on success or if the process doesn't exist (ESRCH).
func killPID(pid string, sig syscall.Signal) error {
	pidInt, err := strconv.Atoi(strings.TrimSpace(pid))
	if err != nil {
		return err
	}
	err = syscall.Kill(pidInt, sig)
	// ESRCH means process doesn't exist - not an error for our purposes
	if err == syscall.ESRCH {
		return nil
	}
	return err
}

// killProcessGroup sends a signal to all processes in a process group.
// Uses syscall.Kill with negative PGID (POSIX convention for process groups).
// Returns nil on success or if the process group doesn't exist (ESRCH).
func killProcessGroup(pgid string, sig syscall.Signal) error {
	pgidInt, err := strconv.Atoi(strings.TrimSpace(pgid))
	if err != nil {
		return err
	}
	err = syscall.Kill(-pgidInt, sig)
	// ESRCH means process group doesn't exist - not an error for our purposes
	if err == syscall.ESRCH {
		return nil
	}
	return err
}
