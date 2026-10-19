#!/bin/zsh
# Build GlassChat in release mode and install it as ~/Applications/GlassChat.app.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK needs SwiftUI macro plugins that ship only with Xcode; 26.5 does not.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
swift build -c release --sdk "$SDK"
BIN="$(swift build -c release --sdk "$SDK" --show-bin-path)"
APP="build/GlassChat.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GlassChat" "$APP/Contents/MacOS/GlassChat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done
codesign --force --deep --sign - "$APP"

mkdir -p ~/Applications
pkill -x GlassChat 2>/dev/null || true
rm -rf ~/Applications/GlassChat.app
ditto "$APP" ~/Applications/GlassChat.app
echo "Installed ~/Applications/GlassChat.app"
[[ "${1:-}" == "--open" ]] && open ~/Applications/GlassChat.app
exit 0
