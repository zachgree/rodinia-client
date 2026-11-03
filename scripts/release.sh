#!/usr/bin/env bash
#
# Builds a notarized, stapled Rodinia-<version>.dmg in dist/.
#
# One-time setup:
#   xcrun notarytool store-credentials rodinia-notary --apple-id <id> --team-id <team>
#   Developer ID provisioning profiles for the app and tunnel, with the
#   Network Extension and System Extension capabilities, installed in Xcode.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-rodinia-notary}"
DIST="$ROOT/dist"
ARCHIVE="$DIST/Rodinia.xcarchive"

cd "$ROOT"
[[ -d Frameworks/RodiniaCore.xcframework ]] || scripts/build-core.sh
xcodegen generate --quiet

TEAM=$(xcodebuild -showBuildSettings -project Rodinia.xcodeproj -scheme Rodinia 2>/dev/null | awk '/ DEVELOPMENT_TEAM =/ {print $3; exit}')
[[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in Config/Local.xcconfig" >&2; exit 1; }

rm -rf "$DIST" && mkdir -p "$DIST"

echo "==> archive"
xcodebuild -project Rodinia.xcodeproj -scheme Rodinia -configuration Release \
  -archivePath "$ARCHIVE" archive -quiet

echo "==> export (Developer ID)"
cat > "$DIST/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$DIST/ExportOptions.plist" \
  -exportPath "$DIST" -quiet

APP="$DIST/Rodinia.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$DIST/Rodinia-$VERSION.dmg"

echo "==> dmg"
STAGE="$DIST/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Rodinia" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "==> notarize"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> $DMG"
