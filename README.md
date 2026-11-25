# Laserdot+

A Mac app for reviewing a large collection of files — movies, pictures, documents — on this Mac and every drive
plugged in. See what a file is when its name doesn't say, clear out junk, and remove duplicates to save space.

- **One window:** places and filters on the left, the files in the middle (a list or big thumbnails; videos flip
  through under the pointer), everything about the selected file on the right — a storyboard of twelve frames for a
  video, its tracks, languages and subtitles, a photo's camera and place, a document's author, a spreadsheet's columns.
- **Filters with counts:** every choice the files on screen have — kind, type, size, date, resolution, length, codec,
  camera, artist, author… Tick several; the counts follow.
- **Drives index themselves** when you plug them in, and are searchable while they are read.
- **Private by design:** what Laserdot+ knows about a drive is kept on that drive, and nowhere else. This Mac keeps
  only its own index. No network at all, no AI.

Built on the engine of [Laserdot](https://github.com/jamalxcode/laserdot-go). See `docs/design.md` for the design
and `docs/how-it-works.md` for how it works.

## Install

Download the disk image from the Releases page, open it, and drag Laserdot+ to Applications. The first time,
right-click Laserdot+ → Open (the app is not notarized). Laserdot+ never connects to the internet, so new versions
are downloaded from the Releases page.

## Build

```bash
app/scripts/build-go.sh
(cd app && swift build && LASERDOTD=$PWD/build/go/laserdotd swift test)
VERSION=0.1.0 app/scripts/bundle.sh && app/scripts/make-dmg.sh out/LaserdotPlus-0.1.0.dmg
```
