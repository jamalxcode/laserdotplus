package scan

import (
	"encoding/binary"
	"os"
	"sync"
	"syscall"
	"unsafe"

	"github.com/ebitengine/purego"
)

const (
	attrCmnAddedTime    = 0x10000000
	attrCmnReturnedAttr = 0x80000000
	fsoptNoFollow       = 0x00000001
)

var (
	getattrlistOnce sync.Once
	getattrlistCall func(path *byte, list unsafe.Pointer, buf unsafe.Pointer, size uintptr, options uint32) int32
)

func changedOf(fi os.FileInfo) int64 {
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		return st.Ctimespec.Sec
	}
	return 0
}

// platformTimes: last opened (the com.apple.lastuseddate#PS attribute macOS
// writes when a file is opened) and the date added to its folder.
func platformTimes(path string) (opened, added int64) {
	if b, ok := getXattr(path, "com.apple.lastuseddate#PS"); ok && len(b) >= 8 {
		opened = int64(binary.LittleEndian.Uint64(b))
	}
	getattrlistOnce.Do(func() {
		lib, err := purego.Dlopen("/usr/lib/libSystem.B.dylib", purego.RTLD_NOW|purego.RTLD_GLOBAL)
		if err != nil {
			return
		}
		if sym, err := purego.Dlsym(lib, "getattrlist"); err == nil {
			purego.RegisterFunc(&getattrlistCall, sym)
		}
	})
	if getattrlistCall == nil {
		return opened, 0
	}
	p, err := syscall.BytePtrFromString(path)
	if err != nil {
		return opened, 0
	}
	req := attrList{bitmapCount: attrBitMapCount, commonAttr: attrCmnReturnedAttr | attrCmnAddedTime}
	var buf [64]byte
	if getattrlistCall(p, unsafe.Pointer(&req), unsafe.Pointer(&buf[0]), uintptr(len(buf)), fsoptNoFollow) != 0 {
		return opened, 0
	}
	// u32 length, attribute_set_t (5 × u32: which came back), then the time.
	if binary.LittleEndian.Uint32(buf[4:])&attrCmnAddedTime == 0 {
		return opened, 0
	}
	added = int64(binary.LittleEndian.Uint64(buf[24:]))
	return opened, added
}
