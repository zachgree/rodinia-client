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

hdiutil detach "$WORK/mnt" -force -quiet 2>/dev/null || true
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
  # NEMachServiceName in the tunnel's Info.plist must start with this App Group.
  sed -e 's/\$(NE_TUNNEL_PROVIDER)/packet-tunnel-provider-systemextension/' \
      -e "s/\$(DEVELOPMENT_TEAM).\$(APP_BUNDLE_ID)/$TEAM.$APP_ID/" "$source" > "$out"
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM.$bundle" "$out"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM" "$out"
}
entitlements Tunnel/RodiniaTunnel.entitlements "$TUNNEL_ID" "$WORK/tunnel.entitlements"
entitlements App/Rodinia.entitlements "$APP_ID" "$WORK/app.entitlements"

# Fail early rather than ship an extension macOS will reject at activation.
MACH=$(/usr/libexec/PlistBuddy -c 'Print :NetworkExtension:NEMachServiceName' "$EXT/Contents/Info.plist")
[[ "$MACH" == "$TEAM.$APP_ID".* ]] || { echo "!! NEMachServiceName '$MACH' must start with the App Group $TEAM.$APP_ID" >&2; exit 1; }

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
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/scripts/dmg/background.tiff" "$STAGE/.background/background.tiff"

# A writable image first, so Finder can store the window layout in it.
# hdiutil underestimates the volume for this bundle; size it from the contents.
RW="$WORK/rw.dmg"
MNT="$WORK/mnt"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 40 ))
# Finder addresses the volume by name, so no other "Rodinia" volume may be mounted.
for v in /Volumes/Rodinia*; do [[ -d "$v" ]] && hdiutil detach "$v" -force -quiet || true; done
# Mounted at a private path rather than /Volumes/Rodinia: once macOS has seen a
# system extension run from /Volumes/Rodinia it refuses writes there.
hdiutil create -volname "Rodinia" -size "${SIZE_MB}m" -fs HFS+ -type UDIF -layout NONE -ov "$RW" -quiet
mkdir -p "$MNT"
hdiutil attach "$RW" -readwrite -noverify -noautoopen -mountpoint "$MNT" -quiet
ditto "$STAGE" "$MNT"

# Window and icon positions match scripts/dmg/background.tiff (640×400, drawn by
# the debug -snapshots renderer). The first run asks to let Terminal control Finder.
osascript - "$MNT" <<'APPLESCRIPT'
on run argv
  set root to POSIX file (item 1 of argv) as alias
  set bg to POSIX file ((item 1 of argv) & "/.background/background.tiff") as alias
  tell application "Finder"
    set win to container window of folder root
    open folder root
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    set the bounds of win to {200, 120, 840, 548}
    set opts to the icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to bg
    set position of item "Rodinia.app" of folder root to {170, 205}
    set position of item "Applications" of folder root to {470, 205}
    close win
    open folder root
    update folder root without registering applications
    delay 2
    close container window of folder root
  end tell
end run
APPLESCRIPT

rm -rf "$MNT/.fseventsd"
chmod -Rf go-w "$MNT" 2>/dev/null || true
sync
hdiutil detach "$MNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" -quiet
codesign --timestamp --sign "$IDENTITY" "$DMG"

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
  echo "==> $DMG (signed, NOT notarized)"
  exit 0
fi

echo "==> notarizing the dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
# A fixed name, so README's releases/latest/download/Rodinia.dmg link always works.
cp "$DMG" "$DIST/Rodinia.dmg"
echo "==> $DIST/Rodinia.dmg (upload this one)"
