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

## 22. Deleted in Finder, still listed (0.1.8)

"I deleted some media files from the Finder that were bad, but Laserdot+ did not refresh to show they are deleted."
The list follows the engine, which follows macOS file events — and on exFAT drives (the T5 EVO) those can go missing.
Decided: a safety net in the app — every 4 seconds, off the main thread, the top of the list (1,500 files) is checked;
files that are gone leave the list at once and the engine is told to list their folders again (`touched`).

## 23. Two View menus, and no Find Duplicates (0.1.9)

"There are 2 View menus in the menu bar; also there is no find duplicates function." Decided: the app's view commands
go into macOS's own View menu. Find Duplicates — the engine already found exact copies, similar pictures and
re-encoded videos — gets a panel over the files (File ▸ Find Duplicates…, ⇧⌘D, or the Duplicates button) for the
current place: groups with the recommended copy to keep, a click to change it, the space freed, and Move Copies to
Trash after a preview (never deletes; a group whose kept copy changed is skipped). It is the first part of the
clean-up screen.

## 24. A UI critique, all of it (0.1.10)

"On a UI level, critique Laserdot+" — then "do all". Found: an empty band under the choices (the top area had a fixed
height); places styled like a filter; Review and Duplicates squeezed into the files' half beside an empty pane; an
empty right pane with nothing selected; raw /private/var paths; documents as big contact-sheet cards; folders as
plain icons; "1 groups", "Put back 1", "bpp"; small text and loud band colours; mode buttons mixed with view
controls. Decided: the top hugs its choices (up to 260 pt, then scrolls; it is no longer dragged); places are a
plain strip; Review and Duplicates cover the files and the right pane; the empty right pane summarises the place
(files, size, kinds, biggest folders, duplicates); paths read from the drive or Home; folders show four of their
pictures (asked of the engine); documents are one line in the contact sheet; counts use proper singulars; notices
clear after 8 s; chips 12 pt, softer bands; a divider sets the modes apart.

## 25. Testing before the owner does (0.1.11)

From the critique: most bugs were found on the owner's Mac first. Decided: CI's test drive is exFAT (like the T5 EVO),
and the self-test deletes a file on it behind the app's back; engine tests cover a drive pulled out while attached,
a stuck second engine, and opening a drive while a home-folder index holds the writer lock. Technical choices
(made with, columns, rows, codec, HDR, chapters) wait under More choices.

## 26. What is this? (0.1.11)

The owner's first goal: "quickly scan through media … where the filename might not be enough to tell what it is".
Decided: a sweep — review mode over only the files whose names say nothing (`NameSense.isUnclear`: a camera or app
prefix with a number, a bare number or date stamp, a long hex id, "untitled", "Screenshot …" — unless other words
follow), with a suggested name from the file's own details (`NameSense.suggest`: date taken or modified, title or
camera or artist, a video's resolution and length). R renames (in the same folder, never over another file;
Edit ▸ Undo renames back). Plain rules, no AI.

## 27. A UI critique, second pass (0.1.11)

"On a UI level, critique Laserdot+" — "do all". Decided: one Tools menu replaces three mode buttons; one `ModeHeader`
for Review, What Is This? and Duplicates; the list without Kind and with a readable date; grid tiles with facts and a
light selection outline; drives with a fullness bar and state icons; bands with stripe and icon only; coloured
summary bars; the bottom bar with listed size and free space; Duplicates rows that switch as a whole. The self-test
now also takes a dark-mode screenshot and a second, short run in Arabic (right to left). Found while testing: the
engine sent `"sections": null` for files with no details, which lost the whole answer in the app — both sides fixed.

## 28. English first (0.1.11)

"Ignore Arabic, focus on English; multi-languages will be done at a later stage." Decided: new strings in English
only, the Arabic self-test run removed; the existing Arabic strings stay for later (a missing key falls back to
English).

## 29. Duplicates: only the big files (0.1.12)

"In Find Duplicates it would be useful to filter only large files — why wait for every file to be checked when the
objective is just to save storage." Decided: a Larger than choice (any, 10 MB, 100 MB, 1 GB; 100 MB by default,
remembered) adds `fsize:>…` to the search the comparison is limited to, so smaller files are never read.

## 30. Clean Up (0.1.13)

From the critique ("clean-up is scattered"). Decided: one Clean Up screen with Duplicates, Junk and Big & old tabs.
Junk is never indexed (system files, partial downloads), so the engine walks the place's folders for it (`junk` op,
`FindJunk`): system bookkeeping files (not a folder's custom icon or localized name), downloads untouched for a day,
empty files, empty folders (deepest first); system and Laserdot folders are skipped. Big & old is a search
(`fsize:>N before:Ny`), so it is instant. Everything goes to the Trash after a preview, with Undo.

## 31. Progress and drive health (0.1.14)

From the critique ("waiting is opaque"; "a health line per drive"). Decided: indexing shows a percentage and a time
left (from the rate since it started); right-click a drive ▸ About This Drive shows space, format, state, files
indexed, index size and place, and when it was last checked; when the drive list has not come back for 12 seconds
the bottom bar says a drive isn't answering. (Duplicate and junk scans still show a spinner: the engine does not
report their progress yet.)

## 32. A duplicate scan that seemed stuck (0.1.15)

"I told Find Duplicates to look at files over 1 GB and it has been spinning for 20 minutes; check everything is OK.
It would be nice to get a detection as soon as it happens, rather than wait for the whole thing." Found: nothing
wrong — but likely copies of big files are read whole to confirm them (about 10–20 s per GB on a USB drive), videos
are decoded for frames when "similar" is on, a drive's fingerprints are never kept on this Mac (privacy), and the app
showed only a spinner although the engine reported each step. Decided: the engine publishes the groups found so far
(`dupes_found`): likely copies right after the sample step, confirmed groups after each pass; the panel shows them
live with the step, files done of total, the file being read, and Stop. Trash waits for confirmation.

## 33. Duplicates moved to the Trash didn't show in the Trash (0.1.17)

The owner: "i moved the duplicates to trash but nothing showed up in the macbook pro trash". Every other Trash action
already used macOS's own call (`FileManager.trashItem`); duplicates went through the engine, which renamed each copy
into the drive's `.Trashes/<uid>` itself — the right place, but the Finder does not always notice such a rename, and
Put Back can't work. Decided: the engine still checks each copy (unchanged, not the kept one) right before; the app
then moves exactly those with macOS's call, off the main thread, undoable with ⌘Z. Copies already moved by 0.1.15 are
in `/Volumes/<drive>/.Trashes/<uid>`.

## 34. Colour-blind-friendly places and kinds (0.1.17)

The owner: "the folder tab volume for the volumes is very intutive and useful, lets give it a color blind friendly
color, and have the next level of tab for document type also colored for a colorblind friewndly viewer". Decided:
the Okabe–Ito palette (already the bands' stripes), never colour alone — every coloured chip keeps an icon. Places
are one colour (blue) since they are one family; each kind its own colour, and a file type (TXT, MP4) its kind's, so
the two rows read together. Labels stay in the normal text colour on a light tint, readable in light and dark.

## 35. A bolder search box (0.1.17)

The owner: "have the top search bar have a darker bolder border to it, to draw attention to it and frame it nicely".
Decided: a 2 pt frame in the text colour at 55% (dark in light mode, light in dark mode), a touch more padding and
corner, a faint shadow; while typing, 2.5 pt in the places' blue — the window's one focus colour.

## 36. Clicking and drag-select like Finder (0.1.18)

The owner: "command click does not work for individual selections, drag select with mouse also doesnt work properly,
i want to use those to open and delete files i found". Found: SwiftUI tap gestures on each tile (single and double)
plus a drag gesture over them; a tile changed its view type when selected (it gained a file drag), which reset its
gestures mid-click, and the modifier keys were read from the global state late. Decided: Finder's rules on AppKit
mouse events, one view over the tiles; the keys that act on what was found (⌫ trash, Return open, Space look) work
once a file is clicked; refreshes wait while the mouse is down. The list view is AppKit's table and already had them.

## 37. Fingerprints on the drive; Recent Items; double click (0.1.19)

- From the critique ("do all"): a drive's fingerprints now live on the drive, which the privacy rule allows (what is
  known about a drive's files stays on it). The engine had refused because a drive is untrusted — a forged hash
  could make a different file look like a copy — so the file is signed with a key only this Mac holds; anything
  else is ignored. Resuming a stopped scan comes with it.
- The owner: "disable recent items recording in apple menu to preserve privacy, or clear it when exiting". Decided:
  don't record rather than clear — files open with `addsToRecentItems = false`. Laserdot+ does not edit macOS's or
  other apps' lists (the app that opens a file may still list it in its own File ▸ Open Recent).
- The owner: "when double clicking on a video to play it, the screen scrolls down and i get the video above it
  playing instead of my choice". The first click selected the file, the details pane grew and pushed the split, the
  grid reflowed, and the second click landed on another tile. Fixed both: the pane can't push, and a double click
  opens the first click's file.

## 38. The critique, done (0.1.20)

The owner: "do all, also add time attributes, like last opened, date created, and related time that is recorded".
- Dates: everything the file carries, read only for the file being looked at (no cost while indexing). Last opened
  is macOS's own record on the file (it lives with the file, on the drive for a drive's file); Laserdot+ still keeps
  no "opened" history of its own. Access time is left out: Laserdot+'s own header reads change it.
- Space, Keep rules, saved views, Rename All, arrows, opening time, VoiceOver: as proposed.
- The drive's Trash: the critique offered an Empty button, but Laserdot+ never deletes (rule 4). Decided: show how
  much is waiting and open Finder's Trash, where the owner empties it.
- Developer ID signing and notarization need the owner's Apple Developer account; not done.

## 39. Dates where they show; bolder titles (0.1.21)

The owner: "have the attribute titles bigger and bolder to make them show, also last opened, date created, and other
file time attributes are not there, include them". They were there — at the bottom of the pane, under the preview and
the storyboard, in small grey type. Decided: every date goes in the first block under the name; a date macOS did not
record says "Not recorded" rather than vanishing (so the owner can tell it was looked for); titles in bold at body
size, section titles as headlines.

## 40. The second critique, done; results while it works (0.1.22)

- The owner: "do all, remove unused code". Last opened can't be indexed cheaply (one attribute read per file while
  indexing breaks the speed rules), so it is read for what is on screen: the list's page and Big & Old's candidates.
  The search language gets no `opened:` filter for the same reason. Unused code removed: thirteen app functions the
  window never called (among them recording opens, which Laserdot+ must not do anyway); the engine had none.
- The owner: "the clean up junk and find duplicates take too long, it would be useful to show results as soon as
  something is found rather than finish the whole drive or task". Junk lists finds as it walks, with Stop; duplicates
  publish what they know every second and read the biggest files first. Move to Trash waits for the end or Stop, so
  nothing is trashed on a half-read list.
- The owner then asked for a review of what could be more Mac-like, "without losing any functionality" (answered as
  a list, not built yet).

## 41. A Mac window; a review for bugs (0.1.23)

- The owner chose, from the Mac-like review: the toolbar, a Finder-style sidebar, the inspector, a window subtitle,
  standard empty screens, a File menu, Finder's right-click order with Open With, a Settings window, the accent
  colour, a remembered window, and drag and drop (1 2 3 5 6 10 11 12 15 18 19). Left as they were: the search field
  and choice bands (7, 8), Return still opens (9 not chosen), alerts stay centred (13), no Dock progress (14), tile
  style (16), column chooser (17), keyboard focus order (20), no Share menu.
- The owner: "review code for any overlooked bugs and interface issues". Found and fixed: ⌫/Space/Return acted on
  files hidden behind Review or Clean Up (⌫ could trash an unseen file — undoable, but wrong); a move onto a drive
  would copy big files on the main thread; hiding the inspector for an overlay could switch it off for good;
  last-opened dates were re-read on every refresh; a drive's Trash and views assumed `/Volumes/<name>`; drags inside
  the app had no operation, so dropping on a sidebar drive did nothing.

## 42. Broken, unwanted, bit rot, a drive's history (0.1.25)

The owner chose four of ten feature ideas: broken files, probably-unwanted files, protection against bit rot and a
drive's history ("do 3 4 6 8"). Decided: broken and unwanted come from the index (no disk reads), as lists to look
through with nothing ticked. Bit rot: a checksum list kept on the drive (it carries its own hash, so a damaged list is
noticed); damage = same size and date, different contents; drives whose index lives on this Mac (read-only,
encrypted) get none, so no names are written in clear. History: on the drive, once a day while plugged in, plus each
clean-up's freed bytes; "full in about N months" from the last six months.

## 43. A beachball while a new drive indexed (0.1.26)

The owner: "for a new drive, i keep getting a beachball every 5 seconds, and it would not scroll up or down … no
hourglass or wait indicator … a new 8tb drive filled with media", then "beachball stopped now, it must have been
indexing". Found: every 3 s while indexing, the app re-ran the search, rebuilt the list and the choices, re-read the
rows' dates and wrote them row by row (one redraw each), and the right pane asked the disk for the drive's mount on
every redraw. Decided: refresh at most every 15 s and never during input, one update per refresh, mounts from the
drive list, and a visible spinner. Lesson: anything on a timer must stay cheap at a 1 TB+ drive's scale.
Then: "now its back again after viewing 1 video" and "and making new attribute choices". Same cause: every new search
(a choice, or a file whose last-opened date changed) filled each row's date with its own assignment to the published
list — hundreds of list copies and redraws on the main thread. The single update in 0.1.26 fixes it.

## 44. A 20-second hang in Clean Up Junk (0.1.27)

The owner sent macOS's hang report (0.1.23, force quit): the main thread was in `JunkModel.take`, inserting each new
find into the published `chosen` set — a copy of the whole set per insert, tens of thousands of times a second on an
8 TB drive. Fixed there and in every similar loop (Keep, the tray), the engine now sends only new finds, removals use a
set, and the lists' Move to Trash runs in the background. Lesson (in how-it-works): never mutate a published
collection per item in a loop.

## 45. The third critique: scale, memory, signing (0.1.28–0.1.29)

The owner: "do all". The update rhythm was not chosen, so it became a setting (default once a day) and releases are
batched. Developer ID needs the owner's Apple account: the build signs and notarizes by itself once the secrets exist.
Notarization runs on the build machine with Apple's tool; the app itself still has no network code.
- The owner, meanwhile: "have command click select media one by one and allow a delete, to help remove unwanted media
  in bulk". ⌘-click and ⌫ already worked in the pictures, but nothing showed it and the list view's ⌫ needed the
  keyboard focus: now a **Move N to Trash** button shows for any multiple selection, ⌫ is on the list itself, and
  many files go to the Trash in the background.
- 0.1.29 also: Junk from the index at once, whole-drive Last Opened, Clean Up in the files' place, the engine's change
  notice, and the 40,000-file self-test that fails a build on a 2-second stall.

## 46. Stopping Junk early (0.1.30)

The owner: "i tried to do a stop on a junk find so i can delete what was found so far, and i got a beach ball", then
"laserdot+ under force quit got a not responding after that". Found: a walk stopped partway reported every folder it
had entered but not finished as an empty folder — ticked like all junk — including folders full of media; and the
list of all of them was drawn at once. Fixed: a stopped walk offers no empty folders (test), lists draw 2,000 rows.
Also: junk files are noted as indexing skips them (`junk.list`, on the drive for a drive), so Junk lists them at once.

## 47. The rest of the critique, and ⌘-click (0.1.31)

The owner: "do 1 (find another way to do 2) (3 save anything needed on actual drive to maintain privacy) 4 6 7", then,
mid-way, "command click stopped working, i need it to choose duplicates to delete". Found: a refresh during indexing
cut the list to its first page, dropping ⌘-clicked rows further down (and Delete left them out) — refreshes now keep
what was loaded. The scale test is the engine at 300,000 files on Linux in every build (instead of a nightly Mac run).
Last-opened dates are remembered on the drive itself (privacy). Junk lists what indexing noted; Look Deeper walks.
Duplicates: Quick / Thorough / Everything. Moving to a drive: progress, Stop, a clear unplug message.

## 48. ⌘-click in the grid (0.1.32)

The owner, on 0.1.31: "command click still does not work", then: "when i do a command click i get a fram around the
selection then as soon as i move the cursor the selection goes, all under 1 second". The grid's background tap gesture
(deselect on empty space) was removed — on the owner's macOS it fired for clicks on the tiles too. The self-test now
sends the ⌘-click through the window's event queue and moves the pointer; Report a Problem traces shrinking selections.
