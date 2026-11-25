# Design conversation

What the owner asked for while designing and building Laserdot+, what was decided, and why. Only added to.

## 1. Rebuild Laserdot as an app (2026-11-25)

"Let's revisit laserdot, I like the filtering and indexing, and duplicates scanner, and file management, I want to
rebuild it as an app, as sort of smart finder window that I can open and review my large collection of files, give me
10 ideas." Ten ideas were offered (`design-ideas.md` 1–10).

## 2. The owner's choices, and ten more ideas

"Do 1; no need for menu bar, it behaves like an app; don't do 2, only what's plugged in, and gets automatically
indexed; 3 filter sidebar, with all relevant choices shown; 4 yes to all; 5 no need; 10 yes. The idea is to quickly
and effectively scan through media, movies, images, files where the filename might not be enough to tell what it is;
also to clean up any random or miscellaneous files that do not need to be there, and also eliminate duplicates to save
space." Ten more ideas built on that (`design-ideas.md` 11–20).

## 3. Privacy, and the overall design

"Privacy needs to be preserved, any logs or indexes get placed on the actual drive, no mention or record of filenames
or metadata displayed or shown anywhere else other than the actual app. No need for 8 [the space map]." Decided: each
drive keeps everything about itself on itself (`.laserdot`); this Mac's index stays on this Mac's disk; nothing about a
drive's files is written to this Mac — no fingerprints, no "opened" records, no paths in logs, no Quick Look thumbnails
(macOS caches those); read-only drives are indexed only when asked and their index is deleted when they leave. The
design is in `design.md`.

## 4. Build it in its own repository

"Use the new repo laserdotplus for the app, build it." Open questions were settled with defaults: a separate app
called Laserdot+; no updater (no network code at all; updates from the Releases page); word search inside documents
kept for this Mac's folders; This Mac's disk included as a place. The engine came from laserdot-go with the privacy
changes and a `details` call for the details panel; the window is new.

## 5. First build

The window passed CI's self-test on a real Mac on its first full run, the privacy checks included. The standard macOS
split view's sidebar did not show in the self-test's screenshots, so the window became a plain three-pane layout.
Phase 2 began with the contact sheet, the timeline, review mode and the clean-up tray (moved up from Phase 3 because
review mode feeds it). Released as 0.1.0.

## 6. 0.1.0 released

Released 25 Nov at 20:45 Kuwait time. Its screenshots showed review mode's buttons pushed off a small window and the
contact sheet's frames running past the row; fixed in 0.1.1 (the preview takes the room left; frames share the width).
