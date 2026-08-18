#!/bin/zsh
# Builds a signed, notarized, universal KVF.app ready to share.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain.
#   2. Notary credentials:
#        xcrun notarytool store-credentials kvf-notary \
#          --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
#      Already have a profile from another app? Point at it instead:
#        KVF_NOTARY_PROFILE=keytype-notary ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${KVF_IDENTITY:-Developer ID Application}"
PROFILE="${KVF_NOTARY_PROFILE:-kvf-notary}"
APP=build/KVF.app
ZIP=build/KVF.zip

echo "==> Building universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product KVF

# Assemble and sign in a temp dir outside any iCloud-synced folder —
# the iCloud file provider re-stamps xattrs that break codesign.
STAGE=$(mktemp -d /tmp/kvf-release.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
STAGED_APP="$STAGE/KVF.app"
STAGED_ZIP="$STAGE/KVF.zip"

echo "==> Assembling ${STAGED_APP}"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp .build/apple/Products/Release/KVF "$STAGED_APP/Contents/MacOS/KVF"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp Resources/app-icon.icns "$STAGED_APP/Contents/Resources/app-icon.icns"
xattr -cr "$STAGED_APP"

echo "==> Signing with '${IDENTITY}' (hardened runtime)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$STAGED_APP"
codesign --verify --strict --verbose=2 "$STAGED_APP"

echo "==> Notarizing (profile: ${PROFILE})"
ditto -c -k --keepParent "$STAGED_APP" "$STAGED_ZIP"
xcrun notarytool submit "$STAGED_ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$STAGED_APP"

# Zip the stapled app and copy the results back into the project.
rm -f "$STAGED_ZIP"
ditto -c -k --keepParent "$STAGED_APP" "$STAGED_ZIP"
rm -rf "$APP" "$ZIP"
mkdir -p build
ditto "$STAGED_APP" "$APP"
cp "$STAGED_ZIP" "$ZIP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
echo ""
echo "Done. ${ZIP} opens on any Mac (macOS 14+) with no warnings."
echo "Publish:"
echo "  gh release create v${VERSION} ${ZIP} --title \"KVF ${VERSION}\" --notes \"...\""
echo "  /opt/homebrew/Library/Taps/steingmo/homebrew-tap/bump-cask.sh kvf-player ${VERSION}"
spctl --assess --type execute --verbose "$APP" || true
