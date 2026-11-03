#!/bin/sh
# Copies the latest release notes into a Tuckaway build, so "What's New" can
# show them offline. The App Store build has no network access, and a released
# app can't fetch notes for its own version afterwards, so the notes travel
# inside the bundle.
#
# It takes this version's CHANGELOG.md section (and, after a larger jump, the
# ones since the previous release) and writes Resources/WhatsNew.md in the form
# WhatsNew.parse reads:
#
#     versions: 1.8.0-1.9.0
#
#     ### Added
#     - …
#
# Run by the Release build phase and by scripts/package-dmg.sh. Missing notes are
# not an error: the app then shows no "What's New" window.
#
#   scripts/embed-release-notes.sh <Tuckaway.app>
set -eu

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: $0 <path to Tuckaway.app>" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
if [ ! -f CHANGELOG.md ]; then
  echo "embed-release-notes: no CHANGELOG.md; skipping" >&2
  exit 0
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
# The release before this one, so an update from it — or from anything older —
# is covered: it is the "## v…" heading just above this version's. `## Unreleased`
# never counts as a release.
PREVIOUS=$(awk -v version="v$VERSION" '
  /^## v/ {
    if (found) { print name; exit }
    name = $2
    if (name == version) found = 1
  }
' CHANGELOG.md)
if [ -z "$PREVIOUS" ]; then
  PREVIOUS="v$VERSION"
fi

mkdir -p "$APP/Contents/Resources"
awk -v from="$PREVIOUS" -v to="v$VERSION" '
  /^## / {
    name = $2
    if (name == to) { section = "target"; print "versions: " substr(from, 2) "-" substr(to, 2); print "" }
    else if (section == "target") exit
    next
  }
  section == "target" { print }
' CHANGELOG.md | sed -e 's/[[:space:]]*$//' > "$APP/Contents/Resources/WhatsNew.md"

# A version with no section yet (a build from source): no notes, not an empty
# "versions:" header the app would refuse on every launch.
if [ "$(grep -c . "$APP/Contents/Resources/WhatsNew.md" || true)" -lt 2 ]; then
  rm -f "$APP/Contents/Resources/WhatsNew.md"
  echo "embed-release-notes: CHANGELOG.md has no section for v$VERSION; skipping" >&2
  exit 0
fi

echo "embed-release-notes: wrote WhatsNew.md for $PREVIOUS..v$VERSION" >&2
