//go:build darwin || linux

package daemon

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// TakeOver makes this the only engine for an index: it holds an exclusive
// lock on path (beside the index) for as long as the process runs. An older
// engine still holding it — one left behind by a force quit or an update,
// no longer answering on the socket — is asked to stop, then stopped. Two
// engines on one index kept a drive's index open in the old one, so the new
// one showed "Opening its index…" for ever (the owner's T5 EVO).
func TakeOver(path string) (*os.File, error) {
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return nil, err
	}
	try := func() bool { return syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) == nil }
	if !try() {
		pid := lockOwner(path)
		stop := func(sig syscall.Signal, wait time.Duration) bool {
			if pid > 0 && pid != os.Getpid() {
				_ = syscall.Kill(pid, sig)
			}
			for end := time.Now().Add(wait); time.Now().Before(end); time.Sleep(100 * time.Millisecond) {
				if try() {
					return true
				}
			}
			return false
		}
		if !stop(syscall.SIGTERM, 8*time.Second) && !stop(syscall.SIGKILL, 5*time.Second) {
			f.Close()
			return nil, fmt.Errorf("another engine (pid %d) holds %s and did not stop", pid, path)
		}
	}
	if err := f.Truncate(0); err == nil {
		_, _ = f.WriteAt([]byte(strconv.Itoa(os.Getpid())+"\n"), 0)
	}
	return f, nil
}

func lockOwner(path string) int {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return 0
	}
	return pid
}
