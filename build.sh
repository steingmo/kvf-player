#!/bin/bash
# Builds KVF.app. `./build.sh` for release, `./build.sh debug` while developing.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP=build/KVF.app

swift build -c "$CONFIG" --product KVF
BIN=$(swift build -c "$CONFIG" --show-bin-path)

# Assemble and sign outside iCloud — the file provider re-stamps FinderInfo on
# anything under ~/Documents, and codesign refuses to sign a bundle carrying it.
STAGE=$(mktemp -d /tmp/kvf-build.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="$STAGE/KVF.app"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$STAGED_APP/Contents/Frameworks"
cp "$BIN/KVF" "$STAGED_APP/Contents/MacOS/KVF"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp Resources/app-icon.icns "$STAGED_APP/Contents/Resources/app-icon.icns"

# The binary links Sparkle, so an unbundled build would crash on launch.
ditto "$BIN/Sparkle.framework" "$STAGED_APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$STAGED_APP/Contents/MacOS/KVF"
xattr -cr "$STAGED_APP"

# ponytail: ad-hoc signature — enough to run locally. Real Developer ID only matters for distribution.
codesign --force --deep --sign - "$STAGED_APP/Contents/Frameworks/Sparkle.framework" >/dev/null
codesign --force --sign - "$STAGED_APP" >/dev/null

rm -rf "$APP"
mkdir -p build
ditto "$STAGED_APP" "$APP"

echo "built $APP  ($(du -sh "$APP" | cut -f1))"
