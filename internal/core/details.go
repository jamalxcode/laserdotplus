package core

// Details (Laserdot+): everything known about one file, for the app's details
// panel, read from its header on request (as indexing reads it) — nothing is
// stored. Sections of key/value rows; the app titles the keys in its language.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jamalxcode/laserdotplus/internal/fold"
	"github.com/jamalxcode/laserdotplus/internal/media"
	"github.com/jamalxcode/laserdotplus/internal/scan"
)

// DetailRow is one fact: a key the app titles ("video.codec") and its value.
type DetailRow struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// DetailSection groups facts: general, video, audio, subtitles, tags, photo, data.
type DetailSection struct {
	ID   string      `json:"id"`
	Rows []DetailRow `json:"rows"`
}

// FileDetails is the details panel's content.
type FileDetails struct {
	Path     string          `json:"path"`
	Name     string          `json:"name"`
	Kind     string          `json:"kind"`
	IsDir    bool            `json:"is_dir"`
	Size     uint64          `json:"size"`
	Modified int64           `json:"modified"`
	Sections []DetailSection `json:"sections"`
}

// Details reads path's header and describes it.
func (ld *Laserdot) Details(path string) (*FileDetails, error) {
	fi, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	ext := media.Extension(fold.Fold(filepath.Base(path)))
	size := uint64(max(fi.Size(), 0))
	kind := media.Classify(ext, fi.IsDir(), size)
	fd := &FileDetails{Path: path, Name: filepath.Base(path), Kind: kind.String(), IsDir: fi.IsDir(), Size: size,
		Modified: fi.ModTime().Unix(), Sections: []DetailSection{}}
	if fi.IsDir() || !media.WantsProbe(kind, ext) {
		fd.Sections = append(fd.Sections, datesSection(path)...)
		return fd, nil
	}
	if st, rec := media.Probe(path, kind, ext, size); st == media.ProbeOK && rec != nil {
		fd.Sections = detailSections(rec)
	}
	fd.Sections = append(datesSection(path), fd.Sections...)
	return fd, nil
}

// datesSection: every date the file carries — created, modified, last opened
// and added to its folder (as macOS records them on the file), and when its
// name or tags last changed. A picture's or video's own date (taken,
// recorded) is in its section. Times are this Mac's local time.
func datesSection(path string) []DetailSection {
	t, err := scan.FileTimes(path)
	if err != nil {
		return nil
	}
	var rows []DetailRow
	add := func(key string, v int64) {
		if v > 0 {
			rows = append(rows, DetailRow{key, time.Unix(v, 0).Local().Format("2006-01-02 15:04")})
		}
	}
	add("dates.created", t.Created)
	add("dates.modified", t.Modified)
	add("dates.opened", t.Opened)
	add("dates.added", t.Added)
	if t.Changed != t.Modified {
		add("dates.changed", t.Changed)
	}
	if len(rows) == 0 {
		return nil
	}
	return []DetailSection{{ID: "dates", Rows: rows}}
}

func detailSections(r *media.Record) []DetailSection {
	out := []DetailSection{} // never null: the app reads an empty list
	add := func(id string, rows []DetailRow) {
		if len(rows) > 0 {
			out = append(out, DetailSection{ID: id, Rows: rows})
		}
	}
	row := func(rows *[]DetailRow, key, value string) {
		if v := strings.TrimSpace(value); v != "" && v != "0" {
			*rows = append(*rows, DetailRow{key, v})
		}
	}
	var general []DetailRow
	row(&general, "general.container", r.Container)
	if r.DurationMS > 0 {
		row(&general, "general.duration", clock(r.DurationMS))
	}
	if r.Width > 0 && r.Height > 0 {
		row(&general, "general.dimensions", fmt.Sprintf("%d × %d", r.Width, r.Height))
	}
	if r.Bitrate > 0 {
		row(&general, "general.bitrate", rate(r.Bitrate))
	}
	if r.VFR {
		row(&general, "general.vfr", "yes")
	}
	add("general", general)
	for _, t := range r.TracksOf(media.TrackVideo) {
		var v []DetailRow
		row(&v, "video.codec", t.Codec)
		row(&v, "video.profile", t.Profile)
		if t.Width > 0 {
			row(&v, "video.resolution", fmt.Sprintf("%d × %d", t.Width, t.Height))
		}
		if t.FPSMilli > 0 {
			row(&v, "video.fps", strings.TrimSuffix(strings.TrimRight(fmt.Sprintf("%.3f", float64(t.FPSMilli)/1000), "0"), "."))
		}
		if t.BitDepth > 0 {
			row(&v, "video.bitDepth", fmt.Sprintf("%d-bit", t.BitDepth))
		}
		row(&v, "video.pixFmt", t.PixFmt)
		row(&v, "video.hdr", hdrName(t.HDR, t.DVProfile))
		if t.Bitrate > 0 {
			row(&v, "video.bitrate", rate(t.Bitrate))
		}
		add("video", v)
	}
	for _, t := range r.TracksOf(media.TrackAudio) {
		var a []DetailRow
		row(&a, "audio.codec", t.Codec)
		row(&a, "audio.language", t.Lang)
		row(&a, "audio.channels", channels(t.Channels))
		if t.SampleRate > 0 {
			row(&a, "audio.sampleRate", fmt.Sprintf("%.1f kHz", float64(t.SampleRate)/1000))
		}
		if t.Atmos {
			row(&a, "audio.atmos", "yes")
		}
		if t.Lossless {
			row(&a, "audio.lossless", "yes")
		}
		if t.Bitrate > 0 {
			row(&a, "audio.bitrate", rate(t.Bitrate))
		}
		add("audio", a)
	}
	var subs []DetailRow
	for _, t := range r.TracksOf(media.TrackSubtitle) {
		v := strings.TrimSpace(t.Lang + " " + t.Codec)
		if t.Forced {
			v += " (forced)"
		}
		row(&subs, "subtitles.track", v)
	}
	add("subtitles", subs)
	var tags []DetailRow
	row(&tags, "tags.title", r.Tags.Title)
	row(&tags, "tags.artist", r.Tags.Artist)
	row(&tags, "tags.album", r.Tags.Album)
	row(&tags, "tags.genre", r.Tags.Genre)
	if r.Tags.Year > 0 {
		row(&tags, "tags.year", fmt.Sprint(r.Tags.Year))
	}
	row(&tags, "tags.description", r.Tags.Description)
	row(&tags, "tags.author", r.Tags.Author)
	row(&tags, "tags.copyright", r.Tags.Copyright)
	row(&tags, "tags.software", r.Tags.Software)
	if r.Tags.Chapters > 0 {
		row(&tags, "tags.chapters", fmt.Sprint(r.Tags.Chapters))
	}
	add("tags", tags)
	if e := r.Exif; e != nil {
		var p []DetailRow
		row(&p, "photo.camera", e.Camera)
		row(&p, "photo.lens", e.Lens)
		if e.ISO > 0 {
			row(&p, "photo.iso", fmt.Sprint(e.ISO))
		}
		if e.Aperture > 0 {
			row(&p, "photo.aperture", fmt.Sprintf("f/%.1f", e.Aperture))
		}
		if e.Focal > 0 {
			row(&p, "photo.focal", fmt.Sprintf("%.0f mm", e.Focal))
		}
		if e.HasTaken {
			row(&p, "photo.taken", time.Unix(e.Taken, 0).UTC().Format("2006-01-02 15:04"))
		}
		if e.GPS && (e.Lat != 0 || e.Lon != 0) {
			row(&p, "photo.location", fmt.Sprintf("%.5f, %.5f", e.Lat, e.Lon))
		}
		if e.Screenshot {
			row(&p, "photo.screenshot", "yes")
		}
		add("photo", p)
	}
	if d := r.Data; d != nil {
		var rows []DetailRow
		n := fmt.Sprint(d.Rows)
		if !d.RowsExact {
			n = "≈ " + n
		}
		row(&rows, "data.rows", n)
		row(&rows, "data.columnCount", fmt.Sprint(len(d.Columns)))
		for i, c := range d.Columns {
			if i >= 40 {
				row(&rows, "data.more", fmt.Sprintf("+%d", len(d.Columns)-40))
				break
			}
			t := ""
			if i < len(d.Types) {
				t = d.Types[i]
			}
			rows = append(rows, DetailRow{"data.column", strings.TrimSpace(c + "  ·  " + t)})
		}
		add("data", rows)
	}
	return out
}

func clock(ms uint64) string {
	s := ms / 1000
	if s >= 3600 {
		return fmt.Sprintf("%d:%02d:%02d", s/3600, s/60%60, s%60)
	}
	return fmt.Sprintf("%d:%02d", s/60, s%60)
}

func rate(bps uint32) string {
	if bps >= 1_000_000 {
		return fmt.Sprintf("%.1f Mbps", float64(bps)/1e6)
	}
	return fmt.Sprintf("%d kbps", bps/1000)
}

func channels(n uint8) string {
	switch n {
	case 0:
		return ""
	case 1:
		return "mono"
	case 2:
		return "stereo"
	case 6:
		return "5.1"
	case 8:
		return "7.1"
	}
	return fmt.Sprint(n)
}

func hdrName(h, dv uint8) string {
	var parts []string
	if h&media.HDRDV != 0 {
		if dv > 0 {
			parts = append(parts, fmt.Sprintf("Dolby Vision (profile %d)", dv))
		} else {
			parts = append(parts, "Dolby Vision")
		}
	}
	if h&media.HDRHDR10Plus != 0 {
		parts = append(parts, "HDR10+")
	} else if h&media.HDRHDR10 != 0 {
		parts = append(parts, "HDR10")
	}
	if h&media.HDRHLG != 0 {
		parts = append(parts, "HLG")
	}
	return strings.Join(parts, ", ")
}
