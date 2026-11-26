package core

import (
	"slices"
	"strings"

	"github.com/RoaringBitmap/roaring/v2"
	"github.com/jamalxcode/laserdotplus/internal/media"
	"github.com/jamalxcode/laserdotplus/internal/query"
)

// BrokenItem: a picture, video or song that cannot be what it claims (the
// owner chose "find broken files"): empty, a header that cannot be read, a
// video without a picture, or a video or song without a length (often cut
// short by a copy that stopped). Found from the index alone — no file is read.
type BrokenItem struct {
	Path   string  `json:"path"`
	Size   uint64  `json:"size"`
	Why    string  `json:"why"` // empty, unreadable, no_picture, no_length
	Volume *string `json:"volume,omitempty"`
}

// Broken lists the broken media in scope (a search, "" everything), biggest
// first.
func (ld *Laserdot) Broken(scopeQuery string) ([]BrokenItem, error) {
	var scope *query.Compiled
	if strings.TrimSpace(scopeQuery) != "" {
		pq, err := query.Parse(scopeQuery)
		if err != nil {
			return nil, err
		}
		if scope, err = query.Compile(pq, false); err != nil {
			return nil, err
		}
	}
	ld.mu.RLock()
	defer ld.mu.RUnlock()
	out := []BrokenItem{}
	for n := 0; n <= len(ld.drives); n++ {
		s := ld.store
		var volume *string
		if n > 0 {
			d := ld.drives[n-1]
			s, volume = d.store, &d.name
		}
		var ids *roaring.Bitmap
		if scope != nil {
			var err error
			if ids, err = s.Execute(scope); err != nil {
				continue
			}
		} else {
			ids = s.Live()
		}
		it := ids.Iterator()
		for it.HasNext() {
			id := it.Next()
			if s.IsDir(id) || s.IsSymlink(id) || s.IsDataless(id) || s.IsPending(id) {
				continue
			}
			kind := s.Kind(id)
			if kind != media.Video && kind != media.Audio && kind != media.Image {
				continue
			}
			ext := media.Extension(s.FoldedName(id))
			why := ""
			switch q, has := s.Quality(id); {
			case s.Size(id) == 0:
				why = "empty"
			case !media.WantsProbe(kind, ext):
				continue // a format Laserdot+ does not read: nothing to say
			case !has:
				why = "unreadable"
			case kind == media.Video && !q.HasVideo:
				why = "no_picture"
			case (kind == media.Video || kind == media.Audio) && q.DurationMS == 0:
				why = "no_length"
			default:
				continue
			}
			out = append(out, BrokenItem{Path: s.Path(id), Size: s.Size(id), Why: why, Volume: volume})
		}
	}
	slices.SortFunc(out, func(a, b BrokenItem) int {
		if a.Size != b.Size {
			if a.Size > b.Size {
				return -1
			}
			return 1
		}
		return strings.Compare(a.Path, b.Path)
	})
	return out, nil
}
