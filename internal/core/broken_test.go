package core

import (
	"path/filepath"
	"testing"
)

// Broken media, from the index: an empty picture, a "video" whose header is
// garbage; a good video is not listed.
func TestBrokenFilesAreFound(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	root := filepath.Join(base, "media")
	writeAged(t, filepath.Join(root, "good.mp4"), corpus(t, "h264_4k.mp4"))
	writeAged(t, filepath.Join(root, "cut.mp4"), []byte("this is not a video at all, just some bytes that stop"))
	writeAged(t, filepath.Join(root, "blank.jpg"), nil)
	ld, err := Open(filepath.Join(base, "data", "index.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer ld.Close()
	if _, err := ld.Index(root); err != nil {
		t.Fatal(err)
	}
	items, err := ld.Broken("")
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, it := range items {
		got[filepath.Base(it.Path)] = it.Why
	}
	if got["cut.mp4"] != "unreadable" || got["blank.jpg"] != "empty" || got["good.mp4"] != "" {
		t.Errorf("%v", got)
	}
}
