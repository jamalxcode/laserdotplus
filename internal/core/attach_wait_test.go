package core

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Opening a drive's index never waits for this Mac's own indexing, which
// holds the writer lock for minutes on a first home-folder walk (the owner
// saw "Opening its index…" for ever).
func TestOpeningADriveDoesNotWaitForThisMacsIndexing(t *testing.T) {
	m := newMac(t)
	drive := makeDrive(t, m.vols, "T5 EVO")
	if _, err := m.ld.CreateDriveIndex(drive, DriveOptions{}); err != nil {
		t.Fatal(err)
	}
	m.ld.DetachDrive(drive)
	if st := m.ld.Drives()[0].State.State; st != DriveDetached {
		t.Fatalf("state %s", st)
	}

	m.ld.wmu.Lock() // as while this Mac's home folder is being indexed
	defer m.ld.wmu.Unlock()
	done := make(chan error, 1)
	go func() {
		_, err := m.ld.AttachDrive(drive, "")
		done <- err
	}()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("opening the drive waited for this Mac's indexing")
	}
	if st := m.ld.Drives()[0].State.State; st != DriveAttached {
		t.Errorf("state %s", st)
	}
	expect(t, dnames(t, m.ld, "invoice volume:\"t5 evo\""), "invoice-march.pdf")
}

// While a drive's index is being opened it is listed as "opening", and a
// second request returns at once instead of opening it again.
func TestADriveBeingOpenedIsListedAsOpening(t *testing.T) {
	m := newMac(t)
	drive := makeDrive(t, m.vols, "Archive")
	if _, err := m.ld.CreateDriveIndex(drive, DriveOptions{}); err != nil {
		t.Fatal(err)
	}
	m.ld.DetachDrive(drive)
	m.ld.mu.Lock()
	m.ld.attaching[drive] = true
	m.ld.mu.Unlock()
	if st := m.ld.Drives()[0].State.State; st != DriveOpening {
		t.Fatalf("state %s", st)
	}
	start := time.Now()
	info, err := m.ld.AttachDrive(drive, "")
	if err != nil || info.State.State != DriveOpening || time.Since(start) > 5*time.Second {
		t.Fatalf("%+v %v", info.State, err)
	}
	m.ld.mu.Lock()
	delete(m.ld.attaching, drive)
	m.ld.mu.Unlock()
}

// A drive whose index cannot be opened says why, instead of "opening" for
// ever.
func TestADriveThatCannotBeOpenedSaysWhy(t *testing.T) {
	m := newMac(t)
	drive := makeDrive(t, m.vols, "Broken")
	if _, err := m.ld.CreateDriveIndex(drive, DriveOptions{}); err != nil {
		t.Fatal(err)
	}
	m.ld.DetachDrive(drive)
	idx := filepath.Join(drive, ".laserdot", "index.db")
	for _, s := range []string{"-wal", "-shm"} {
		os.Remove(idx + s)
	}
	if err := os.WriteFile(idx, append([]byte("SQLite format 3\x00"), make([]byte, 200)...), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := m.ld.AttachDrive(drive, "")
	if err == nil {
		t.Fatal("a broken index opened")
	}
	st := m.ld.Drives()[0].State
	if st.State != DriveDetached || st.Detail == "" {
		t.Fatalf("%+v", st)
	}
}

// A drive pulled out while attached (no eject): it leaves the list and its
// files leave the results; nothing hangs.
func TestADrivePulledOutLeavesCleanly(t *testing.T) {
	m := newMac(t)
	drive := makeDrive(t, m.vols, "Pulled")
	if _, err := m.ld.CreateDriveIndex(drive, DriveOptions{}); err != nil {
		t.Fatal(err)
	}
	expect(t, dnames(t, m.ld, "invoice volume:pulled"), "invoice-march.pdf")
	done := make(chan []string, 1)
	if err := os.RemoveAll(drive); err != nil { // pulled out
		t.Fatal(err)
	}
	go func() {
		_, gone := m.ld.SyncDrives()
		done <- gone
	}()
	select {
	case gone := <-done:
		if len(gone) != 1 {
			t.Fatalf("gone %v", gone)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("noticing a pulled-out drive hung")
	}
	if n := len(m.ld.Drives()); n != 0 {
		t.Errorf("%d drives listed", n)
	}
	expect(t, dnames(t, m.ld, "invoice volume:pulled"))
}
