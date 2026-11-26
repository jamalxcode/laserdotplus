//go:build darwin || linux

package daemon

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// A helper process that takes the lock and then hangs, like an engine left
// behind that no longer answers.
func TestMain(m *testing.M) {
	if p := os.Getenv("LASERDOT_TAKEOVER_HOLD"); p != "" {
		if _, err := TakeOver(p); err != nil {
			os.Exit(2)
		}
		os.Stdout.WriteString("held\n")
		time.Sleep(time.Hour)
	}
	os.Exit(m.Run())
}

func TestANewEngineStopsAnOldOneHoldingTheIndex(t *testing.T) {
	lock := filepath.Join(t.TempDir(), "laserdotd.lock")
	old := exec.Command(os.Args[0], "-test.run=^$")
	old.Env = append(os.Environ(), "LASERDOT_TAKEOVER_HOLD="+lock)
	out, _ := old.StdoutPipe()
	if err := old.Start(); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 5)
	if _, err := out.Read(buf); err != nil || string(buf) != "held\n" {
		t.Fatalf("helper: %q %v", buf, err)
	}
	done := make(chan error, 1)
	go func() { done <- old.Wait() }()

	f, err := TakeOver(lock)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	select {
	case <-done: // the old engine was stopped
	case <-time.After(5 * time.Second):
		old.Process.Kill()
		t.Fatal("the old engine is still running")
	}
	if got := lockOwner(lock); got != os.Getpid() {
		t.Errorf("lock owner %d, want %d", got, os.Getpid())
	}
}
