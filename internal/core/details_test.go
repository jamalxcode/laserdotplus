package core

import (
	"path/filepath"
	"testing"
)

// The details panel: a video's tracks and a data file's columns, read on request.
func TestDetailsDescribeAFile(t *testing.T) {
	base, _ := filepath.EvalSymlinks(t.TempDir())
	writeAged(t, filepath.Join(base, "trip.mp4"), corpus(t, "h264_4k.mp4"))
	writeAged(t, filepath.Join(base, "sales.csv"), []byte("region,amount\nnorth,1\n"))
	ld, _ := Open(filepath.Join(base, "i.db"))
	defer ld.Close()
	d, err := ld.Details(filepath.Join(base, "trip.mp4"))
	if err != nil || d.Kind != "video" {
		t.Fatalf("%v %+v", err, d)
	}
	has := func(d *FileDetails, section, key, value string) bool {
		for _, s := range d.Sections {
			for _, r := range s.Rows {
				if s.ID == section && r.Key == key && (value == "" || r.Value == value) {
					return true
				}
			}
		}
		return false
	}
	if !has(d, "video", "video.codec", "h264") || !has(d, "general", "general.dimensions", "3840 × 2160") || !has(d, "audio", "audio.codec", "") {
		t.Errorf("%+v", d.Sections)
	}
	d, _ = ld.Details(filepath.Join(base, "sales.csv"))
	if !has(d, "data", "data.column", "region  ·  text") || !has(d, "data", "data.rows", "1") {
		t.Errorf("%+v", d.Sections)
	}
	// Every file and folder: its dates, first.
	if !has(d, "dates", "dates.modified", "") || d.Sections[0].ID != "dates" {
		t.Errorf("dates: %+v", d.Sections)
	}
	if f, _ := ld.Details(base); f == nil || !has(f, "dates", "dates.modified", "") {
		t.Errorf("a folder's dates: %+v", f)
	}
}
