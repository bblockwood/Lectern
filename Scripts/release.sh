#!/bin/zsh
# Builds a distributable Lectern.app and a DMG in dist/ (gitignored).
#
#   Scripts/release.sh                      # build, sign, DMG
#   NOTARY_PROFILE=Lectern Scripts/release.sh   # ... and notarize + staple with that notarytool keychain profile
#
# Signing: a "Developer ID Application" certificate in the keychain is used when present (what Gatekeeper
# accepts for downloads); otherwise the "Apple Development" identity, which runs on your own Macs after
# "Open Anyway" in System Settings > Privacy & Security but shows a warning on other people's. Override with
# CODESIGN_IDENTITY="Developer ID Application: Name (TEAM)".
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^ *CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml | head -1)
COMMIT=$(git rev-parse --short HEAD)
DERIVED=build/Release
DIST=dist
APP="$DERIVED/Build/Products/Release/Lectern.app"

identities=$(security find-identity -v -p codesigning)
IDENTITY=${CODESIGN_IDENTITY:-}
TIMESTAMP=--timestamp
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(print -r -- "$identities" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(print -r -- "$identities" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
  TIMESTAMP=--timestamp=none
  echo "note: no Developer ID Application certificate in the keychain; signing with the development identity."
  echo "      Gatekeeper will warn when this DMG is downloaded. See README.md, Releases."
fi
[[ -n "$IDENTITY" ]] || { echo "error: no code-signing identity found"; exit 1 }
echo "signing as: $IDENTITY"

xcodegen generate -q
xcodebuild -scheme Lectern-macOS -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" build | xcbeautify --quiet

rm -rf "$DIST/stage"
mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"
ln -s /Applications "$DIST/stage/Applications"
codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$DIST/stage/Lectern.app"
codesign --verify --deep --strict --verbose=1 "$DIST/stage/Lectern.app"

DMG="$DIST/Lectern-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Lectern $VERSION" -srcfolder "$DIST/stage" -ov -format UDZO -quiet "$DMG"
codesign --force $TIMESTAMP --sign "$IDENTITY" "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo
echo "built $DMG ($(du -h "$DMG" | cut -f1)) from $COMMIT"
echo "Gatekeeper assessment of the app:"
spctl --assess --type execute --verbose=2 "$DIST/stage/Lectern.app" 2>&1 | sed 's/^/  /' || true
