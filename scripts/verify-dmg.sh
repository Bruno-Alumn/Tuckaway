#!/bin/sh
# Mounts a Tuckaway DMG, copies and verifies its app, then ejects and cleans up.
set -eu

DMG="${1:-dist/Tuckaway.dmg}"
EXPECTED_BUNDLE_ID="${2:-com.brunoalumn.tuckaway}"
if [ ! -f "$DMG" ]; then
  echo "error: DMG not found: $DMG" >&2
  exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tuckaway-dmg-check.XXXXXX")
MOUNT="$WORK/mount"
EXTRACTED="$WORK/extracted"
ATTACHED=0

cleanup() {
  if [ "$ATTACHED" -eq 1 ]; then
    if diskutil image attach --help >/dev/null 2>&1; then
      diskutil eject "$MOUNT" >/dev/null 2>&1 || true
    else
      hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM
mkdir -p "$MOUNT" "$EXTRACTED"

if diskutil image attach --help >/dev/null 2>&1; then
  diskutil image attach "$DMG" --readOnly --nobrowse --mountPoint "$MOUNT" >/dev/null
else
  hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" >/dev/null
fi
ATTACHED=1

ditto "$MOUNT/Tuckaway.app" "$EXTRACTED/Tuckaway.app"
codesign --verify --deep --strict "$EXTRACTED/Tuckaway.app"
ACTUAL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXTRACTED/Tuckaway.app/Contents/Info.plist")
if [ "$ACTUAL_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
  echo "error: unexpected bundle ID: $ACTUAL_BUNDLE_ID" >&2
  exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED/Tuckaway.app/Contents/Info.plist")
echo "Verified $DMG: Tuckaway $VERSION ($ACTUAL_BUNDLE_ID), mounted, copied, signature checked, and ejected."
