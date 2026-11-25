# Design ideas

The ideas offered while designing Laserdot+, the owner's answers, and where each stands. Done ones say the version.

## First ten (the owner's answers in brackets)

1. **A proper main window** — sidebar, files, details panel; an ordinary app [yes; no menu bar, behaves like an app].
   *Done 0.1.0.*
2. **Browse drives that aren't plugged in** (an offline catalog) [no: only what's plugged in, indexed automatically].
   *Not doing.* Drives index themselves when plugged in (0.1.0).
3. **A filter sidebar** with every relevant choice and counts [yes]. *Done 0.1.0*; became Laserdot's compact choice
   bands above the files in 0.1.2 (the owner's request).
4. **Views made for media** [yes to all]:
   - contact sheet — *done 0.1.0*;
   - photo grid with a zoom slider — *done 0.1.0*;
   - timeline — *done 0.1.0* (by modified date; by date taken: later);
   - places, grouped by GPS position (no map: maps need the internet) — *next*.
5. **A collection health page per drive** [no need]. *Not doing.*
6. **"What's not backed up"** across drives [not chosen yet].
7. **A duplicates workspace with side-by-side compare** [not chosen yet; see 17].
8. **Organize by rules** (move/rename by details) [not chosen yet; see 15].
9. **Compare two folders or drives** [not chosen yet].
10. **A full details panel and saved views** [yes]: details panel — *done 0.1.0*; saved views and tabs — *next*.

## Second ten (built on the owner's goals: tell what a file is when the name doesn't say; clear junk; remove duplicates)

11. **Review mode** (← → with keep/trash/move keys) [yes]. *Done 0.1.0.*
12. **See inside a video without opening it** — a 12-frame storyboard, snippets on a key [yes]. *Storyboard done
    0.1.0*; three-second snippets with sound — later.
13. **Folders that show what's inside** — a cover of four thumbnails, what it holds, its dates [yes]. *Next.*
14. **Find names that say nothing** (`IMG_1234`, `VID_…`, `Untitled`, `download (3)`) [yes]. *Phase 3.*
15. **New names from what's inside the file** (date taken + camera; title + year + resolution) [yes]. *Phase 3.*
16. **Junk finder by category** (empty files, unfinished downloads, lock files, used installers, broken media,
    torrent leftovers, old screenshots) [yes]. *Phase 3.*
17. **Smarter duplicates** (whole folders, the same film in several qualities, photo bursts, songs) [yes]. *Phase 3.*
18. **Space map of each drive** [no need]. *Not doing.*
19. **Clean-up tray** [yes]. *Done 0.1.0* (review mode feeds it).
20. **Drives in the sidebar** with progress, space, Eject and settings [yes]. *Done 0.1.0*; in 0.1.2 they moved to the
    places band over the files (the owner's request). Per-drive settings later.

## Asked for since

21. **Check for updates** [asked for]. *Done 0.1.2* (version number from GitHub only; the browser downloads).
22. **Select the whole drive** [asked for]. *Done 0.1.2* (Select All in a drive's place).
23. **Laserdot's compact choice bands instead of the sidebar list** [asked for]. *Done 0.1.2.*
24. **The selected file's full path in the status bar** [asked for]. *Done 0.1.2.*
25. **Places over the main window, as in Laserdot** [asked for]. *Done 0.1.2* (the sidebar became a band).
26. **The list follows changes made in Finder** [asked for]. *Done 0.1.3.*
27. **The files at the centre: search on top, a slim right pane, a bottom bar about the selected file, resizable
    panes** [asked for]. *Done 0.1.3.*
