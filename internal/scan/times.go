package scan

import "os"

// Times: the dates a file carries (0: not recorded). The details panel shows
// them (the owner: "add time attributes, like last opened, date created, and
// related time that is recorded"). Read for one file when asked, never while
// indexing: no extra work per file.
type Times struct {
	Created  int64 // birth time
	Modified int64 // contents last changed
	Changed  int64 // name, permissions or tags last changed (ctime)
	Opened   int64 // last opened, as macOS records it on the file
	Added    int64 // put in its folder (moved or copied there), macOS
}

// FileTimes reads path's dates (without following a symlink).
func FileTimes(path string) (Times, error) {
	fi, err := os.Lstat(path)
	if err != nil {
		return Times{}, err
	}
	t := Times{Modified: fi.ModTime().Unix()}
	st := statOf(path, fi)
	if st.created > 0 {
		t.Created = st.created
	}
	t.Changed = changedOf(fi)
	t.Opened, t.Added = platformTimes(path)
	return t, nil
}
