package core

import (
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
