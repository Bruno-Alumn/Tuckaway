#!/bin/sh
# Downloads a release DMG, verifies its actual SHA-256 against GitHub's digest,
# and checks that it is signed with the Developer ID and notarized.
set -eu

TAG="${1:-$(gh release view --repo Bruno-Alumn/Tuckaway --json tagName --jq .tagName)}"
RELEASE_JSON=$(gh release view "$TAG" --repo Bruno-Alumn/Tuckaway --json assets)
DMG_URL=$(printf '%s' "$RELEASE_JSON" | python3 -c 'import json,sys; print(next(a["url"] for a in json.load(sys.stdin)["assets"] if a["name"] == "Tuckaway.dmg"))')
EXPECTED=$(printf '%s' "$RELEASE_JSON" | python3 -c 'import json,sys; print(next(a["digest"] for a in json.load(sys.stdin)["assets"] if a["name"] == "Tuckaway.dmg"))')
EXPECTED=${EXPECTED#sha256:}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tuckaway-release-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
curl --fail --location --silent --show-error --connect-timeout 20 --max-time 300 --output "$WORK/Tuckaway.dmg" "$DMG_URL"
ACTUAL=$(shasum -a 256 "$WORK/Tuckaway.dmg" | cut -d' ' -f1)
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "error: SHA-256 mismatch for $TAG: expected $EXPECTED, got $ACTUAL" >&2
  exit 1
fi
GATEKEEPER=$(spctl --assess --type open --context context:primary-signature -v "$WORK/Tuckaway.dmg" 2>&1) || true
if ! printf '%s' "$GATEKEEPER" | grep -q 'source=Notarized Developer ID'; then
  echo "error: $TAG DMG is not a notarized Developer ID build:" >&2
  printf '%s\n' "$GATEKEEPER" >&2
  exit 1
fi
xcrun stapler validate -q "$WORK/Tuckaway.dmg"
echo "Verified $TAG DMG SHA-256: $ACTUAL, notarized Developer ID, ticket stapled"
