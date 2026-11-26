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
  Move Copies to Trash runs `cleanupPreview` (dry run, an alert with count and bytes) then `cleanup` (to the Trash);
  moved copies leave the panel. The self-test finds the fixtures' one picture at four sizes.
- **The window (0.1.10):** `TopArea` = search row, `PlacesBar` (a plain strip), and `ChoiceBands` in a scroll view
  whose height follows the bands' measured height (max 260); then the files and `DetailsView` side by side, with
  Review/Duplicates overlaid on both. Nothing selected → `PlaceSummary` (engine counts only). `friendlyPath` /
  `placeParts` turn paths into "Drive › …" / "Home › …"; `FolderCover` asks the engine for four pictures in a folder.
- **Calm choices** (`RefineLogic.compact`): the technical groups (`software`, `column`, `rows`, `codec`, `hdr`,
  `chapters`) show only under More choices.
