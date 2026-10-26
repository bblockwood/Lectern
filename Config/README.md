# Config

`Local.xcconfig` holds per-machine signing settings and is gitignored. Every XcodeGen project in this repo uses a committed `Signing.xcconfig` that contains `#include? "../../Config/Local.xcconfig"`, so builds work on a fresh clone without it (Simulator and ad-hoc Mac builds) and pick it up automatically once it exists.

To build for real devices:

    cp Config/Local.xcconfig.example Config/Local.xcconfig
    # then set DEVELOPMENT_TEAM to your Team ID

A plain `configFiles:` reference to a missing file makes `xcodebuild` fail with "Unable to open base configuration reference file", even with XcodeGen's `missingConfigFiles` validation disabled, which is why the optional include is used.
