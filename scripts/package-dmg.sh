#!/bin/sh
# Builds the direct-download release and packages it as dist/Tuckaway.dmg,
# the asset the in-app updater installs from.
#
# Releases are signed with the "Tuckaway Release Signing" certificate or the
# maintainer's Developer ID, always with the same designated requirement
# (Updater.releaseRequirement), which accepts either. That requirement is what
# lets macOS keep Tuckaway's permissions (and firewall rules) across updates,
# and the updater refuses updates that don't meet it. A Developer ID build is
# also notarized and stapled. See docs/RUNBOOK.md.
#
#   scripts/package-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: Bruno Cassina (22R95V8NA5)" scripts/package-dmg.sh
#   NOTARY_PROFILE=name                     # notarytool keychain profile (default tuckaway-notary)
#   SKIP_NOTARIZE=1                         # Developer ID test builds that won't be published
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

# The designated requirement, from the one place the updater reads it too.
REQUIREMENT=$(sed -n 's/^ *static let releaseRequirement = #"\(.*\)"#$/\1/p' hidden/Features/Update/Updater.swift)
if [ -z "$REQUIREMENT" ] || ! csreq -r="$REQUIREMENT" -t >/dev/null; then
  echo "error: couldn't read Updater.releaseRequirement" >&2; exit 1
fi
case "$IDENTITY" in
  "Developer ID Application:"*) DEVELOPER_ID=1 ;;
  *) DEVELOPER_ID= ;;
esac
NOTARY_PROFILE="${NOTARY_PROFILE:-tuckaway-notary}"
if [ -n "$DEVELOPER_ID" ] && [ "${SKIP_NOTARIZE:-}" != 1 ] \
   && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "error: notarytool profile \"$NOTARY_PROFILE\" missing or rejected (see docs/RUNBOOK.md)." >&2
  exit 1
fi

if [ -n "${EXPECTED_VERSION:-}" ]; then
  PROJECT_VERSION=$(grep -m1 'MARKETING_VERSION = ' Tuckaway.xcodeproj/project.pbxproj | cut -d' ' -f3 | tr -d ';')
  if [ "$EXPECTED_VERSION" != "$PROJECT_VERSION" ] && [ "$EXPECTED_VERSION" != "v$PROJECT_VERSION" ]; then
    echo "error: expected version $EXPECTED_VERSION, but the project is $PROJECT_VERSION" >&2
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

# "What's New" after an update reads the notes from the bundle. The build phase
# writes them too; doing it again before signing means a release can never ship
# without them, whatever the build folder held.
scripts/embed-release-notes.sh "$APP"
if [ ! -f "$APP/Contents/Resources/WhatsNew.md" ]; then
  echo "error: CHANGELOG.md has no section for this version; rename '## Unreleased' to '## v<version> (<date>)' first (RUNBOOK.md, Release step 2)" >&2
  exit 1
fi

# Xcode signs the build ad-hoc; re-sign it with the release identity and the
# direct build's own entitlements (which also drops the debug-only
# get-task-allow Xcode adds).
# Notarization needs a secure timestamp.
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --options runtime --entitlements hidden/Hidden-Direct.entitlements \
    -s - "$APP" 2>&1 | grep -v "replacing existing signature" || true
else
  codesign --force --deep --options runtime --entitlements hidden/Hidden-Direct.entitlements \
    ${DEVELOPER_ID:+--timestamp} -r="designated => $REQUIREMENT" \
    -s "$IDENTITY" "$APP" 2>&1 | grep -v "replacing existing signature" || true
fi
codesign --verify --deep --strict "$APP"
if [ "$IDENTITY" != "-" ] && ! codesign --verify -R="$REQUIREMENT" "$APP"; then
  echo "error: $APP doesn't meet Updater.releaseRequirement" >&2; exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

mkdir -p "$STAGING" dist
ditto "$APP" "$STAGING/Tuckaway.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
# macOS 27's diskutil replaces hdiutil, but older diskutil versions that have
# `image create from` lack --volumeName (CI's macOS 15 did), so check for the
# option itself rather than the subcommand.
if diskutil image create from --help 2>&1 | grep -q -- '--volumeName'; then
  diskutil image create from --format UDZO --volumeName "Tuckaway $VERSION" "$STAGING" "$DMG" >/dev/null
else
  hdiutil create -volname "Tuckaway $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
fi
rm -rf "$STAGING"

if [ -n "$DEVELOPER_ID" ]; then
  codesign --force --timestamp -s "$IDENTITY" "$DMG"
  if [ "${SKIP_NOTARIZE:-}" = 1 ]; then
    echo "warning: not notarized (SKIP_NOTARIZE=1); don't publish this DMG." >&2
  else
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
  fi
fi

echo "Built $DMG (Tuckaway $VERSION, signed by \"$IDENTITY\"). Publish it as the release asset, tagged v$VERSION."
