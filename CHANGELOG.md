# Changelog

What's new in each version, in plain words. A new `## x.y.z` section is released when CI passes on main.

## 0.1.11

- **What Is This?** (⌘E, or the button by Review) goes through only the files whose names say nothing — IMG_1234,
  VID_20240812_183011, DSC00042, untitled 3, a long id — one at a time, big, with K keep, T trash, M move, and a
  **suggested name** built from the file itself: its date (when the photo was taken), its title or camera, a video's
  resolution and length — "2023-08-14 Apple iPhone 12 Pro 1080p 0m42s.mp4". R (or the button) renames to it;
  Edit ▸ Undo puts the old name back.
- **The test drive is exFAT** (like most portable drives) and every change is checked on it before release: a file
  deleted on it outside Laserdot+ must leave the list, a pulled-out drive must leave cleanly.
- **Calmer choices.** Technical choices — what a file was made with, a data file's columns and rows, codec, HDR,
  chapters — wait under More choices instead of showing by default.

## 0.1.10

A tidier window:

- **The files get the room.** The top area is only as tall as its choices (no empty band above the files), and the
  places — everything plugged in, This Mac, each drive — are a strip of their own instead of looking like a filter.
- **Review and Duplicates use the whole width**, instead of half the window beside an empty pane.
- **The right pane says what's here** when nothing is selected: how many files, how big, what kinds, the biggest
  folders, and the duplicates found, with Find Duplicates one click away.
- **Paths read like Finder's**: "T5 EVO › Movies › 2023 › clip.mp4", "Home › Pictures …" — no system folders.
- **Folders show what's inside** in the grid (up to four of their pictures), and the contact sheet gives documents a
  compact line instead of a big card.
- **Clearer words**: "1 file", "2 groups", no "bpp" in Duplicates, one clear Keep/Trash per copy, and messages in the
  bottom bar go away by themselves. Slightly larger text in the choices and softer band colours. Duplicates and Review
  sit apart from the view controls.

## 0.1.9

- **Find Duplicates.** File ▸ Find Duplicates… (⇧⌘D) or the Duplicates button finds copies of the same file in the
  current place — exact copies and, if you like, the same picture or video saved at another size or quality. The
  best copy of each is marked to keep (click to change); **Move Copies to Trash** shows how much space you free,
  previews, and moves the rest to the Trash. Nothing is deleted, and a group is skipped if a kept copy changed.
- **One View menu.** The view, Review, Quick Look and Clear Filters are now in macOS's own View menu (there were two).

## 0.1.8

- **Files deleted in Finder leave the list on drives too.** Some drives (exFAT ones, like most portable drives) don't
  always tell macOS what changed, so a file deleted in Finder could stay listed. Laserdot+ now also checks every few
  seconds that the listed files are still there, drops those that are gone, and has the engine re-read their folders.

## 0.1.7

- **The T5 EVO stuck on "Opening its index…" — found and fixed.** An old copy of Laserdot+'s engine, left running
  after a force quit or an update, still held the drive's index, so the new one waited for it for ever. A new engine
  now stops any old one on the same index before it starts, and an engine asked to stop never lingers more than
  10 seconds, even if a drive stopped answering.
- **All the choices, compact.** With More choices open, the choices that give nothing right now fold into a small
  "+N" after each group (click it to see them), and the bands with nothing to choose at all fold into one short line
  at the bottom ("Nothing to choose now: Camera · Artist · …"). A drive still opening no longer fills the top.
- **Updates are found even if Laserdot+ stays open.** The daily look for a new version used to happen only when
  Laserdot+ started; a copy left open for days never saw one. It now looks once a day while it runs, too.

## 0.1.6

- **Choices you can't pick shrink.** With More choices open, a choice that gives no files right now is small grey
  text instead of a full button; it grows back into a chip as soon as it applies. What you can pick comes first: in
  each group, then in each band, and bands with nothing to pick move to the bottom.
- **A drive that can't be opened says so.** Instead of "Opening its index…" for ever, it reads "Couldn't open its
  index · click to try again", with the reason when you point at it.

## 0.1.5

- **A drive opens straight away, and the window never freezes waiting for it.** Opening a drive's index (the T5 EVO
  stayed on "Opening its index…") no longer waits for Laserdot+ to finish reading this Mac's home folder, which can
  take many minutes the first time; and the window no longer locks up (and refuses to quit) when the engine is slow
  to answer. Quitting can no longer hang on its own answer either (it could, after an update or from the self-test).
- **A drive shows up at once, with an hourglass while it gets ready.** A drive whose index is still opening (or that
  is being indexed for the first time) appears straight away in the places and, once chosen, in the search box — with
  an hourglass and what it is waiting for ("Opening its index…"); its files appear by themselves when it is ready.
- **A new icon:** a little ship firing its laser across a starry sky.
- **Laserdot+ updates itself.** When a newer version is out, **Install and Relaunch** downloads it from GitHub,
  replaces this copy (the old one goes to the Trash) and opens the new one — no download page. Laserdot+ looks once a
  day (turn it off in the View menu); it asks GitHub only for the version and the update, and sends nothing about you
  or your files.

## 0.1.4

- **The chosen drive shows in the search box.** Pick a drive (or This Mac) and it appears as the first pill in the
  search box, with a drive icon; ✕ on it, or clearing the search, goes back to everything plugged in.
- **Drag to select in the picture views.** In the grid, contact sheet and timeline, drag across the files to select
  them with a box, as in Finder (⌘ or ⇧ adds to what is selected). Dragging a selected file still drags it out.

## 0.1.3

- **The files take the centre of the window.** A few lines at the top to search (the search box, the view and sort,
  then the places and choices), a slim pane on the right with the preview and the file's details, and a bottom bar
  about the selected file — its name, kind, size, date and details, and its full path. Drag the edges to make the
  top area or the right pane bigger or smaller.
- **The list follows Finder:** a file deleted, moved away or renamed outside Laserdot+ leaves the list (or changes)
  by itself within a few seconds, and new files appear — on this Mac and on drives.
- **Quitting is instant:** no more spinning beachball for a few seconds — the window goes at once and the engine
  finishes saving on its own.

## 0.1.2

- **Laserdot's compact choices are back:** the filters sit above the files as shaded bands of chips with counts
  (kind, type, folder, size, date, resolution, length, camera…), a few rows high, with **More choices** for the rest.
  Click a chip to narrow, ⌥-click to leave it out; chosen ones become pills in the search box (✕ takes one out).
- **Places on top, as in Laserdot:** the left pane is gone — Everything plugged in, This Mac and each drive (with how
  far its index has got) are a band over the files; right-click a drive to eject, index or unlock it.
- **Select All** (the status bar's "Select all N", or ⌥⌘A): every file in the place — choose a drive first to select
  the whole drive, then review it, add it to the tray or move it to the Trash.
- With one file selected, the status bar shows its **full path** (select it to copy).
- **Check for Updates…** in the Laserdot+ menu: it asks GitHub for the latest version number — nothing else is sent —
  and, if there is a newer one, opens its page so you can download it. Tick **Check for Updates Once a Day** to have
  it ask by itself (off unless you turn it on). It is the only part of Laserdot+ that goes online.

## 0.1.1

- Review mode fits any window size: the preview takes the room left, so Keep, Trash and Move always show.
- The contact sheet's frames fit the row, and the search box no longer slides off the toolbar when the thumbnail size
  slider shows.

## 0.1.0

- **First version of Laserdot+:** one window to review the files on this Mac and every drive plugged in.
- **Sidebar:** the places (everything plugged in, This Mac, each drive with its state, space and an Eject button) and
  filters with counts for everything the files on screen have — kind, type, folder, size, date, resolution, length,
  codec, camera, artist, author, a data file's columns…
- **Four views:** a list, thumbnails, a contact sheet (eight frames per video) and a timeline by month.
- **Details panel:** a large preview that flips through a video under the pointer, twelve frames across it, and
  everything read from the file — tracks, languages, subtitles, HDR, camera, place, title, author.
- **Review mode** (⌘R): one file at a time, ← → K T M, into a **clean-up tray** applied with one confirmation and one
  Undo. Move to Trash (⌫) with Undo (⌘Z), Quick Look (Space), Show in Finder, Copy Path.
- **Drives index themselves** when plugged in; **private by design:** what Laserdot+ knows about a drive stays on that
  drive. No network at all, no AI.
