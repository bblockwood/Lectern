# Lectern: Product & Technical Spec (v0.1)

*Lectern is a working name. Owner: Ben. Builder: Fable via Claude Code.*
*Scope of this version: everything, with milestones M0–M3 specified in the most detail.*

---

## 1. What this is

A presenter app for PDF slide decks on macOS, iPadOS and iOS, with an Apple Watch remote.
- LaTeX Beamer is the primary source format.
- PowerPoint and Keynote PDF exports are second.
- The target use is academic seminars, conference talks and lectures. These involve long Q&A, frequent jumps to backup slides, dense tables and last-minute recompiles.

### 1.1 Design principles (in priority order)

1. **Never fail on stage.** A talk in progress must survive display hot-plug, file changes, memory pressure and malformed PDFs. It must not crash and must not show the audience anything unintended.
2. **The audience sees only what the presenter commits.** Browsing, searching and previewing happen on the presenter screen only.
3. **Advancing is instant.** With a warm cache, the new slide reaches the audience display within one display refresh of the keypress. No flicker, no blank frames, and no progressive rendering ever visible to the audience.
4. **Beamer-aware.** Frames vs. builds (overlays), notes, links, outline and appendix behave the way a Beamer author expects.
5. **Keyboard-first on Mac, touch/Pencil-first on iPad.** Every action is also reachable from a keyboard or a presentation clicker.

### 1.2 Non-goals (for now)

- Editing slide content.
- PDF JavaScript, optional-content (OCG) animations from the `animate` package, RichMedia/3D annotations.
- Non-Apple platforms.
- Cloud services beyond iCloud Drive file sync.

---

## 2. Platforms

- macOS 26+, iPadOS/iOS 26+, watchOS 26+. Raise these freely; there is no back-compat requirement.
- Swift 6 language mode with strict concurrency.
- Distribution is personal/TestFlight first. The App Store is optional later.

---

## 3. Architecture

### 3.1 Modules

```
Packages/PresenterCore      Foundation + CoreGraphics + PDFKit only (no UIKit/AppKit/SwiftUI)
  Document/   PDF loading, page labels, frame grouping, outline, links, text search
  Notes/      notes providers + merge
  Render/     RenderCache actor, render requests, thumbnails
  Session/    SessionState, Command, SessionController, history stack
  Ink/        stroke model, persistence, PDF export
  Timing/     timer, pacing, rehearsal logs
  Sidecar/    per-deck JSON persistence
Packages/PresenterProtocol  Foundation only (must build for watchOS): Command, SessionSnapshot, wire messages
Apps/macOS                  AppKit display windows + SwiftUI presenter chrome
Apps/iOS                    UIKit scenes (incl. external display) + SwiftUI chrome; iPad and iPhone
Apps/watchOS                remote (M8)
Spikes/                     throwaway prototypes (M0), never shipped
```

### 3.2 Single source of truth: SessionState + Command

Every input is translated into a `Command` and sent to one `SessionController`, which mutates `SessionState`. Inputs include keyboard, clicker, mouse, touch, Pencil, iPhone remote and Watch. Every view renders from `SessionState`, including the audience, presenter and remote views. **No view mutates state directly.** This is what makes remotes, mirroring and testing cheap.

`SessionState` includes at minimum:
- `committedPage`: what the audience sees.
- `browsePage`: a presenter-only preview; nil when not browsing.
- `audienceMode`: `live | frozen(page) | black | white`.
- `pointer`: optional normalized point plus style.
- `ink`: strokes for the visible page, ephemeral and persistent.
- `history`: back stack of page indices from link and jump navigation.
- `timer`: start, paused state, target duration, section targets.
- `displayConfig`.

Initial `Command` set:
- Navigation: `next`, `previous`, `nextFrame`, `previousFrame`, `goToPage(i)`, `goToFrameLabel(s)`, `followLink(id)`, `back`.
- Browsing: `beginBrowse`, `browseTo(i)`, `commitBrowse`, `cancelBrowse`.
- Audience: `setAudienceMode`.
- Pointer: `pointerMove(pt)`, `pointerHide`.
- Ink: `inkBegin/Append/End`, `clearInk`, `insertWhiteboard`.
- Timer: `timerStart/Pause/Reset`.

Semantics:
- `next` and `previous` move one page (one build).
- `nextFrame` goes to the first page of the next frame.
- `previousFrame` goes to the **last** page of the previous frame, so it is fully built. This matches pdfpc behavior.
- Any jump that is not a step pushes the current page onto `history`. That includes link follows, jump-by-number and committed browses. `back` pops.

### 3.3 Rendering

- Rasterize with Apple's renderer (`CGContext.drawPDFPage` / `PDFPage` drawing). **Never use `PDFView` for any slide surface.**
- `RenderCache` is an actor keyed by (page index, pixel size, crop rect, color space). It renders on background tasks and produces `CGImage`s. Slide surfaces are CALayer-backed views that set `contents`.
- Prefetch, per surface:
  - The committed page ±2 pages.
  - The first page of the next frame.
  - The page that `back` would return to.
- The next-slide preview surface gets the same treatment. Thumbnails use a separate low-res, memory-bounded cache.
- Cancel stale requests when navigation moves on.
- On a cache miss, the audience keeps showing the previous image until the new one is complete. Never show a partial or low-res image to the audience. Log misses.
- Fill the page background with white before drawing, since some PDFs have transparent backgrounds. Render in the target display's color space.
- Fit slides with letterboxing or pillarboxing. The surround color is configurable (default black).
- Note annotations (§5.1) must never appear on any slide surface. Verify on fixtures 4–5.
- In notes-split mode (§5.1.4), the audience render uses a crop rect containing only the slide half.
- Fallback engine: if the Apple renderer shows fidelity bugs on the fixture corpus, evaluate PDFium (BSD). **Do not use MuPDF or Poppler** (AGPL/GPL).
- Add `os_signpost` intervals for input received → command applied → frame presented on the audience display.

### 3.4 Sidecar persistence

- One sidecar per deck: `<deck>.lectern.json` next to the PDF when that location is writable, so it syncs via iCloud Drive with the PDF. Otherwise store it in the app container, keyed by a file bookmark.
- Contents:
  - Settings: notes split mode, target duration, end-of-talk page, section targets.
  - User-authored notes, keyed by frame label plus page index.
  - Persistent ink and whiteboard pages.
  - Rehearsal timing logs and the last position.
- The schema is versioned and tolerates unknown keys. A bad sidecar must never prevent opening a deck: log it and continue without it.

---

## 4. Document semantics

### 4.1 Pages, frames, builds

- A **page** is a PDF page.
- A **frame** is a maximal run of consecutive pages with identical page labels. Beamer gives every overlay of a frame the same label; verify this with the overlays fixture.
- If the PDF has no page labels, or every label is unique, each page is its own frame.
- The **build index** is a page's position within its frame.
- The presenter shows "Frame 12 / 40" using labels, plus "Build 2/3" when the frame has more than one page.
- Thumbnails and the overview show the **last** page of each frame.

### 4.2 End of main talk / appendix

`endOfTalkPage` comes from the first available of:
1. pdfpc metadata, if present.
2. The sidecar.
3. A heuristic: the first outline entry titled Appendix, Backup, or Supplementary (case-insensitive).

The remaining-frames count and the pace indicator use it. Beyond this page, the presenter screen (only) shows an "APPENDIX" badge.

### 4.3 Links

- **GoTo** actions, to an explicit page or a named destination, navigate there and push history.
- **Named actions** map to commands, which covers Beamer's navigation symbols: NextPage, PrevPage, FirstPage, LastPage, GoBack (→ `back`), GoForward.
- **URI** links are ignored by default. A setting allows opening them in the browser on the presenter device, after confirmation.
- **Launch / `run:` links** are reserved for video (M9).
- Activation on Mac: click a link on the presenter's current-slide view, or on the audience window. Show a hover cursor.
- Activation on iPad: tap the link (§7).

### 4.4 Outline and search

- Show the PDF outline as a collapsible table of contents in the overview.
- The notes pane doubles as the table of contents (feedback rounds 2 and 3): a Contents heading shows the outline with the current part highlighted and each entry's frame; clicking an entry jumps there. Which of the two shows is decided once when a deck opens (contents if the first slide has no notes) and then only by the presenter; it never flips from slide to slide.
- Full-text search uses the PDF text layer. Results are grouped by frame. Selecting a result browses to it privately; Enter commits.

### 4.5 Transitions

Dropped for now (Ben, 2026-10-27): pages replace each other instantly; `/Trans`, `/Dur` and crossfades between builds are ignored. `transitions.pdf` stays in the corpus as an ordinary deck. Revisit only if Ben asks.

---

## 5. Notes

### 5.1 Sources

Read all of these and merge them per page. Earlier sources take priority.

1. **Sidecar notes** authored in the app. These can override any other source.
2. **pdfpc `.pdfpc` file** with the same basename as the PDF. Implement this per pdfpc's current documentation and source; do not guess keys. Also read its metadata (duration, end slide) where present.
3. **Embedded note annotations**, as produced by the pdfpc LaTeX package and the `pdfcomment` package. Inspect the exact annotation shapes those packages emit in fixtures 4–5 and handle those. Visible page content must never be treated as notes.
4. **Beamer second-screen notes**, from `\setbeameroption{show notes on second screen=right}` (also `left` and `bottom`). Each page holds the slide plus a notes panel.
   - Detect this with an aspect-ratio heuristic: the page is roughly twice as wide or twice as tall as a standard slide.
   - Confirm with the user once per deck and store the answer in the sidecar.
   - The notes pane shows the notes half as a rendered image. The audience gets only the slide half.
5. **PowerPoint notes**, when a `.pptx` with the same basename sits next to the PDF.
   - Get the slide order from `ppt/presentation.xml` (`sldIdLst`) and the relationships files.
   - Skip hidden slides (`show="0"`), since PowerPoint omits them from PDF export by default.
   - Read each slide's `notesSlide` text and map it to PDF pages in order.
   - If the counts don't match, show a warning rather than risk mis-mapping.

### 5.2 Display and editing

- Text notes render as basic Markdown: emphasis, lists, inline code, line breaks. Font size is adjustable (⌘+/⌘−) and persists per device.
- If a build has no notes, show its frame's notes.
- An inline notes editor on the presenter screen writes to the sidecar: Mac in M3, iPad in M5.

---

## 6. macOS presenter (M1–M3)

### 6.1 Displays

- **Windows:**
  - Chooser: a modest window with Open, drag-and-drop and recents, like iWork's chooser (feedback round 3). It hides while a deck is open and returns when the deck closes; closing it quits.
  - Presenter: exists only while a deck is open; fills the visible area of the chooser's screen when a deck opens, whatever the chooser's size. Its title bar shows the deck's icon and name centred (drawn by the app, since AppKit on macOS 26 puts a toolbar-less window's title at the leading edge).
  - Audience: borderless and full-screen on the target display. The cursor is hidden unless pointer mode is on or the mouse is actively over it.
- **Auto-assignment:** the built-in display is the presenter and the largest external display is the audience. Remember choices per display (name plus resolution). Provide a swap shortcut.
- **Single display:** rehearsal mode. The audience view becomes a resizable window, or can be hidden.
- **Mirrored displays:** detect mirroring and warn that notes would be visible. Offer a button that opens Displays settings.
- **Hot-plug:** if the audience display disappears mid-talk, keep presenting and show a banner. When it returns, restore the audience window at the current page.
- **While presenting:** hold a power assertion that prevents display sleep, and keep the menu bar and Dock off the audience display. Prompt once about enabling a Focus.

### 6.2 Presenter layout

- **Panes:**
  - Current slide: large, on the left.
  - Next page preview: top right.
  - Notes: bottom right.
- **Status bar:**
  - Frame label and total, build x/y.
  - The timer: elapsed time, or, once a countdown is set (pdfpc duration, sidecar, or by clicking the timer), the time left in its place: green while positive, red and counting up once exhausted (feedback round 2). The wall clock beside it.
  - Audience-mode indicator: LIVE, or FROZEN/BLACK/WHITE in amber or red.
- Panes are resizable and the layout persists. Dark UI by default.

### 6.3 Overview and jumping

- The overview opens with Tab. It shows a grid of frames with labels, an outline sidebar, and a search field.
- Arrow keys and clicks browse **privately**. The presenter's current-slide view shows the browsed slide with a banner: "PREVIEW: audience sees Frame N".
- Enter commits the browse and pushes history. Esc cancels it.
- Jump by number: typing digits then Return, from anywhere, goes to the frame with that label and pushes history. Return with no digits typed means `next`.

### 6.4 Pointer

- Pointer mode toggles with L.
- In pointer mode, the mouse over the presenter's current slide maps to normalized coordinates and draws a pointer on the audience slide. Moving over the audience window directly also works.
- Default style: a red dot about 1.2% of slide height with a soft glow, plus a fading trail (~300 ms). Color and size are configurable.
- The pointer hides after 2 s without movement or when the mouse leaves the slide.

### 6.5 Default key map

Clickers generally send Page Up/Down, B or `.`, and F5/Esc. All of those must work.

| Action | Keys |
|---|---|
| Next build | → ↓ Space Page Down Return N |
| Previous build | ← ↑ Page Up P |
| Next / previous frame | ⇧→ / ⇧← |
| Back (return from jump) | Delete, ⌘[ |
| Overview | Tab |
| Jump to frame | digits + Return |
| Black / white screen | B or `.` / W |
| Freeze audience | F |
| Laser pointer | L |
| Draw / clear drawing | D / C |
| Next build (also) | click on the current or next slide |
| Full screen | ⌃⌘F |
| Shortcut card | hold ⌘ alone for ~0.5 s; it stays up; a tap of ⌘, Esc or a click outside closes it; its rows are clickable |
| Timer start-pause / reset | T / ⌥T |
| Swap displays | ⌥⌘D |
| Start presenting | ⌥⌘P, F5 |
| End presenting | Esc twice within 1 s (single Esc cancels browse) |

### 6.6 Live reload

- Watch the PDF, the sidecar, `.pdfpc` and `.pptx` files.
- Watch the **directory**, not just the file, because latexmk and editors replace files atomically. Debounce ~300 ms, wait for the file size to stabilize, and require a successful parse before swapping.
- On reload:
  - Restore position by (frame label, build index), falling back to the nearest page index.
  - Rebuild the caches.
  - Swap the audience image only once the new render is ready.
- If the new file fails to parse, keep the old document and retry.

### 6.7 Timer and pacing

- Elapsed time starts at the first advance or at a manual start. Setting a countdown by hand starts it at once (feedback round 3); a deck's own duration still waits for the first advance.
- The target duration comes from pdfpc metadata, the sidecar, or the UI.
- The time left is green while positive and red, counting up, once exhausted (feedback round 2). The frames-vs-time pace indicator (amber when behind) is not shown for now.
- Section targets come in M6.

---

## 7. iPad and iPhone (M4–M5)

- **External display.** Put the audience view in a scene with the non-interactive external-display role (`UISceneSession.Role.windowExternalDisplayNonInteractive`).
  - Handle the extended-desktop case (Stage Manager / windowed multitasking) per Spike A's findings. Either place the audience window on the external screen, or detect it and guide the user to switch modes.
  - If the app is backgrounded mid-talk, the system mirrors the iPad screen again. Re-establish the audience scene on return, and warn once that switching apps exposes the iPad screen.
- **Layout by size class:**
  - iPad landscape mirrors the Mac layout.
  - iPad portrait stacks the panes.
  - iPhone shows current slide, notes and timer, with the next slide on a swipe or peek.
- **Touch:**
  - Tapping a link follows it.
  - Otherwise, tap the right 30% of the current slide or swipe left to advance; tap the left 30% or swipe right to go back.
  - Touch-and-hold on the current slide shows the pointer under the finger.
- **Apple Pencil:**
  - Hover, on supported iPads, puts the pointer on the audience slide with no contact.
  - Contact draws ink.
  - Double-tap or squeeze cycles pointer → ink → eraser, respecting the system Pencil settings.
- **Keyboards and clickers** use the same key map as the Mac, via `UIKeyCommand` and `pressesBegan`.
- Disable the idle timer while presenting.
- **Files:** open decks via the document picker and iCloud Drive, with security-scoped bookmarks, a recent-decks list, and "Open in" from the share sheet.

---

## 8. Ink and whiteboard (basic on Mac in M3, full on iPad in M5)

- Store strokes in normalized coordinates of the slide crop rect, with width relative to slide height, so they look identical on every display.
- Two modes:
  - **Ephemeral:** page-scoped; cleared by C or by leaving the page. On the Mac they do not fade (feedback round 3); the fade (N seconds) stays available as a setting for later.
  - **Persistent:** kept per page in the sidecar.
- The audience mirrors strokes live by redrawing the vectors; never stream bitmaps.
- PencilKit may be used for capture on iPad, but the canonical model is the app's own stroke type, shared with the Mac.
- **Whiteboard:** insert a blank virtual page (white or grid) after the current page. It lives in the sidecar, appears in the overview with a marker, and can be deleted.
- **Export:** "Export annotated PDF" writes a new file with persistent ink as PDF ink annotations.

---

## 9. Remotes (M7–M8)

### 9.1 Protocol (`PresenterProtocol`)

- Messages are Codable:
  - `command(Command)`.
  - `state(SessionSnapshot)`: page index, frame label, build, next page, notes text, timer, audience mode.
  - `thumbnail(page, jpeg)`, on request.
  - `ping`/`pong` with timestamps.
- The presenting device is the host.

### 9.2 iPhone remote (for Mac and iPad hosts)

- **Transport:** Network framework with Bonjour discovery.
  - Pair with a 4-digit code shown on the host; use TLS with a pre-shared key derived from pairing.
  - Enable peer-to-peer Wi-Fi so it works at venues with no shared network.
- **UI:**
  - Current and next thumbnails, notes, timer.
  - Big Next/Prev targets.
  - A pointer pad: dragging on the thumbnail moves the pointer on the audience display.

### 9.3 Apple Watch remote

- **Transport:** chosen per Spike B.
  - (A) WatchConnectivity to the iPhone app, which relays to the host over §9.2.
  - (B) Core Bluetooth. The host advertises a GATT service, and the Watch connects as central. Next/Prev are write-without-response; state comes via notify.
- **UI:** a huge Next button as the primary action, plus Prev, the frame label, and elapsed/remaining time.
- **Double tap:** the system double-tap gesture triggers Next via `.handGestureShortcut(.primaryAction)` (Series 9 / Ultra 2 or newer).
- **Haptics:** configurable pacing taps, such as 10 min left, 5 min left, time up, and behind pace.
- The app must be frontmost with the screen awake. Document the recommended Wake Screen setting.

---

## 10. Media and interactivity (M9)

### 10.1 Video

- Convention: a Launch/URI link pointing to a video file relative to the PDF. Also support pdfpc's movie conventions if they are simple.
- An AVPlayer layer overlays the link rect on the audience display. Controls (play/pause/scrub) are on the presenter side.
- An `?autostart` flag starts playback on arrival.

### 10.2 Interactive widgets

- Convention: a link with URI `lectern-widget:path/to/widget.html?params`.
- The app overlays a WKWebView at that rect on the audience display and gives the presenter an interactive twin.
- Injected JS API: `lectern.state`, `lectern.setState(patch)`, `lectern.onState(cb)`. Interactions on the presenter side update state, and the app relays it to the audience copy.
- Widgets must work offline, with bundled libraries.
- Other PDF viewers show whatever static placeholder the author placed under the link.

### 10.3 LaTeX package `lectern.sty`

- Macros:
  - `\lecternnote{…}` emits a note annotation compatible with §5.1(3).
  - `\lecternwidget[w,h]{file.html}{placeholder}`.
  - `\lecternvideo{file.mp4}{poster}`.
  - `\lecternsetup{duration=45, endslide=…}`.
- Must work with pdfLaTeX and LuaLaTeX.

---

## 11. Milestones

### M0: Spikes (throwaway, in `Spikes/`)

**A. iPad external display.**
- Build a minimal app that shows different content on each screen plus a shared counter.
- Test on the Simulator's external display.
- Ben tests on his iPad with a USB-C→HDMI adapter, in default and extended/Stage Manager modes, including what happens when the app is backgrounded.
- Output: `docs/spikes/A-external-display.md` with findings and a recommended approach.

**B. Watch latency.**
- Build a minimal watch app with a Next button bound to double tap. Implement transports A and B to a Mac host.
- Measure round-trip time: the Watch timestamps each send, the host echoes immediately, and one-way latency is about RTT/2. Use at least 100 presses per transport.
- Report median and p95, behavior with the wrist lowered or screen dimmed, and reconnect time.
- Target: median one-way < 100 ms, p95 < 200 ms.
- Output: `docs/spikes/B-watch-latency.md` with a recommendation.

**C. Render benchmark.**
- Time per-page rendering at 1080p, 1440p and 4K for every fixture.
- Confirm that a warm-cache advance takes less than one frame.
- Output: `docs/spikes/C-render.md`.

### M1: Mac core presenting

- Open a PDF via the open panel, drag-and-drop, or the recents list.
- Audience and presenter windows with display assignment, mirroring warning and hot-plug handling.
- Render cache.
- Next/previous by build and by frame, plus the next-page preview.
- Status bar, basic timer, keep-awake.

**Accept:**
- Principle 3 is verified with signposts on all fixtures.
- No flicker.
- Unplugging and replugging the audience display mid-talk works.

### M2: Mac navigation

- Overview grid, outline and search.
- Jump by number and private browse.
- History/back.
- Link following, including named actions.
- Black/white/freeze.

**Accept:** an appendix round-trip on fixture 6 works in one keypress each way.

### M3: Mac notes, pointer, live reload

- All notes sources (§5.1), the Markdown notes pane, and the notes editor.
- Pointer.
- Live reload.
- Sidecar.
- Basic ephemeral ink with the mouse.

**Accept:**
- Notes appear correctly for fixtures 3, 4, 5 and 9.
- Recompiling fixture 2 mid-talk keeps the position.

**→ Ben uses it for a real talk. Collect issues before M4.**

### Later milestones

- **M4. iOS/iPadOS core:** external display per Spike A, touch navigation, keyboard/clicker, file access, notes, overview.
- **M5. iPad pointer and ink:** Pencil hover, touch pointer, ink, whiteboard, annotated export, notes editor.
- **M6. Timing:** section targets, rehearsal mode logging time per slide, rehearsal report.
- **M7. iPhone remote** for Mac and iPad hosts.
- **M8. Watch remote** per Spike B.
- **M9. Media and interactivity:** transitions, video, widgets, `lectern.sty`.
- **M10. Polish:** iCloud sidecar sync and Handoff of position, settings UI, accessibility, optional App Store prep.

---

## 12. Test corpus (`Fixtures/`)

Generate fixtures from LaTeX sources in `Fixtures/src/` with latexmk wherever possible.

1. `basic-169.pdf`: 16:9, 20 frames, no overlays.
2. `overlays.pdf`: 4:3 with heavy `\pause`, `\only` and `\uncover`.
3. `notes-right.pdf` and `notes-bottom.pdf`: Beamer second-screen notes.
4. `pdfpc-notes.pdf` + `pdfpc-notes.pdfpc`: notes via the pdfpc LaTeX package.
5. `pdfcomment-notes.pdf`: notes via `pdfcomment`.
6. `links-appendix.pdf`: hyperlinks into `\appendix` frames, navigation symbols on, named actions.
7. `tikz-heavy.pdf`: pgfplots/TikZ with shadings and transparency.
8. `transitions.pdf`: `\transdissolve`, `\transduration`.
9. `ppt-export.pdf` + `ppt-export.pptx`: a PowerPoint export with notes and one hidden slide. *Ben supplies this.*
10. `huge.pdf`: 300+ pages, for memory and thumbnail stress.
11. `malformed.pdf`: a truncated file. Must not crash.

PresenterCore unit tests must cover:
- Frame grouping.
- Notes for each source and the merge order.
- PPTX mapping, including the hidden slide.
- Notes-split detection.
- The history stack.
- Live-reload position restore.
- Sidecar round-trip and tolerance of a corrupt sidecar.

---

## 13. Open decisions (Ben)

- App name.
- Personal/TestFlight only, or eventually the App Store?
- Support Watches without double tap (button-only)?
- May URI links ever open a browser during a talk?
