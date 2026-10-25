#!/bin/zsh
# Build the debug app and run its self-tests (the pure logic; the rest is checked by running the app).
set -euo pipefail
cd "$(dirname "$0")/.."

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
# Built outside the project: its folder is synced (File Provider), which marks new bundles with Finder info
# that codesign refuses.
SCRATCH="$HOME/Library/Caches/dev.lixelv.glasschat/build"
mkdir -p .build
swift build --sdk "$SDK" --scratch-path "$SCRATCH" > .build/selftest-build.log 2>&1 || { grep -E "error:" .build/selftest-build.log | sort -u | head -20; exit 1; }
GLASSCHAT_SELF_TEST=1 "$(swift build --sdk "$SDK" --scratch-path "$SCRATCH" --show-bin-path)/GlassChat"
