# Spike B: Watch latency (throwaway)

Findings and the measurement procedure live in `docs/spikes/B-watch-latency.md`.

```sh
xcodegen generate                       # after editing project.yml or adding files

# Mac host (ad-hoc signed, no team needed)
xcodebuild -project WatchLatency.xcodeproj -scheme SpikeWatchHost -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build | xcbeautify

# iPhone relay + embedded Watch app, Simulator
xcodebuild -project WatchLatency.xcodeproj -scheme SpikeWatchRelay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build | xcbeautify
```

Targets: `SpikeWatchHost` (macOS), `SpikeWatchRelay` (iOS), `SpikeWatchRemote` (watchOS, embedded in the relay).
Signing comes from `Signing.xcconfig`, which optionally includes `../../Config/Local.xcconfig`.
Xcode auto-creates one scheme per target; none are checked in.

Headless Simulator run: launch the relay with `-host 127.0.0.1:52777`, then the Watch app with
`-autorun 100 -transport A` (or `Aphone`). The host appends CSVs under
`~/Library/Application Support/LecternSpikeB/`.
