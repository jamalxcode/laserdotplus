//go:build !darwin

package scan

import (
	"os"
	"syscall"
)

func changedOf(fi os.FileInfo) int64 {
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		return st.Ctim.Sec
	}
	return 0
}

// platformTimes: macOS only.
func platformTimes(string) (opened, added int64) { return 0, 0 }
