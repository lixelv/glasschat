#!/bin/zsh
# Renders Resources/AppIcon.icon (an Icon Composer document) with Icon Composer's ictool into
# Resources/AppIcon.icns (the light rendition: Finder and Launchpad show it) and
# Resources/AppIcon-Light.png / AppIcon-Dark.png (the app shows the one of the current appearance in the Dock).
set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
TMP="$(mktemp -d)"

# One rendition as a 1024 px macOS icon: ictool draws the shape edge to edge, a macOS icon's is 824 of 1024.
render() {
  "$ICTOOL" Resources/AppIcon.icon --export-image --output-file "$TMP/$1-full.png" \
    --platform macOS --rendition "$1" --width 1024 --height 1024 --scale 1 >/dev/null
  sips -Z 824 "$TMP/$1-full.png" --out "$TMP/$1-shape.png" >/dev/null
  sips --padToHeightWidth 1024 1024 "$TMP/$1-shape.png" --out "$2" >/dev/null
}

render Default "$TMP/1024.png"
render Dark "$TMP/dark.png"
sips -z 512 512 "$TMP/1024.png" --out Resources/AppIcon-Light.png >/dev/null
sips -z 512 512 "$TMP/dark.png" --out Resources/AppIcon-Dark.png >/dev/null

SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for px in 16 32 64 128 256 512 1024; do
  sips -z $px $px "$TMP/1024.png" --out "$TMP/$px.png" >/dev/null
done
cp "$TMP/16.png" "$SET/icon_16x16.png"
for px in 32 128 256 512; do
  cp "$TMP/$px.png" "$SET/icon_${px}x${px}.png"
  cp "$TMP/$((px * 2)).png" "$SET/icon_$((px / 2))x$((px / 2))@2x.png"
done
cp "$TMP/64.png" "$SET/icon_32x32@2x.png"
cp "$TMP/1024.png" "$SET/icon_512x512@2x.png"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns, AppIcon-Light.png, AppIcon-Dark.png"
