# Progress

## M0: Spikes (branch `m0-spikes`)

Started 2026-10-25. Toolchain: Xcode 27.1 (SDKs macOS 27.0, iOS 27.1, watchOS 27.0; simulator runtimes iOS 26.5, watchOS 26.5), Swift 6.4, XcodeGen 2.45.4, xcbeautify, TeX Live 2021 with beamer, pdfpc, pdfcomment, pgfplots.

### Plan

1. **Fixtures first.** Write LaTeX sources for fixtures 1–8 and 10 in `Fixtures/src/`, a `Makefile` that runs latexmk, and derive `malformed.pdf` by truncating `basic-169.pdf`. Fixture 9 (`ppt-export`) is Ben's.
2. **Spike C, render benchmark** (`Spikes/RenderBench`, a SwiftPM executable). Render every page of every fixture at 1080p, 1440p and 4K with `CGContext.drawPDFPage`, report per-page timings, and check that annotation icons from fixtures 4–5 never reach the bitmap. Measure the warm-cache handoff cost. Output `docs/spikes/C-render.md`.
3. **Spike A, iPad external display** (`Spikes/ExternalDisplay`, XcodeGen project). Minimal UIKit-scene app with a shared counter, one view per screen, external scene declared with the non-interactive external-display role. Verify on the Simulator's external display; leave default/extended/Stage Manager and backgrounding behaviour on real hardware to Ben. Output `docs/spikes/A-external-display.md`.
4. **Spike B, Watch latency** (`Spikes/WatchLatency`, XcodeGen project): Watch app with a Next button on double tap, iPhone relay, Mac host. Transport A = WatchConnectivity → iPhone → Network framework/Bonjour → Mac. Transport B = Core Bluetooth, Mac as peripheral, Watch as central. Watch timestamps sends, host echoes, Watch computes RTT and reports median/p95. Transport A is verifiable on paired simulators; Transport B and the real numbers need hardware. Output `docs/spikes/B-watch-latency.md`.
5. **Report** here with known issues and a Ben device checklist, then merge `m0-spikes` into `main`.

Spikes are throwaway: each has its own `project.yml` or `Package.swift` under `Spikes/` so nothing leaks into the real targets.

### M0 report (2026-10-25)

**Done**

- `Fixtures/`: LaTeX sources and built PDFs for fixtures 1–8, 10 and 11, a Makefile, a JSON `.pdfpc` sidecar in pdfpc's format-2 layout, and `tools/inspect.swift` to dump labels, annotations, `/Trans`, `/Dur`, outline and links. Findings in `Fixtures/README.md`: overlay pages share a page label (`overlays.pdf`), `\appendix` does not restart numbering, pdfpc notes are hidden zero-rect `/Text` annots repeated on every build, pdfcomment notes are `/F 4` `/Text` annots with `/Name`, `/T`, `/Subj`, beamer's nav bar puts ~20 link annots per page including `GoBack`/`GoForward`/`Find`/`GoToPage` named actions, and `malformed.pdf` makes both `CGPDFDocument` and `PDFDocument` return nil without crashing.
- Spike C (`Spikes/RenderBench`, `docs/spikes/C-render.md`): typical Beamer pages render in ~1 ms at 1080p and ~3 ms at 4K; the worst TikZ page is 18 ms at 4K; `CGContext.drawPDFPage` never draws annotations (pixel-diffed against PDFKit); thumbnails of all 401 pages of `huge.pdf` take 86 ms; sharing one `CGPDFDocument` across 4 threads scaled 4× without crashing; display-P3 costs ~15 % on the heaviest page; a warm-cache layer handoff costs ~1 µs on the CPU side. No fallback engine needed.
- Spike A (`Spikes/ExternalDisplay`, `docs/spikes/A-external-display.md`): the non-interactive external-display scene works in the Simulator (present at launch, ~100 ms on hot-plug with one connect/disconnect/connect bounce, torn down on unplug, counter shared). No API can place a scene on a chosen screen; an application scene the user drags to the external display is the fallback for Stage Manager's extended desktop, detected with `windowScene(_:didUpdateEffectiveGeometry:)`. Recommendation for M4 is in the doc.
- Spike B (`Spikes/WatchLatency`, `docs/spikes/B-watch-latency.md`): watchOS remote (Next on double tap), iOS relay and macOS host built; Transport A (WatchConnectivity → iPhone → TCP/Bonjour → Mac) verified end to end on paired Simulators (100/100 echoes, but the Simulator's WatchConnectivity bridge adds ~3.8 s per message so the numbers are meaningless for hardware); Transport B (Mac as `CBPeripheralManager`, Watch as central, since `CBPeripheralManager` is unavailable on watchOS) compiles on both sides but Core Bluetooth is absent in the Simulator. Provisional recommendation: B, pending Ben's numbers.
- Tooling facts recorded in `CLAUDE.md` gotchas: Xcode 27.1 replaces Simulator.app with DeviceHub.app and the external display is attached with `xcrun simctl io <udid> screenConfig --display=external power on`; `Config/Local.xcconfig` is optional thanks to a `Signing.xcconfig` with `#include?`.

**Known issues**

- Fixture 9 (`ppt-export.pdf` + `.pptx`) is missing until Ben supplies it; the PPTX mapping tests in M3 wait on it.
- `\pdfmarkupcomment` produced no annotation with TeX Live 2021, so the corpus has no markup annotation; the visible-annotation negative test uses FreeText instead.
- Second-screen-notes decks have page labels that are not frame numbers (`notes-right.pdf`: labels 1,1,2,2,3,3 for 5 frames). Open decision for M3 in `docs/decisions.md`.
- Spike C's "warm-cache advance < 1 frame" is verified on the CPU side only (no window in a CLI tool); the input-to-glass number comes from M1's signposts.
- Spike B: the first Simulator run over the Mac's LAN address stalled ~63 s before all 100 echoes arrived (TCP retransmit pattern, cause unconfirmed); loopback was fine. Watch for it on hardware.
- Spike A: the Simulator never mirrors the iPad to the external display, so backgrounding behaviour on a real iPad is unknown.
- `.pdfpc`'s `endSlide` base (0 or 1) is unconfirmed; check pdfpc's source in M3.

**Ben device checklist**

Set up signing once: `cp Config/Local.xcconfig.example Config/Local.xcconfig`, put your Team ID in `DEVELOPMENT_TEAM` (Xcode → Settings → Accounts → your Apple ID → the team row shows the ID), and sign Xcode in to that Apple ID so `xcodebuild -allowProvisioningUpdates` can create profiles.

1. **iPad + USB-C→HDMI** (`docs/spikes/A-external-display.md`, section "Ben device checklist", Tests 1–5): build and install `SpikeExternalDisplay` on the iPad from the terminal with the commands given there, trust the developer certificate on the iPad (Settings → General → VPN & Device Management), then run the five tests: plug after launch, plug before launch, unplug/replug, backgrounding and locking, Stage Manager extended desktop with the draggable audience window. Send back the event list text or screenshots. Tests 4 and 5 decide the M4 design.
2. **Apple Watch latency** (`docs/spikes/B-watch-latency.md`, section "Measurement procedure", steps 1–10): run the Mac host from the terminal, the relay on the iPhone and the remote on the Watch via Xcode (⌘R with the device selected; enable Developer Mode on iPhone and Watch first), then 100+ double-tap presses on each of A, A′ and B, plus the wrist-down and reconnect checks. Report median/p95 per transport and the reconnect times; the CSVs are in `~/Library/Application Support/LecternSpikeB/`. These numbers pick the M8 transport.
3. **PowerPoint fixture** (SPEC §12 item 9): export a small deck with speaker notes and one hidden slide to `Fixtures/ppt-export.pdf` and put the `.pptx` beside it as `Fixtures/ppt-export.pptx`.

Nothing in M1 depends on these; they feed M3 (fixture 9), M4 (Spike A) and M8 (Spike B).

## M1: Mac core presenting (branch `m1-mac-core`)

Started 2026-10-25.

### Plan

1. **`Packages/PresenterProtocol`** (Foundation only): `Command`, `AudienceMode`, `NormalizedPoint`, `SessionSnapshot`. Verify it builds for watchOS with `xcodebuild -destination 'generic/platform=watchOS'`.
2. **`Packages/PresenterCore`**, depending on PresenterProtocol:
   - `Document/`: `PresentationDocument` (CGPDFDocument for rendering, PDFKit for labels), `PageInfo`, `FrameIndex` with the §4.1 grouping rules as a pure function.
   - `Session/`: `SessionState`, a pure `SessionReducer` implementing the §3.2 semantics, and a `@MainActor SessionController` that owns the state and notifies on change.
   - `Timing/`: `TimerState` (auto-start on first advance, pause, reset, target) and the §6.7 pace indicator.
   - `Render/`: `PageRenderer` (the Spike C recipe), `RenderRequest` keyed by page, pixel size, crop and colour space, an LRU `ImageStore` with a lock-protected synchronous lookup for the warm path, the `RenderCache` actor with one render in flight, priority ordering, cancellation and `os_log` on misses, and a pure `PrefetchPlanner` for §3.3.
   - Tests: frame grouping on `overlays.pdf`, `basic-169.pdf`, `huge.pdf` and a label-less PDF; malformed file fails cleanly; navigation semantics and the history stack; timer; cache hit/miss/prefetch/cancel; prefetch plan.
3. **`Apps/macOS`** (AppKit lifecycle, SwiftUI chrome), `project.yml` at the repo root:
   - Open via panel, drag-and-drop onto the window or Dock, `application(_:open:)`, and a recents list (UserDefaults bookmarks).
   - `SlideSurfaceView`: CALayer-backed, swaps `contents` only when an image is ready, used for audience, current and preview.
   - `DisplayManager`: built-in = presenter, largest external = audience, remembered per display name+resolution, swap (⌥⌘D), mirroring warning with a button to Displays settings, hot-plug via `didChangeScreenParametersNotification` with a banner and automatic restore.
   - Presenting mode (⌥⌘P / F5, Esc twice to end): borderless audience window at shielding level on the audience display, power assertion, cursor hidden; single display → resizable audience window (rehearsal).
   - Presenter layout: current slide left, next preview top right, notes placeholder bottom right, resizable with persisted fractions, status bar (frame label/total, build x/y, elapsed, wall clock, remaining vs target, LIVE/FROZEN/BLACK/WHITE), dark.
   - Key map for the M1 subset of §6.5, clicker keys included.
   - Signposts input → command applied → commit → next display-link target, and a `-selftest` launch mode that drives synthetic key events through the same path and prints latency statistics, so Principle 3 can be checked on every fixture from the terminal.
4. **Acceptance**: self-test on all fixtures with the signpost numbers recorded here; no-flicker argument from the surface design plus a unit test that contents are never cleared on a miss; hot-plug logic unit-tested with a fake topology and left to Ben's checklist for the physical test.
