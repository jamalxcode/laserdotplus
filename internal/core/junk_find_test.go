package core

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFindJunk(t *testing.T) {
	root := t.TempDir()
	w := func(rel string, data string, age time.Duration) {
		p := filepath.Join(root, rel)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte(data), 0o644)
		if age > 0 {
			old := time.Now().Add(-age)
			os.Chtimes(p, old, old)
		}
	}
	w("Photos/.DS_Store", "xxxx", 0)
	w("Photos/._beach.jpg", "xx", 0)
	w("Photos/beach.jpg", "jpeg", 0)
	w("Downloads/movie.mkv.part", "partial", 48*time.Hour)
	w("Downloads/now.crdownload", "still coming", 0)
	w("Docs/empty.txt", "", 0)
	w("Docs/Icon\r", "", 0)
	os.MkdirAll(filepath.Join(root, "Old/Nested/Deeper"), 0o755)
	w("Thumbs.db", "t", 0)

	got := map[string]string{}
	for _, j := range FindJunk(root, nil) {
		rel, _ := filepath.Rel(root, j.Path)
		got[rel] = j.Why
	}
	want := map[string]string{
		"Photos/.DS_Store": "system", "Photos/._beach.jpg": "system", "Thumbs.db": "system",
		"Downloads/movie.mkv.part": "partial", "Docs/empty.txt": "empty_file",
		"Old/Nested/Deeper": "empty_folder", "Old/Nested": "empty_folder", "Old": "empty_folder",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s: got %q, want %q", k, got[k], v)
		}
	}
	for _, k := range []string{"Photos/beach.jpg", "Downloads/now.crdownload", "Docs/Icon\r", "Photos", "Docs"} {
		if _, ok := got[k]; ok {
			t.Errorf("%s offered as junk", k)
		}
	}
}
