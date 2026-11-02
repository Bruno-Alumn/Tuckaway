#!/bin/bash
# Points packaging/tuckaway.rb at a published release, taking the sha256 from
# GitHub's digest of the uploaded DMG. With --publish it also copies the cask
# into the tap (Bruno-Alumn/homebrew-tuckaway) and pushes it.
#
#   scripts/update-cask.sh [--publish] [vX.Y.Z]   (default: the latest release)
set -euo pipefail

REPO=Bruno-Alumn/Tuckaway
TAP=Bruno-Alumn/homebrew-tuckaway
CASK=packaging/tuckaway.rb

publish=0
tag=""
for arg in "$@"; do
  case "$arg" in
    --publish) publish=1 ;;
    v*) tag=$arg ;;
    *) echo "usage: $0 [--publish] [vX.Y.Z]" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
[ -n "$tag" ] || tag=$(gh release view --repo "$REPO" --json tagName -q .tagName)
digest=$(gh release view "$tag" --repo "$REPO" --json assets \
  -q '.assets[] | select(.name == "Tuckaway.dmg") | .digest')
sha=${digest#sha256:}
if ! [[ $sha =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: $tag has no Tuckaway.dmg digest (got '$digest')" >&2
  exit 1
fi
version=${tag#v}

# Replace exactly one version and one sha256 line, or fail.
sed -E -i '' \
  -e "s/^  version \"[^\"]*\"$/  version \"$version\"/" \
  -e "s/^  sha256 \"[0-9a-f]*\"$/  sha256 \"$sha\"/" "$CASK"
grep -qx "  version \"$version\"" "$CASK" && grep -qx "  sha256 \"$sha\"" "$CASK" || {
  echo "error: could not set version and sha256 in $CASK" >&2
  exit 1
}
ruby -c "$CASK" >/dev/null
echo "$CASK now points at Tuckaway $version ($sha)"

[ "$publish" = 1 ] || exit 0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh repo clone "$TAP" "$work/tap" -- --quiet
mkdir -p "$work/tap/Casks"
cp "$CASK" "$work/tap/Casks/tuckaway.rb"
if git -C "$work/tap" diff --quiet -- Casks/tuckaway.rb \
  && git -C "$work/tap" ls-files --error-unmatch Casks/tuckaway.rb >/dev/null 2>&1; then
  echo "The tap already has Tuckaway $version"
  exit 0
fi
git -C "$work/tap" add Casks/tuckaway.rb
# Commit as this repository's author: the global email may be one GitHub
# refuses to publish.
git -C "$work/tap" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
  commit --quiet -m "tuckaway $version"
git -C "$work/tap" push --quiet origin HEAD
echo "Published Tuckaway $version to $TAP"
