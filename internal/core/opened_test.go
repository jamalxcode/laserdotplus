package core

import (
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// A last-opened sort answers from the dates remembered beside the index, and
// reads them again in the background so a file opened since is right next time.
func TestByOpenedRemembersDates(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	root := filepath.Join(base, "r")
	for _, n := range []string{"a.txt", "b.txt", "c.txt"} {
		writeAged(t, filepath.Join(root, n), []byte(n))
	}
	dates := map[string]int64{"a.txt": 300, "b.txt": 100, "c.txt": 200}
	var reads atomic.Int64
	old := readOpened
	readOpened = func(p string) (int64, error) {
		reads.Add(1)
		if _, err := os.Lstat(p); err != nil {
			return 0, err
		}
		return dates[filepath.Base(p)], nil
	}
	defer func() { readOpened = old }()

	dbPath := filepath.Join(base, "data", "i.db")
	ld, _ := Open(dbPath)
	if _, err := ld.Index(root); err != nil {
		t.Fatal(err)
	}
	order := func() string {
		r, err := ld.ByOpened("txt", 0, 10, false)
		if err != nil {
			t.Fatal(err)
		}
		var names []string
		for _, h := range r.Hits {
			names = append(names, filepath.Base(h.Path))
		}
		return strings.Join(names, ",")
	}
	if got := order(); got != "a.txt,c.txt,b.txt" {
		t.Fatalf("first order %s", got)
	}
	if b, err := os.ReadFile(filepath.Join(base, "data", openedListFile)); err != nil || !strings.Contains(string(b), "300\t"+filepath.Join(root, "a.txt")) {
		t.Fatalf("not remembered beside the index: %v %q", err, b)
	}
	// b.txt is opened now: the next sort answers from memory, the refresh fixes it.
	dates["b.txt"] = 400
	n := reads.Load()
	if got := order(); got != "a.txt,c.txt,b.txt" {
		t.Fatalf("remembered order %s", got)
	}
	for deadline := time.Now().Add(5 * time.Second); ld.od.refreshing.Load() || reads.Load() < n+3; {
		if time.Now().After(deadline) {
			t.Fatal("no background refresh")
		}
		time.Sleep(20 * time.Millisecond)
	}
	if got := order(); got != "b.txt,a.txt,c.txt" {
		t.Fatalf("after the refresh %s", got)
	}
	ld.Close()

	// Remembered across a restart.
	ld2, _ := Open(dbPath)
	defer ld2.Close()
	reads.Store(0)
	dates["c.txt"] = 999 // not read again before answering
	r, _ := ld2.ByOpened("txt", 0, 10, false)
	if len(r.Hits) != 3 || filepath.Base(r.Hits[0].Path) != "b.txt" {
		t.Fatalf("after reopening: %+v", r.Hits)
	}
}
