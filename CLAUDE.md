# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

**Laserdot+** — a Mac app with one window for reviewing a large collection of files on the drives that are plugged
in: see quickly what a file is when its name doesn't say, clear out junk, remove duplicates to save space. It is an
ordinary app (no menu-bar item, no global hotkey). Go engine (`laserdotd`, the single writer of each index) + a
SwiftUI window app that talks to it over a Unix socket.

The engine comes from `jamalxcode/laserdot-go` (Laserdot, the ⌥Space search tool), whose code, tests and history are
the reference: when changing the engine, read its docs (`docs/history/lessons-learned.md` especially).

## Key documents

- `docs/design.md` — the design: what the app is, the privacy rules, the window, the phases. The source of truth.
- `docs/how-it-works.md` — how it works now (keep current with every behaviour change).
- `CHANGELOG.md` — what's new, per version, in plain words (a new `## x.y.z` section releases that version).

## Non-negotiable rules

1. **Privacy: what Laserdot+ knows about a disk's files stays on that disk.** A drive's index, its fingerprints,
   thumbnails and histories live on the drive (`/Volumes/<name>/.laserdot/`). This Mac's own index lives on this
   Mac's disk (`~/Library/Application Support/laserdotplus/`). Nothing about a drive's files — names, paths, details —
   is ever written to this Mac: no logs with paths (`crash.Redact`), no fingerprints (`keepsFingerprint`), no
   "opened" records, no histories, no Quick Look thumbnails (they are cached by macOS; CI fails on
   `QLThumbnailGenerator`). App settings hold only view mode, sort and tile size. Read-only drives can't hold their
   index: it is kept on this Mac only until the drive leaves (and deleted then). `internal/core/privacy_test.go` and
   the self-test (which scans this Mac's data folder for a drive's file name) guard this.
2. **No network, ever — one exception.** The engine denies itself the network (sandbox) before anything else; the
   app has no network code (CI greps for it). **The exception** (the owner asked for "a check for updates"): the
   bundled `laserdotplus-update-check` (`app/Sources/UpdateCheck`) asks github.com which Laserdot+ release is the
   latest (one HEAD request, ephemeral session, no cookies or cache) and prints its version; it sends nothing about
   the user or their files. It runs only on Check for Updates… or once a day if the user turns that on (off by
   default). A newer version's page opens in the browser; the app downloads and installs nothing. Do not widen this.
   No telemetry.
3. **No AI.** Perceptual hashes and plain pixel measures are fine.
4. **Never deletes.** Files go to the Trash (undoable) or a folder, after a preview for bulk actions.
5. **The window never waits on a disk.** Nothing on the main thread touches a file: icons start as the type's,
   pictures and frames load off the main thread, a few at a time, only for rows that stay on screen.
6. **Only what's plugged in.** A writable drive is indexed by itself when connected; unplugged drives disappear.

## Layout

```
internal/…        the engine (from laserdot-go): fold, query, scan, watch, media, index, core, sandbox, ipc, daemon
cmd/laserdotd     the engine process; cmd/laserdot the CLI
app/Sources/LaserdotKit   engine client (socket, protocol), registry, shared logic (no UI)
app/Sources/LaserdotPlus  the SwiftUI window app
app/scripts/      build-go.sh, bundle.sh (→ app/build/Laserdot+.app), make-dmg.sh, build-ffmpeg.sh, check-selftest.py
```

## Commands

```bash
go build ./... && go vet ./... && gofmt -l . && go test ./...
app/scripts/build-go.sh                      # laserdotd, CLI, Registry.generated.swift (macOS)
(cd app && swift build && LASERDOTD=$PWD/build/go/laserdotd swift test)
VERSION=0.1.0 app/scripts/bundle.sh          # → app/build/Laserdot+.app
app/scripts/make-dmg.sh out/LaserdotPlus-0.1.0.dmg
app/scripts/release-local.sh [--quick]     # on the owner's Mac: test, build, publish the CHANGELOG's newest version (minutes)
```

Swift compiles only on macOS (CI). The self-test (`LASERDOT_SELFTEST`, `SelfTest.swift`) drives the real app in CI
and prints screenshots base64 in the job log (`=== SCREENSHOT name.png`); extend it for every visible change.

## Conventions

- Work on a branch; fast-forward `main` to a commit whose CI passed (a commit is tested once).
- Commit as the owner: `git -c user.name="jamal xcode" -c user.email="j.mutawa@gmail.com" commit`.
- User-facing strings in English and Arabic (`app/Sources/LaserdotPlus/Resources/*.lproj`).
- Keep `docs/design.md` and `docs/how-it-works.md` in sync with behaviour.
