//go:build windows

package tmux

import (
	"fmt"
	"syscall"
)

// killPID is a stub on Windows where syscall.Kill is not available.
func killPID(pid string, sig syscall.Signal) error {
	return fmt.Errorf("killPID: not supported on Windows")
}

// killProcessGroup is a stub on Windows where syscall.Kill is not available.
func killProcessGroup(pgid string, sig syscall.Signal) error {
	return fmt.Errorf("killProcessGroup: not supported on Windows")
}
