#!/usr/bin/env bash
#
# Publishes what scripts/release.sh built as GitHub release v<version>, marked
# latest, so both the README download link and the in-app updater pick it up.
#
#   scripts/publish.sh            # notes from scripts/notes/<version>.md if present
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
cd "$ROOT"

[[ -f "$DIST/Rodinia.dmg" && -f "$DIST/appcast.xml" ]] || { echo "!! run scripts/release.sh first" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DIST/work/Rodinia.app/Contents/Info.plist")
TAG="v$VERSION"
SHA=$(shasum -a 256 "$DIST/Rodinia.dmg" | cut -d' ' -f1)

NOTES="$(cat "scripts/notes/$VERSION.md" 2>/dev/null || true)"
NOTES="$NOTES

Open the dmg and drag Rodinia into Applications. Already installed? Rodinia updates itself.

SHA-256 of Rodinia.dmg: \`$SHA\`"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DIST/Rodinia.dmg" "$DIST/appcast.xml" --clobber
  gh release edit "$TAG" --notes "$NOTES" --latest
else
  gh release create "$TAG" "$DIST/Rodinia.dmg" "$DIST/appcast.xml" \
    --title "Rodinia $VERSION" --notes "$NOTES" --latest
fi
echo "==> published $TAG"
