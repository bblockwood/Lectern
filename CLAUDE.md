# CLAUDE.md: Lectern

You are building **Lectern**, a PDF presenter app for macOS, iPadOS, iOS and watchOS.

- **SPEC.md is the source of truth.** Re-read the relevant sections before starting each milestone.
- If the spec is ambiguous or seems wrong, ask Ben before deviating, and record the outcome in `docs/decisions.md`.

## Owner

Ben is an experienced LaTeX/Beamer user who works mostly in the terminal (zsh, tmux, Homebrew), often over SSH from an iPad.
- Prefer command-line workflows.
- Don't assume he can see Xcode's GUI.
- He is not an iOS developer, so briefly explain any Apple-platform step you ask him to do.

## Repo layout

```
project.yml                 XcodeGen spec. Never hand-edit project.pbxproj; the .xcodeproj is generated and gitignored.
Config/Local.xcconfig       Ben's signing settings (gitignored)
Packages/PresenterCore/     core logic (see SPEC §3.1)
Packages/PresenterProtocol/ Foundation-only; must build for watchOS
Apps/macOS/  Apps/iOS/  Apps/watchOS/
Spikes/                     M0 prototypes, never shipped
Fixtures/src/               LaTeX sources for the test corpus; Fixtures/*.pdf are built outputs
docs/                       progress.md, decisions.md, spikes/
Design/AppIcon/             Ben's icon artwork and make-appicon.swift, which builds Apps/macOS/Assets.xcassets from it
```

## Commands

- One-time setup: `brew install xcodegen xcbeautify`.
- Regenerate the project after changing `project.yml` or adding/removing files: `xcodegen generate`.
- Core tests: `swift test --package-path Packages/PresenterCore`.
- Mac build: `xcodebuild -scheme Lectern-macOS -destination 'platform=macOS' build | xcbeautify`.
- iOS build: `xcodebuild -scheme Lectern-iOS -destination 'platform=iOS Simulator,name=<device>' build | xcbeautify`. Pick a current iPad from `xcrun simctl list devices available`.
- Fixtures: `make -C Fixtures`, which runs latexmk.

## Conventions

- Swift 6 language mode with strict concurrency. New code must have no warnings.
- SwiftUI for chrome; CALayer-backed AppKit/UIKit views for slide surfaces. **Never `PDFView` in the presentation path.**
- All input → `Command` → `SessionController`. Views never mutate `SessionState` directly.
- PresenterCore imports only Foundation, CoreGraphics and PDFKit. PresenterProtocol imports only Foundation.
- No third-party dependencies without asking Ben. **Never MuPDF or Poppler** (license).
- Instrument latency with `os_signpost` (input → audience frame presented). Log render-cache misses with `os_log`.
- Make small, focused commits with clear messages. Use one branch per milestone and merge it when its acceptance checks pass.

## Working loop

1. **Plan.** At the start of a milestone, write a short plan in `docs/progress.md`.
2. **Verify continuously.** Build all affected targets and run tests after every meaningful change. Never report something as done unless everything builds and the tests pass.
3. **Use the Simulator** for everything it can cover, including external displays (I/O → External Displays).
4. **Report.** At the end of each milestone, append to `docs/progress.md`:
   - What was done.
   - Known issues.
   - A **Ben device checklist**: exact steps for anything only real hardware can verify, such as a projector over HDMI, Pencil hover, Watch double tap and latency, and clickers.
5. **Protect the principles.** Never weaken the principles in SPEC §1.1 to make something work. Flag the tradeoff to Ben instead.

## Ben does these (don't attempt)

- Signing and provisioning: he sets `DEVELOPMENT_TEAM` in `Config/Local.xcconfig`. Don't change signing settings otherwise.
- Physical-device testing.
- Supplying the PowerPoint fixture (SPEC §12, item 9).

## Gotchas

- Frames are defined by page labels, because Beamer overlays share a label. Verify against `Fixtures/overlays.pdf`.
- latexmk and editors replace files atomically. Watch the directory, debounce, and confirm the new PDF parses before reloading.
- After M0, follow the recommendations in `docs/spikes/` for the iPad external display and the Watch transport.
- Don't guess file formats (e.g. `.pdfpc`) or Apple APIs you're unsure of. Check documentation or source, and say when you're uncertain.
- Xcode 27.1 has no Simulator.app (DeviceHub.app replaced it) and no External Displays menu. Attach a simulated external display from the terminal: `xcrun simctl io <udid> screenConfig --display=external power on`, and capture it with `xcrun simctl io <udid> screenshot --display=external out.png`. See `docs/spikes/A-external-display.md`.
- `Config/Local.xcconfig` is optional for Simulator builds: each project.yml points at a committed `Signing.xcconfig` that does `#include? "../../Config/Local.xcconfig"`. Keep that pattern for new projects.
