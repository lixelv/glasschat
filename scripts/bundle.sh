#!/bin/zsh
# Build GlassChat in release mode and install it as ~/Applications/GlassChat.app.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK needs SwiftUI macro plugins that ship only with Xcode; 26.5 does not.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
# Built outside the project: its folder is synced (File Provider), which marks new bundles with Finder info
# that codesign refuses.
SCRATCH="$HOME/Library/Caches/dev.lixelv.glasschat/build"
swift build -c release --sdk "$SDK" --scratch-path "$SCRATCH"
BIN="$(swift build -c release --sdk "$SDK" --scratch-path "$SCRATCH" --show-bin-path)"
# Assembled and signed outside the repository: a synced folder (iCloud Drive, File Provider) puts Finder
# information back on the .bundle folders, and codesign refuses them.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/GlassChat.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GlassChat" "$APP/Contents/MacOS/GlassChat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/AppIcon-Light.png Resources/AppIcon-Dark.png "$APP/Contents/Resources/" 2>/dev/null || true
for b in "$BIN"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
# A copy for scripts/dmg-settings.py.
rm -rf build/GlassChat.app
mkdir -p build
ditto --norsrc --noextattr "$APP" build/GlassChat.app

mkdir -p ~/Applications
pkill -x GlassChat 2>/dev/null || true
rm -rf ~/Applications/GlassChat.app
ditto --norsrc --noextattr "$APP" ~/Applications/GlassChat.app
echo "Installed ~/Applications/GlassChat.app"
[[ "${1:-}" == "--open" ]] && open ~/Applications/GlassChat.app
exit 0
