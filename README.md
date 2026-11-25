# Laserdot+

A Mac app for reviewing a large collection of files — movies, pictures, documents — on this Mac and every drive
plugged in. See what a file is when its name doesn't say, clear out junk, and remove duplicates to save space.

**[⬇ Download Laserdot+ (latest version)](https://github.com/jamalxcode/laserdotplus/releases/latest/download/LaserdotPlus.dmg)**
— macOS 14 or later · [what's new and all versions](https://github.com/jamalxcode/laserdotplus/releases)

- **One window, as compact as Laserdot:** places (everything plugged in, This Mac, each drive) and choice bands with
  counts over the files, everything about the selected file on the right — a storyboard of twelve frames for a video, its tracks, languages and subtitles, a photo's camera and place,
  a document's author, a spreadsheet's columns.
- **Four ways to look:** a list with sortable columns, big thumbnails (videos flip through under the pointer), a
  contact sheet (a strip of frames per video, to tell films apart at a glance) and a timeline by month.
- **Review and clean up:** go through files one at a time, full-window — ← → to move, K keep, T trash, M move. What you
  mark collects in a clean-up tray; nothing moves until you apply it, and one Undo puts everything back.
- **Filters with counts:** every choice the files on screen have — kind, type, size, date, resolution, length, codec,
  camera, artist, author… Tick several; the counts follow.
- **Drives index themselves** when you plug them in, and are searchable while they are read.
- **Private by design:** what Laserdot+ knows about a drive is kept on that drive, and nowhere else. This Mac keeps
  only its own index. No network, no AI — except **Check for Updates…**, which only asks GitHub for the latest
  version number when you choose it (or once a day, if you turn that on).

Built on the engine of [Laserdot](https://github.com/jamalxcode/laserdot-go). See `docs/design.md` for the design,
`docs/how-it-works.md` for how it works, `docs/design-ideas.md` for the ideas and where each stands, and
`docs/design-conversation.md` for what was asked and decided.

## Install

[Download the disk image](https://github.com/jamalxcode/laserdotplus/releases/latest/download/LaserdotPlus.dmg)
(always the latest version), open it, and drag Laserdot+ to Applications. The first time,
right-click Laserdot+ → Open (the app is not notarized). **Laserdot+ ▸ Check for Updates…** tells you when a newer
version is out and opens its page here to download it.

## Build

```bash
app/scripts/build-go.sh
(cd app && swift build && LASERDOTD=$PWD/build/go/laserdotd swift test)
VERSION=0.1.0 app/scripts/bundle.sh && app/scripts/make-dmg.sh out/LaserdotPlus-0.1.0.dmg
```
