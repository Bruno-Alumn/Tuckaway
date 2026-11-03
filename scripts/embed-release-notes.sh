#!/bin/sh
# Copies the released sections of CHANGELOG.md into a Tuckaway build, so "What's
# New" can show them offline. The App Store build has no network access, and a
# released app can't fetch notes for its own version afterwards, so the notes
# travel inside the bundle. The app picks the sections newer than the version
# the user last ran (WhatsNew.plan).
#
# Run by the Release build phase and by scripts/package-dmg.sh. A version with no
# section of its own (a build from source) gets no notes and shows no window; the
# packaging script refuses that for a release.
#
#   scripts/embed-release-notes.sh <Tuckaway.app>
set -eu

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: $0 <path to Tuckaway.app>" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
OUT="$APP/Contents/Resources/WhatsNew.md"
rm -f "$OUT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if ! grep -q "^## v$VERSION\( \|$\)" CHANGELOG.md 2>/dev/null; then
  echo "embed-release-notes: CHANGELOG.md has no '## v$VERSION' section; skipping" >&2
  exit 0
fi

mkdir -p "$APP/Contents/Resources"
# Everything from the first released section down; `## Unreleased` sits above it.
awk '/^## v/ { found = 1 } found { print }' CHANGELOG.md > "$OUT"
echo "embed-release-notes: wrote $(grep -c '^## v' "$OUT") releases, newest v$VERSION" >&2
