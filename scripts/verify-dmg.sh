#!/bin/sh
# Mounts a Tuckaway DMG, copies and verifies its app, then ejects and cleans up.
set -eu

# Older diskutil versions have `image attach` without every option used here,
# so check for the options themselves rather than the subcommand.
diskutil_attach_supported() {
  attach_help=$(diskutil image attach --help 2>&1) || return 1
  for option in --readOnly --nobrowse --mountPoint; do
    printf '%s\n' "$attach_help" | grep -q -- "$option" || return 1
  done
}

DMG="${1:-dist/Tuckaway.dmg}"
EXPECTED_BUNDLE_ID="${2:-com.brunoalumn.tuckaway}"
EXPECTED_VERSION="${3:-}"
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
    if diskutil_attach_supported; then
      diskutil eject "$MOUNT" >/dev/null 2>&1 || true
    else
      hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM
mkdir -p "$MOUNT" "$EXTRACTED"

if diskutil_attach_supported; then
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
if [ -n "$EXPECTED_VERSION" ] && [ "$EXPECTED_VERSION" != "$VERSION" ] && [ "$EXPECTED_VERSION" != "v$VERSION" ]; then
  echo "error: expected version $EXPECTED_VERSION, but the app is $VERSION" >&2
  exit 1
fi
echo "Verified $DMG: Tuckaway $VERSION ($ACTUAL_BUNDLE_ID), mounted, copied, signature checked, and ejected."
