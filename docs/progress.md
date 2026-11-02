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

## Feedback round 1 (2026-10-26, branch `feedback-1`)

Ben's first-use feedback on the Mac presenter, eight items, all in the chrome and navigation:

### Plan

1. Closing the deck with the window's red button returns to the welcome screen instead of quitting (⌘W already did). Closing the welcome screen quits.
2. Status bar: timer fixed at the centre regardless of the frame/build text; about twice the height; larger type.
3. Settings window (⌘,): back-navigation option (← at the start of a frame lands on the previous frame's first build instead of its last), hold-⌘ overlay on/off, notes size, web links. Pulled forward from M10 at Ben's request; the option is implemented in `SessionReducer` behind `NavigationOptions`.
4. Current and next slides top-aligned under matching pane titles, each sized to its exact fitted rect.
5. Larger type everywhere in the presenter (a `Theme` table; notes default 22 pt).
6. Laser / Pen / Clear buttons directly under the current slide, lit when active, driving the same actions as L, D and E.
7. Holding ⌘ for a third of a second shows a translucent overlay of every shortcut; releasing hides it.

### Feedback round 1 report (2026-10-26)

All eight items are in, each verified in-app by screenshots from the self-test (`-screenshot DIR`, with the new `-shortcuts`, `-settings` and `-closebutton` steps):

1. **Close returns to the welcome screen.** `windowShouldClose` closes the deck and keeps the window when a deck is open; ⌘W did this already. Closing the welcome screen quits. Self-test: `performClose` on the presenter window leaves the window open on the welcome screen with no deck.
2. **Status bar.** Three fixed regions in a `ZStack`: frame / build / frames-left on the left, timer and clock always centred, LIVE pill on the right. Twice the height (30 pt frame label and timer, 24 pt secondary, 14 pt vertical padding). The POINTER / DRAW badges moved out of the bar into the buttons under the slide.
3. **Settings (⌘,).** `SettingsView` in its own window: ← landing option (see `docs/decisions.md`), hold-⌘ overlay toggle, notes size stepper, web links toggle. `NavigationOptions` in PresenterCore; `SessionController.navigationOptions` is read on every command, so a change applies to the next key press. Keys pressed while the Settings window is key no longer reach the presenter, and ⌘W there closes Settings. Four new reducer tests.
4. **Aligned slide tops.** Both slide panes start with a 16 pt title ("Current", "Next") and size their surface to the exact fitted rect pinned to the top, so the top edges line up at any split. Second-screen decks use the cropped aspect.
5. **Larger type.** A `Theme` table: status 30/24, pane titles 16, body 18, small 14; notes default 22 pt (was 18; ⌘+/⌘− and the Settings stepper share the stored value). Banners, badges, overview captions and the welcome screen follow it.
6. **Laser / Pen / Clear buttons** directly under the current slide, lit red / orange when active, with their keys shown; they drive the same `AppAction`s as L, D and E. A hint to the right says what the active mode does.
7. **Hold ⌘ overlay.** A `flagsChanged` monitor arms a 350 ms task when ⌘ is the only modifier and the presenter window is key; the overlay lists every shortcut in three columns at 94 % black and hides on release, on any other modifier, or on any key press (so ⌘-shortcuts never flash it). `ShortcutReference` mirrors `KeyMap` and the menu. Self-test posts real ⌘ down/up events and checks both transitions.
8. The welcome screen's hint line now says "hold ⌘ for every shortcut".

**Known issues**

- `ShortcutReference` is a hand-maintained list; a new key in `KeyMap` must be added there too.
- The overlay is sized for the default window; on a very narrow presenter window the three columns would overflow (it is not scrollable).
- The Settings window is not resizable and uses the system (light) appearance, unlike the presenter.

**Ben device checklist (feedback round 1, no new hardware)**

1. Open a deck and click the window's red close button: the welcome screen with recents comes back, the app stays open. Close the welcome screen: the app quits.
2. Step through `Fixtures/overlays.pdf`: the timer stays centred while "Build x/y" appears and disappears on the left; the bar is about twice its old height.
3. The top edge of the current slide and of the Next slide line up; drag the vertical split and they still do.
4. Click Laser under the slide: it lights red and the dot follows the mouse over the slide (and on the projector); click it again or press L to turn it off. Same for Pen (orange) and Clear.
5. Hold ⌘ for half a second: the shortcut card appears; release: it goes. Press ⌘E normally: no card flashes.
6. ⌘, opens Settings. Choose "the previous frame's first build", then in `overlays.pdf` go to frame 3 build 1 and press ←: you land on frame 2 build 1 (not build 3). Switch back and ← lands on frame 2's last build. Tell me if you meant something different by "jumps to the first build of each frame".

## Feedback round 2 (2026-10-27, branch `feedback-2`)

Ben's second round after using the round-1 build, nine items, all in the Mac presenter.

### Plan

1. Labels match keys: Laser (L), Draw (D), Clear (C); E unbound; menus and the shortcut card follow.
2. Shortcut card: a ⌘ tap toggles it; it stays until ⌘ again, Esc or a click outside; rows are clickable and run their command; the "B ." entry lists only B.
3. A click on the current or next slide is the next build.
4. Countdown: once a target exists, the time left replaces the elapsed time, green then red (negative, counting up); clicking the timer opens an editor for any deck.
5. Drop "X left" from the status bar.
6. The notes editor's Done button must not move the pane header.
7. ⌃⌘F toggles full screen.
8. The notes pane doubles as the table of contents, with the current part highlighted; a frame without notes shows the contents.
9. Transitions: nothing was implemented (M9); strike them from the spec instead.

### Feedback round 2 report (2026-10-27)

1. **Semantic labels.** Buttons under the slide read Laser L, Draw D, Clear C; the Presentation menu says Laser Pointer (L), Draw on Slide (D), Clear Drawing (C); `KeyMap` binds C to clear and E to nothing. SPEC §6.5 updated.
2. **Shortcut card.** `AppDelegate` arms a "tap" when ⌘ goes down alone and toggles the card when ⌘ comes up with no key or click in between; any key press, mouse click or extra modifier disarms it, so ⌘-shortcuts and ⌘-clicks never show it. The card is now an `.overlay` over the whole window with a backdrop that takes clicks (so a click outside closes it without reaching the slide) and rows that are buttons: `ShortcutReference` rows carry a `perform` closure, `AppModel.run(_:)` closes the card and runs it. Esc closes it and is consumed. Rows with two commands were split (⇧→ / ⇧←, T / ⌥T, ⌘O / ⌘W) and an App group holds ⌃⌘F, ⌘, ⌘O, ⌘W. "." stays bound (clickers) but is not listed. Settings wording: "Tap ⌘ on its own…".
3. **Click to advance.** `SlideSurfaceView.onClick` fires for a click that hit no link and started no stroke; the current and next surfaces route it to `.next` through the same latency instrumentation as a key press. The audience window is untouched.
4. **Countdown.** `StatusBar` shows `timer.remaining` in place of the elapsed time when a target is set: green, or red with a leading minus once `remaining.rounded() < 0`. The timer is a button; its popover (`CountdownEditor`) takes "45", "45:30", "1:05:00", "90m", "1h30" (`DurationParser`, 3 app tests), Return sets, and a button removes the countdown. The popover's field is focused on open, so digits go to the field and not to jump-by-number (the self-test types into it through the real event path). The Target Duration menu became Countdown; "Custom…" opens the same popover; the `NSAlert` prompt is gone. pdfpc decks with a duration show the countdown from the first advance, as before.
5. **"X left"** removed, with `Presentation.mainTalkFramesLeft`.
6. **Pane header height** is fixed (`Theme.paneHeader`, 26 pt) and the Done button is `.small`; the self-test screenshots with and without the editor show the heading at the same place.
7. **Full screen.** View ▸ Enter Full Screen (⌃⌘F) with AppKit's `toggleFullScreen:`; the presenter window is `fullScreenPrimary`. Self-test enters and leaves.
8. **Contents in the notes pane.** `Outline.currentEntry(forPage:)` in PresenterCore (2 tests) finds the last entry starting at or before the page. `OutlineList` (shared with the overview sidebar, which now highlights the containing entry too) shows the entries with their frame labels, highlights and scrolls to the current one, and jumps on click. `NotesPane` has Notes / Contents headings; Contents is shown on request or whenever the frame has no notes; clicking Notes on a frame without notes opens the editor; Done after writing a note shows the note.
9. **Transitions** struck from SPEC §4.5 and the §13 open decision; recorded in `docs/decisions.md`. No code existed.
10. Also fixed on the way: in the overview's narrow current pane the Laser / Draw / Clear titles had truncated to "… L"; the bar now drops its hint text instead (`ViewThatFits`).

The self-test gained `-clicks`, `-countdown`, `-contents` and `-fullscreen` steps and a `-shortcuts` step that drives every card transition with real ⌘, key and mouse events. It also now starts every run at page 1 (the sidecar restores the last position, which had made runs order-dependent) and names captured popover windows `popover-*.png`.

Verified: 96 PresenterCore tests, 15 app tests, warnings-as-errors build; self-tests on `basic-169.pdf`, `pdfpc-notes.pdf`, `overlays.pdf` and `links-appendix.pdf` with no misses; screenshots of the card, the contents tab, the editor header, the countdown in green and red, the editor popover and the overview.

**Known issues**

- Keys pressed while the shortcut card is up still do their job and leave the card up (Ben listed only ⌘, Esc and a click outside as ways to close it); clicking a row closes it. Say if a key press should close it too.
- The card is about 1120 pt wide; on a presenter window narrower than that it overflows (window minimum is 900 pt).
- A countdown set during the talk counts from the talk's start (time left = countdown − elapsed), shown in the editor. If "from now" is what you expect, say so.
- The Contents list is flat (indented), not collapsible.
- With the card or the countdown popover open, the self-test cannot verify that the row hover highlight renders; hover is visual only.

**Ben device checklist (feedback round 2, no new hardware)**

1. Tap ⌘ (press and release alone): the card appears and stays. Press →: the slide advances, the card stays. Tap ⌘: it closes. Tap ⌘, press Esc: closes. Tap ⌘, click the slide outside the card: closes, slide unchanged. Tap ⌘, click "Black screen": audience goes black, card closes. ⌘E, ⌘W, ⌘-click: no card.
2. Click the current slide: next build; click the Next preview: next build. With Draw on, a click-drag draws instead; a link still follows.
3. `Fixtures/pdfpc-notes.pdf`: the timer is green 30:00 and counts down from the first advance. `basic-169.pdf`: white elapsed time; click it, type `1`, Return: green 01:00 minus the elapsed time, red and counting up after a minute. Presentation ▸ Countdown ▸ None: white again. Also try the presets and that the popover's field has the cursor when it opens.
4. `basic-169.pdf` has sections but no notes: the pane shows Contents with the current section highlighted; click a section: jump; ⌫: back. `pdfpc-notes.pdf`: Notes shown; click Contents, then Notes. ⌘E on a frame without notes: the editor opens; type, Done: the Notes heading does not move.
5. ⌃⌘F: full screen; ⌃⌘F again: back. The green button too.
6. The buttons say Laser L, Draw D, Clear C; C clears, E does nothing.
7. Tell me if ← inside the card's "Previous build" row, the countdown-from-start rule, or the keys-leave-the-card-up rule is not what you meant.

## Feedback round 3 (2026-10-27, branch `feedback-3`)

Ben's third round, eight items.

### Plan

1. Shortcut card: hold ⌘ for about half a second instead of a tap; it stays up after release.
2. Setting a countdown starts the timer at once.
3. Drawn strokes stay until C or the next build; no fade.
4. The chooser is its own window (scrollable, title never cropped); the presenter window fills the screen when a deck opens, whatever the chooser's size.
5. Title bar: deck name with proxy icon, centred.
6. Notes vs Contents decided once on open (contents if the first slide has no notes), then only by the user.
7. Overview: a more prominent selection outline.
8. No links on the next-slide preview.

### Feedback round 3 report (2026-10-27)

1. **Hold ⌘.** `AppDelegate` starts a 500 ms task when ⌘ goes down alone and shows the card when it fires; the card stays after release. While it is up, pressing and releasing ⌘ alone closes it. A key, a click or another modifier cancels either, so ⌘-shortcuts never show it. Settings wording updated. Self-test: a 100 ms tap is ignored, a 750 ms hold shows and keeps it, a tap then hides it, plus the Esc, click-outside, ⌘J-during-hold and row-click checks from round 2.
2. **Countdown starts on set.** `AppModel.setTargetDuration` starts the timer when it is not running. A deck's own pdfpc duration still waits for the first advance (SPEC §6.7).
3. **Ink stays.** `Presentation.ephemeralInkLifetime` is nil: no fade, no prune loop; C clears, and the next build already cleared page-scoped ink. The hint under the slide says so. Self-test: a stroke is still there after 3.5 s, gone after C, and gone after the next build.
4. **Two windows.** `WelcomeWindowController` (720×600, resizable, min 480×360) hosts the chooser, now a ScrollView centred when it fits so the title is never cropped. `PresenterWindowController` is created at launch but shown only when a deck opens, sized to the visible frame of the chooser's screen, and hidden (leaving full screen first if needed) when the deck closes; `AppModel.onDeckOpened/onDeckClosed` drive the swap. Closing the presenter closes the deck; closing the chooser quits. Both content views accept the first click on an inactive app. Self-test: the presenter fills its screen, closing swaps the windows, reopening restores the title and represented URL.
5. **Title bar.** The presenter sets `title` and `representedURL`, so AppKit shows the deck's name with a real proxy icon. AppKit on this macOS leading-aligns the title (probe: 148 of 1512 pt) and offers no alignment API; a drawn, centred strip was built and then reverted because Ben prefers native behaviour (see decisions).
6. **Sticky Notes / Contents.** `AppModel.notesShowsContents` is decided in `open()` (outline present, first slide without notes and no split) and changed only by the headings or by writing a note. Self-test on `basic-169.pdf` (opens on Contents) and `pdfpc-notes.pdf` (opens on Notes): the choice survives moving between slides.
7. **Overview selection**: 6 pt accent stroke, glow and accent-coloured label on the selected frame.
8. **Preview links**: `SurfaceController` gives link rects only to the audience and current surfaces.

Self-test additions: `-welcome` (captures the chooser after closing the deck), `-titlebar` (checks the title and proxy icon), a composited capture that renders each top-level layer separately (an `NSScrollView` fills its background with clear using copy compositing, which erased everything beneath it in one flattened render), an activation warning, and skipping focus checks when another Lectern instance keeps this one inactive.

Verified: 96 PresenterCore tests, 15 app tests, warnings-as-errors build; self-tests on `basic-169.pdf`, `overlays.pdf`, `pdfpc-notes.pdf` and `links-appendix.pdf` with no misses; screenshots of the chooser, the presenter with its title strip, the card, the contents tab and the overview.

**Known issues**

- Window titles are leading-aligned, as AppKit lays them out on macOS 26.
- A deck's own pdfpc duration still starts counting at the first advance, unlike a countdown you set yourself.
- Strokes never fade now; a fade can come back as a setting (`ephemeralInkLifetime`).
- With another Lectern instance running, the self-test's focus checks are skipped (the second instance cannot become active).

**Ben device checklist (feedback round 3, no new hardware)**

1. Hold ⌘ for half a second: the card appears and stays after you let go. Tap ⌘: it closes. A quick tap with nothing up does nothing. ⌘E, ⌘W: no card.
2. Click the timer, type `5`, Return: it starts counting down immediately, green. Presentation ▸ Countdown ▸ 15 minutes: same.
3. Press D, draw, wait: the stroke stays. Press C: gone. Draw, press →: gone.
4. Launch: a modest "Lectern" chooser window. Shrink it: the title stays visible and the recents scroll. Open a deck: the presenter window fills the screen regardless of the chooser's size, the chooser disappears. Close the deck (red button or ⌘W): the chooser is back. Close the chooser: the app quits.
5. The presenter's title bar shows the PDF's proxy icon and file name, AppKit-style: drag the icon to the Finder, ⌘-click the title for the folder path.
6. `basic-169.pdf` (no notes): opens on Contents; move around: stays on Contents; click Notes: stays on Notes until you click Contents. `pdfpc-notes.pdf`: opens on Notes.
7. Tab: the selected frame has a thick blue outline with a glow; the committed one is green.
8. Hover over a link on the Next preview: plain arrow cursor; on the current slide: pointing hand.

### Follow-ups after round 3 (2026-10-27, `main`)

- **Native title bar.** Ben prefers native Mac behaviour, so the drawn centred title went and AppKit's header with the real proxy icon stayed (see decisions).
- **Opaque hover highlight** on the shortcut card's rows.
- **Overview jumps directly** (branch `overview-direct`). Clicking a frame, an outline entry or a search hit goes there at once and closes the overview; the audience follows. Arrow keys move a cursor (blue) without changing the slide; the current frame stays green; Return jumps to the cursor; Esc closes. The private browse and its PREVIEW banner are gone from the Mac. ⌫ still returns to where the jump started. Self-test `-overview` checks that → moves only the cursor and Return jumps and closes.
- **Overview stays open** after a click, Return, an outline entry or a search hit (branch `overview-stay`); Tab or Esc closes it. Under each frame: a stack icon with the build count beside the label (frames with more than one build), the appendix mark, and a notes icon at the right when the frame has notes. Self-test `-overview` now checks that Return keeps the overview open and Esc closes it.
- **Present and Swap buttons** (branch `present-buttons`) in the status bar's right region, next to the LIVE pill: Present ⌥⌘P turns into End while presenting; Swap ⌥⌘D is dimmed without a second display. Tooltips explain that a TV or projector must be set to "Use As Separate Display", not mirroring. Icons only when the window is narrow.

## Feedback round 4 (2026-10-27, branch `feedback-4`)

1. **⌘D swaps displays**; ⌥⌘D belonged to the Dock. Menu, card, key map and SPEC §6.5 updated.
2. **C** clears the drawing and turns Laser and Draw off (`Presentation.deactivateTools`). Self-test `-ink` checks both.
3. **Present button carries the presenting state**: Present ⌥⌘P when idle; lit green "Live" (with an audience display) or "Rehearsal" (without) while presenting, Esc Esc hint, click to end. The LIVE / NOT PRESENTING pill and REHEARSAL tag are gone; FROZEN / BLACK / WHITE keep theirs.
4. **Overview cursor**: thick blue stroke, no glow.
5. **Audience ring** in the overview is orange and marks the frame the audience sees, so when frozen it stays on the frozen page while the cursor moves.
6. **Overview layout**: the current slide keeps its size and position (same split fraction as the presenter layout); the right column becomes search plus a two-column grid, with the outline as titled dividers between the frames of each section (pinned while scrolling, subsections indented). ↑/↓ move the cursor by two.

## Feedback round 5 (2026-10-27, branch `feedback-5`)

1. **Overview without section dividers**: a plain two-column grid again; the outline remains in the notes pane's Contents list.
2. **Shortcut card on ⌘/ or ?** (Help ▸ Keyboard Shortcuts), closed by Esc, a click outside, a row click, or the app going to the background. The hold-⌘ trigger went: ⌘-Tab is never delivered to apps and the app stays active while the switcher is up, so a hold cannot be told from a system chord (see decisions). The Settings toggle and the modifier monitors are gone; the welcome hint says "? for every shortcut". Self-test `-shortcuts` drives ?, ⌘/, Esc, a click outside and a row click.

## Feedback round 6 (2026-10-27, branch `feedback-6`)

1. **Any key closes the shortcut card** and still does its job (Esc and ⌘/ / ? only close it).
2. **Overview labels stay white**; only the ring is blue.
3. **Esc turns Laser / Draw off** before anything else (after clearing typed digits).
4. **Overview button** at the top right of the right column, lit while in the overview; Tab unchanged. Both pane headers now share `Theme.paneHeader`, so the slide tops still line up.
5. **Hint** under the slide reads "Click to advance" in the same style as the Draw hint.
6. **Contents list**: a section whose first subsection starts on the same page shows no frame number.
7. **B / W / F only while presenting**: keys and menu items are inert otherwise, the pills are hidden, and ending presenting returns the audience to live.
8. **Notes editing removed** (⌘E, Edit / Done, the editor); the sidecar's existing user notes still load.
9. **Overview is a presenting mode**: every key keeps its meaning (→, Space, digits, frames, back), the blue ring follows the current frame and the orange one the audience's when frozen; clicks jump; the cursor and its ↑/↓ row moves are gone. Self-test `-overview` presses → and Space with the overview open.
- **First Esc while presenting** (branch `esc-inplace`) no longer raises a banner: the Present button turns orange and reads "Esc again to end" for a second.
- **App icon** (branch `app-icon`): Ben's artwork moved to `Design/AppIcon/`; `make-appicon.swift` builds `Apps/macOS/Assets.xcassets/AppIcon.appiconset` (rounded-square mask, ten sizes); `ASSETCATALOG_COMPILER_APPICON_NAME` set; the chooser shows the icon above its title.
- **Release DMG** (branch `release-dmg`): `Scripts/release.sh` builds, signs (Developer ID if present, else development), packages `dist/Lectern-<version>.dmg` and can notarize + staple with `NOTARY_PROFILE`. README has a Releases section with the certificate and notarization steps.
- **Full screen while presenting** (branch `present-fullscreen`, 2026-10-28): with a second display, Present (⌥⌘P) also takes the presenter window into full screen and End leaves it; a Settings checkbox (on by default) turns it off; rehearsal is unaffected; a display arriving mid-talk triggers it too. Ben checklist: with the TV as a separate display, press Present and confirm the presenter fills the Mac screen, Esc Esc returns it; turn the setting off and repeat; press ⌃⌘F before Present and confirm End leaves you in full screen.

## Feedback round 7 (2026-11-01, branch `feedback-7`)

**Plan.** Ben's eight items, in one branch:

1. Drop the "Click to advance" hint under the slide.
2. The clock runs only while presenting: Present or Rehearse starts (or resumes) it, End pauses it. Idle it shows 00:00 or the countdown with an arrow for the direction it will run. The reducer refuses `timerStart` outside presenting; the controller starts and pauses it as `displayConfig.isPresenting` flips. Reset while presenting restarts at once. Clicking the timer offers Reset.
3. Two modes: Present (⇧⌘P, F5) shows the audience view (second display, else a window); Rehearse (⇧⌘R) shows none. Both are buttons in the status bar; the lit one ends, the other switches. B / W / F only when live. Full screen (from `present-fullscreen`) now applies to rehearsal too and still not to Present with one display, where the audience window would be hidden.
4. Clear button and C only in Draw mode.
5. Back / Forward buttons under the slide's bottom right after any jump (`history` / `forwardHistory`); new `Command.forward` on ⌘]; `back` skips entries for the page you are on.
6. Overview: Frames (collapsed) / Builds (expanded) toggle; in Frames the selected multi-build frame shows "1 2 3" with the current build lit and its thumbnail follows the current build; label row aligned on the text baseline.
7. SPEC §3.2, §6.1, §6.2, §6.3, §6.5, §6.7; decisions; self-test flags `-modes`, `-back`; key map tests; reducer tests.

**Done.**

1. **No "Click to advance" hint.** The row under the slide shows a hint only for the active tool.
2. **The clock runs only while presenting.** `SessionController.setDisplayConfig` starts or resumes the timer when `isPresenting` turns on and pauses it when it turns off; the reducer refuses `timerStart` outside presenting and restarts after a `timerReset` while presenting; the auto-start on the first advance and `TimerState.hasStarted` are gone, so a pdfpc duration no longer waits for the first advance. Idle, the status bar shows `↑ 00:00` or `↓ 20:00` (the direction it will run) dimmed; paused mid-talk, `⏸ 06:12`. T is inert outside presenting; the countdown editor has a Reset button (⌥T too). Setting a countdown outside presenting no longer starts the clock.
3. **Present and Rehearse.** `AppModel.presentingMode` is `.live` or `.rehearsal`; `isPresenting` covers both, `isLive` gates B / W / F, the pills and the audience window. Present (⇧⌘P, F5) shows the audience view on the audience display or, with one display, in a window ("Audience", Presentation ▸ Audience Window hides it). Rehearse (⇧⌘R) shows none anywhere. Two status-bar buttons: the lit one (green Live, teal Rehearsing) ends, the other switches mode without ending, so the clock keeps running; Esc Esc ends either; the first Esc still turns the lit button orange. Menu, shortcut card, chooser hint, key map and tests follow; ⌥⌘P is gone. The full-screen rule from `present-fullscreen` now reads: full screen for Rehearse and for Present with an audience display, not for Present with one display (it would hide the audience window); the window controller queues requests that arrive mid-transition.
4. **Clear only in Draw mode**: the button appears beside Laser / Draw only then, and C does nothing otherwise (menu item disabled too).
5. **Back / Forward.** `SessionState.backTarget` / `forwardTarget` skip entries for the page on screen; `back` drops such spent entries instead of a no-op; new `Command.forward` on ⌘] and in the Presentation menu. Under the slide's bottom right: "Back to Frame 12 ⌫" after any jump, "Forward to Frame 30 ⌘]" after a Back; within the same frame they say "build 3". Steps never touch the stack, so builds shown at a jump's target still return to where the jump started. Titles drop first, then the hint, when the row is narrow.
6. **Overview Frames / Builds.** A segmented toggle in the overview header, persisted in `overview.showsBuilds`. Frames: one cell per frame, the last page, except the current frame, whose thumbnail follows the build on screen and whose label shows `1 2 3` with the current build lit (each number jumps; frames with more than eight builds show `k/n`). Builds: one cell per page labelled `2 ⧉ 2/3`, ring on the current page. `ThumbnailProvider` is keyed by page now. The label row aligns on the text baseline (the build count sat low before).
7. **Docs**: SPEC §3.2, §6.1, §6.2, §6.3, §6.5, §6.7; six decisions. Self-test: `-modes` (replaces `-rehearsalstaysput`), `-back`, `-ink` checks C outside Draw, `-overview` captures both modes; `FULLSCREEN` and the full-screen half of `-modes` say NOT CHECKABLE when the app cannot activate.

**Verified** (2026-11-01, lid closed, over SSH): 101 PresenterCore tests (five new: back / forward semantics, spent entries, clock refused outside presenting, reset semantics, controller start / pause on presenting), 15 app tests (⇧⌘P, ⇧⌘R, ⌘], ⌥⌘P now unmapped), warnings-as-errors build. Self-tests: `overlays.pdf` (MODES, BACK, OVERVIEW, INK ×2), `basic-169.pdf` (SHORTCUTS, CLICKS, COUNTDOWN, CONTENTS, CLOSEBUTTON, ESCAPE, TITLEBAR), `links-appendix.pdf` (BACK, ROUNDTRIP), `pdfpc-notes.pdf` (COUNTDOWN, RELOAD ×3), all OK; screenshots of the presenter idle, live, rehearsing, with Back / Forward, and the overview in both modes.

**Known issues**

- Full screen could not be verified this session: with the lid closed the app never becomes active and `toggleFullScreen` never completes (the direct `-fullscreen` check fails the same way on the unchanged code from round 2). The self-test now reports this as NOT CHECKABLE. Needs the lid open; see the checklist.
- The countdown editor's focus check is skipped for the same reason.
- Rehearsal with a second display connected leaves that display showing the desktop; Present puts the slides there. That is the intended difference, but a projector audience would see the desktop while rehearsing.
- The overview's Builds mode renders every page's thumbnail on demand from a 96 MB cache; long decks scroll with brief grey cells while they render.

**Ben device checklist (feedback round 7)**

1. Open a deck, lid open. The clock reads `↑ 00:00` dimmed. Click it, set 20: it reads `↓ 20:00` dimmed and does not move. Press → a few times: still does not move.
2. ⇧⌘P: the Present button lights green "Live", the audience window appears (or the TV fills, set as a separate display), the clock runs, and with the TV the presenter goes full screen. Esc Esc: everything returns, the clock shows the pause mark and keeps its value. ⇧⌘R: the Rehearse button lights teal, no audience view anywhere (TV included), the clock resumes from where it was, and the presenter goes full screen. Click Present while rehearsing: it switches to Live without the clock resetting. Click the lit button: ends.
3. Settings: turn "Go full screen while presenting or rehearsing" off; ⇧⌘R leaves the window as it is. Turn it on, press ⌃⌘F first, then ⇧⌘R and Esc Esc: you stay in full screen (entered by hand).
4. Press D: a Clear button appears; press C with Draw off: nothing; with Draw on: strokes go, Draw turns off.
5. Click a link to the appendix, press → twice, read "Back to Frame X" under the slide's bottom right, click it: back where you were, and "Forward to Frame Y" offers the way on; ⌘] takes it. Tab, click a frame, then a frame in the Contents list: Back goes through them in order.
6. Tab: the header shows Frames | Builds. In Frames, go into a multi-build frame: under its thumbnail `1 2 3` with the current build lit, the thumbnail changing with each →; click a number. Switch to Builds: every build is a cell with `k/n`; the ring follows →. The label row's numbers sit level with the frame number.
7. Clock click: "Reset clock to zero" while presenting restarts at once; while idle it stays at zero.

## Feedback round 8 (2026-11-02, branch `feedback-8`)

**Plan.** Ben's five items, in one branch:

1. The clock's direction arrow: smaller, lighter, after the time.
2. Overview, Frames mode: keep the builds symbol between the frame number and the build list.
3. Overview, Frames mode: the label row keeps one height, so listing builds does not push the rows below down.
4. The timer popover: two radio choices, Count up / Count down from [time], instead of the field, Set button and paragraph.
5. Present goes full screen like Rehearse, with one display too.

**Done.**

1. **Clock arrow.** `StatusBar.clock` puts the time first and the arrow (or pause mark) after it at two thirds of the digits' size, regular weight; accessibility labels carry the time and state.
2. **Builds symbol** stays before the `1 2 3` list in Frames mode.
3. **Fixed label row.** `FrameCell.labelRowHeight` (24 pt) for every cell, count or list.
4. **Countdown popover.** `CountdownEditor` is two symbol-drawn radio rows and a small "Reset to 00:00". Count up applies at once; Count down applies the field's time as it is chosen or typed (a half-typed "20:" is left alone); Return closes; the field starts from the current countdown, else the last one set (`timer.lastCountdown`), else 20:00. No paragraph, no Set button.
5. **Present full screen with one display.** `presentingChanged` wants full screen for either mode. The windowed audience view rides above the full-screen presenter as its child window (`AudienceWindowController.ride(above:)`), attached in `windowDidEnterFullScreen` and detached in `windowWillExitFullScreen`; `windowDidExitFullScreen` orders it front again. `canJoinAllSpaces` and a hide-and-reshow were tried first: the first does not put a window into a full-screen Space, the second switches Spaces instead of moving the window. Switching from rehearsal to live while full screen, and Presentation ▸ Audience Window, attach too. Settings note and SPEC §6.1 follow.
6. **Self-test.** The full-screen setting is off for the process through a volatile argument-domain default (nothing written to defaults), so steps are not paced by animations; `-modes` turns it on and now checks Present full screen with the audience window on the active Space and unoccluded, still so after the presenter is ordered front, and back above it after ⌃⌘F by hand. Activation is retried; launching through `open -W -n --stdout … --args` gets it reliably from SSH where a bare launch is refused while another app (Reminders) is frontmost.

**Verified** (2026-11-02, lid open, over SSH): 15 app tests, warnings-as-errors build. Self-tests: `overlays.pdf` (MODES with full screen checkable, BACK, FULLSCREEN, ESCAPE, OVERVIEW, COUNTDOWN ×2, INK ×2), `basic-169.pdf` (SHORTCUTS, CLICKS, COUNTDOWN ×2, CONTENTS, CLOSEBUTTON, ESCAPE, TITLEBAR), `links-appendix.pdf` (BACK, ROUNDTRIP), `pdfpc-notes.pdf` (COUNTDOWN ×2, RELOAD ×3), all OK. Screenshots reviewed: idle `00:11 ⏸`, live `00:29 ↑`, countdown `24:58 ↓`, the popover, the overview with `2 ⧉ 1 2 3` and level rows. PresenterCore untouched.

**Known issues**

- With one display the audience window covers part of the full-screen presenter; drag it aside or close it (Presentation ▸ Audience Window brings it back). Its position is not remembered between talks.
- Typing a countdown applies each keystroke's value in turn (2, 20, 20:00), so the status bar passes through intermediate times while the popover is open.
- The self-test's in-process screenshots cannot show the audience window over the presenter; the Space and occlusion checks stand in for it.

**Ben device checklist (feedback round 8)**

1. Lid open, one display. ⇧⌘P: the presenter goes full screen and the Audience window floats above it; drag it, close it, bring it back with Presentation ▸ Audience Window. ⌃⌘F: back to a window with the audience window still above. Esc Esc ends.
2. With the TV: ⇧⌘P fills the TV and the presenter goes full screen, as before.
3. Click the clock: Count up / Count down from [20:00]. Click Count down: the clock reads `20:00 ↓` at once; type 45: it reads `45:00`; Return closes. Click Count up: `00:00 ↑`. Reset to 00:00 while presenting restarts at once.
4. Tab in a multi-build frame: `2 ⧉ 1 2 3` under its thumbnail, and the rows below stay put as you move in and out of the frame.

## Feedback round 9 (2026-11-02, branch `feedback-9`)

**Plan.** Ben's one item: an ⓘ after both the Notes and the Contents heading, each opening a popover that explains how to get content into that pane, with detail on every supported notes format.

**Done.**
1. **ⓘ after both headings** (`PaneInfoButton`): `info.circle` at the small size, secondary until open, with a hover hint. The popover opens below the heading, 440 pt wide, text selectable. Which popover is open is model state (`AppModel.paneInfoShown`, `showPaneInfo`), so the self-test can drive it; Esc closes an open popover before it does anything else.
2. **Notes popover** (`NotesSourcesInfo`): an opening paragraph (sources merge per page, the earlier wins, a build inherits its frame's notes, the heading names the source), then the five sources of SPEC §5.1 in priority order with the LaTeX or companion file each needs: the `.pdfpc` file; the pdfpc package (`\pdfpcnote`, `\only<2>{…}`, `duration` / `enduserslide`); pdfcomment (`\pdfcomment`, `\pdfmargincomment`); Beamer second-screen notes (`pgfpages`, `show notes on second screen=right`, `\note`); PowerPoint (`.pptx` beside the PDF, hidden slides skipped, a count mismatch warns). A closing line covers the sidecar and Markdown (⌘+ / ⌘−).
3. **Contents popover** (`ContentsSourcesInfo`): the PDF outline, click to jump, Back returns; Beamer's `\part` / `\section` / `\subsection` / `\subsubsection` make entries (checked in `beamerbasesection.sty`, which calls `\Hy@writebookmark` for each); other LaTeX needs `hyperref`; PowerPoint and Keynote exports usually carry none, so the Overview serves instead; the Appendix / Backup / Supplementary rule. The opening paragraph changes when the deck has no outline.
4. **Contents tab always shown**, dim and inert when the outline is empty (`PaneTab.enabled`), because that is exactly when the explanation is needed; it used to be hidden.
5. **Self-test**: `-contents` now opens both popovers through the model, closes the Notes one with the escape command and the other through the model, and prints `PANEINFO` with the popover's size and appearance. Popover screenshots are filled with their appearance's background first: `render(in:)` drops the vibrant material, so white text vanished on the PNG's white.

**Verified** (2026-11-02, over SSH, the Mac at its login window): 15 app tests, warnings-as-errors build. Self-tests `basic-169.pdf` (outline of 4; `-contents -escape`), `transitions.pdf` (no outline), `pdfpc-notes.pdf` (`-notes -contents`): PANEINFO notes and contents OK on all three, popovers 502×599 and 502×323 in NSAppearanceNameVibrantDark, closed again. Screenshots reviewed: both popovers' full text, the header `Notes ⓘ Contents ⓘ`, the dim Contents tab on `transitions.pdf`, the "from PDF annotations" label still at the right. PresenterCore untouched.

**Known issues**
- The dim Contents tab shows no hover hint (AppKit gives disabled controls none); its ⓘ carries the explanation.
- The two popovers are the only in-app documentation of the notes formats; a Help menu entry could reuse the same texts.
- "PowerPoint and Keynote exports usually carry no outline" is from experience, not checked against current versions of either.

**Ben device checklist (feedback round 9)**
1. Open a deck, click ⓘ after Notes: the popover opens below the heading with the five sources. Press Esc: it closes and nothing else happens (no "Esc again to end", Laser and Draw untouched). Click ⓘ again, then click elsewhere: it closes.
2. Click ⓘ after Contents: the outline explanation. Click an outline entry with the popover closed: still jumps.
3. Open a PDF without bookmarks (a PowerPoint or Keynote export, or `Fixtures/transitions.pdf`): Contents is dim and does nothing; its ⓘ opens and says the deck has no outline.
4. Read both texts once for your own workflow: anything wrong or missing (a notes format you use that is not listed, a macro named wrong) is a one-line change.
