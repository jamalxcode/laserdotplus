package core

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"testing"
	"time"

	"github.com/jamalxcode/laserdotplus/internal/index"
)

// An 8 TB drive's worth of files (the owner's: hundreds of thousands), with
// time budgets for what the window asks the engine (the critique: the app had
// only been tried on small samples — a nightly Mac run of this size was too
// slow, so the engine is measured here, on Linux, on every build).
// LASERDOT_SCALE=300000 sets the number of files (CI's Ubuntu job); without
// it the test is skipped.
func TestDriveScale(t *testing.T) {
	n, _ := strconv.Atoi(os.Getenv("LASERDOT_SCALE"))
	if n <= 0 {
		t.Skip("set LASERDOT_SCALE (CI uses 300000)")
	}
	base, _ := filepath.EvalSymlinks(t.TempDir())
	root := filepath.Join(base, "drive")
	const perFolder = 100
	folders := (n + perFolder - 1) / perFolder
	start := time.Now()
	made := 0
	for d := 0; d < folders && made < n; d++ {
		dir := filepath.Join(root, fmt.Sprintf("year %02d", d%30), fmt.Sprintf("shoot %05d", d))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		// Each folder: Finder's .DS_Store (junk indexing notes).
		os.WriteFile(filepath.Join(dir, ".DS_Store"), []byte("x"), 0o644)
		for f := 0; f < perFolder && made < n; f++ {
			name := fmt.Sprintf("clip %03d.mp4", f)
			body := []byte("not really a video " + strconv.Itoa(made))
			switch {
			case f%10 == 0:
				body = nil // empty files: junk from the index
			case f%25 == 1:
				name = "._" + name // AppleDouble leftovers
			case f%3 == 0:
				name = fmt.Sprintf("photo %03d.jpg", f)
			}
			if err := os.WriteFile(filepath.Join(dir, name), body, 0o644); err != nil {
				t.Fatal(err)
			}
			made++
		}
	}
	t.Logf("made %d files in %d folders: %v", made, folders, time.Since(start))

	ld, err := Open(filepath.Join(base, "data", "index.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer ld.Close()
	scale := float64(n) / 300_000
	budget := func(what string, max time.Duration, f func()) {
		t.Helper()
		max = time.Duration(float64(max) * scale)
		if max < time.Second {
			max = time.Second
		}
		s := time.Now()
		f()
		if d := time.Since(s); d > max {
			t.Errorf("%s took %v (budget %v)", what, d, max)
		} else {
			t.Logf("%s: %v (budget %v)", what, d, max)
		}
	}
	budget("index", 60*time.Second, func() {
		if _, err := ld.Index(root); err != nil {
			t.Fatal(err)
		}
	})
	budget("a search over everything (first page)", 2*time.Second, func() {
		r, err := ld.Search("clip", SearchOptions{})
		if err != nil || r.Total < uint64(n/3) {
			t.Errorf("%v %+v", err, r)
		}
	})
	budget("Select All (200,000 rows)", 4*time.Second, func() {
		r, err := ld.Search("clip", SearchOptions{Page: index.Page{Limit: 200_000}})
		if err != nil || len(r.Hits) < n/3 {
			t.Errorf("%v %d rows", err, len(r.Hits))
		}
	})
	budget("the choices (refinements)", 4*time.Second, func() {
		if g, err := ld.Refinements("clip"); err != nil || len(g) == 0 {
			t.Errorf("%v %d groups", err, len(g))
		}
	})
	budget("Junk from the index (empty files + noted system files)", 4*time.Second, func() {
		got := ld.JunkIndexed(root)
		why := map[string]int{}
		for _, j := range got {
			why[j.Why]++
		}
		// Empty files from the index, and the system files indexing passed.
		if why["system"] < folders || len(got) < n/10+folders {
			t.Errorf("%d junk items %v", len(got), why)
		}
	})
	budget("Space: the folders by size", 10*time.Second, func() {
		if rep, err := ld.Storage(root, 60); err != nil || len(rep.Items) == 0 {
			t.Errorf("%v", err)
		}
	})
	budget("Last Opened sort, first time (dates read)", 15*time.Second, func() {
		if _, err := ld.ByOpened("clip", 0, 500, false); err != nil {
			t.Error(err)
		}
	})
	budget("Last Opened sort again (dates remembered)", 3*time.Second, func() {
		if _, err := ld.ByOpened("clip", 0, 500, false); err != nil {
			t.Error(err)
		}
	})
	var m runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&m)
	t.Logf("engine heap after all: %d MB", m.HeapAlloc>>20)
	if limit := uint64(1500*scale) << 20; m.HeapAlloc > limit && m.HeapAlloc > 200<<20 {
		t.Errorf("heap %d MB over %d MB", m.HeapAlloc>>20, limit>>20)
	}
}
