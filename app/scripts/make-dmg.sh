#!/usr/bin/env bash
# Packs app/build/Laserdot+.app into a drag-to-install disk image:
#   app/scripts/make-dmg.sh out/LaserdotPlus-0.1.0.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: make-dmg.sh OUTPUT.dmg}"
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "build/Laserdot+.app" "$STAGE/Laserdot+.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
for i in 1 2 3; do hdiutil create -volname "Laserdot+" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null && break; sleep 5; done
echo "built $OUT"
