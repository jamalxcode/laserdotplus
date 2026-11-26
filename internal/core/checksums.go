package core

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/jamalxcode/laserdotplus/internal/media"
)

// Protection against bit rot (the owner chose it): a drive's files are read
// once and a list of their contents' hashes is kept on that drive
// (`.laserdot/checksums.bin`; nothing of it on this Mac). Later, Check for
// Damage reads them again: a file whose size and date are the same but whose
// contents differ was damaged on the drive (an edited file has a new date
// and is only counted as changed). Saving resumes where it stopped (files
// already listed and unchanged are skipped); the list carries its own hash,
// so a damaged list is noticed rather than trusted.

const checksumsFile = "checksums.bin"

var checksumsMagic = []byte("LDPLUSCK1\n")

type checksumEntry struct {
	size  uint64
	mtime int64
	hash  [32]byte
}

// ChecksumProgress: the running save or check.
type ChecksumProgress struct {
	Running bool   `json:"running"`
	Phase   string `json:"phase"` // saving, checking
	Done    uint64 `json:"done"`
	Total   uint64 `json:"total"`
	Bytes   uint64 `json:"bytes"`
	Current string `json:"current"`
}

// ChecksumStatus: what a drive's list holds.
type ChecksumStatus struct {
	Exists  bool   `json:"exists"`
	Files   uint64 `json:"files"`
	SavedAt int64  `json:"saved_at"`
	// Unlisted: files on the drive not in the list yet (new since).
	Unlisted uint64 `json:"unlisted"`
}

// ChecksumReport: the outcome of a save or a check.
type ChecksumReport struct {
	Files   uint64   `json:"files"`   // listed (save) or checked (check)
	Read    uint64   `json:"read"`    // read now
	Damaged []string `json:"damaged"` // same size and date, different contents
	Missing []string `json:"missing"`
	Changed uint64   `json:"changed"` // edited since (new date): not damage
	Stopped bool     `json:"stopped"`
	MS      uint64   `json:"ms"`
}

type checksumState struct {
	mu   sync.Mutex
	prog ChecksumProgress
	stop atomic.Bool
}

func checksumsPath(d *drive) string { return filepath.Join(d.dir, checksumsFile) }

func loadChecksums(path string) (map[string]checksumEntry, int64, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, err
	}
	if len(b) < len(checksumsMagic)+8+32 || !bytes.HasPrefix(b, checksumsMagic) {
		return nil, 0, errors.New("not a checksum list")
	}
	body, sum := b[:len(b)-32], b[len(b)-32:]
	if s := sha256.Sum256(body); !bytes.Equal(s[:], sum) {
		return nil, 0, errors.New("the checksum list itself is damaged")
	}
	saved := int64(binary.LittleEndian.Uint64(body[len(checksumsMagic):]))
	r := bufio.NewReader(bytes.NewReader(body[len(checksumsMagic)+8:]))
	m := map[string]checksumEntry{}
	for {
		n, err := binary.ReadUvarint(r)
		if err != nil {
			return m, saved, nil
		}
		if n > 4096 {
			return nil, 0, errors.New("bad checksum list")
		}
		rel := make([]byte, n)
		if _, err := io.ReadFull(r, rel); err != nil {
			return nil, 0, errors.New("bad checksum list")
		}
		var e checksumEntry
		if e.size, err = binary.ReadUvarint(r); err != nil {
			return nil, 0, errors.New("bad checksum list")
		}
		if e.mtime, err = binary.ReadVarint(r); err != nil {
			return nil, 0, errors.New("bad checksum list")
		}
		if _, err := io.ReadFull(r, e.hash[:]); err != nil {
			return nil, 0, errors.New("bad checksum list")
		}
		m[string(rel)] = e
	}
}

func saveChecksums(path string, m map[string]checksumEntry) error {
	var buf bytes.Buffer
	buf.Write(checksumsMagic)
	buf.Write(binary.LittleEndian.AppendUint64(nil, uint64(time.Now().Unix())))
	var tmp [binary.MaxVarintLen64]byte
	for rel, e := range m {
		buf.Write(tmp[:binary.PutUvarint(tmp[:], uint64(len(rel)))])
		buf.WriteString(rel)
		buf.Write(tmp[:binary.PutUvarint(tmp[:], e.size)])
		buf.Write(tmp[:binary.PutVarint(tmp[:], e.mtime)])
		buf.Write(e.hash[:])
	}
	sum := sha256.Sum256(buf.Bytes())
	buf.Write(sum[:])
	t := path + ".tmp"
	if err := os.WriteFile(t, buf.Bytes(), 0o600); err != nil {
		return err
	}
	if err := os.Rename(t, path); err != nil {
		os.Remove(t)
		return err
	}
	return nil
}

// checksumDrive: the drive at mount, if its list can be kept on it (an
// encrypted drive's names would be written in clear: none).
func (ld *Laserdot) checksumDrive(mount string) (*drive, error) {
	ld.mu.RLock()
	d := ld.driveAt(mount)
	ld.mu.RUnlock()
	if d == nil {
		return nil, fmt.Errorf("%s is not an indexed drive", mount)
	}
	if !d.holdsDrive() {
		return nil, errors.New("this drive's index is not kept on it (encrypted or read-only): no checksum list")
	}
	return d, nil
}

// driveFiles: the drive's files now (path on the drive, size, date).
func (ld *Laserdot) driveFiles(d *drive) map[string]checksumEntry {
	ld.mu.RLock()
	defer ld.mu.RUnlock()
	out := map[string]checksumEntry{}
	s := d.store
	it := s.Live().Iterator()
	for it.HasNext() {
		id := it.Next()
		if s.IsDir(id) || s.IsSymlink(id) || s.IsDataless(id) || s.IsRoot(id) {
			continue
		}
		rel, err := filepath.Rel(d.mount, s.Path(id))
		if err != nil {
			continue
		}
		out[rel] = checksumEntry{size: s.Size(id), mtime: s.Modified(id)}
	}
	return out
}

func (ld *Laserdot) ckProgress(f func(p *ChecksumProgress)) {
	ld.ck.mu.Lock()
	f(&ld.ck.prog)
	ld.ck.mu.Unlock()
}

// ChecksumProgress: the running save or check (Running false: none).
func (ld *Laserdot) ChecksumProgress() ChecksumProgress {
	ld.ck.mu.Lock()
	defer ld.ck.mu.Unlock()
	return ld.ck.prog
}

// StopChecksums ends the running save or check early (a save keeps what it read).
func (ld *Laserdot) StopChecksums() { ld.ck.stop.Store(true) }

// ChecksumStatus says whether the drive has a list, how many files it holds,
// when it was saved and how many files are not in it yet.
func (ld *Laserdot) ChecksumStatus(mount string) (ChecksumStatus, error) {
	d, err := ld.checksumDrive(mount)
	if err != nil {
		return ChecksumStatus{}, err
	}
	m, saved, err := loadChecksums(checksumsPath(d))
	if err != nil {
		return ChecksumStatus{}, nil // none yet (or unreadable: saving makes a new one)
	}
	st := ChecksumStatus{Exists: true, Files: uint64(len(m)), SavedAt: saved}
	for rel, f := range ld.driveFiles(d) {
		if e, ok := m[rel]; !ok || e.size != f.size || e.mtime != f.mtime {
			st.Unlisted++
		}
	}
	return st, nil
}

// SaveChecksums reads the drive's files not listed yet (or changed since) and
// writes the list on the drive, every minute and at the end.
func (ld *Laserdot) SaveChecksums(mount string) (ChecksumReport, error) {
	d, err := ld.checksumDrive(mount)
	if err != nil {
		return ChecksumReport{}, err
	}
	start := time.Now()
	path := checksumsPath(d)
	old, _, _ := loadChecksums(path)
	files := ld.driveFiles(d)
	list := map[string]checksumEntry{}
	var todo []string
	for rel, f := range files {
		if e, ok := old[rel]; ok && e.size == f.size && e.mtime == f.mtime {
			list[rel] = e
		} else {
			todo = append(todo, rel)
		}
	}
	ld.ck.stop.Store(false)
	ld.ckProgress(func(p *ChecksumProgress) {
		*p = ChecksumProgress{Running: true, Phase: "saving", Total: uint64(len(todo))}
	})
	defer ld.ckProgress(func(p *ChecksumProgress) { *p = ChecksumProgress{} })
	rep := ChecksumReport{Damaged: []string{}, Missing: []string{}}
	lastSave := time.Now()
	for i, rel := range todo {
		if ld.ck.stop.Load() || ld.released(d.mount) {
			rep.Stopped = true
			break
		}
		p := filepath.Join(d.mount, rel)
		ld.ckProgress(func(pr *ChecksumProgress) { pr.Done, pr.Current = uint64(i), p })
		h, err := media.FullHash(p)
		if err != nil {
			continue // unreadable now: listed on a later save
		}
		list[rel] = checksumEntry{size: files[rel].size, mtime: files[rel].mtime, hash: h}
		rep.Read++
		ld.ckProgress(func(pr *ChecksumProgress) { pr.Bytes += files[rel].size })
		if time.Since(lastSave) > time.Minute {
			_ = saveChecksums(path, list)
			lastSave = time.Now()
		}
	}
	if err := saveChecksums(path, list); err != nil {
		return rep, err
	}
	rep.Files = uint64(len(list))
	rep.MS = uint64(time.Since(start).Milliseconds())
	return rep, nil
}

// CheckChecksums reads the listed files again and reports damage: same size
// and date, different contents. Missing and edited files are counted apart.
func (ld *Laserdot) CheckChecksums(mount string) (ChecksumReport, error) {
	d, err := ld.checksumDrive(mount)
	if err != nil {
		return ChecksumReport{}, err
	}
	start := time.Now()
	list, _, err := loadChecksums(checksumsPath(d))
	if err != nil {
		return ChecksumReport{}, fmt.Errorf("no checksum list on this drive (%v): save one first", err)
	}
	ld.ck.stop.Store(false)
	ld.ckProgress(func(p *ChecksumProgress) {
		*p = ChecksumProgress{Running: true, Phase: "checking", Total: uint64(len(list))}
	})
	defer ld.ckProgress(func(p *ChecksumProgress) { *p = ChecksumProgress{} })
	rep := ChecksumReport{Damaged: []string{}, Missing: []string{}}
	i := 0
	for rel, e := range list {
		if ld.ck.stop.Load() || ld.released(d.mount) {
			rep.Stopped = true
			break
		}
		p := filepath.Join(d.mount, rel)
		ld.ckProgress(func(pr *ChecksumProgress) { pr.Done, pr.Current = uint64(i), p })
		i++
		fi, err := os.Stat(p)
		if err != nil {
			rep.Missing = append(rep.Missing, p)
			continue
		}
		rep.Files++
		if uint64(fi.Size()) != e.size || fi.ModTime().Unix() != e.mtime {
			rep.Changed++
			continue
		}
		h, err := media.FullHash(p)
		if err != nil {
			rep.Damaged = append(rep.Damaged, p) // listed and unchanged, but cannot be read: damage too
			continue
		}
		rep.Read++
		ld.ckProgress(func(pr *ChecksumProgress) { pr.Bytes += e.size })
		if h != e.hash {
			rep.Damaged = append(rep.Damaged, p)
		}
	}
	rep.MS = uint64(time.Since(start).Milliseconds())
	return rep, nil
}
