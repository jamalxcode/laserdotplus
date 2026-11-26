package core

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Bit rot: the list is kept on the drive; a file whose contents change while
// its size and date stay the same is damaged; an edited file is only
// changed; a removed one is missing. Saving again reads only what is new.
func TestChecksumsFindDamage(t *testing.T) {
	m := newMac(t)
	drive := makeDrive(t, m.vols, "archive")
	for _, n := range []string{"a.bin", "b.bin", "c.bin"} {
		writeAged(t, filepath.Join(drive, "Keep", n), []byte("original contents of "+n))
	}
	if _, err := m.ld.CreateDriveIndex(drive, DriveOptions{}); err != nil {
		t.Fatal(err)
	}
	rep, err := m.ld.SaveChecksums(drive)
	if err != nil || rep.Files != 27 || rep.Read != 27 { // the test drive's 24 files and these 3
		t.Fatalf("%v %+v", err, rep)
	}
	if _, err := os.Stat(filepath.Join(drive, ".laserdot", checksumsFile)); err != nil {
		t.Fatal("the list is not on the drive")
	}
	if again, _ := m.ld.SaveChecksums(drive); again.Read != 0 {
		t.Errorf("read %d again", again.Read)
	}
	// a.bin rots: same size, same date, one byte different.
	a := filepath.Join(drive, "Keep", "a.bin")
	fi, _ := os.Stat(a)
	b, _ := os.ReadFile(a)
	b[0] ^= 1
	os.WriteFile(a, b, 0o644)
	os.Chtimes(a, fi.ModTime(), fi.ModTime())
	// b.bin is edited (new date); c.bin is removed.
	bb := filepath.Join(drive, "Keep", "b.bin")
	os.WriteFile(bb, []byte("edited"), 0o644)
	os.Chtimes(bb, time.Now(), time.Now())
	os.Remove(filepath.Join(drive, "Keep", "c.bin"))
	chk, err := m.ld.CheckChecksums(drive)
	if err != nil || len(chk.Damaged) != 1 || filepath.Base(chk.Damaged[0]) != "a.bin" || chk.Changed != 1 || len(chk.Missing) != 1 {
		t.Errorf("%v %+v", err, chk)
	}
	if p := m.ld.ChecksumProgress(); p.Running {
		t.Error("still running")
	}
}
