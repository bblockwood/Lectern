#!/bin/zsh
# Builds a distributable Lectern.app and a DMG in dist/ (gitignored).
#
#   Scripts/release.sh                                        # build, sign, DMG
#   NOTARY_PROFILE=Lectern Scripts/release.sh                 # ... and notarize + staple with that notarytool keychain profile
#   GITHUB_RELEASE=1 NOTARY_PROFILE=Lectern Scripts/release.sh   # ... and publish it as the GitHub release v<version>
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

# GITHUB_RELEASE=1: attach the DMG to the GitHub release for tag v$VERSION, tagging HEAD first when the tag does
# not exist yet. RELEASE_NOTES=path.md supplies the notes; without it they are generated from the commits since
# the previous release. Needs the GitHub CLI logged in (brew install gh; gh auth login).
if [[ -n "${GITHUB_RELEASE:-}" ]]; then
  TAG="v$VERSION"
  [[ -z "$(git status --porcelain)" ]] || { echo "error: uncommitted changes; the release must be built from a commit"; exit 1 }
  if git rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null; then
    [[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] \
      || { echo "error: tag $TAG is not at HEAD; bump the version in project.yml"; exit 1 }
  else
    git tag -a "$TAG" -m "Lectern $VERSION"
    git push origin "$TAG"
  fi
  if [[ -n "${RELEASE_NOTES:-}" ]]; then
    gh release create "$TAG" "$DMG" --title "Lectern $VERSION" --notes-file "$RELEASE_NOTES" --verify-tag
  else
    gh release create "$TAG" "$DMG" --title "Lectern $VERSION" --generate-notes --verify-tag
  fi
  echo "download URL for the website: $(gh repo view --json url -q .url)/releases/download/$TAG/$(basename "$DMG")"
fi
