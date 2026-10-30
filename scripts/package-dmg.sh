#!/bin/sh
# Builds the direct-download release and packages it as dist/Tuckaway.dmg,
# the asset the in-app updater installs from.
#
#   scripts/package-dmg.sh                 # ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: …" scripts/package-dmg.sh
set -eu

cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:--}"
DERIVED="build/package"
APP="$DERIVED/Build/Products/Release-Direct/Tuckaway.app"
STAGING="build/dmg-staging"
DMG="dist/Tuckaway.dmg"

rm -rf "$DERIVED" "$STAGING"
xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway -configuration Release-Direct \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build >/dev/null

# Guard against shipping the wrong build (v1.0.0 shipped a Debug build).
if [ -e "$APP/Contents/MacOS/Tuckaway.debug.dylib" ]; then
  echo "error: $APP is a Debug build" >&2; exit 1
fi
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox; then
  echo "error: $APP is the sandboxed App Store build" >&2; exit 1
fi
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

mkdir -p "$STAGING" dist
ditto "$APP" "$STAGING/Tuckaway.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Tuckaway $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Built $DMG (Tuckaway $VERSION). Publish it as the release asset, tagged v$VERSION."
