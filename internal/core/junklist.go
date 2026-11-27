package core

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/jamalxcode/laserdotplus/internal/scan"
)

// The junk files indexing leaves out (system files like .DS_Store and ._…,
// unfinished downloads) are noted as the walk passes them, so Clean Up Junk
// lists them at once instead of walking the drive again (the owner chose it).
// A drive's list is kept on the drive (`.laserdot/junk.list`, paths on the
// drive) — never on this Mac; this Mac's own in its data folder. Encrypted
// drives keep none (the list would name files in clear). Entries are checked
// when listed: one that is gone is dropped.
type junkNotes struct {
	mu      sync.Mutex
	pending []string
	lists   map[string]map[string]struct{} // list file -> paths as stored
	dirty   map[string]bool
	unhook  func()
	stop    chan struct{}
}

const junkListFile = "junk.list"

func (ld *Laserdot) startJunkNotes() {
	j := &ld.jn
	j.lists = map[string]map[string]struct{}{}
	j.dirty = map[string]bool{}
	j.stop = make(chan struct{})
	j.unhook = scan.AddJunkHook(func(p string) {
		j.mu.Lock()
		if len(j.pending) < 2_000_000 {
			j.pending = append(j.pending, p)
		}
		j.mu.Unlock()
	})
	go func() {
		t := time.NewTicker(30 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-t.C:
				ld.flushJunkNotes()
			case <-j.stop:
				return
			}
		}
	}()
}

func (ld *Laserdot) stopJunkNotes() {
	if ld.jn.unhook != nil { // Close may be called twice
		ld.jn.unhook()
		ld.jn.unhook = nil
		close(ld.jn.stop)
		ld.flushJunkNotes()
	}
}

// junkOwner: the list file a path belongs to and how it is stored there.
func (ld *Laserdot) junkOwner(p string) (file, stored string, ok bool) {
	for _, d := range ld.drives {
		if within(p, d.mount) {
			if !d.holdsDrive() {
				return "", "", false
			}
			rel, err := filepath.Rel(d.mount, p)
			if err != nil {
				return "", "", false
			}
			return filepath.Join(d.dir, junkListFile), rel, true
		}
	}
	return filepath.Join(filepath.Dir(ld.dbPath), junkListFile), p, true
}

func (j *junkNotes) load(file string) map[string]struct{} {
	if m, ok := j.lists[file]; ok {
		return m
	}
	m := map[string]struct{}{}
	if f, err := os.Open(file); err == nil {
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 64<<10), 64<<10)
		for sc.Scan() {
			if l := sc.Text(); l != "" {
				m[l] = struct{}{}
			}
		}
		f.Close()
	}
	j.lists[file] = m
	return m
}

// flushJunkNotes files the noted paths into their lists and writes the lists
// that changed (temp file + rename; a read-only drive keeps none).
func (ld *Laserdot) flushJunkNotes() {
	j := &ld.jn
	j.mu.Lock()
	pending := j.pending
	j.pending = nil
	j.mu.Unlock()
	if len(pending) > 0 {
		ld.mu.RLock()
		j.mu.Lock()
		for _, p := range pending {
			if strings.ContainsAny(p, "\n\r") {
				continue
			}
			if file, stored, ok := ld.junkOwner(p); ok {
				m := j.load(file)
				if _, had := m[stored]; !had {
					m[stored] = struct{}{}
					j.dirty[file] = true
				}
			}
		}
		j.mu.Unlock()
		ld.mu.RUnlock()
	}
	j.mu.Lock()
	defer j.mu.Unlock()
	for file := range j.dirty {
		var b strings.Builder
		for p := range j.lists[file] {
			b.WriteString(p)
			b.WriteByte('\n')
		}
		tmp := file + ".tmp"
		if os.WriteFile(tmp, []byte(b.String()), 0o600) == nil {
			os.Rename(tmp, file)
		}
		delete(j.dirty, file)
	}
}

// notedJunk: the noted junk under root ("" everywhere) that is still there.
func (ld *Laserdot) notedJunk(root string) []JunkItem {
	ld.flushJunkNotes()
	ld.mu.RLock()
	type src struct {
		file, base string
	}
	var srcs []src
	for _, d := range ld.drives {
		if d.holdsDrive() {
			srcs = append(srcs, src{filepath.Join(d.dir, junkListFile), d.mount})
		}
	}
	srcs = append(srcs, src{filepath.Join(filepath.Dir(ld.dbPath), junkListFile), ""})
	ld.mu.RUnlock()
	dayAgo := time.Now().Add(-24 * time.Hour)
	out := []JunkItem{}
	j := &ld.jn
	j.mu.Lock()
	defer j.mu.Unlock()
	for _, s := range srcs {
		m := j.load(s.file)
		for stored := range m {
			p := stored
			if s.base != "" {
				p = filepath.Join(s.base, stored)
			}
			if root != "" && !within(p, root) {
				continue
			}
			fi, err := os.Lstat(p)
			if err != nil {
				delete(m, stored) // gone
				j.dirty[s.file] = true
				continue
			}
			name := filepath.Base(p)
			why := "system"
			if !scan.IsSystemJunk(name) {
				if fi.ModTime().After(dayAgo) {
					continue // a download still in progress
				}
				why = "partial"
			}
			out = append(out, JunkItem{p, fi.Size(), why})
		}
	}
	return out
}
