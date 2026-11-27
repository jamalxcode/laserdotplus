package core

import (
	"sort"

	"github.com/jamalxcode/laserdotplus/internal/index"
	"github.com/jamalxcode/laserdotplus/internal/scan"
)

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
	read := map[int]int64{}
	for i, p := range paths {
		t, err := scan.FileTimes(p)
		if err != nil {
			continue
		}
		read[i] = t.Opened
		out = append(out, FileTime{Path: p, Created: t.Created, Modified: t.Modified, Opened: t.Opened, Added: t.Added})
	}
	// What was just read is remembered for the next last-opened sort.
	ld.rememberOpened(ld.openedPlaces(), paths, read)
	return out
}

// ByOpenedLimit: how many matches are looked at for a last-opened order (one
// small read each).
const ByOpenedLimit = 50_000

// ByOpened: the matches of q in order of when macOS says each was last opened
// (newest first; reverse: oldest — never opened — first), over the whole
// search, not just a page (the critique: the Last Opened column sorted only
// the rows loaded). One attribute read per match, up to ByOpenedLimit.
func (ld *Laserdot) ByOpened(q string, offset, limit int, reverse bool) (*SearchResults, error) {
	r, err := ld.search(q, SearchOptions{Page: index.Page{Limit: ByOpenedLimit}})
	if err != nil || r == nil {
		return r, err
	}
	paths := make([]string, len(r.Hits))
	for i := range r.Hits {
		paths[i] = r.Hits[i].Path
	}
	// Remembered dates at once (on the drive for a drive); read again in the
	// background so a file opened since is right next time.
	dates, ok, fromMemory := ld.openedDatesOf(paths)
	for i := range r.Hits {
		if ok[i] {
			r.Hits[i].Opened = dates[i]
		}
	}
	if fromMemory {
		ld.refreshOpened(paths)
	}
	sort.SliceStable(r.Hits, func(i, j int) bool {
		if reverse {
			return r.Hits[i].Opened < r.Hits[j].Opened
		}
		return r.Hits[i].Opened > r.Hits[j].Opened
	})
	if offset > len(r.Hits) {
		offset = len(r.Hits)
	}
	end := min(len(r.Hits), offset+max(limit, 1))
	r.Hits = r.Hits[offset:end]
	if r.Total > ByOpenedLimit {
		r.Total = ByOpenedLimit
	}
	return r, nil
}
