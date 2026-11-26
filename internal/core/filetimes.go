package core

import "github.com/jamalxcode/laserdotplus/internal/scan"

// FileTime: one file's dates (Unix seconds; 0 when not recorded).
type FileTime struct {
	Path     string `json:"path"`
	Created  int64  `json:"created"`
	Modified int64  `json:"modified"`
	Opened   int64  `json:"opened"`
	Added    int64  `json:"added"`
}

// MaxFileTimes: paths per request (the rows of a page of results).
const MaxFileTimes = 2000

// FileTimes reads the dates of the given files — last opened as macOS records
// it on the file — for the rows the app shows (the owner: last opened must
// show; Big & Old asks which big files were not opened for years). Read from
// the files when asked, never while indexing. A file that is gone is left out.
func (ld *Laserdot) FileTimes(paths []string) []FileTime {
	if len(paths) > MaxFileTimes {
		paths = paths[:MaxFileTimes]
	}
	out := make([]FileTime, 0, len(paths))
	for _, p := range paths {
		t, err := scan.FileTimes(p)
		if err != nil {
			continue
		}
		out = append(out, FileTime{Path: p, Created: t.Created, Modified: t.Modified, Opened: t.Opened, Added: t.Added})
	}
	return out
}
