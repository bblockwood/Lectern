# Lectern

A PDF presenter for macOS, iPadOS, iOS and watchOS, built for Beamer decks: presenter view with notes and timer, an audience window on the projector, frame-aware navigation, live reload while you recompile, pointer and ink. `SPEC.md` is the design; `docs/progress.md` is where each milestone is reported.

## Build on a new machine

Requires Xcode 27.1 or later (install from the App Store, open it once to accept the licence) and Homebrew.

    brew install xcodegen xcbeautify
    git clone git@github.com:bblockwood/Lectern.git
    cd Lectern
    xcodegen generate
    xcodebuild -scheme Lectern-macOS -destination 'platform=macOS' -derivedDataPath build/DerivedData build | xcbeautify
    open build/DerivedData/Build/Products/Debug/Lectern.app

`xcodegen generate` turns `project.yml` into the gitignored `.xcodeproj`; rerun it after pulling changes that add or remove files.

The Mac app runs on your own machine without any signing setup. To build for an iPad, iPhone or Watch, Xcode must be signed in to your Apple ID (Xcode → Settings → Apple Accounts) and `Config/Local.xcconfig` must hold your Team ID:

    cp Config/Local.xcconfig.example Config/Local.xcconfig
    security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject   # Team ID is the OU= field
    # edit Config/Local.xcconfig and replace XXXXXXXXXX with it

That file is gitignored, so it has to be created on each machine.

## Tests

    swift test --package-path Packages/PresenterCore
    xcodebuild -scheme Lectern-macOS -destination 'platform=macOS' -derivedDataPath build/DerivedData test | xcbeautify

## Fixtures

`Fixtures/*.pdf` are committed, so TeX Live is only needed to rebuild them from `Fixtures/src` with `make -C Fixtures`.

## Layout

See `CLAUDE.md` for the repo layout, conventions and gotchas, `docs/decisions.md` for design decisions, and `docs/spikes/` for the M0 prototype findings. The app icon's source lives in `Design/AppIcon/`; `swift Design/AppIcon/make-appicon.swift` rebuilds the asset catalog from it.

## Releases

`Scripts/release.sh` builds a Release `Lectern.app`, signs it with the hardened runtime, and wraps it in `dist/Lectern-<version>.dmg` with an Applications shortcut, ready to upload to a website. The version comes from `project.yml`.

What a download needs to open without a Gatekeeper warning:

1. A **Developer ID Application** certificate, which needs the paid Apple Developer Program. Create it in Xcode (Settings > Accounts > your team > Manage Certificates > + > Developer ID Application). The script uses it automatically when it is in the keychain; without it the DMG is signed with the development identity and other Macs show "Apple could not verify…" until the person allows it in System Settings > Privacy & Security.
2. **Notarization.** Once, store credentials for `notarytool` (an app-specific password from appleid.apple.com, and the Team ID):

       xcrun notarytool store-credentials Lectern --apple-id you@example.com --team-id TEAMID

   Then build with `NOTARY_PROFILE=Lectern Scripts/release.sh`; the script submits the DMG, waits, and staples the ticket.

Bump `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml` for each release.

