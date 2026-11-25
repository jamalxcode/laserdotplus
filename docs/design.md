# Laserdot+ — design

A Mac app with one window for reviewing a large collection of files on whatever drives are plugged in: see quickly
what a file is when its name doesn't say, clear out junk, remove duplicates to save space. No menu-bar icon, no
global hotkey: it opens and quits like any app. Built on Laserdot's engine (`jamalxcode/laserdot-go`).

## Ground rules

1. **Privacy:** what the app knows about a drive's files stays on that drive (below).
2. **No network, no AI.** One exception, asked for by the owner: updates. The bundled helper asks github.com for the
   latest release's version (on request, or daily — on by default) and, on Install and Relaunch, downloads that
   release's disk image from GitHub, checks it, puts the old copy in the Trash, moves the new one in and reopens.
   Nothing about the user or their files is sent; the app and the engine have no network code.
3. **Never deletes:** everything goes to the Trash or a folder, after a preview, with Undo.
4. **Never waits on a disk:** a sleeping or slow drive never freezes the window. Nor on the engine: a slow request has a
   connection of its own, and status is asked one request at a time; opening one drive's index never waits for
   another index's work.
5. **Only what's plugged in:** a drive appears when connected and disappears when ejected.

## Privacy

1. Each drive keeps everything about itself on itself, in `.laserdot` at its top: the index of names and details,
   thumbnails and frames (later phases), duplicate fingerprints (later phases), histories, saved views, settings.
2. This Mac's own disk works the same way: its index is on this Mac's disk, in the app's own folder.
3. Nothing about files is written anywhere else: logs carry no names or paths; no search history, recent files or
   window contents are kept; the app's settings hold only the view mode, sort and thumbnail size.
4. Thumbnails are made by the app (ImageIO, PDFKit, macOS's video reader, the bundled ffmpeg) and kept in memory:
   macOS's Quick Look thumbnails would be kept in a system cache on this Mac.
5. Read-only drives can't hold an index: theirs is kept on this Mac only until the drive is ejected, then deleted.
   They are indexed only when asked.
6. Optional passphrase per drive (the engine's encrypted drive index).
7. What the app can't control: opening a file in another app may add it to that app's or macOS's Recent lists.

## The window

Centred on the files (the owner: "the focus to be on the files being reviewed and looked at and arranged, with other
functions surrounding it"): a few lines at the top to search, the files in the middle, a slim right pane with the
preview and details, a bottom margin about the selected file; the top area and the right pane are resizable.

Over the files, as in Laserdot: the places band (everything plugged in, This Mac, each drive with its state; right-
click a drive to eject, index or unlock it) and Laserdot's compact choice bands (every choice the current files have, with counts; several in a group mean any of them;
chosen ones — and the chosen drive — are pills in the search box) · the files (a list with
sortable columns, or thumbnails; videos flip under the pointer) · the details panel (a large preview, a 12-frame
storyboard for videos, and everything read from the file: tracks, languages, subtitles, chapters, HDR, camera, GPS,
author, the app that made it, a data file's columns). Search box in the toolbar (plain words or the engine's
filters: `res:4k`, `kind:video since:30d`…). Click, ⌘-click, ⇧-click select; right-click acts on the selection.

## Status

- 0.1.0: Phase 1 complete; from Phase 2 the contact sheet, timeline, review mode and the clean-up tray (brought
  forward from Phase 3, since review mode feeds it).
- Next: folder covers, tabs, places (GPS groups), saved views (on their drive); then Phase 3.

## Phases

1. **The window** (0.1): sidebar with places, drives and filters; list and thumbnails; details panel with storyboard;
   Open, Show in Finder, Copy Path, Quick Look, Move to Trash with Undo; drives indexed by themselves; the privacy rules.
2. **Review:** contact sheet, timeline, places (GPS groups), folder covers, review mode (← → with keep/trash/move
   keys into a tray), saved views and tabs (stored on their drive).
3. **Clean-up:** junk finder, names that say nothing + suggested names from the file's details, smarter duplicates
   (whole folders, the same film in several qualities, photo bursts, songs), the clean-up tray (dry run, one
   confirmation, one Undo).
