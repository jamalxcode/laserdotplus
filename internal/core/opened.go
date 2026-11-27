package core

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/jamalxcode/laserdotplus/internal/scan"
)

// Last-opened dates, remembered (the critique: sorting a drive by Last Opened
// read every file's date each time). Privacy: a drive's dates are kept on the
// drive (`<drive>/.laserdot/opened.list`, paths relative to the drive); this
// Mac's beside this Mac's index; an encrypted or read-only drive's only in
// memory. A sort answers from what is remembered at once and reads the dates
// again in the background, so a file opened since is right the next time.

const openedListFile = "opened.list"

// maxOpenedPerList bounds one list (an 8 TB drive's matches are far fewer).
const maxOpenedPerList = 500_000

// readOpened reads one file's last-opened date (tests replace it).
var readOpened = func(p string) (int64, error) {
	t, err := scan.FileTimes(p)
	return t.Opened, err
}

type openedDates struct {
	mu         sync.Mutex
	lists      map[string]map[string]int64 // list file ("" in memory only) → stored path → date
	dirty      map[string]bool
	refreshing atomic.Bool
}

type openedPlace struct {
	mount, file string // file "": not written anywhere
}

// openedPlaces: where each drive's dates go, read once under the lock.
func (ld *Laserdot) openedPlaces() []openedPlace {
	ld.mu.RLock()
	defer ld.mu.RUnlock()
	var out []openedPlace
	for _, d := range ld.drives {
		f := ""
		if d.holdsDrive() {
			f = filepath.Join(d.dir, openedListFile)
		}
		out = append(out, openedPlace{d.mount, f})
	}
	return out
}

// openedKey: the list a path's date belongs to and how it is stored there.
func (ld *Laserdot) openedKey(places []openedPlace, p string) (file, stored string) {
	for _, pl := range places {
		if within(p, pl.mount) {
			if pl.file == "" {
				return "", p
			}
			if rel, err := filepath.Rel(pl.mount, p); err == nil {
				return pl.file, rel
			}
			return "", p
		}
	}
	return filepath.Join(filepath.Dir(ld.dbPath), openedListFile), p
}

func (o *openedDates) load(file string) map[string]int64 {
	if o.lists == nil {
		o.lists = map[string]map[string]int64{}
		o.dirty = map[string]bool{}
	}
	if m, ok := o.lists[file]; ok {
		return m
	}
	m := map[string]int64{}
	if file != "" {
		if f, err := os.Open(file); err == nil {
			sc := bufio.NewScanner(f)
			sc.Buffer(make([]byte, 64<<10), 64<<10)
			for sc.Scan() && len(m) < maxOpenedPerList {
				secs, path, ok := strings.Cut(sc.Text(), "\t")
				if !ok || path == "" {
					continue
				}
				if n, err := strconv.ParseInt(secs, 10, 64); err == nil {
					m[path] = n
				}
			}
			f.Close()
		}
	}
	o.lists[file] = m
	return m
}

// openedDatesOf returns each path's last-opened date: remembered ones at
// once, the rest read now. fromMemory: some came from what was remembered.
func (ld *Laserdot) openedDatesOf(paths []string) (dates []int64, ok []bool, fromMemory bool) {
	places := ld.openedPlaces()
	dates = make([]int64, len(paths))
	ok = make([]bool, len(paths))
	var missing []int
	o := &ld.od
	o.mu.Lock()
	for i, p := range paths {
		file, stored := ld.openedKey(places, p)
		if v, had := o.load(file)[stored]; had {
			dates[i], ok[i], fromMemory = v, true, true
		} else {
			missing = append(missing, i)
		}
	}
	o.mu.Unlock()
	read := map[int]int64{}
	for _, i := range missing {
		if v, err := readOpened(paths[i]); err == nil {
			read[i] = v
			dates[i], ok[i] = v, true
		}
	}
	ld.rememberOpened(places, paths, read)
	return dates, ok, fromMemory
}

// rememberOpened stores dates read (index into paths → date) and saves.
func (ld *Laserdot) rememberOpened(places []openedPlace, paths []string, read map[int]int64) {
	if len(read) == 0 {
		return
	}
	o := &ld.od
	o.mu.Lock()
	for i, v := range read {
		if strings.ContainsAny(paths[i], "\n\r\t") {
			continue
		}
		file, stored := ld.openedKey(places, paths[i])
		m := o.load(file)
		if old, had := m[stored]; (!had && len(m) < maxOpenedPerList) || (had && old != v) {
			m[stored] = v
			o.dirty[file] = true
		}
	}
	o.mu.Unlock()
	ld.saveOpened()
}

// refreshOpened reads the dates of paths again in the background (one at a
// time), forgetting files that are gone.
func (ld *Laserdot) refreshOpened(paths []string) {
	o := &ld.od
	if !o.refreshing.CompareAndSwap(false, true) {
		return
	}
	ld.background.Add(1)
	go func() {
		defer ld.background.Done()
		defer o.refreshing.Store(false)
		places := ld.openedPlaces()
		read := map[int]int64{}
		var gone []int
		for i, p := range paths {
			if ld.closing.Load() {
				return
			}
			if v, err := readOpened(p); err == nil {
				read[i] = v
			} else {
				gone = append(gone, i)
			}
		}
		if len(gone) > 0 {
			o.mu.Lock()
			for _, i := range gone {
				file, stored := ld.openedKey(places, paths[i])
				if m := o.load(file); m != nil {
					if _, had := m[stored]; had {
						delete(m, stored)
						o.dirty[file] = true
					}
				}
			}
			o.mu.Unlock()
		}
		ld.rememberOpened(places, paths, read)
		ld.saveOpened()
	}()
}

// saveOpened writes the lists that changed (not the in-memory one).
func (ld *Laserdot) saveOpened() {
	o := &ld.od
	o.mu.Lock()
	defer o.mu.Unlock()
	for file := range o.dirty {
		delete(o.dirty, file)
		if file == "" {
			continue
		}
		var b strings.Builder
		for p, v := range o.lists[file] {
			b.WriteString(strconv.FormatInt(v, 10))
			b.WriteByte('\t')
			b.WriteString(p)
			b.WriteByte('\n')
		}
		tmp := file + ".tmp"
		if os.WriteFile(tmp, []byte(b.String()), 0o600) == nil {
			os.Rename(tmp, file)
		}
	}
}
