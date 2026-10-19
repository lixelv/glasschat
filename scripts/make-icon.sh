#!/bin/zsh
# Renders Resources/AppIcon.icon (an Icon Composer document) into Resources/AppIcon.icns with Icon Composer's ictool.
set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
TMP="$(mktemp -d)"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"

"$ICTOOL" Resources/AppIcon.icon --export-image --output-file "$TMP/full.png" \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 >/dev/null
# ictool draws the shape edge to edge; a macOS icon's shape is 824 of 1024 points, centred.
sips -Z 824 "$TMP/full.png" --out "$TMP/shape.png" >/dev/null
sips --padToHeightWidth 1024 1024 "$TMP/shape.png" --out "$TMP/1024.png" >/dev/null

for px in 16 32 64 128 256 512 1024; do
  sips -z $px $px "$TMP/1024.png" --out "$TMP/$px.png" >/dev/null
done
cp "$TMP/16.png" "$SET/icon_16x16.png"
for px in 32 128 256 512; do
  cp "$TMP/$px.png" "$SET/icon_${px}x${px}.png"
  cp "$TMP/$((px * 2)).png" "$SET/icon_$((px / 2))x$((px / 2))@2x.png"
done
cp "$TMP/1024.png" "$SET/icon_512x512@2x.png"
cp "$TMP/64.png" "$SET/icon_32x32@2x.png"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
