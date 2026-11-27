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
- **Following changes:** the engine counts every change it applies (`core.Changes`: files added, removed, moved
  or changed by the watcher — FSEvents on this Mac and on drives — and drives attached or gone) and reports it in
  `status.changes`; the app reads the status every 3 s and searches again when the count moved, keeping the
  selection where it still exists. A file deleted or moved out of the place in Finder leaves the list.
- **Search:** the toolbar's words, plus the place (`volume:local` or `volume:"<drive>"`), plus each filter group's
  ticks joined with OR; with nothing typed, every file (`-kind:folder`). Results come 500 at a time; the engine sorts.
- **Filters:** the engine's `refine` answer for the current search, shown as Laserdot's compact choice bands above
  the files (`ChoiceBands`: one band per family, Okabe–Ito colour and icon; chips with counts in a `FlowLayout`; the
  calm view `RefineLogic.compact`, More choices for the rest). Click narrows (several in a group: OR), ⌥-click leaves
  out (a `-` word); chosen and left-out values are pills in the search box (`FilterPills`), after the chosen place (a drive or
  This Mac, its own pill with a drive icon; ✕ or Clear goes back to everything plugged in).
- **Select All** (status bar, ⌥⌘A): loads the rest of the results (up to 200,000) and selects them — with a drive
  chosen, the whole drive. One file selected: its full path in the status bar.
- **Details:** the engine's `details` call reads the file's header on request and returns sections of key/value
  rows; nothing is stored. Videos get a 12-frame storyboard (macOS's reader, else the bundled ffmpeg).
- **Pictures:** icons from the file's type (no disk read); thumbnails through ImageIO / PDFKit / video frames, three
  at a time, newest first, only for rows on screen 0.2 s; kept in memory.
- **Window** (centred on the files): `VSplitView` of the top area (`TopArea`: the search box, view, size, sort and
  Review on one line, then — scrolling — the places band `PlacesBar` and the choice bands) and an `HSplitView` of the
  files (`FilesArea`) and the slim right pane (`DetailsView`: preview at the pane's width, two-column storyboard,
  small details); under them the clean-up tray when it holds something and the bottom bar (`BottomBar`: the selected
  file's icon, name, kind, size, date, badges and full path; several: count and size; none: count, Select All). Both
  dividers can be dragged. Plain split views, not `NavigationSplitView` (its sidebar does not show in window
  captures). Review mode covers the files area and a toolbar with the place's name, the view picker, Review, the size
  slider, sort and a search box.
- **Views:** list (`Table`, the engine sorts), thumbnails (`LazyVGrid`; videos scrub), contact sheet (eight frames per
  video, `FrameStrip`), timeline (the loaded results by month of their modified date). ⌘1–⌘4.
- **Review mode** (⌘R, `ReviewView`): the results one at a time from the selection; ← → move, Space Quick Look,
  K keep (out of the tray), T trash, M move (into the tray), Esc closes.
- **Clean-up tray** (`LibraryModel.tray`): files marked from review mode or the right-click menu, by action; the bar
  under the files shows how many and how big; Apply confirms once, asks a folder for moves, then trashes and moves
  in one Undo group (moves take a new name when one is taken).
- **Actions:** Open, Show in Finder, Copy Path, Quick Look (Space, ⌘Y), Move to Trash (⌫, ⌘⌫) with Undo (⌘Z); a
  right-click on one of several selected files acts on all of them.
- **Releases:** each release carries `LaserdotPlus-<version>.dmg` and the same image as `LaserdotPlus.dmg`, so the
  README's link `releases/latest/download/LaserdotPlus.dmg` always downloads the newest version.
- **Quitting:** `applicationShouldTerminate` hides the window, asks the engine to stop on a background thread
  (`Engine.shutdown(waitForExit: false)`: the stop request, 2 s at most; no wait for the engine to exit — it saves
  on its own; one that does not answer gets SIGTERM) and then quits. Nothing waits on the main thread.
- **Updates:** Laserdot+ ▸ Check for Updates… (and once a day — at launch or while it stays open, on by default) runs the bundled
  `laserdotplus-update-check`, the only networked code: a HEAD request to github.com's latest-release address, whose
  redirect names the version. A newer version offers **Install and Relaunch**: the helper (`--install v --app path
  --pid n`) downloads `LaserdotPlus-v.dmg` from the release (redirects followed to `*.githubusercontent.com` only),
  checks the app in it has the same bundle id and that version, copies it next to the running app and prints `ready`;
  the app quits, the helper puts the old copy in the Trash, moves the new one in and opens it. Ephemeral session, no
  cookies or cache; nothing about the user or their files is sent. CI checks that no other code uses the network, that
  the helper names no host but github.com, and runs a real download-and-swap against the latest release.
- **Self-test** (CI): indexes fixtures and a mounted test drive, then search, a filter, each view, details, Trash and
  Undo, review mode and the tray, with screenshots; it also checks the drive's index is on the drive and that nothing
  in this Mac's data folder names the drive's file.

- **Drag to select** (`Marquee.swift`): in the grid, contact sheet and timeline a box drawn over the tiles selects
  what it touches, live (⌘/⇧ add); a drag that starts on a selected file drags it out instead.

- **A drive not ready yet** (`DrivesModel.isWaiting`: its index opening, first indexing, or busy) shows an hourglass
  in the places band and in its search-box pill, with what it waits for; the files area says so until its files arrive.
- **Opening a drive's index** (`AttachDrive`) does not take the engine's writer lock (this Mac's first home-folder index
  holds it for minutes): the mount is reserved in `attaching`, listed as `opening`, and a second request returns at
  once. The app sends it on a connection of its own (`Engine.driveAttach`) and asks for status one request at a time,
  so a slow engine never piles up threads or freezes the window.
- **Quitting** hides the window, stops the engine in the background and answers AppKit's "should terminate" through the
  run loop (`performSelector(onMainThread:modes:)`), never `DispatchQueue.main`, which is busy when the quit began in a
  main-queue block. CI samples the app's threads if the self-test has not ended after five minutes.
- **Choices** are arranged by `RefineLogic.arranged`: live values first in each group, live groups first in each band,
  bands with nothing to choose last; a value with no results is drawn as small grey text, not a button.
- **A drive that cannot be opened**: the engine keeps why in memory (`attachErr`) and sends it as the drive's state
  detail; the app shows "Couldn't open its index · click to try again" (reason in the tooltip), not the hourglass.
- **All the choices** (More choices): live values show as chips; a group's values with no results fold into "+N"
  (`ChoiceBands.revealed` unfolds one group); bands with nothing to choose become one line, "Nothing to choose now: …".
- **One engine per index:** `laserdotd` takes an exclusive `flock` on `laserdotd.lock` beside the index (it holds
  its pid) before opening it (`daemon.TakeOver`). An older engine that still holds it — left behind by a force quit or
  an update, not answering on the socket — gets SIGTERM, then SIGKILL; otherwise it would keep drives' indexes open.
- **Stopping the engine** (quit, SIGTERM, the shutdown request) finishes what it is writing; if that hangs it leaves
  after 10 seconds anyway (SQLite WAL keeps everything committed), and a second signal leaves at once.
- **Gone files** (`LibraryModel.dropGone`): every 4 s, off the main thread, the first 1,500 results are checked
  for existence; missing ones leave the list and their folders are sent to the engine (`touched`), which re-lists
  them — a safety net for drives whose file events go missing (exFAT).
- **Releases:** CI's app job builds the universal app with the CHANGELOG's version, runs every check and the
  self-test on it, and keeps that disk image (`release-dmg`); `release.yml` (on Linux) publishes exactly that file —
  no second build, about a minute after the check passes. `app/scripts/release-local.sh` still releases from the
  owner's Mac.
- **Find Duplicates** (`Duplicates.swift`): `engine.findDuplicates(scope: place token, exactOnly: !similar)` on a
  connection of its own; groups show best first with the engine's keep recommendation (at least one copy always kept);
  Move Copies to Trash runs `cleanupPreview` (dry run, an alert with count and bytes), runs it again after the
  answer (each copy still unchanged, not the kept one), then `trashInBackground` moves exactly those with macOS's own
  Trash call (`FileManager.trashItem`, off the main thread) — so they appear in the Finder's Trash, Put Back works and
  ⌘Z brings them back (0.1.17; before, the engine renamed them into the drive's `.Trashes` itself, which the Finder
  did not always show). Moved copies leave the panel. The self-test finds the fixtures' one picture at four sizes.
- **0.1.31:** A keep-selection refresh asks for as many rows as are loaded (up to 20,000). Junk: `scan(roots:)`
  lists `JunkIndexed` only; `deeper: true` adds the walk; finds are merged off the main thread. Dupes presets set
  `minMB`/`similar`. `moveInBackground` publishes `moving` (done/total/drive), checks Stop and the drive before each
  file. Last opened: `openedDates` (internal/core/opened.go) remembers dates per place — `<drive>/.laserdot/opened.list`
  (paths on the drive), this Mac's beside its index, encrypted/read-only drives in memory only; `ByOpened` answers from
  it and re-reads in the background. `ChoicesArea` passes only the open groups to an `Equatable` `ChoiceBands`.
  `TestDriveScale` (LASERDOT_SCALE=300000, CI's Ubuntu job) times index, search, Select All, choices, Junk, Space and
  Last Opened at an 8 TB drive's scale.
- **0.1.30:** `findJunk` returns no empty folders when its walk was stopped. Clean-up lists draw `shownRows`
  (2,000) rows plus a "…and N more" line. `scan.AddJunkHook`: the walk reports each system file / partial download it
  skips; `junkNotes` files them per place (`<drive>/.laserdot/junk.list`, paths on the drive; this Mac's beside its
  index; none for encrypted drives), saved every 30 s; `JunkIndexed` adds those still there (checked with lstat).
- **0.1.29:** `trashSelected` (⌫ in the grids and list, ⌘⌫, the menu and the bottom bar's **Move N to Trash**) uses
  `trashInBackground` for more than one file. `junk_indexed` (engine `JunkIndexed`: empty files, old partial
  downloads, folders with no indexed child) shows at once; the walk adds system files. `by_opened` (engine
  `ByOpened`: up to 50,000 matches, each one's last-opened read, then a page) backs the Last Opened column
  (`openedOrder`) and Big & Old ▸ Not opened. `wait_change` (engine `WaitChange`, 25 s long poll on the change
  counter) drives `watchChanges` → `refreshIfDue` (15 s while indexing, 2 s otherwise, never within 4 s of input).
  Clean Up replaces `FilesArea` (Review stays an overlay); clicking a Clean Up row's name shows it in the inspector
  (`extraSelected`, `inspect`). The self-test's `scale()` step: 40,000 files (half empty) + 5,000 `._` files; index,
  search, Select All, Junk; checks the longest main-thread stall (< 2 s, `FreezeWatch.takeLongest`) and memory
  (< 1.5 GB).
- **0.1.28:** picture caches are limited by bytes (`pictureCache`, `cachePut` with pixel cost; 120 MB thumbnails,
  120 MB frames, 20 MB icons). Rows call `model.reached(h)` on appear; the last 40 rows load the next page (one at a
  time). `applyTray` uses `trashInBackground` then `moveInBackground`. `activeView` highlights a saved view until the
  words, choices or place change. `FreezeWatch`: a thread pings the main queue every 0.5 s; a wait over 2 s is noted
  (time, seconds, the step last set with `FreezeWatch.mark`) in this Mac's preferences, shown with the version and
  memory in Help ▸ Report a Problem…; `takeLongest()` gives the self-test the longest stall. Update rhythm:
  `Updates.rhythm` (hourly/daily/weekly/off). Signing: with `DEVELOPER_ID` set (CI imports the `DEVELOPER_ID_P12` /
  `DEVELOPER_ID_PASSWORD` secrets), `bundle.sh` signs each piece with the hardened runtime; with `NOTARY_KEY_P8`,
  `NOTARY_KEY_ID`, `NOTARY_ISSUER`, `make-dmg.sh` notarizes and staples the disk image. Without them: ad hoc, as before.
- **Big lists (0.1.27):** published sets, dictionaries and arrays (`chosen`, `keep`, `tray`, `results`) are built
  aside and assigned once — never mutated per item in a loop (each mutation copies the whole collection and
  redraws). `junk_found` takes an offset and returns only new finds (`from`, `total`); removals use a `Set`; clean-up
  lists trash with `trashInBackground`.
- **Calm while indexing (0.1.26):** `refreshStatus` re-runs the search for index changes at most every 15 s and only
  after 4 s without input (`LibraryModel.lastInput`, a local event monitor); `apply` sets `results` once; `Place.mount`
  reads `Place.mounts` (filled from the drive list) instead of the file system. The sidebar shows a spinner beside a
  drive that is indexing or opening, and the subtitle adds "indexing…".
- **Integrity (0.1.25):** `Broken` (engine, from the index: media that is empty, has no record, a video with no
  video track, or no duration); `UnwantedModel` (searches: clips <3 s, height <240, bitrate <300 kbps, screenshots,
  pictures under 160×160 — `internal/query/unwanted_test.go` keeps them valid). Checksums (`checksums.go`):
  `<drive>/.laserdot/checksums.bin` = magic, saved-at, entries (path on the drive, size, mtime, full hash), then a
  SHA-256 of all that; `checksum_save` reads only new or changed files (resumable, saved every minute),
  `checksum_check` re-reads: same size+mtime and a different hash (or unreadable) = damaged; progress and stop like
  junk. About This Drive (`DriveInfo.swift`, a sheet) shows facts, `DriveHistory` (`<drive>/.laserdot/history.json`:
  a snapshot a day, freed bytes per clean-up; Swift Charts; months until full from the last 183 days) and the
  checksum controls.
- **The window (0.1.23):** `NavigationSplitView`: `Sidebar` (places, drives with state/fullness/eject and drops that
  move files there via `moveInBackground`, the place's saved views, the tools) | the detail (`TopArea` = search box +
  choice bands, `FilesArea` with Review/Clean Up as overlays, tray, bottom bar), with `.inspector` = `DetailsView`
  (hidden while an overlay shows; `showInspector` remembered) and `MainToolbar` (view, size, sort, tools, inspector).
  `.navigationSubtitle` = place — count. Empty screens use `ContentUnavailableView`. A folder dropped on the files
  is indexed. Menus: `FileCommands` (Open ⌘O, Open With ▸, Get Info ⌘I, Rename…, Quick Look ⌘Y, Show in Finder ⇧⌘R,
  Copy Path ⌥⌘C, Move to Trash ⌘⌫ — in a text field it deletes to the line's start —, Index a Folder ⇧⌘I), Tools
  (⌘E, ⌘R, ⇧⌘D/J/B/S), View (⌘1–4, ⌥⌘I); `SettingsView` (⌘,) holds update checks, the inspector, and Duplicates' and
  Big & Old's defaults (UserDefaults). The right-click menu (`FileMenu`) follows Finder's order with `OpenWithMenu`.
  The place is remembered only as Everything / This Mac (never a drive's name). `Place.mount(of:)` finds a drive's
  real mount (a namesake is at `/Volumes/<name> 1`). Keys in `MouseCatcherView` and the delete command do nothing
  while Review or Clean Up covers the files.
- **Live results (0.1.22):** junk: `findJunk` reports each find and folder to `ld.junk` (`JunkProgress`); the app
  polls `junk_found` every second on its own connection and stops with `junk_stop`; Move to Trash waits for the end
  or Stop. Duplicates: `compute` calls `run.tick` about once a second from the loop that records reads; during the
  exact pass it publishes `soFar` (same size+samples = likely, same full hash = exact); files are read biggest first.
- **Last opened (0.1.22):** `file_times` (paths → created/modified/opened/added, read from the files, ≤2000 a
  request); the list fills `Hit.opened` for each loaded page (Last Opened column, sorted locally); Big & Old ▸ Not
  opened reads the candidates' dates and keeps those older than the cut-off (no record = never opened).
- **Compare (0.1.22):** `CompareView` sheet per group (frames for videos, pictures otherwise), Keep/Trash per copy,
  Quick Look over the group. Keep/Trash colours are Okabe–Ito blue/vermillion.
- **Messages (0.1.22):** `notice` fades after 8 s; `trouble` (moves that failed, a failed rename) stays with ✕.
  What's New (`WhatsNew.swift`, the bundled CHANGELOG via `Changelog` in LaserdotKit, unit-tested) shows once per new
  version; Help ▸ Keyboard Shortcuts (⌘/); ⌘F focuses the search box.
- **Drive fingerprints (0.1.22):** `fingerprints-<id>.bin`, the id derived from this Mac's key (one file per Mac;
  0.1.19's `fingerprints.bin` is read once); written at most once a minute during a scan (`saveIfDue`), always at
  the end. `TestEachMacKeepsItsOwnFingerprintFile`; `TestManyFilesStayQuick` (20,000 files: index, Space, dates,
  two duplicate scans, with time budgets). The self-test also clicks through the window (`clickThroughWindow`).
- **Dates in the pane (0.1.21):** `facts` shows them under the name (from the `dates` section once read, the hit's
  dates before); Last opened / Added read "Not recorded" when absent; the `dates` section is not repeated below.
  Labels are `.callout` semibold, section titles `.headline`. The bottom bar labels Modified, Created and Opened.
- **Dates (0.1.20):** `scan.FileTimes` reads, for one file when its details are asked: birth time, mtime, ctime,
  last opened (`com.apple.lastuseddate#PS`, macOS) and date added (`getattrlist` `ATTR_CMN_ADDEDTIME` through
  purego). `Details` puts them first as the `dates` section (local time). Never read while indexing (no cost per
  file); atime is not shown (the indexer's own header reads change it). The list has a Date Created column.
- **Space (0.1.20, `SpaceView.swift`):** Clean Up's fourth tab (Tools ▸ Where Is My Space?, ⇧⌘S) uses the engine's
  `storage` op (sizes from the index): the place's folders by size, click to go in, Up to go back.
- **Keep rules (0.1.20):** `DupesModel.apply(.best/.oldest/.newest/.inFolder)` sets one kept copy per group;
  `protect(folder)` keeps every copy in a folder (and `toggle` won't untick them). `minMB >= 1000` unticks Similar.
- **Drive Trash (0.1.20, `DriveTrash.swift`):** sums `<drive>/.Trashes/<uid>` off the main thread (refreshed after
  a clean-up) and offers Open Trash (Finder's); Laserdot+ never empties it.
- **Saved views (0.1.20, `SavedViews.swift`):** words, choices and labels as JSON — a drive's in
  `<drive>/.laserdot/views.json`, This Mac's and Everything's beside this Mac's index; a view outside a drive that
  names a drive (`/Volumes/…`, `volume:`) is refused. The self-test saves one on the test drive and checks this Mac.
- **Rename All (0.1.20):** reads each unclear file's details, previews old → new, renames off the main thread, one
  Undo. Arrow keys in `MouseCatcherView.move`; `DrivesModel` times "opening its index".
- **Drive fingerprints (0.1.19, `internal/core/drivefp.go`):** a drive's duplicate fingerprints are kept in
  `<drive>/.laserdot/fingerprints.bin` (not in its index, whose schema is whitelisted): a binary list (path on the
  drive, size, mtime, hashes) closed by an HMAC-SHA256 with this Mac's key (`fingerprint.key` beside this Mac's
  index, 32 random bytes). A file that fails the check is ignored (re-read), so a forged hash can't make a file look
  like a copy. Saved as the scan goes (every `saveEvery`) and at the end, by temp file + rename; read-only and
  encrypted drives keep none. `TestDriveFingerprintsStayOnTheDrive`.
- **Opening files (0.1.19):** `open` uses `NSWorkspace.OpenConfiguration.addsToRecentItems = false` (no  ▸ Recent
  Items entry); Laserdot+'s own recent documents are cleared at launch and quit. A double click opens the file the
  first click was on (`lastClick`); the details pane has `layoutPriority(-1)` and a flexible frame so it never
  pushes the split.
- **Clicking and the selection box (0.1.18, `Marquee.swift`):** one AppKit view (`MouseCatcherView`) laid over a
  picture view's tiles takes the left button's events (its `hitTest` lets right-clicks, control-clicks, hovering and
  "Load more" through): click, ⌘-click, ⇧-click from an anchor file, double click opens, a drag from empty space or
  an unselected tile draws the box (live, autoscrolling), a drag from a selected tile starts a file drag of the whole
  selection (copy, outside the app). Once clicked it is first responder: ⌫/⌦ trash, Return opens, Space Quick Look.
  It replaced SwiftUI tap gestures, which read the modifier keys late and lost clicks because a tile's view changed
  type when selected (`onDrag` added). `runSearch` waits while the mouse button is down. The self-test sends real
  mouse events to it (click, ⌘-click twice, a drag).
- **Colours (0.1.17, `Palette.swift`):** colour-blind-safe Okabe–Ito, always with an icon beside them. Places
  (Everything, This Mac, drives) are blue: the chosen one filled, the others' icons and fullness bars blue. Kind and
  Type chips wear their kind's colour and icon (`TintedChipStyle`: light fill, border, normal text) — videos
  vermillion, pictures bluish green, sound reddish purple, documents sky blue, folders orange, archives yellow, the
  rest grey; a file type's kind comes from macOS (`UTType`, "mp4" → video). Pills in the search box take the same
  colours. The self-test checks the six colours differ and the types' kinds. The search box has a 2 pt dark frame
  (`primary` at 55%), 2.5 pt places-blue while focused.
- **Review keeps its file selected:** a search landing while Review or What Is This? is open re-selects the file on
  screen (`runSearch`), so its details and suggested name still come.
- **The window (0.1.10):** `TopArea` = search row, `PlacesBar` (a plain strip), and `ChoiceBands` in a scroll view
  whose height follows the bands' measured height (max 260); then the files and `DetailsView` side by side, with
  Review/Duplicates overlaid on both. Nothing selected → `PlaceSummary` (engine counts only). `friendlyPath` /
  `placeParts` turn paths into "Drive › …" / "Home › …"; `FolderCover` asks the engine for four pictures in a folder.
- **Calm choices** (`RefineLogic.compact`): the technical groups (`software`, `column`, `rows`, `codec`, `hdr`,
  `chapters`) show only under More choices.
- **Real-drive tests:** the self-test's drive is an exFAT disk image (like most portable drives): it is indexed by
  itself, a file deleted on it outside the app must leave the list, and its file names must not appear on this Mac.
  Engine tests cover a second engine taking over, a drive pulled out while attached, and opening a drive while this
  Mac's index holds the writer lock.
- **What Is This?** (`LibraryModel.startSweep`): `sweep` holds the listed files with unclear names; review mode walks
  `reviewItems` (the sweep, else the results). `suggestedName` builds a name from the selected file's details;
  `rename` moves it within its folder (a free name; undoable) and tells the engine.
- **UI pass 2:** `ModeHeader` (shared by the covering modes), the Tools menu in `TopArea`, drive fullness bars in
  `PlacesBar`. The self-test shoots `dark.png` (NSApp in dark aqua). English only for now (the owner's call).
- **Duplicates' size limit:** `DupesModel.minMB` (default 100, remembered) adds `fsize:>NNmb` / `fsize:>Ngb` to the
  place's token in the scope given to `findDuplicates`; smaller files are never read.
- **Clean Up** (`Cleanup.swift`): tabs Duplicates (`DupesModel`), Junk (`JunkModel` → engine `junk` op →
  `core.FindJunk`, a walk of the drive's mount / this Mac's roots / every place) and Big & old (`BigOldModel`, a search
  `fsize:>… before:…y -kind:folder`). Chosen files go through `trashPaths` (Trash, undoable) after an alert.
- **Progress and drive health:** `LibraryModel.indexingText` (percent from the engine's done/total, time left from
  the rate since the run began); `DrivesModel.showInfo` (About This Drive); `DrivesModel.notAnswering` when a drives
  request has been out for 12 s.
- **Live duplicates:** `FindDuplicates` stores the groups found so far in `dupeFound` — `likely` groups (same size
  and quick hash) right after the quick pass, then `groupsOf` after the exact and image passes; `dupes_found` returns
  them. The panel polls it and `status.dupes` (step, done/total, current file) every 1.2 s, with Stop (`dupes_stop`).
