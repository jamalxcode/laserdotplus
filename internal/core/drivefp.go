package core

import (
	"bufio"
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/jamalxcode/laserdotplus/internal/index"
)

// A drive's duplicate fingerprints are kept on that drive (the owner: a scan
// of a big drive took 20 minutes every time; privacy allows what is known
// about a drive's files to stay on the drive): `.laserdot/fingerprints.bin`,
// next to its index. A second scan of the drive then reads only new or
// changed files, and a scan that was stopped or quit goes on where it was.
//
// The drive is untrusted (any drive can be plugged in), and a forged hash
// could make a different file look like a copy. So the file is signed with
// a key that only this Mac holds (`fingerprint.key` beside this Mac's index;
// 32 random bytes, which say nothing about any file): a file this Mac did not
// write — another Mac's, a damaged or forged one — is ignored and the files
// are read again. Encrypted drives keep none (the file is not encrypted).

// driveFPFile: the file of the Mac whose key is key — one per Mac, so two
// Macs using the same drive do not overwrite each other's work. (0.1.19 wrote
// one "fingerprints.bin"; it is read once if this Mac signed it, then left.)
func driveFPFile(key []byte) string {
	sum := sha256.Sum256(append([]byte("laserdotplus-fp-file"), key...))
	return fmt.Sprintf("fingerprints-%x.bin", sum[:6])
}

const legacyDriveFPFile = "fingerprints.bin"

// driveFPSaveEvery: while a scan runs, the file is written at most this
// often (a rewrite of a big drive's file over USB is not free); and always
// at the end.
const driveFPSaveEvery = time.Minute

var driveFPMagic = []byte("LDPLUSFP1\n")

// fpKey: this Mac's signing key, made on first use.
func (ld *Laserdot) fpKey() []byte {
	ld.fpKeyOnce.Do(func() {
		p := filepath.Join(filepath.Dir(ld.dbPath), "fingerprint.key")
		if b, err := os.ReadFile(p); err == nil && len(b) == 32 {
			ld.fpKeyBytes = b
			return
		}
		b := make([]byte, 32)
		if _, err := rand.Read(b); err != nil {
			return
		}
		tmp := p + ".tmp"
		if os.WriteFile(tmp, b, 0o600) == nil && os.Rename(tmp, p) == nil {
			ld.fpKeyBytes = b
		}
	})
	return ld.fpKeyBytes
}

// driveFPs: the fingerprints of one drive's files, by path relative to the
// drive, as read from (and written back to) its file.
type driveFPs struct {
	mu    sync.Mutex
	dir   string
	key   []byte
	m     map[string]index.Fingerprint
	dirty bool
	saved time.Time
}

func loadDriveFPs(dir string, key []byte) *driveFPs {
	d := &driveFPs{dir: dir, key: key, m: map[string]index.Fingerprint{}}
	if len(key) != 32 {
		return d
	}
	d.saved = time.Now()
	b, err := os.ReadFile(filepath.Join(dir, driveFPFile(key)))
	if err != nil {
		b, err = os.ReadFile(filepath.Join(dir, legacyDriveFPFile))
	}
	if err != nil || len(b) < len(driveFPMagic)+32 || !bytes.HasPrefix(b, driveFPMagic) {
		return d
	}
	body, sum := b[:len(b)-32], b[len(b)-32:]
	mac := hmac.New(sha256.New, key)
	mac.Write(body)
	if !hmac.Equal(mac.Sum(nil), sum) {
		return d // not written by this Mac: read the files again
	}
	if m, err := decodeDriveFPs(body[len(driveFPMagic):]); err == nil {
		d.m = m
	}
	return d
}

func (d *driveFPs) get(rel string, size uint64, mtime int64) (index.Fingerprint, bool) {
	d.mu.Lock()
	defer d.mu.Unlock()
	f, ok := d.m[rel]
	if !ok || f.Size != size || f.Modified != mtime {
		return index.Fingerprint{}, false
	}
	return f, true
}

func (d *driveFPs) put(rel string, f index.Fingerprint) {
	d.mu.Lock()
	d.m[rel] = f
	d.dirty = true
	d.mu.Unlock()
}

// saveIfDue: save, if the last save was a while ago.
func (d *driveFPs) saveIfDue() error {
	d.mu.Lock()
	due := time.Since(d.saved) >= driveFPSaveEvery
	d.mu.Unlock()
	if !due {
		return nil
	}
	return d.save()
}

// save writes the file again (to a temporary file, then renamed) when
// something changed. A read-only drive just keeps nothing.
func (d *driveFPs) save() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.dirty || len(d.key) != 32 {
		return nil
	}
	d.saved = time.Now()
	var buf bytes.Buffer
	buf.Write(driveFPMagic)
	encodeDriveFPs(&buf, d.m)
	mac := hmac.New(sha256.New, d.key)
	mac.Write(buf.Bytes())
	buf.Write(mac.Sum(nil))
	p := filepath.Join(d.dir, driveFPFile(d.key))
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, buf.Bytes(), 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, p); err != nil {
		os.Remove(tmp)
		return err
	}
	d.dirty = false
	return nil
}

const (
	fpHasQuick = 1 << iota
	fpHasFull
	fpHasImage
	fpHasFrames
)

func encodeDriveFPs(w *bytes.Buffer, m map[string]index.Fingerprint) {
	var tmp [binary.MaxVarintLen64]byte
	uv := func(v uint64) { w.Write(tmp[:binary.PutUvarint(tmp[:], v)]) }
	for rel, f := range m {
		uv(uint64(len(rel)))
		w.WriteString(rel)
		uv(f.Size)
		w.Write(tmp[:binary.PutVarint(tmp[:], f.Modified)])
		var has byte
		if f.Quick != nil {
			has |= fpHasQuick
		}
		if f.Full != nil {
			has |= fpHasFull
		}
		if f.Image != nil {
			has |= fpHasImage
		}
		if f.Frames != nil {
			has |= fpHasFrames
		}
		w.WriteByte(has)
		w.WriteByte(f.Flags)
		if f.Quick != nil {
			w.Write(f.Quick[:])
		}
		if f.Full != nil {
			w.Write(f.Full[:])
		}
		if f.Image != nil {
			w.Write(binary.LittleEndian.AppendUint64(nil, *f.Image))
		}
		if f.Frames != nil {
			for _, h := range f.Frames {
				w.Write(binary.LittleEndian.AppendUint64(nil, h))
			}
			w.WriteByte(f.Flat)
		}
	}
}

var errBadFP = errors.New("bad fingerprint file")

func decodeDriveFPs(b []byte) (map[string]index.Fingerprint, error) {
	r := bufio.NewReader(bytes.NewReader(b))
	m := map[string]index.Fingerprint{}
	full := func(n int) ([]byte, error) {
		out := make([]byte, n)
		if _, err := io.ReadFull(r, out); err != nil {
			return nil, errBadFP
		}
		return out, nil
	}
	for {
		n, err := binary.ReadUvarint(r)
		if err != nil {
			return m, nil // the end
		}
		if n > 4096 {
			return nil, errBadFP
		}
		rel, err := full(int(n))
		if err != nil {
			return nil, err
		}
		var f index.Fingerprint
		if f.Size, err = binary.ReadUvarint(r); err != nil {
			return nil, errBadFP
		}
		if f.Modified, err = binary.ReadVarint(r); err != nil {
			return nil, errBadFP
		}
		hf, err := full(2)
		if err != nil {
			return nil, err
		}
		has := hf[0]
		f.Flags = hf[1]
		if has&fpHasQuick != 0 {
			q, err := full(32)
			if err != nil {
				return nil, err
			}
			f.Quick = (*[32]byte)(q)
		}
		if has&fpHasFull != 0 {
			q, err := full(32)
			if err != nil {
				return nil, err
			}
			f.Full = (*[32]byte)(q)
		}
		if has&fpHasImage != 0 {
			q, err := full(8)
			if err != nil {
				return nil, err
			}
			v := binary.LittleEndian.Uint64(q)
			f.Image = &v
		}
		if has&fpHasFrames != 0 {
			q, err := full(25)
			if err != nil {
				return nil, err
			}
			var h [3]uint64
			for i := range h {
				h[i] = binary.LittleEndian.Uint64(q[i*8:])
			}
			f.Frames, f.Flat = &h, q[24]
		}
		m[string(rel)] = f
	}
}
