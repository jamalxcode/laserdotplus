package core

import (
	"os"
	"path/filepath"
	"testing"
)

// The owner: "when a file is deleted from the Finder, it needs to be
// reflected on Laserdot+, or if it is moved to a place that is not being
// viewed, it also needs to be removed". Each change the watcher applies
// moves the change count (the app then searches again), and the file is
// gone from the results.
func TestChangesMoveTheCountAndLeaveTheResults(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	lib := filepath.Join(base, "lib")
	writeAged(t, filepath.Join(lib, "keep.txt"), []byte("k"))
	writeAged(t, filepath.Join(lib, "deleted.txt"), []byte("d"))
	writeAged(t, filepath.Join(lib, "moved.txt"), []byte("m"))
	ld, _ := Open(filepath.Join(base, "i.db"))
	defer ld.Close()
	ld.Index(lib)
	before := ld.Changes()
	os.Remove(filepath.Join(lib, "deleted.txt"))
	os.Rename(filepath.Join(lib, "moved.txt"), filepath.Join(base, "moved.txt")) // out of the indexed folder
	if _, err := ld.ApplyChanges([]Change{{Path: lib}}); err != nil {
		t.Fatal(err)
	}
	if ld.Changes() == before {
		t.Error("the change count did not move")
	}
	expect(t, lnames(t, ld, "txt"), "keep.txt")
	// Nothing changed: the count stays (the app does not search for nothing).
	now := ld.Changes()
	ld.ApplyChanges([]Change{{Path: lib}})
	if ld.Changes() != now {
		t.Error("the count moved without a change")
	}
}
