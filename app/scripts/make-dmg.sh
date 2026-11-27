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
# Notarized by Apple when the keys are there (an App Store Connect API key:
# NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER), so it opens without the
# right-click step. Only the disk image's checksum is sent to Apple, by
# Apple's own tool, at build time on the build machine — never by the app.
if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_KEY_PATH:-}" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$OUT"
  xcrun notarytool submit "$OUT" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  xcrun stapler staple "$OUT"
fi
echo "built $OUT"
