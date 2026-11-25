# How Laserdot+ works now

- **Engine:** `laserdotd` (Go), started by the app and bundled in it; it denies itself the network before anything
  else and is the only writer of each index. This Mac's index: `~/Library/Application Support/laserdotplus/index.db`
  (the home folder is indexed on first use). A drive's index: `/Volumes/<drive>/.laserdot/` (read-only drives: on
  this Mac until the drive leaves).
- **Privacy in the engine:** duplicate fingerprints are kept only for this Mac's files (a drive's are computed per
  scan, in memory); files opened on a drive are not recorded; the crash log and the engine's messages have paths
  replaced by `<path>`; the app keeps the engine's messages in memory only.
- **Drives:** the app asks for the list every 3 s on its own connection; a writable drive with no index starts
  indexing by itself (not an installer disk image); read-only, locked and detached drives show what they need.
- **Search:** the toolbar's words, plus the place (`volume:local` or `volume:"<drive>"`), plus each filter group's
  ticks joined with OR; with nothing typed, every file (`-kind:folder`). Results come 500 at a time; the engine sorts.
- **Filters:** the engine's `refine` answer for the current search (kind, type, size, date, resolution, length,
  codec, camera, place, artist, author, columns…), each value with its count.
- **Details:** the engine's `details` call reads the file's header on request and returns sections of key/value
  rows; nothing is stored. Videos get a 12-frame storyboard (macOS's reader, else the bundled ffmpeg).
- **Pictures:** icons from the file's type (no disk read); thumbnails through ImageIO / PDFKit / video frames, three
  at a time, newest first, only for rows on screen 0.2 s; kept in memory.
- **Actions:** Open, Show in Finder, Copy Path, Quick Look (Space, ⌘Y), Move to Trash (⌫, ⌘⌫) with Undo (⌘Z).
