#!/usr/bin/env bash
# Assembles app/build/Laserdot+.app: the SwiftUI app, laserdotd (and the
# bundled ffmpeg, when built) beside it in Contents/MacOS, the icon and the
# version. Run app/scripts/build-go.sh first.
#
#   VERSION=0.1.0 BUILD=42 app/scripts/bundle.sh
#
# Signed ad hoc (Apple Silicon requires a signature). The only networked code is
# the bundled update check (asks GitHub for the latest version, on request).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
DAEMON=build/go/laserdotd
[ -x "$DAEMON" ] || { echo "missing $DAEMON: run app/scripts/build-go.sh first" >&2; exit 1; }
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/Laserdot+.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/LaserdotPlus" "$APP/Contents/MacOS/LaserdotPlus"
cp "$DAEMON" "$APP/Contents/MacOS/laserdotd"
# The update check: the only code that uses the network (GitHub, latest
# release's version only).
cp "$BIN/laserdotplus-update-check" "$APP/Contents/MacOS/laserdotplus-update-check"
if [ -x build/ffmpeg/ffprobe ]; then
  cp build/ffmpeg/ffmpeg build/ffmpeg/ffprobe "$APP/Contents/MacOS/"
  mkdir -p "$APP/Contents/Resources/FFmpeg"
  cp build/ffmpeg/LICENSE.txt build/ffmpeg/README.txt "$APP/Contents/Resources/FFmpeg/"
fi
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
cp Info.plist "$APP/Contents/Info.plist"
for lang in en ar; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
  printf '"CFBundleDisplayName" = "Laserdot+";\n"CFBundleName" = "Laserdot+";\n' > "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP ($VERSION, build $BUILD)"
