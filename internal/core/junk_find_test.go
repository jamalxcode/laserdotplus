package core

import (
	"fmt"
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

// The walk reports each find as it goes (the app shows them at once), and how
// far it has got; the engine's progress is empty once it is done.
func TestJunkShowsAsItIsFound(t *testing.T) {
	root := t.TempDir()
	for _, rel := range []string{"A/.DS_Store", "B/.DS_Store", "C/Thumbs.db"} {
		p := filepath.Join(root, rel)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte("x"), 0o644)
	}
	var seen []string
	var folders int
	all := findJunk(root, nil, &junkWatch{
		found: func(j JunkItem) { seen = append(seen, j.Path) },
		dir:   func(string) { folders++ },
	})
	if len(seen) != len(all) || len(seen) != 6 || folders < 3 { // 3 files + their 3 folders (junk only)
		t.Errorf("seen %d of %d, %d folders", len(seen), len(all), folders)
	}
	base, _ := filepath.EvalSymlinks(t.TempDir())
	ld, _ := Open(filepath.Join(base, "i.db"))
	defer ld.Close()
	if items, _ := ld.Junk(root); len(items) != 6 || ld.JunkFound(0).Running {
		t.Errorf("%d items, running %v", len(items), ld.JunkFound(0).Running)
	}
}

// The app asks only for the finds it has not seen yet.
func TestJunkFoundSendsOnlyWhatIsNew(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	ld, _ := Open(filepath.Join(base, "i.db"))
	defer ld.Close()
	ld.junk = JunkProgress{Running: true, Items: []JunkItem{{"/a", 1, "system"}, {"/b", 1, "system"}, {"/c", 1, "system"}}}
	p := ld.JunkFound(2)
	if p.Total != 3 || p.From != 2 || len(p.Items) != 1 || p.Items[0].Path != "/c" {
		t.Errorf("%+v", p)
	}
	if p := ld.JunkFound(9); len(p.Items) != 0 || p.From != 3 {
		t.Errorf("%+v", p)
	}
}

// The index already knows empty files and empty folders: listed at once.
func TestJunkFromTheIndex(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	root := filepath.Join(base, "home")
	writeAged(t, filepath.Join(root, "Docs/empty.txt"), nil)
	writeAged(t, filepath.Join(root, "Docs/real.txt"), []byte("kept"))
	os.MkdirAll(filepath.Join(root, "Old/Nested"), 0o755)
	ld, _ := Open(filepath.Join(base, "data", "i.db"))
	defer ld.Close()
	if _, err := ld.Index(root); err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, j := range ld.JunkIndexed(root) {
		rel, _ := filepath.Rel(root, j.Path)
		got[rel] = j.Why
	}
	if got["Docs/empty.txt"] != "empty_file" || got["Old/Nested"] != "empty_folder" || got["Docs/real.txt"] != "" || got["Docs"] != "" {
		t.Errorf("%v", got)
	}
}

// The system files and old downloads indexing leaves out are noted as it
// passes them: Junk lists them without walking again; a removed one leaves.
func TestJunkNotedWhileIndexing(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	root := filepath.Join(base, "home")
	writeAged(t, filepath.Join(root, "Photos/.DS_Store"), []byte("x"))
	writeAged(t, filepath.Join(root, "Photos/beach.jpg"), []byte("jpeg"))
	old := filepath.Join(root, "Downloads/film.mkv.part")
	writeAged(t, old, []byte("partial"))
	past(t, old, 48*time.Hour)
	ld, _ := Open(filepath.Join(base, "data", "i.db"))
	defer ld.Close()
	if _, err := ld.Index(root); err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, j := range ld.JunkIndexed(root) {
		rel, _ := filepath.Rel(root, j.Path)
		got[rel] = j.Why
	}
	if got["Photos/.DS_Store"] != "system" || got["Downloads/film.mkv.part"] != "partial" {
		t.Errorf("%v", got)
	}
	os.Remove(filepath.Join(root, "Photos/.DS_Store"))
	for _, j := range ld.JunkIndexed(root) {
		if filepath.Base(j.Path) == ".DS_Store" {
			t.Error("a removed file is still listed")
		}
	}
}

// A stopped walk offers no empty folders: folders it had not finished reading
// would look empty.
func TestAStoppedWalkOffersNoEmptyFolders(t *testing.T) {
	root := t.TempDir()
	for i := 0; i < 50; i++ {
		p := filepath.Join(root, fmt.Sprintf("Films %02d", i), "film.mkv")
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte("a film"), 0o644)
	}
	os.WriteFile(filepath.Join(root, "Films 00", ".DS_Store"), []byte("x"), 0o644)
	n := 0
	stop := func() bool { n++; return n > 10 } // stops partway
	for _, j := range findJunk(root, stop, nil) {
		if j.Why == "empty_folder" {
			t.Errorf("offered %s as empty after a stop", j.Path)
		}
	}
}
