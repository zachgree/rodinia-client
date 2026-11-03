#!/usr/bin/env bash
#
# Builds Frameworks/RodiniaCore.xcframework from Core/ against a pinned Xray-core.
#
#   scripts/build-core.sh            # macOS (default)
#   TARGETS=macos,ios scripts/build-core.sh
#
set -euo pipefail

XRAY_VERSION="${XRAY_VERSION:-v26.10.31}"
TARGETS="${TARGETS:-macos}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
XRAY_SRC="$BUILD/Xray-core"
OUT="$ROOT/Frameworks/RodiniaCore.xcframework"

# Xray needs a newer Go than Homebrew may have; let the go command fetch it.
export GOTOOLCHAIN=auto
export PATH="$(go env GOPATH)/bin:$PATH"

mkdir -p "$BUILD" "$ROOT/Frameworks"

if [[ "$(git -C "$XRAY_SRC" describe --tags 2>/dev/null || true)" != "$XRAY_VERSION" ]]; then
  echo "==> fetching Xray-core $XRAY_VERSION"
  rm -rf "$XRAY_SRC"
  git clone --quiet --depth 1 --branch "$XRAY_VERSION" https://github.com/XTLS/Xray-core.git "$XRAY_SRC"
fi

if ! command -v gomobile >/dev/null; then
  echo "==> installing gomobile"
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
fi

cd "$ROOT/Core"
go mod tidy
echo "==> gomobile bind ($TARGETS)"
rm -rf "$OUT"
# -trimpath and stripped symbols keep the framework small and the build reproducible.
gomobile bind \
  -target="$TARGETS" \
  -macosversion=15.0 -iosversion=17.0 \
  -trimpath -ldflags="-s -w -buildid=" \
  -o "$OUT" .

echo "==> built $(du -sh "$OUT" | cut -f1) $OUT"
