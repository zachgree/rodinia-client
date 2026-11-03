#!/usr/bin/env bash
#
# Builds a Developer ID signed, notarized and stapled dist/Rodinia-<version>.dmg.
#
# Xcode can't sign a Network Extension for Developer ID with automatic signing
# (its managed "Direct" profiles are refused for manual signing, and an export
# doesn't rewrite the packet-tunnel entitlement), so this script builds unsigned
# and signs with codesign itself.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain.
#   2. Developer ID provisioning profiles for both bundle IDs. Either let Xcode
#      create them (a Debug build with -allowProvisioningUpdates, then an Xcode
#      Developer ID export attempt), or download them from the developer portal
#      into ~/Library/Developer/Xcode/UserData/Provisioning Profiles.
#   3. xcrun notarytool store-credentials rodinia-notary
#
#   scripts/release.sh            # build, sign, notarize
#   SKIP_NOTARIZE=1 scripts/release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTARY_PROFILE="${NOTARY_PROFILE:-rodinia-notary}"
DIST="$ROOT/dist"
WORK="$DIST/work"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

cd "$ROOT"
[[ -d Frameworks/RodiniaCore.xcframework ]] || scripts/build-core.sh
xcodegen generate --quiet

setting() {
  xcodebuild -showBuildSettings -project Rodinia.xcodeproj -target Rodinia -configuration Release 2>/dev/null \
    | awk -v key="$1" '$1 == key && $2 == "=" { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }'
}
TEAM=$(setting DEVELOPMENT_TEAM)
APP_ID=$(setting APP_BUNDLE_ID)
TUNNEL_ID=$(setting TUNNEL_BUNDLE_ID)
[[ -n "$TEAM" ]] || { echo "!! set DEVELOPMENT_TEAM in Config/Local.xcconfig" >&2; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' -v team="($TEAM)" '/Developer ID Application/ && index($2, team) { print $2; exit }')
[[ -n "$IDENTITY" ]] || { echo "!! no Developer ID Application certificate for team $TEAM in the keychain" >&2; exit 1; }

# The newest Developer ID profile for a bundle ID that allows the system-extension tunnel.
profile_for() {
  local bundle="$1" best="" best_date=0
  for f in "$PROFILES"/*.provisionprofile; do
    [[ -e "$f" ]] || continue
    local plist; plist=$(security cms -D -i "$f" 2>/dev/null) || continue
    local appid; appid=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:com.apple.application-identifier' /dev/stdin <<<"$plist" 2>/dev/null) || continue
    [[ "$appid" == "$TEAM.$bundle" ]] || continue
    /usr/libexec/PlistBuddy -c 'Print Entitlements:com.apple.developer.networking.networkextension' /dev/stdin <<<"$plist" 2>/dev/null \
      | grep -q 'packet-tunnel-provider-systemextension' || continue
    local created; created=$(/usr/libexec/PlistBuddy -c 'Print CreationDate' /dev/stdin <<<"$plist" | xargs -I{} date -j -f "%a %b %d %T %Z %Y" "{}" +%s 2>/dev/null || echo 0)
    if (( created >= best_date )); then best="$f"; best_date=$created; fi
  done
  [[ -n "$best" ]] || { echo "!! no Developer ID provisioning profile for $bundle (see the header of this script)" >&2; exit 1; }
  echo "$best"
}
APP_PROFILE=$(profile_for "$APP_ID")
TUNNEL_PROFILE=$(profile_for "$TUNNEL_ID")

rm -rf "$DIST" && mkdir -p "$WORK"

echo "==> building $APP_ID (Release, unsigned)"
xcodebuild -project Rodinia.xcodeproj -scheme Rodinia -configuration Release \
  -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath "$ROOT/.build/release" CODE_SIGNING_ALLOWED=NO build -quiet
cp -R "$ROOT/.build/release/Build/Products/Release/Rodinia.app" "$WORK/"
APP="$WORK/Rodinia.app"
EXT="$APP/Contents/Library/SystemExtensions/$TUNNEL_ID.systemextension"
[[ -d "$EXT" ]] || { echo "!! tunnel extension missing from the app bundle" >&2; exit 1; }

# Entitlements as Developer ID wants them: the -systemextension tunnel value and
# the identifiers the profile is checked against.
entitlements() {
  local source="$1" bundle="$2" out="$3"
  sed 's/\$(NE_TUNNEL_PROVIDER)/packet-tunnel-provider-systemextension/' "$source" > "$out"
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM.$bundle" "$out"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM" "$out"
}
entitlements Tunnel/RodiniaTunnel.entitlements "$TUNNEL_ID" "$WORK/tunnel.entitlements"
entitlements App/Rodinia.entitlements "$APP_ID" "$WORK/app.entitlements"

echo "==> signing with $IDENTITY"
cp "$TUNNEL_PROFILE" "$EXT/Contents/embedded.provisionprofile"
cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
# Inside out: the extension first, then the app that contains it.
codesign --force --options runtime --timestamp --entitlements "$WORK/tunnel.entitlements" --sign "$IDENTITY" "$EXT"
codesign --force --options runtime --timestamp --entitlements "$WORK/app.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=1 "$APP"

if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
  # Staple the app itself so it opens offline even after it's copied out of the dmg.
  echo "==> notarizing the app (a few minutes)"
  ditto -c -k --keepParent "$APP" "$WORK/Rodinia.zip"
  xcrun notarytool submit "$WORK/Rodinia.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$DIST/Rodinia-$VERSION.dmg"

echo "==> dmg"
STAGE="$WORK/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
# hdiutil underestimates the volume for this bundle; size it from the contents.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 40 ))
hdiutil create -volname "Rodinia" -srcfolder "$STAGE" -size "${SIZE_MB}m" -fs HFS+ -ov -format UDZO "$DMG" -quiet
codesign --timestamp --sign "$IDENTITY" "$DMG"

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
  echo "==> $DMG (signed, NOT notarized)"
  exit 0
fi

echo "==> notarizing the dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "==> $DMG"
