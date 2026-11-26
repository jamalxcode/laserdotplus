package core

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Laserdot+ at a real drive's scale (the critique: the newer screens had only
// seen a dozen sample files): 20,000 files in 200 folders. Indexing, the
// Space view's measurement, a page of dates and a second duplicate scan stay
// quick. The budgets are generous (CI machines are slow); a regression that
// makes any of them grow with the square of the files fails.
func TestManyFilesStayQuick(t *testing.T) {
	if testing.Short() {
		t.Skip("scale")
	}
	base, _ := filepath.EvalSymlinks(t.TempDir())
	root := filepath.Join(base, "big")
	var paths []string
	for d := 0; d < 200; d++ {
		dir := filepath.Join(root, fmt.Sprintf("folder %03d", d))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		for f := 0; f < 100; f++ {
			p := filepath.Join(dir, fmt.Sprintf("file %03d.bin", f))
			// Every tenth file of an odd folder is a copy of the one in the
			// folder before it: 1,000 pairs.
			body := []byte(fmt.Sprintf("%06d %s", d*100+f, string(make([]byte, 2000))))
			if f%10 == 0 && d%2 == 1 {
				body = []byte(fmt.Sprintf("%06d %s", (d-1)*100+f, string(make([]byte, 2000))))
			}
			if err := os.WriteFile(p, body, 0o644); err != nil {
				t.Fatal(err)
			}
			paths = append(paths, p)
		}
	}
	ld, err := Open(filepath.Join(base, "data", "index.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer ld.Close()
	budget := func(what string, max time.Duration, f func()) {
		t.Helper()
		start := time.Now()
		f()
		if d := time.Since(start); d > max {
			t.Errorf("%s took %v (budget %v)", what, d, max)
		} else {
			t.Logf("%s: %v", what, d)
		}
	}
	budget("index 20,000 files", 60*time.Second, func() {
		if _, err := ld.Index(root); err != nil {
			t.Fatal(err)
		}
	})
	budget("Space: the folders by size", 3*time.Second, func() {
		rep, err := ld.Storage(root, 60)
		if err != nil || len(rep.Items) != 60 || rep.Items[0].Files != 100 {
			t.Errorf("%v %d items", err, len(rep.Items))
		}
	})
	budget("the dates of a page of 2,000 rows", 5*time.Second, func() {
		if got := ld.FileTimes(paths[:2000]); len(got) != 2000 {
			t.Errorf("%d dates", len(got))
		}
	})
	opts := DefaultDupeOptions()
	opts.Images, opts.Videos = false, false
	var first *DupeReport
	budget("first duplicate scan", 60*time.Second, func() { first, _ = ld.FindDuplicates(opts) })
	if first == nil || len(first.Groups) != 1000 {
		n := -1
		if first != nil {
			n = len(first.Groups)
		}
		t.Fatalf("%d groups, want 1000", n)
	}
	budget("second duplicate scan (fingerprints kept)", 20*time.Second, func() {
		again, _ := ld.FindDuplicates(opts)
		if again.Read != 0 {
			t.Errorf("read %d files again", again.Read)
		}
	})
}
