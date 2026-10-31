#!/bin/sh
# Updates the cask's version and SHA-256 from the latest GitHub release, then validates it.
set -eu
trap 'brew developer off >/dev/null 2>&1 || true' EXIT INT TERM

CASK_PATH="${CASK_PATH:-Casks/tuckaway.rb}"
if [ ! -f "$CASK_PATH" ]; then
  echo "error: cask not found: $CASK_PATH" >&2
  exit 1
fi

TAG=$(gh release view --repo Bruno-Alumn/Tuckaway --json tagName --jq .tagName)
DIGEST=$(gh release view "$TAG" --repo Bruno-Alumn/Tuckaway --json assets --jq '.assets[] | select(.name == "Tuckaway.dmg") | .digest')
VERSION=${TAG#v}
SHA=${DIGEST#sha256:}
case "$SHA" in
  *[!0-9a-f]*)
    echo "error: invalid DMG digest from GitHub: $DIGEST" >&2
    exit 1
    ;;
esac
if [ "${#SHA}" -ne 64 ]; then
  echo "error: invalid DMG digest from GitHub: $DIGEST" >&2
  exit 1
fi

CASK_PATH="$CASK_PATH" VERSION="$VERSION" SHA="$SHA" python3 - <<'PY'
import os
import re

path = os.environ["CASK_PATH"]
with open(path) as source:
    content = source.read()
content, version_count = re.subn(r'version "[^"]+"', f'version "{os.environ["VERSION"]}"', content, count=1)
content, sha_count = re.subn(r'sha256 "[^"]+"', f'sha256 "{os.environ["SHA"]}"', content, count=1)
if version_count != 1 or sha_count != 1:
    raise SystemExit(f"error: could not update version and SHA-256 in {path}")
with open(path, "w") as destination:
    destination.write(content)
PY

ruby -c "$CASK_PATH"
brew style "$CASK_PATH"
echo "Updated $CASK_PATH to Tuckaway $VERSION"
