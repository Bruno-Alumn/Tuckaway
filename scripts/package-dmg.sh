#!/bin/sh
# Builds the direct-download release and packages it as dist/Tuckaway.dmg,
# the asset the in-app updater installs from.
#
# Releases are signed with the "Tuckaway Release Signing" certificate from the
# login keychain. Signing every release with the same certificate is what lets
# macOS keep Tuckaway's permissions (and firewall rules) across updates, and
# the updater refuses updates signed with anything else. See docs/RUNBOOK.md.
#
#   scripts/package-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: …" scripts/package-dmg.sh
#   ALLOW_ADHOC=1 scripts/package-dmg.sh    # test builds only: resets users' permissions
#   EXPECTED_VERSION=vX.Y.Z scripts/package-dmg.sh  # fail if the app version differs
set -eu

cd "$(dirname "$0")/.."
IDENTITY="${SIGN_IDENTITY:-Tuckaway Release Signing}"
DERIVED="build/package"
APP="$DERIVED/Build/Products/Release-Direct/Tuckaway.app"
STAGING="build/dmg-staging"
DMG="dist/Tuckaway.dmg"
trap 'rm -rf "$STAGING"' EXIT INT TERM

if ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  if [ "${ALLOW_ADHOC:-}" = 1 ]; then
    echo "warning: \"$IDENTITY\" not found; signing ad-hoc. Users would have to re-grant permissions." >&2
    IDENTITY="-"
  else
    echo "error: signing identity \"$IDENTITY\" not found in the keychain (see docs/RUNBOOK.md)." >&2
    echo "       Set ALLOW_ADHOC=1 for a throwaway test build." >&2
    exit 1
  fi
fi

rm -rf "$DERIVED" "$STAGING"
xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway -configuration Release-Direct \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build >/dev/null

# Guard against shipping the wrong build (v1.0.0 shipped a Debug build).
if [ -e "$APP/Contents/MacOS/Tuckaway.debug.dylib" ]; then
  echo "error: $APP is a Debug build" >&2; exit 1
fi
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox; then
  echo "error: $APP is the sandboxed App Store build" >&2; exit 1
fi

# Xcode signs the build ad-hoc; re-sign it with the release identity and the
# direct build's own entitlements (which also drops the debug-only
# get-task-allow Xcode adds).
codesign --force --deep --options runtime --entitlements hidden/Hidden-Direct.entitlements \
  -s "$IDENTITY" "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --deep --strict "$APP"
if [ "$IDENTITY" != "-" ] && ! codesign -dr - "$APP" 2>&1 | grep -q "certificate"; then
  echo "error: $APP is not certificate-signed" >&2; exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [ -n "${EXPECTED_VERSION:-}" ] && [ "$EXPECTED_VERSION" != "$VERSION" ] && [ "$EXPECTED_VERSION" != "v$VERSION" ]; then
  echo "error: expected version $EXPECTED_VERSION, but the app is $VERSION" >&2
  exit 1
fi

mkdir -p "$STAGING" dist
ditto "$APP" "$STAGING/Tuckaway.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from --format UDZO --volumeName "Tuckaway $VERSION" "$STAGING" "$DMG" >/dev/null
else
  hdiutil create -volname "Tuckaway $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
fi
rm -rf "$STAGING"

echo "Built $DMG (Tuckaway $VERSION, signed by \"$IDENTITY\"). Publish it as the release asset, tagged v$VERSION."
