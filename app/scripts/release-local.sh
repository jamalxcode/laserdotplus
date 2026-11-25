#!/usr/bin/env bash
# Releases Laserdot+ from this Mac in a few minutes, without waiting for
# GitHub's Mac runners: tests, builds the universal app, packs the disk
# image, checks it launches, pushes main and publishes the release.
#
#   app/scripts/release-local.sh            # the newest "## x.y.z" in CHANGELOG.md
#   app/scripts/release-local.sh --quick    # skip the Go and Swift tests (CI on the branch passed)
#
# Needs: Xcode command-line tools, Go, and the GitHub CLI signed in (`gh auth login`).
# The first run also builds ffmpeg (about 10 minutes); later runs reuse it.
# CI still runs on main afterwards; release.yml sees the release exists and stops.
set -euo pipefail
cd "$(dirname "$0")/../.."

quick=false
[ "${1:-}" = --quick ] && quick=true

for tool in go swift gh git hdiutil; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "sign in first: gh auth login" >&2; exit 1; }

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || { echo "switch to main first (on $branch)" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first" >&2; exit 1; }
git fetch --quiet origin main
git merge --ff-only --quiet origin/main

v=$(awk '/^## [0-9]+\.[0-9]+\.[0-9]+/ {print $2; exit}' CHANGELOG.md)
[ -n "$v" ] || { echo "no ## x.y.z section in CHANGELOG.md" >&2; exit 1; }
if gh release view "v$v" >/dev/null 2>&1; then
  echo "v$v is already released — add a new ## section to CHANGELOG.md" >&2
  exit 1
fi
sha=$(git rev-parse HEAD)
echo "== Laserdot+ $v from ${sha:0:7}"
start=$(date +%s)

if ! $quick; then
  echo "== Go tests"
  test -z "$(gofmt -l .)" || { gofmt -l .; exit 1; }
  go vet ./...
  go test ./...
fi

echo "== Build"
app/scripts/build-ffmpeg.sh
VERSION="$v" app/scripts/build-go.sh universal
git diff --exit-code app/Sources/LaserdotKit/Registry.generated.swift \
  || { echo "the registry changed: commit Registry.generated.swift" >&2; exit 1; }
if ! $quick; then
  echo "== Swift tests"
  (cd app && LASERDOTD="$PWD/build/go/laserdotd" swift test)
fi
VERSION="$v" BUILD="local-$(date +%Y%m%d%H%M)" app/scripts/bundle.sh
out=$(mktemp -d)
app/scripts/make-dmg.sh "$out/LaserdotPlus-$v.dmg"

echo "== The packaged app launches"
d=$(mktemp -d)
LASERDOT_DB="$d/data/index.db" "app/build/Laserdot+.app/Contents/MacOS/LaserdotPlus" >"$d/app.log" 2>&1 &
pid=$!
sleep 6
kill -0 "$pid" 2>/dev/null || { cat "$d/app.log"; echo "Laserdot+ exited at launch" >&2; exit 1; }
kill "$pid"
pkill -f "Laserdot+.app/Contents/MacOS/laserdotd" || true
rm -rf "$d"

echo "== Publish"
git push --quiet origin main
{ awk -v h="## $v" '$0 == h {on=1; next} /^## / {on=0} on' CHANGELOG.md; echo
  echo "Open the disk image and drag Laserdot+ to Applications. The first time, right-click Laserdot+ → Open (the app is not notarized). Laserdot+ ▸ Check for Updates… tells you when a newer version is out (it asks GitHub for the version number only)."; } >"$out/notes.md"
# Also under a fixed name: the README links to releases/latest/download/LaserdotPlus.dmg.
cp "$out/LaserdotPlus-$v.dmg" "$out/LaserdotPlus.dmg"
gh release create "v$v" "$out/LaserdotPlus-$v.dmg" "$out/LaserdotPlus.dmg" \
  --target "$sha" --title "Laserdot+ $v" --notes-file "$out/notes.md"
echo "== Released Laserdot+ $v in $(( ($(date +%s) - start) / 60 )) min"
