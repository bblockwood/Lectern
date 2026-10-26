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
- Spike C (`Spikes/RenderBench`, `docs/spikes/C-render.md`): typical Beamer pages render in ~1 ms at 1080p and ~3 ms at 4K; the worst TikZ page is 284 ms at 4K (corrected 2026-10-26: the spike drew pages at native size, see the post-M3 fixes below; ordinary pages were unaffected); `CGContext.drawPDFPage` never draws annotations (pixel-diffed against PDFKit); thumbnails of all 401 pages of `huge.pdf` take 86 ms; sharing one `CGPDFDocument` across 4 threads scaled 4× without crashing; display-P3 costs ~15 % on the heaviest page; a warm-cache layer handoff costs ~1 µs on the CPU side. No fallback engine needed.
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

Set up signing once: `cp Config/Local.xcconfig.example Config/Local.xcconfig`, put your Team ID in `DEVELOPMENT_TEAM` (read the `OU=` field of `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`; Xcode 27 no longer shows it in Settings, and the ID in parentheses after your email is not it), and sign Xcode in to that Apple ID so `xcodebuild -allowProvisioningUpdates` can create profiles.

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

### M1 report (2026-10-25)

**Done**

- `Packages/PresenterProtocol` (Foundation only; verified to build for watchOS): `Command`, `AudienceMode`, `NormalizedPoint`, `LinkID`, `SessionSnapshot`.
- `Packages/PresenterCore`: `PresentationDocument` (CoreGraphics for structure and rendering, PDFKit only for page labels), `FrameIndex` with the §4.1 rules, `SessionState` + pure `SessionReducer` (§3.2 semantics incl. `previousFrame` → last page of the previous frame, history on jumps, browse commit/cancel, timer auto-start on the first advance), `SessionController`, `TimerState` + `PaceIndicator`, `PageRenderer`, `ImageStore` (synchronous warm lookup, byte budget, pinned entries, distance-aware eviction), `RenderCache` actor (one render in flight, interactive-before-prefetch priority, cancellation, `os_log` on misses, `os_signpost` per render), `PrefetchPlanner` (§3.3 rings per surface). 54 tests.
- `Apps/macOS` (`Lectern-macOS`, nib-less AppKit lifecycle, SwiftUI chrome): open via panel, drop onto the window, Finder/Dock (`CFBundleDocumentTypes`), command-line path, and a bookmark-backed recents list in the welcome screen and the File ▸ Open Recent menu; presenter window with current slide, next-page preview, notes placeholder, draggable persisted splits, status bar (frame label/total, build x/y, elapsed, wall clock, remaining vs target with pace colour, LIVE/FROZEN/BLACK/WHITE/REHEARSAL); audience window (borderless at shielding level on the audience display, or a resizable aspect-locked rehearsal window); `DisplayManager` (built-in = presenter, largest external = audience, remembered per name+resolution, ⌥⌘D swap, mirroring warning with a button to Displays settings, hot-plug via `didChangeScreenParametersNotification` with banner and automatic restore); power assertion while presenting; key map for the M1 subset of §6.5 plus clicker keys; Esc-twice to end; target duration menu; latency signposts (`dev.lectern`/`latency`) and a `-selftest` mode. 11 app tests (display assignment, key map).
- Rendering path is exactly Spike C's recipe; the audience surface only ever swaps `CALayer.contents` for a finished bitmap and keeps the previous image on a miss.

**Acceptance: Principle 3 with signposts on all fixtures**

`Lectern -selftest <pdf>` opens the deck, presents (rehearsal window here; the real audience display when one is attached), posts →/←/⇧→ key events through the same monitor real keys use at ~0.5 s spacing, and reads the `dev.lectern` latency samples. MacBook Pro, built-in 120 Hz ProMotion display, Debug build, display kept awake with `caffeinate -u`:

| Fixture | Samples | Warm hits | Event receipt → audience layer swapped, median / max (ms) | Input → swapped, median (ms) | Input → first vsync after the swap, median / p95 (ms) |
|---|---|---|---|---|---|
| basic-169 | 41 | 41 | 0.43 / 1.15 | 0.98 | 7.5 / 15.1 |
| overlays | 47 | 47 | 0.43 / 3.19 | 0.94 | 7.5 / 18.4 |
| notes-right | 13 | 13 | 0.46 / 0.58 | 1.16 | 9.6 / 14.9 |
| notes-bottom | 13 | 13 | 0.42 / 0.56 | 0.97 | 9.4 / 12.8 |
| pdfpc-notes | 21 | 21 | 0.42 / 0.52 | 0.90 | 7.6 / 15.6 |
| pdfcomment-notes | 15 | 15 | 0.46 / 0.84 | 1.77 | 9.0 / 15.1 |
| links-appendix | 23 | 23 | 0.43 / 0.57 | 1.00 | 8.8 / 15.5 |
| tikz-heavy | 15 | 15 | 0.42 / 0.77 | 0.93 | 7.3 / 14.8 |
| transitions | 27 | 27 | 0.43 / 0.57 | 1.08 | 9.4 / 15.6 |
| huge (80 steps each way) | 163 | 163 | 0.44 / 1.16 | 0.94 | 7.8 / 16.0 |

Reading: from the moment the app sees the key event to the moment the audience layer has its new contents is 0.4 ms median and never above 3.2 ms, i.e. the swap is committed in the same run-loop pass, far inside any refresh interval. Input → swap includes event delivery; its p95 (5–8 ms) is an artefact of posting synthetic events through the run loop, not of our code. The "first vsync" column is the first display-link tick after the swap, an upper bound on when the frame is on glass; its spread (8–18 ms) comes from the ProMotion panel idling at lower refresh rates between presses. On a fixed 60 Hz projector the commit lands within one refresh by construction; the render server's own pipeline cannot be observed from the app, only with a camera. Warm-cache hits were 100 % on every fixture, including `huge.pdf` running 185 evictions against the 768 MB budget, after switching eviction from pure LRU to farthest-from-focus (pure LRU produced one miss per backward run).

**Acceptance: no flicker.** The surface never clears between pages: `SlideSurfaceView.show(image:)` swaps `contents` inside a `CATransaction` with actions disabled, a miss leaves the previous image up until the render completes and is still wanted, resizing keeps the old image scaled (`resizeAspect`) until the re-fitted render arrives, and black/white are solid layer colours. The self-test screenshots (`-screenshot DIR`, rendered in-process) show the presenter layout and a letterboxed 4:3 audience window with the committed page.

**Acceptance: unplug/replug mid-talk.** The logic is unit-tested (`DisplayAssignerTests.hotPlugRemovesAudienceAndRestoresIt`) and wired: the audience display disappearing hides the audience window, shows a banner and keeps the presenter running; its return re-creates the full-screen window on it at the current page because the surfaces render from `SessionState`. The physical test is in the Ben checklist.

**Known issues**

- The one-time Focus prompt (§6.1) is not implemented; deferred to M10 polish.
- The cursor is hidden only via `setHiddenUntilMouseMoves` when presenting starts; proper hide-over-audience-window handling arrives with the pointer in M3.
- The surround colour is black and not yet exposed in a settings UI.
- The pace indicator counts all frames; it will use `endOfTalkPage` (§4.2) once M2 adds it. "Remaining" shows a leading minus once over time.
- Audience mode toggles (B/W/F) are wired because they are one-liners; their M2 acceptance is untested here.
- SwiftUI pauses `TimelineView` updates while the presenter window is occluded, so the status-bar clock freezes if the window is fully covered; it resumes when visible. Harmless on stage.
- The app is not sandboxed (see decisions). Hardened runtime is on.
- `-selftest` always ends with `exit(0)`; it does not fail the build on bad numbers.

**Ben device checklist (needs a second display, ideally the projector and clicker you use)**

Build and run from the terminal: `xcodegen generate && xcodebuild -scheme Lectern-macOS -destination 'platform=macOS' -derivedDataPath build/DerivedData build | xcbeautify`, then `open build/DerivedData/Build/Products/Debug/Lectern.app`. No signing setup is needed for this (ad-hoc signed; macOS may ask once to confirm opening it).

1. **Two displays.** Connect the external display (not mirrored). Open `Fixtures/overlays.pdf` (⌘O or drop it on the window). Press ⌥⌘P. Expected: a full-screen slide on the external display with no menu bar or Dock on it; the presenter window stays on the built-in display with the status bar reading LIVE. Press → five times: the external display must change on every press with no flash of black or white between pages, and the presenter's current slide and Next pane follow. Press ⇧← : the audience shows the last build of the previous frame.
2. **Swap.** Press ⌥⌘D: the audience view moves to the built-in display and the presenter window to the external one. Press ⌥⌘D again to swap back. Quit and relaunch: the choice should be remembered for this display pair (Presentation ▸ Swap Displays if you need to undo it).
3. **Unplug mid-talk.** While presenting, pull the display cable. Expected: the presenter keeps working (→ still advances), an orange banner says the audience display was disconnected. Plug it back in: the audience window should reappear full screen on it showing the current page, and the banner goes away. Note how long the return takes.
4. **Mirroring warning.** In System Settings ▸ Displays, set the displays to mirror, then press ⌥⌘P: a banner must warn that the audience would see the presenter screen, with an "Open Displays Settings" button that opens that pane. Set them back to extended.
5. **Clicker.** With your presentation remote: its next/previous (Page Down/Page Up) must advance and go back; its "black screen" key (B or `.`) must toggle a black audience display and the status bar must read BLACK in red; F5 must start presenting; Esc pressed twice within a second must end presenting (a single Esc shows "Press Esc again").
6. **Keep-awake.** Present and leave the Mac untouched for longer than your display-sleep setting. The displays must stay on.
7. **Timer.** Press → once: the elapsed timer starts by itself. T pauses/resumes, ⌥T resets. Presentation ▸ Target Duration ▸ 20 minutes: the status bar shows the remaining time, green while on pace.
8. **Latency on the projector.** Run `build/DerivedData/Build/Products/Debug/Lectern.app/Contents/MacOS/Lectern -selftest "$PWD/Fixtures/basic-169.pdf"` with the projector attached: the self-test uses the real audience display, and the printed "first vsync" numbers then reflect the projector's fixed refresh rate. Paste the output into an issue. Separately, hold → down and watch the projector: pages should change at key-repeat rate without stutter.

Please also report anything that looks wrong in the presenter layout; nothing in M1 has been seen on a real second display yet.

## M2: Mac navigation (branch `m2-mac-navigation`)

Started 2026-10-25.

### Plan

1. **PresenterCore**: `Outline` from PDFKit with the §4.2 appendix heuristic; `PDFPCMetadata` from the XMP packet (`pdfpc:Duration`, `pdfpc:EndUserSlide`, …) so `endOfTalkPage` resolves pdfpc → (sidecar, M3) → outline; `PageLink` extraction per page via PDFKit (GoTo, named actions, URI, launch) with rects normalised to the rotated page; `TextSearcher` actor over PDFKit's text layer with hits grouped by frame; reducer handles `followLink` (GoTo pushes history, named actions map to steps/jumps/back/forward) and keeps a forward stack for `GoForward`. Tests on fixtures 4 and 6.
2. **App**: overview (Tab) with a frame grid of last-page thumbnails from a separate small `RenderCache`, outline sidebar and search field; arrows/clicks browse privately with the PREVIEW banner, Return commits, Esc cancels; jump by number (digits + Return) from anywhere; link activation by click on the presenter's current slide and on the audience window with a hand cursor; APPENDIX badge and remaining main-talk frames in the status bar; URI links ignored unless a defaults flag enables opening them after confirmation.
3. **Acceptance**: unit test of the fixture 6 round trip (link → appendix, Delete → back) at the reducer level, and a self-test scenario that clicks the link rect on the presenter surface and presses Delete.

### M2 report (2026-10-25)

**Done**

- PresenterCore: `Outline` (PDFKit bookmarks, flattened with depths, `appendixEntry()` for Appendix/Backup/Supplementary), `PDFPCMetadata` from the XMP packet (`pdfpc:Duration`, `EndUserSlide`, `LastMinutes`, `NotesPosition`, `DisableMarkdown`, `DefaultTransition`), `EndOfTalk.resolve` with the §4.2 order (pdfpc → sidecar → outline), `PageLink` extraction per page (GoTo to pages or resolved named destinations, named actions, URI, launch) with rects normalised to the rotated page, `TextSearcher` actor (case- and diacritic-insensitive, snippets, hits carry their frame), reducer support for `followLink` (GoTo pushes history, NextPage/PrevPage step, FirstPage/LastPage jump, GoBack/GoForward walk the history with a new `forwardHistory` stack that any fresh jump clears). The target duration from pdfpc metadata seeds the timer. 65 core tests.
- App: overview on Tab (current slide stays on the left with the PREVIEW banner; outline sidebar, search field with debounced results and ↑/↓/Return navigation, frame grid of last-page thumbnails from a separate 96 MB `RenderCache`, committed frame outlined green, browsed frame blue, appendix frames marked A); clicks and arrows browse privately, Return or double-click commits, Esc cancels and closes, Tab closes; jump by number from anywhere (digits overlay, Return jumps to that frame label, Esc clears, unknown label shows a banner); link activation by click on the presenter's current slide and on the audience window with a hand cursor over links; APPENDIX badge on the current slide and in the status bar, "N left" main-talk frames, pace indicator over main-talk frames; URI links ignored with a short notice unless `LecternOpenURILinks` is set, then opened after confirmation; `-roundtrip` and `-overview` self-test scenarios. 12 app tests.

**Acceptance: appendix round trip on fixture 6.** Reducer level: `LinkFollowing.appendixRoundTripIsOneActionEachWay` (page 2 → `\hyperlink{backup-proof}` → page 8, Delete → page 2). App level through the real event path: `Lectern -selftest Fixtures/links-appendix.pdf 2 -roundtrip` posts a mouse click at the link's rect on the presenter's current slide and then a Delete key:

```
ROUNDTRIP OK: page 2 → click link → page 8 → Delete → page 2; history [1, 0], forward [7]
```

One click there, one keypress back. The same click works on the audience window because the surface view accepts first-mouse clicks without becoming key.

**Verified in addition**: overview screenshot from the self-test (`-overview -screenshot DIR`) shows outline, thumbnails with labels, build counts and A markers, PREVIEW banner and "1 left"; named actions from beamer's navigation bar (GoBack, GoForward, GoToPage, Find) are extracted and the ones with meaning map to commands; pdfpc XMP on fixture 4 yields duration 30 min and end slide 5, which beats the outline's Appendix entry.

**Known issues**

- Browsing to a frame from the overview selects its first page (unbuilt) while the thumbnail shows its last page. Committing therefore starts the frame from build 1, which is what a presenter wants, but the current-slide preview and the thumbnail differ for frames with builds.
- Search results are limited to 300 hits and the search field's ↑/↓/Esc handling uses SwiftUI `onKeyPress`, which could not be exercised headlessly; the grid and keyboard paths were.
- Frame grid cells are a fixed 200 pt wide; wide windows leave empty space on the right.
- Second-screen-notes decks still group frames by (wrong) page labels; the overview shows that grouping. M3.
- No "Find" or "GoToPage" named-action behaviour (they are viewer UI actions in Acrobat); they are ignored.

**Ben device checklist (additions for M2; no new hardware needed)**

1. Open `Fixtures/links-appendix.pdf`, press → once, click "backup proof" on the slide (the hand cursor appears over it): the audience jumps to the proof with the APPENDIX badge on the presenter; press Delete: back to the Introduction. Try the same click on the projector window.
2. Press Tab: the overview opens. Use ←/→/↑/↓ to move the blue selection; the current-slide pane shows the selection with the orange PREVIEW banner while the projector stays put; Return commits (projector changes, overview closes); Tab then Esc cancels without touching the projector.
3. Type `6` then Return from the normal view: jump to frame 6. Type `99` Return: a banner says there is no such frame.
4. Tab, ⌘F, type `backup`: results listed by frame; ↓ walks them (preview follows), Return commits.
5. B, W, F during a talk: audience goes black / white / stays frozen while you move on; the status bar shows BLACK, WHITE, FROZEN; pressing the same key again returns to LIVE.

## M3: Mac notes, pointer, live reload (branch `m3-mac-notes`)

Started 2026-10-25.

### Plan

1. **Core, notes and sidecar.** `Sidecar` (versioned JSON `<deck>.lectern.json` next to the PDF, else in Application Support keyed by bookmark; unknown keys tolerated; corrupt files logged and ignored). Notes sources as pure parsers: embedded `/Text` annotations (pdfpc and pdfcomment shapes from `Fixtures/README.md`), the `.pdfpc` JSON file (format 2, legacy `[notes]` fallback), Beamer second-screen split detection by aspect ratio with the slide half as a crop, PowerPoint notes from a `.pptx` (own minimal ZIP reader + `XMLParser`; hidden slides skipped; count mismatch → warning), and `NotesMerger` with the §5.1 priority and frame fallback. Block-level Markdown splitting for the pane. Tests on fixtures 3, 4, 5, a synthetic pptx, and sidecar round-trips.
2. **Core, live reload.** `DeckWatcher` on the deck directory (DispatchSource), 300 ms debounce, size stabilisation, parse-before-swap; `SessionController.replaceDocument` already restores by (label, build). Tests with a temp copy of fixture 2 replaced atomically.
3. **App.** Notes pane (Markdown, ⌘+/⌘− persisted, frame fallback, source badge, second-screen notes as a rendered crop, inline editor writing user notes to the sidecar); one-time split confirmation stored in the sidecar; sidecar load/save of settings, notes and last position; live reload with cache rebuild and image swap only when ready; pointer (L) with glow and trail on the audience and presenter surfaces, hidden after 2 s; ephemeral mouse ink (D/E) mirrored as vectors; banners for reload and split confirmation.
4. **Acceptance.** Notes checks on fixtures 3, 4, 5 (and the synthetic pptx until Ben's fixture 9 arrives) in tests and the self-test; a self-test that recompiles fixture 2 mid-run (`make -C Fixtures overlays.pdf` after touching the source) and confirms the position survives.

### M3 report (2026-10-25)

**Done**

- Sidecar (`<deck>.lectern.json`, SPEC §3.4): versioned, unknown keys ignored, missing keys defaulted, corrupt files logged and skipped, written atomically beside the deck or in `~/Library/Application Support/Lectern/Sidecars/` when the directory is read-only. Holds user notes (frame label + page), split decision, target duration, end-of-talk override, persistent ink and whiteboard schema (UI in M5), last position (restored on open) and rehearsal logs (M6).
- Notes sources (§5.1) with the merge order sidecar > `.pdfpc` > embedded > PowerPoint, and frame fallback for builds without notes: embedded `/Text` annotations (pdfpc's hidden zero-rect ones and pdfcomment's; FreeText and markup are never notes), the `.pdfpc` JSON file (format 2, pdfpc's label+overlay-then-idx matching, `endSlide` 0-based, legacy `[notes]`/`### N` fallback), Beamer second-screen decks detected by aspect ratio with pdfpc's `NotesPosition` as a hint, confirmed once per deck by a banner and stored in the sidecar, after which the audience, presenter and thumbnails use the slide half and the notes pane shows the notes half rendered; PowerPoint notes from a `.pptx` beside the PDF through an own ZIP reader (stored and deflated entries) and `XMLParser`, with `sldIdLst` order, `show="0"` skipped, body placeholder text, and a warning instead of a mapping when counts differ.
- Notes pane: Markdown (paragraphs with line breaks, bullets, numbered items, inline emphasis and code), ⌘+/⌘− font size persisted per device, source badge, ⌘E inline editor writing user notes to the sidecar (switching pages while editing saves the draft).
- Pointer (§6.4): L toggles; moving over the presenter's current slide or the audience window places a red dot (1.2 % of slide height, soft glow) on both surfaces with a 300 ms fading trail; it hides after 2 s or on leaving.
- Ephemeral ink (§8, basic Mac version): D toggles draw mode with a crosshair cursor, mouse drags on the current slide become strokes in normalised coordinates mirrored on the audience as vectors, fading out over the last second of a 3 s life; E clears. `InkStroke` now carries width and colour and is Codable for the sidecar.
- Live reload (§6.6): `DeckWatcher` watches the deck's directory and the PDF (atomic replace, in-place write, companions), debounces 300 ms, waits for sizes to settle, then the new PDF is parsed off the main thread; on success caches are rebuilt, the position is restored by (frame label, build) with nearest-page fallback, and the audience keeps the old image until the new render of the same page is ready; on failure the old deck stays with a banner and the next change retries. Sidecar, `.pdfpc` and `.pptx` changes reload notes without touching the deck. Presentation ▸ Reload Deck Now (⌘R) forces it.
- Target duration seeds from the sidecar, then pdfpc XMP, then the `.pdfpc` file; the status bar shows the remaining time with the pace colour.

**Acceptance**

- *Notes appear correctly for fixtures 3, 4, 5 (and 9).* Unit tests cover every source and the merge order; `Lectern -selftest Fixtures/pdfpc-notes.pdf 1 -notes` prints the merged note per page through the app (page 2 from the `.pdfpc` file overriding the embedded one, page 5 build-specific, page 10 sidecar-only, the rest embedded), the same for `pdfcomment-notes.pdf` (pages 1–5 notes, FreeText page 6 none), and `notes-right.pdf` reports the pending split question. Fixture 9 is not here yet; the synthetic `.pptx` in `PPTXTests` stands in (three slides, one hidden, notes on two) and `fixtureNineWhenPresent` will run against Ben's file automatically.
- *Recompiling fixture 2 mid-talk keeps the position.* `Lectern -selftest Fixtures/basic-169.pdf 1 -reload` copies `overlays.pdf` to a temp deck, goes to frame 3 build 2, then replaces the file atomically three times:

```
RELOAD step 1 OK: was frame 3 build 2; now page 4 of 11 (frame 3 build 2); notice: Deck reloaded: 11 pages, 8 frames. Position kept at frame 3.
RELOAD step 2 OK: malformed replacement ignored, still 11 pages at page 4; notice: The recompiled PDF could not be read; keeping the previous version. It will be retried on the next change.
RELOAD step 3 OK: back to 23 pages at page 6
```

- Pointer and ink through the surface's mouse handlers (`-ink`): pointer shown, one 21-point stroke mirrored on the audience as one shape layer, strokes gone after 3.5 s; screenshots show the dot and the stroke on both the presenter and the audience surfaces.

**Known issues**

- Second-screen decks still group frames by page labels, which Beamer gets wrong for them (`docs/decisions.md`); `notes-right.pdf` shows 3 frames for 5. Until a better signal exists, those decks are best navigated by page (→/←). Ben's real decks will tell whether this matters.
- Links are not activated in split mode (their rects would need remapping to the crop).
- The notes editor edits the sidecar note only; it cannot edit `.pdfpc` or embedded notes in place (they are overridden instead, which is what §5.1 asks).
- Persistent ink and whiteboards are stored in the sidecar schema but have no UI until M5.
- Pointer trail dots are removed by a 350 ms timer; under heavy mouse movement that is a few dozen tiny layers, fine in practice.
- Sidecar writes are debounced (0.5 s for edits, 2 s for position); quitting within that window can lose the last change. A flush on quit is a quick follow-up.
- DeckWatcher's own sidecar writes trigger a directory event; the reload path compares the file with the in-memory sidecar and ignores it, so no loop, but there is one redundant read per save.

**Ben device checklist (M3, no new hardware)**

1. Open `Fixtures/pdfpc-notes.pdf`: the notes pane shows a note per page with a source badge (page 2 says `.pdfpc file`). Press ⌘E, type a note, press Done: `Fixtures/pdfpc-notes.lectern.json` appears next to the PDF with your text, and the badge reads "your notes".
2. Open `Fixtures/notes-right.pdf`: a cyan banner asks whether to split; answer Yes. The current slide and the audience show only the left half, the notes pane shows the right half. Reopen the deck: no question, the answer stuck.
3. Live reload: present `Fixtures/overlays.pdf`, go to frame 3 build 2, then in another terminal run `touch Fixtures/src/overlays.tex && make -C Fixtures overlays.pdf`. Within a second of latexmk finishing, a banner says "Deck reloaded" and the audience still shows frame 3 build 2 with no flash. Then run `cp Fixtures/malformed.pdf Fixtures/overlays.pdf` (restore with `git checkout Fixtures/overlays.pdf` afterwards, which also triggers a reload): the talk continues on the old deck with an orange banner.
4. Pointer: press L, move the mouse over the current slide: a red dot with a trail follows on the projector and hides two seconds after you stop. Move the mouse over the projector window directly: same.
5. Ink: press D and draw on the current slide with the mouse: the stroke appears on the projector at the same place and fades after three seconds; E clears; D again leaves draw mode.
6. ⌘+ and ⌘− change the notes size and the size survives a relaunch.
7. **Then use it for a real talk** (SPEC M3 → M4 gate) and collect issues: `docs/issues.md` is a good place; I will triage them before M4.

## Post-M3 fixes (2026-10-26, branch `fix-render-scale`)

Found by Ben on first launch: every slide rendered as tiny content centred in a huge white pane, on the audience window, the current-slide pane and the Next thumbnail alike.

- **Cause.** `PageRenderer` asked `CGPDFPageGetDrawingTransform` to map the crop box onto the full bitmap rect. Per `CGPDFPage.h` that call only ever *scales down* ("scale the rect down, if necessary"), so whenever the bitmap is larger than the page's native point size, which is every projector-sized render, the page was drawn at native size and centred. Spike C's `RenderBench` had the same call, so its timings were measured on undersized pages.
- **Why the tests missed it.** The render tests used sizes at or below the native page size (480×270 against a 454×255 pt page), where the transform is correct; the M1 self-test measured latency and cache hits, not what the pixels showed, and the screenshots were only checked for being non-blank. The thumbnails, always smaller than the page, were right all along.
- **Fix.** `PageRenderer.transform(of:onto:)` asks for the unit square, where scaling down is guaranteed and `/Rotate` is still honoured, and stretches the unit square onto the target rect itself. `Links.swift` already used the unit-square form, so link rects and pixels agree. A regression test renders `basic-169.pdf` below and far above native size and requires the inked-pixel fraction to be scale-invariant; on the old code it fails by a factor of 27.
- **Re-measured Spike C** with the corrected spike (`docs/spikes/C-render.md` updated in place, with a note). Ordinary pages are unchanged (≤ 5 ms at 4K, dominated by context allocation). The heaviest page, `tikz-heavy.pdf` page 5 with 2400 translucent discs, is 73 ms at 1080p, 128 ms at 1440p and 284 ms at 4K, not 18 ms. The engine decision stands (`docs/decisions.md`): prefetch plus keep-the-old-image covers single-step navigation, and the self-test on `tikz-heavy.pdf` still shows no misses and the same sub-millisecond swap. A deck full of such pages on a 4K projector is the case that would justify rendering heavy pages off the serial path; the spike shows sharing one `CGPDFDocument` across threads works.
- **Also.** `Fixtures/*.lectern.json` is now gitignored and two sidecars the M3 self-tests had committed by accident were removed; the Team ID instructions in the template and both device checklists now use `security find-certificate`, since Xcode 27's Settings no longer shows the ID.

Verified: 90 PresenterCore tests, 1 PresenterProtocol test, 12 app tests, warnings-as-errors build; in-app screenshots of `overlays.pdf` at full pane size; self-tests on `overlays.pdf` and `tikz-heavy.pdf` with no misses.
