#!/bin/bash
# Builds KVF.app. `./build.sh` for release, `./build.sh debug` while developing.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP=build/KVF.app

swift build -c "$CONFIG" --product KVF

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c "$CONFIG" --show-bin-path)/KVF" "$APP/Contents/MacOS/KVF"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/app-icon.icns "$APP/Contents/Resources/app-icon.icns"

xattr -cr "$APP"  # the icon carries Finder metadata that codesign refuses

# ponytail: ad-hoc signature — enough to run locally. Real Developer ID only matters for distribution.
codesign --force --sign - "$APP" >/dev/null

echo "built $APP  ($(du -sh "$APP" | cut -f1))"
