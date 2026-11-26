package core

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jamalxcode/laserdotplus/internal/scan"
)

// JunkItem is a file or folder nobody needs: a system bookkeeping file
// (.DS_Store, ._name, Thumbs.db…), a download left unfinished, an empty file
// or an empty folder. Found by walking the folder (they are never indexed).
type JunkItem struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
	// Why: system, partial, empty_file, empty_folder.
	Why string `json:"why"`
}

// Not offered as junk: they carry something the user sees (a folder's
// custom icon, a drive's icon, a folder's localized name).
var keepJunk = map[string]bool{"icon\r": true, ".volumeicon.icns": true, ".localized": true}

// Folders a walk for junk never enters: the system's and Laserdot's own.
var junkSkipDirs = map[string]bool{
	".laserdot": true, ".trashes": true, ".spotlight-v100": true, ".fseventsd": true, ".temporaryitems": true,
	".documentrevisions-v100": true, ".mobilebackups": true, ".trash": true,
}

var homeLibrary = func() string { h, _ := os.UserHomeDir(); return filepath.Join(h, "Library") }()

// FindJunk walks root and lists the junk in it, biggest first (an empty
// folder after its contents: deepest first). A download is unfinished only
// when untouched for a day (one still in progress is left alone). stop, when
// it answers true, ends the walk early with what was found.
func FindJunk(root string, stop func() bool) []JunkItem {
	var out []JunkItem
	nonEmpty := map[string]bool{} // folders holding something that is not junk
	var dirs []string
	dayAgo := time.Now().Add(-24 * time.Hour)
	_ = filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if stop != nil && stop() {
			return filepath.SkipAll
		}
		name := d.Name()
		lower := strings.ToLower(name)
		if d.IsDir() {
			if p != root && (junkSkipDirs[lower] || p == homeLibrary) {
				nonEmpty[filepath.Dir(p)] = true
				return filepath.SkipDir
			}
			if p != root && scan.IsHiddenPackage(name, scan.DefaultOptions()) {
				nonEmpty[filepath.Dir(p)] = true // an app or a photo library: opaque
				return filepath.SkipDir
			}
			dirs = append(dirs, p)
			return nil
		}
		info, err := d.Info()
		if err != nil {
			nonEmpty[filepath.Dir(p)] = true
			return nil
		}
		switch {
		case keepJunk[lower]:
			nonEmpty[filepath.Dir(p)] = true
		case scan.IsSystemJunk(name):
			out = append(out, JunkItem{p, info.Size(), "system"})
		case scan.IsPartialDownload(name) && info.ModTime().Before(dayAgo):
			out = append(out, JunkItem{p, info.Size(), "partial"})
		case info.Size() == 0 && info.Mode().IsRegular() && !strings.HasPrefix(name, "."):
			out = append(out, JunkItem{p, 0, "empty_file"})
		default:
			nonEmpty[filepath.Dir(p)] = true
		}
		return nil
	})
	// Empty folders: deepest first, so a folder whose only content is empty
	// folders is empty too. The root itself is never offered.
	sort.Slice(dirs, func(i, j int) bool { return len(dirs[i]) > len(dirs[j]) })
	for _, d := range dirs {
		if d == root {
			continue
		}
		if nonEmpty[d] {
			nonEmpty[filepath.Dir(d)] = true
			continue
		}
		out = append(out, JunkItem{d, 0, "empty_folder"})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Size > out[j].Size })
	return out
}

// Junk lists the junk in the folders of a place: a drive's mount, or (for
// "") every attached drive and this Mac's indexed folders.
func (ld *Laserdot) Junk(root string) ([]JunkItem, error) {
	roots := []string{root}
	if root == "" {
		roots = nil
		if rs, err := ld.Roots(); err == nil {
			for _, r := range rs {
				roots = append(roots, r.Path)
			}
		}
		ld.mu.RLock()
		for _, d := range ld.drives {
			roots = append(roots, d.mount)
		}
		ld.mu.RUnlock()
	}
	var out []JunkItem
	for _, r := range roots {
		if fi, err := os.Stat(r); err == nil && fi.IsDir() {
			out = append(out, FindJunk(r, nil)...)
		}
	}
	return out, nil
}
