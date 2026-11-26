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

## 7. A check for updates (0.1.2)

"Add a check for updates." Laserdot+ had no network code at all; this is the one exception, kept as small as
Laserdot's: a separate bundled helper asks github.com only which release is the latest (one request, no cookies or
cache, nothing about the user or files sent), on request or once a day if the owner turns that on (off by default).
A newer version's page opens in the browser; the app itself downloads and installs nothing. CI checks no other code
uses the network and the helper names no other host.

## 8. Whole drive, compact choices, full path (0.1.2)

"I need a way to select the whole drive, also the search tag arrangement of Laserdot is nice and compact, let's have
that back", then "when a file is selected, have the full path shown on the bottom window bar". Decided: Select All
(status bar and ⌥⌘A) selects every file of the place — the whole drive when a drive is chosen; the sidebar's tall
filter list became Laserdot's choice bands above the files, with pills in the search box; the status bar shows the
selected file's full path.

## 9. Places over the files (0.1.2)

"The left pane would be better placed over the main window, similar to Laserdot original." The sidebar became a
places band over the files, in the same style as the choice bands: Everything plugged in, This Mac and each drive
(its state beside its name; right-click to eject, index or unlock). The window is now two panes: files and details.

## 10. The list follows Finder (0.1.3)

"When files are deleted from the Finder, it needs to be reflected on Laserdot+, or if it's moved to a place that is not
being viewed, it also needs to be removed." The engine already kept its indexes current; the window did not search
again. Decided: the engine counts the changes it applies and reports the count; the app searches again when it moves.
The self-test deletes a file behind the app's back and checks it leaves the list.

## 11. Quitting without a beachball (0.1.3)

"When I quit Laserdot+ I get a beachball for a few seconds before quitting." The app waited on its main thread for the
engine to finish shutting down. Decided: the window goes at once, the engine is asked to stop in the background and
finishes saving on its own; the app does not wait for it.

## 12. The files at the centre (0.1.3)

"I need the focus to be on the files being reviewed and looked at and arranged, with other functions surrounding it;
privacy also needs to be preserved; top few lines for search, bottom margin about the file selected, right pane slim
with info and preview of the file; panes can be made bigger or smaller and adjusted." Decided: the search box, view
and sort move from the toolbar into a top area with the places and choices (it scrolls when made small); the files
fill the middle; the right pane is slim (the preview takes its width); a bottom bar describes the selected file and
shows its full path; the top area and the right pane are resized by dragging. Privacy is unchanged.

## 13. The chosen drive in the search box (0.1.4)

"When I choose a disk, it should be included and shown in the search bar text box." Decided: the chosen place (a
drive or This Mac) is the first pill in the search box, with a drive icon, before the chosen filters; ✕ on it, or
clearing the search, goes back to everything plugged in. The place bar above still highlights it.

## 14. Drag to select (0.1.4)

"Drag select should work in the files preview area." Decided: the grid, contact sheet and timeline get Laserdot's
selection box — drag across tiles to select them (⌘/⇧ add to the selection); a drag that starts on a selected file
drags it out to Finder or Mail, as before. The list already selects by dragging.

## 15. Updates install themselves (0.1.5)

"If there is an update, I want it to self update, not send me to a downloads page." This widens the network exception
(the owner's call): the bundled helper may now download the latest release's disk image from GitHub (and GitHub's
file hosts) and swap it in. Decided: a newer version offers Install and Relaunch; the helper downloads and checks the
app (same bundle, that version) before Laserdot+ quits, then puts the old copy in the Trash, moves the new one in and
reopens it. The daily check is now on by default. Still nothing about the user or their files is sent, and the app and
engine keep no network code.

## 16. A drive that is still opening (0.1.5)

"I plugged in the T5 EVO and it would not appear; it said it was opening its index. It should still appear but with an
indicator like an hourglass saying there is some waiting involved, in the search bar." Decided: a drive that is not
ready (its index opening, a first indexing, or busy) shows an hourglass in the places band and, when chosen, in its
pill in the search box, with what it waits for; clicking it chooses it at once (it is no longer only "click to
search it"), and the files area says it is opening instead of "no results"; the files appear by themselves.

## 17. The T5 EVO stuck on "Opening its index…", and a frozen window (0.1.5)

"T5 EVO opening its index is taking longer than usual, it is still pending", then "Laserdot+ not responding, had to do
a force quit", then "fix it all, publish it, and update all documentation." Found: opening a drive's index waited for
the engine's writer lock, which this Mac's first home-folder index holds for minutes; the app's attach request sat on
the shared connection meanwhile, so its status checks (every 3 s) queued up behind it, each holding a thread, until
the app starved and froze. Decided: a drive's index is opened without the writer lock (the mount is reserved instead;
the drive is listed as "opening" with the hourglass); the app opens a drive on a connection of its own, and asks for
status one request at a time.
Also found while testing it (a stack sample from CI): quitting could wait for itself for ever. The engine is stopped in
the background and the "quit now" answer was sent back through the main queue — busy, when the quit itself started
in a main-queue block (Install and Relaunch, the self-test). The answer now goes through the run loop, in the modes
AppKit waits in. CI now samples a hung self-test after five minutes, so a freeze shows where it is.

## 18. Choices that can't be chosen, and a clearer order (0.1.6)

"Let's have the many choices that are shown but not available shrunk, because they can't be chosen, and when they
become available take a proper size; also rearrange to make it more logical and clear." (The screenshot also showed
the T5 EVO and another drive still "Opening its index…".) Decided: a choice with no results is small grey text (no
button) and grows back into a chip when it applies; values that give results lead each group (in their usual order),
groups with something to choose lead each band, and bands with nothing to choose go to the bottom
(`RefineLogic.arranged`). A drive whose index could not be opened now says so ("Couldn't open its index · click to try
again", the engine's reason in the tooltip) instead of showing the hourglass for ever; "opening" is shown only while
the engine is really opening it.

## 19. An update not found by a copy left open (0.1.7)

"I have Laserdot+ 0.1.5 running on another machine, no update detected." The daily check ran only at launch, so a copy
left open never looked again. Decided: it also looks once a day while it runs (an hourly timer checks whether a day
has passed); still once a day at most, still only GitHub, still nothing sent about the user.

## 20. Still too long (0.1.7)

"Choice list still large and not compacted, and still waiting for index." Shrinking the unavailable choices was not
enough: with a drive still opening, nothing is available and every band still showed. Decided: in each group the
unavailable values fold into a small "+N" (click to unfold); bands with nothing to choose fold into one line at the
bottom naming their groups. (The T5 EVO still opening is being looked at on the owner's Mac.)

## 21. Two engines at once (0.1.7)

The owner's Mac showed two `laserdotd` processes from Laserdot+.app, both with the T5 EVO's index open: one left
behind (21 minutes old, after a force quit / update) and the current one, which waited on it — "Opening its index…"
for ever. Decided: an engine takes an exclusive lock beside the index (`laserdotd.lock`, with its pid) before opening
anything; an older engine still holding it (one that no longer answers on the socket — a live one is simply used) is
asked to stop, then stopped.

## 22. Deleted in Finder, still listed (0.1.7)

"I deleted some media files from the Finder that were bad, but Laserdot+ did not refresh to show they are deleted."
The list follows the engine, which follows macOS file events — and on exFAT drives (the T5 EVO) those can go missing.
Decided: a safety net in the app — every 4 seconds, off the main thread, the top of the list (1,500 files) is checked;
files that are gone leave the list at once and the engine is told to list their folders again (`touched`).
