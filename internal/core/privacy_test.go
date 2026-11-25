package core

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
)

// Laserdot+'s rule (the owner): "any logs or indexes get placed on the
// actual drive, no mention or record of filenames or metadata … anywhere
// else". A duplicate scan of a drive keeps no fingerprints on this Mac, and
// opening a drive's file leaves no record here.
func TestNothingAboutADriveIsWrittenToThisMac(t *testing.T) {
	m := newMac(t)
	drive := makeDrive(t, m.vols, "plex media")
	// Two identical files on the drive, two on this Mac.
	same := []byte(strings.Repeat("same bytes ", 500))
	writeAged(t, filepath.Join(drive, "Films/a.bin"), same)
	writeAged(t, filepath.Join(drive, "Films/b.bin"), same)
	home := filepath.Join(m.base, "home")
	writeAged(t, filepath.Join(home, "c.bin"), same)
	writeAged(t, filepath.Join(home, "d.bin"), same)
	if _, err := m.ld.Index(home); err != nil {
		t.Fatal(err)
	}
	if _, err := m.ld.CreateDriveIndex(drive, DriveOptions{}); err != nil {
		t.Fatal(err)
	}
	opts := DefaultDupeOptions()
	opts.Images, opts.Videos = false, false
	rep, err := m.ld.FindDuplicates(opts)
	if err != nil || len(rep.Groups) == 0 {
		t.Fatalf("%v %+v", err, rep)
	}
	if err := m.ld.RecordOpen(filepath.Join(drive, "Films/a.bin")); err != nil {
		t.Fatal(err)
	}
	if err := m.ld.RecordOpen(filepath.Join(home, "c.bin")); err != nil {
		t.Fatal(err)
	}
	dbPath := m.ld.DBPath()
	conn, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	var driveKeys, macKeys int
	conn.QueryRow("SELECT count(*) FROM fingerprints WHERE key LIKE 'drive:%'").Scan(&driveKeys)
	conn.QueryRow("SELECT count(*) FROM fingerprints WHERE key NOT LIKE 'drive:%'").Scan(&macKeys)
	if driveKeys != 0 || macKeys == 0 {
		t.Errorf("fingerprints kept on this Mac: %d of the drive's, %d of its own", driveKeys, macKeys)
	}
	var opens string
	conn.QueryRow("SELECT value FROM meta WHERE key = 'opens'").Scan(&opens)
	if strings.Contains(opens, "plex media") || !strings.Contains(opens, "c.bin") {
		t.Errorf("opens on this Mac: %s", opens)
	}
	// And no file of this Mac's index folder names the drive's files.
	filepath.Walk(filepath.Dir(dbPath), func(p string, fi os.FileInfo, err error) error {
		if err != nil || fi.IsDir() || strings.Contains(p, "drives") {
			return nil
		}
		b, _ := os.ReadFile(p)
		if strings.Contains(string(b), "Films/a.bin") {
			t.Errorf("%s names a drive's file", filepath.Base(p))
		}
		return nil
	})
}
