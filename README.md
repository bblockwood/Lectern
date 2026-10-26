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

See `CLAUDE.md` for the repo layout, conventions and gotchas, `docs/decisions.md` for design decisions, and `docs/spikes/` for the M0 prototype findings.
