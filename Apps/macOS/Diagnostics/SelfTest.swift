import AppKit
import PresenterCore

/// `Lectern -selftest deck.pdf [steps]`: opens the deck, presents in rehearsal mode, drives synthetic key events
/// through the real input path, and prints latency statistics (SPEC §11 M1 acceptance). Exits when done.
@MainActor
final class SelfTest {
    private let url: URL
    private let requestedSteps: Int?
    private var samples: [Latency.Sample] = []
    private var pending: CheckedContinuation<Void, Never>?

    init(url: URL, steps: Int?) {
        self.url = url
        self.requestedSteps = steps
    }

    static let isActive = CommandLine.arguments.contains("-selftest")

    static func fromArguments(_ arguments: [String]) -> SelfTest? {
        guard let index = arguments.firstIndex(of: "-selftest"), arguments.indices.contains(index + 1) else { return nil }
        let steps = arguments.indices.contains(index + 2) ? Int(arguments[index + 2]) : nil
        return SelfTest(url: URL(fileURLWithPath: arguments[index + 1]), steps: steps)
    }

    func run(in model: AppModel) {
        NSApp.activate()
        continueRun(in: model)
    }

    private func continueRun(in model: AppModel) {
        model.open(url: url)
        guard let presentation = model.presentation else {
            print("SELFTEST FAIL: could not open \(url.path)")
            exit(2)
        }
        presentation.apply(.goToPage(0))   // the sidecar restores the last position; runs must not depend on it
        model.startPresenting()
        Latency.shared.onSample = { [weak self] sample in
            self?.samples.append(sample)
            self?.pending?.resume()
            self?.pending = nil
        }
        let forward = requestedSteps ?? (presentation.document.pageCount - 1)
        Task { await drive(forward: forward, presentation: presentation) }
    }

    private func drive(forward: Int, presentation: Presentation) async {
        try? await Task.sleep(for: .seconds(1.5))   // let the first prefetch ring land
        if !NSApp.isActive { print("SELFTEST WARNING: this instance is not the active app (another Lectern running?); focus-dependent checks are skipped") }
        for _ in 0..<forward { await press(keyCode: 124, character: "\u{F703}") }   // → next
        captureScreenshots()
        if CommandLine.arguments.contains("-shortcuts"), let model = (NSApp.delegate as? AppDelegate)?.model {
            await shortcutsCheck(model: model, presentation: presentation)
        }
        if CommandLine.arguments.contains("-clicks"), let model = (NSApp.delegate as? AppDelegate)?.model {
            // A plain click on the current slide, then on the next-slide preview, advances one build each.
            let before = presentation.state.committedPage
            await click(on: presentation.currentSurface.view, at: (0.5, 0.5))
            let afterCurrent = presentation.state.committedPage
            await click(on: presentation.previewSurface.view, at: (0.5, 0.5))
            let afterNext = presentation.state.committedPage
            print("CLICKS \(afterCurrent == before + 1 && afterNext == before + 2 ? "OK" : "FAIL"): page \(before + 1) → click current → \(afterCurrent + 1) → click next → \(afterNext + 1)")
            _ = model.perform(.command(.previous))
            _ = model.perform(.command(.previous))
        }
        if CommandLine.arguments.contains("-countdown"), let model = (NSApp.delegate as? AppDelegate)?.model {
            // 25 minutes: green time left in place of the elapsed time; 1 second: already over, red and negative.
            let fromDeck = presentation.state.timer.target
            model.setTargetDuration(25 * 60)
            try? await Task.sleep(for: .milliseconds(300))
            let remaining = presentation.state.timer.remaining(at: Date()) ?? 0
            captureScreenshots(suffix: "-countdown")
            model.setTargetDuration(1)
            try? await Task.sleep(for: .milliseconds(1800))   // well past the 1 s target
            let over = presentation.state.timer.remaining(at: Date()) ?? 0
            captureScreenshots(suffix: "-overtime")
            model.requestCountdownEditor()
            try? await Task.sleep(for: .milliseconds(500))
            captureScreenshots(suffix: "-countdown-editor")
            // Keys must land in the popover's field, not in the presenter's key map (a digit would start a jump).
            func fields(_ view: NSView?) -> [NSTextField] {
                (view?.subviews ?? []).flatMap { ($0 as? NSTextField).map { [$0] } ?? fields($0) }
            }
            let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
            if NSApp.isActive {
                let fieldFocused = popover?.isKeyWindow == true && popover?.firstResponder is NSTextView
                let jumpBefore = model.jumpBuffer
                await press(keyCode: 20, character: "3")
                let fieldText = fields(popover?.contentView).first?.stringValue ?? ""
                let typedIntoField = fieldText.hasSuffix("3") && model.jumpBuffer == jumpBefore
                print("COUNTDOWN editor \(fieldFocused && typedIntoField ? "OK" : "FAIL"): popover \(popover == nil ? "missing" : "open"), its field focused \(fieldFocused); typing 3 gave the field \"\(fieldText)\" and the jump buffer \"\(model.jumpBuffer)\"")
            } else {
                print("COUNTDOWN editor SKIPPED (app not active): popover \(popover == nil ? "missing" : "open")")
            }
            await press(keyCode: 53, character: "\u{1b}")   // closes the popover
            try? await Task.sleep(for: .milliseconds(300))
            _ = model.perform(.escape)   // clears a stray jump digit, if any
            model.setTargetDuration(fromDeck)
            presentation.flushSidecar()   // the save is debounced; exit(0) below would otherwise keep the test's target
            print("COUNTDOWN \(remaining > 24 * 60 && remaining <= 25 * 60 && over < 0 ? "OK" : "FAIL"): deck target \(fromDeck.map { "\(Int($0)) s" } ?? "none"); 25 min set → \(Int(remaining)) s left; 1 s set → \(Int(over)) s (negative = over time)")
        }
        if CommandLine.arguments.contains("-contents"), let model = (NSApp.delegate as? AppDelegate)?.model {
            // The notes pane's Contents tab, with the entry containing the current page highlighted.
            let outline = presentation.document.outline
            let openedWithContents = model.notesShowsContents
            model.setNotesShowsContents(true)
            try? await Task.sleep(for: .milliseconds(400))
            captureScreenshots(suffix: "-contents")
            _ = model.perform(.command(.next))
            _ = model.perform(.command(.previous))
            let stuck = model.notesShowsContents
            print("CONTENTS sticky \(stuck ? "OK" : "FAIL"): opened showing \(openedWithContents ? "contents" : "notes") (first slide \(presentation.notes.table.note(for: 0, frames: presentation.document.frames) == nil ? "has no notes" : "has notes")); still contents after moving \(stuck)")
            model.setNotesShowsContents(false)
            // The notes editor's Done button must not move the pane header (feedback round 2).
            model.setNotesEditing(true)
            try? await Task.sleep(for: .milliseconds(400))
            captureScreenshots(suffix: "-editing")
            model.setNotesEditing(false)
            try? await Task.sleep(for: .milliseconds(200))
            let page = presentation.state.presenterPage
            let current = outline.currentEntry(forPage: page)
            print("CONTENTS outline entries \(outline.flattened.count); on page \(page + 1) the current entry is \(current.map { "\"\($0.title)\" (page \(($0.pageIndex ?? -1) + 1))" } ?? "none")")
        }
        if CommandLine.arguments.contains("-fullscreen"), let window = NSApp.windows.first(where: { $0 is PresenterWindow }) {
            window.toggleFullScreen(nil)
            try? await Task.sleep(for: .seconds(2))
            let entered = window.styleMask.contains(.fullScreen)
            window.toggleFullScreen(nil)
            try? await Task.sleep(for: .seconds(2))
            let left = !window.styleMask.contains(.fullScreen)
            print("FULLSCREEN \(entered && left ? "OK" : "FAIL"): entered \(entered), left again \(left)")
        }
        if CommandLine.arguments.contains("-closebutton"), let model = (NSApp.delegate as? AppDelegate)?.model,
           let window = NSApp.windows.first(where: { $0 is PresenterWindow }) {
            // The red button: performClose asks windowShouldClose, which closes the deck; the presenter window
            // hides and the chooser comes back (feedback round 3).
            let welcome = NSApp.windows.first { $0 is WelcomeWindow }
            let filled = window.frame == window.screen?.visibleFrame
            window.performClose(nil)
            try? await Task.sleep(for: .milliseconds(600))
            let closed = model.presentation == nil, presenterHidden = !window.isVisible, chooserBack = welcome?.isVisible == true
            captureScreenshots(suffix: "-welcome")
            model.open(url: url)
            model.startPresenting()   // opening ends presenting; keep the audience surface as the measured one
            try? await Task.sleep(for: .seconds(1.5))   // a fresh deck: let its prefetch land before more steps
            let reopened = window.isVisible && welcome?.isVisible == false && window.title == url.lastPathComponent && window.representedURL == url
            print("CLOSEBUTTON \(closed && presenterHidden && chooserBack && reopened ? "OK" : "FAIL"): presenter filled its screen \(filled); deck closed \(closed); presenter hidden \(presenterHidden); chooser back \(chooserBack); reopened with the deck's title and proxy icon \(reopened)")
        }
        if CommandLine.arguments.contains("-welcome"), let model = (NSApp.delegate as? AppDelegate)?.model {
            // The chooser, as it comes back after a deck closes.
            model.close()
            try? await Task.sleep(for: .seconds(1))
            captureScreenshots(suffix: "-chooser")
            model.open(url: url)
            model.startPresenting()
            try? await Task.sleep(for: .seconds(1.5))
        }
        if CommandLine.arguments.contains("-titlebar"), let window = NSApp.windows.first(where: { $0 is PresenterWindow }) {
            // AppKit's own header: the deck's name as the title and a real proxy icon (NSThemeDocumentButton).
            func views(_ v: NSView?) -> [NSView] { (v?.subviews ?? []).flatMap { [$0] + views($0) } }
            let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview
            let all = views(titlebar)
            let proxy = all.contains { String(describing: type(of: $0)).contains("DocumentButton") }
            let titled = window.titleVisibility == .visible && window.title == url.lastPathComponent && window.representedURL == url
            print("TITLEBAR \(titled && proxy ? "OK" : "FAIL"): system title \"\(window.title)\" \(window.titleVisibility == .visible ? "visible" : "hidden"); representedURL \(window.representedURL?.lastPathComponent ?? "nil"); proxy icon \(proxy ? "present" : "absent")")
        }
        if CommandLine.arguments.contains("-overview"), let model = (NSApp.delegate as? AppDelegate)?.model {
            let before = presentation.state.committedPage
            await press(keyCode: 48, character: "\t")                               // Tab: overview
            try? await Task.sleep(for: .seconds(1))                                   // the current pane shrank: new render size
            await press(keyCode: 124, character: "\u{F703}")                        // → moves the cursor only
            try? await Task.sleep(for: .seconds(1.5))                                 // thumbnails
            captureScreenshots(suffix: "-overview")
            let cursorMoved = model.overviewSelectedFrame == presentation.document.frames.frame(containing: before).index + 1
            let slideStayed = presentation.state.committedPage == before && !presentation.state.isBrowsing
            await press(keyCode: 36, character: "\r")                               // Return: jump to the cursor
            let jumped = presentation.state.committedPage == presentation.document.frames.frames[presentation.document.frames.frame(containing: before).index + 1].firstPage
            let closed = !model.overviewVisible
            print("OVERVIEW \(cursorMoved && slideStayed && jumped && closed ? "OK" : "FAIL"): → moved the cursor \(cursorMoved) while the slide stayed \(slideStayed); Return jumped to it \(jumped) and closed the overview \(closed)")
            await press(keyCode: 51, character: "\u{7f}")                           // ⌫ back to where the jump started
        }
        for _ in 0..<forward { await press(keyCode: 123, character: "\u{F702}") }   // ← previous
        // A few frame jumps and a back, which may legitimately miss.
        await press(keyCode: 124, character: "\u{F703}", shift: true)
        await press(keyCode: 124, character: "\u{F703}", shift: true)
        await press(keyCode: 123, character: "\u{F702}", shift: true)
        if CommandLine.arguments.contains("-roundtrip") { await roundTrip(presentation: presentation) }
        if CommandLine.arguments.contains("-notes") { notesCheck(presentation: presentation) }
        if CommandLine.arguments.contains("-ink") { await inkCheck(presentation: presentation) }
        if CommandLine.arguments.contains("-reload") { await reloadCheck() }
        report(presentation: presentation)
        exit(0)
    }

    /// Prints the merged note for every page so fixtures 3, 4 and 5 can be eyeballed from the terminal.
    private func notesCheck(presentation: Presentation) {
        print("NOTES split=\(presentation.notesSplit) pending=\(presentation.pendingSplitQuestion.map { "\($0)" } ?? "none") warnings=\(presentation.notes.warnings)")
        for page in 0..<presentation.document.pageCount {
            let note = presentation.notes.table.note(for: page, frames: presentation.document.frames)
            print("  p\(page + 1): \(note.map { "[\($0.source.rawValue)] " + $0.text.replacingOccurrences(of: "\n", with: "⏎") } ?? "–")")
        }
    }

    /// Pointer and ephemeral ink through the surface view's mouse handlers, then screenshots.
    private func inkCheck(presentation: Presentation) async {
        guard let model = (NSApp.delegate as? AppDelegate)?.model else { return }
        let view = presentation.currentSurface.view
        guard let window = view.window else { print("INK FAIL: no window"); return }
        func event(_ type: NSEvent.EventType, _ normalized: (Double, Double)) -> NSEvent {
            let slide = view.slideFrame
            let point = NSPoint(x: slide.minX + slide.width * normalized.0, y: slide.minY + slide.height * (1 - normalized.1))
            return NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 7, clickCount: 1, pressure: 1)!
        }
        _ = model.perform(.togglePointer)
        view.mouseMoved(with: event(.mouseMoved, (0.3, 0.4)))
        view.mouseMoved(with: event(.mouseMoved, (0.32, 0.42)))
        let pointerShown = presentation.state.pointer != nil && presentation.pointerMode
        _ = model.perform(.toggleDraw)
        view.mouseDown(with: event(.leftMouseDown, (0.2, 0.7)))
        for i in 1...20 { view.mouseDragged(with: event(.leftMouseDragged, (0.2 + Double(i) * 0.03, 0.7 + 0.1 * sin(Double(i) / 3)))) }
        view.mouseUp(with: event(.leftMouseUp, (0.8, 0.7)))
        let strokes = presentation.state.ink.strokes
        let audienceHasInk = presentation.audienceSurface.view.inkStrokeCount
        print("INK \(pointerShown && strokes.count == 1 && strokes[0].points.count == 21 && audienceHasInk == 1 ? "OK" : "FAIL"): pointer shown \(pointerShown), strokes \(strokes.count) with \(strokes.first?.points.count ?? 0) points, audience ink layers \(audienceHasInk), draw mode \(presentation.drawMode)")
        captureScreenshots(suffix: "-ink")
        try? await Task.sleep(for: .seconds(3.5))
        let kept = presentation.state.ink.strokes.count
        _ = model.perform(.command(.clearInk))
        let cleared = presentation.state.ink.strokes.count
        view.mouseDown(with: event(.leftMouseDown, (0.3, 0.3)))
        view.mouseDragged(with: event(.leftMouseDragged, (0.5, 0.3)))
        view.mouseUp(with: event(.leftMouseUp, (0.5, 0.3)))
        let drawnAgain = presentation.state.ink.strokes.count
        _ = model.perform(.command(.next))
        let afterAdvance = presentation.state.ink.strokes.count
        _ = model.perform(.command(.previous))
        print("INK persistence \(kept == 1 && cleared == 0 && drawnAgain == 1 && afterAdvance == 0 ? "OK" : "FAIL"): strokes after 3.5 s \(kept) (expected 1), after C \(cleared), drawn again \(drawnAgain), after the next build \(afterAdvance)")
        _ = model.perform(.toggleDraw)
    }

    /// M3 acceptance: a deck recompiled mid-talk keeps the position by (frame label, build).
    private func reloadCheck() async {
        guard let model = (NSApp.delegate as? AppDelegate)?.model else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lectern-reload-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let deck = dir.appendingPathComponent("deck.pdf")
        let fixtures = url.deletingLastPathComponent()
        do { try FileManager.default.copyItem(at: fixtures.appendingPathComponent("overlays.pdf"), to: deck) } catch { print("RELOAD FAIL: \(error)"); return }
        model.open(url: deck)
        guard let presentation = model.presentation else { print("RELOAD FAIL: could not open copy"); return }
        try? await Task.sleep(for: .seconds(1))
        _ = model.perform(.command(.goToPage(5)))    // frame "3", build 2 of overlays.pdf
        let before = (presentation.document.frames.frame(containing: 5).label, presentation.document.frames.buildIndex(of: 5))
        func replace(with name: String) async -> Bool {
            let outcomesBefore = presentation.reloadOutcomes
            let temp = dir.appendingPathComponent("deck.pdf.tmp")
            try? FileManager.default.removeItem(at: temp)
            do {
                try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: temp)
                _ = try FileManager.default.replaceItemAt(deck, withItemAt: temp)
            } catch { print("RELOAD FAIL: replace \(error)"); return false }
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
                if presentation.reloadOutcomes > outcomesBefore { return true }
            }
            return false
        }
        // 1. A recompiled deck with different pagination but the same labels: links-appendix frame "3" has 3 builds.
        let step1 = await replace(with: "links-appendix.pdf")
        let after1 = presentation.state.committedPage
        let restored1 = presentation.document.pageCount == 11 && presentation.document.frames.frame(containing: after1).label == before.0
            && presentation.document.frames.buildIndex(of: after1) == before.1
        print("RELOAD step 1 \(step1 && restored1 ? "OK" : "FAIL"): was frame \(before.0) build \(before.1 + 1); now page \(after1 + 1) of \(presentation.document.pageCount) (frame \(presentation.document.frames.frame(containing: after1).label) build \(presentation.document.frames.buildIndex(of: after1) + 1)); notice: \(presentation.reloadNotice ?? "none")")
        // 2. A broken PDF must be ignored and the old deck kept.
        let pagesBefore2 = presentation.document.pageCount
        let step2 = await replace(with: "malformed.pdf")
        let kept = presentation.document.pageCount == pagesBefore2 && presentation.reloadFailed && presentation.state.committedPage == after1
        print("RELOAD step 2 \(step2 && kept ? "OK" : "FAIL"): malformed replacement ignored, still \(presentation.document.pageCount) pages at page \(presentation.state.committedPage + 1); notice: \(presentation.reloadNotice ?? "none")")
        // 3. The next good compile is picked up again.
        let step3 = await replace(with: "overlays.pdf")
        let ok3 = presentation.document.pageCount == 23 && !presentation.reloadFailed
        print("RELOAD step 3 \(step3 && ok3 ? "OK" : "FAIL"): back to \(presentation.document.pageCount) pages at page \(presentation.state.committedPage + 1)")
        try? FileManager.default.removeItem(at: dir)
    }

    /// M2 acceptance: click a link into the appendix on the presenter's current slide, press Delete to return.
    private func roundTrip(presentation: Presentation) async {
        guard let model = (NSApp.delegate as? AppDelegate)?.model else { return }
        _ = model.perform(.command(.goToPage(0)))
        // Find the first page with a GoTo link into the appendix.
        guard let end = presentation.document.endOfTalkPage,
              let (page, link) = (0...end).lazy.compactMap({ page -> (Int, PageLink)? in
                  presentation.document.links(onPage: page).first { link in
                      // A body link (not beamer's navigation bar at the very bottom) that jumps past the end of the talk.
                      guard link.rect.y < 0.9, case .goToPage(let target) = link.action else { return false }
                      return target > end
                  }.map { (page, $0) }
              }).first else { print("ROUNDTRIP: no appendix link in this deck"); return }
        _ = model.perform(.command(.goToPage(page)))
        try? await Task.sleep(for: .milliseconds(300))
        let view = presentation.currentSurface.view
        guard let window = view.window else { print("ROUNDTRIP FAIL: no window"); return }
        let slide = view.slideFrame
        let center = NSPoint(x: slide.minX + slide.width * (link.rect.x + link.rect.width / 2),
                             y: slide.minY + slide.height * (1 - (link.rect.y + link.rect.height / 2)))
        let windowPoint = view.convert(center, to: nil)
        let before = presentation.state.committedPage
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        try? await Task.sleep(for: .milliseconds(300))
        let afterClick = presentation.state.committedPage
        await press(keyCode: 51, character: "\u{7f}")   // Delete → back
        let afterBack = presentation.state.committedPage
        let ok = afterClick > end && afterBack == before
        print("ROUNDTRIP \(ok ? "OK" : "FAIL"): page \(before + 1) → click link → page \(afterClick + 1) → Delete → page \(afterBack + 1); history \(presentation.state.history), forward \(presentation.state.forwardHistory)")
    }

    /// Feedback round 2: a ⌘ tap toggles the card; Esc and a click outside close it; a row click runs its command;
    /// ⌘ plus a key never flashes it.
    private func shortcutsCheck(model: AppModel, presentation: Presentation) async {
        func hold(_ ms: Int) async {
            postFlags([.command])
            try? await Task.sleep(for: .milliseconds(ms))
            let duringHold = model.shortcutOverlayVisible
            postFlags([])
            try? await Task.sleep(for: .milliseconds(200))
            lastHoldShowedBeforeRelease = duringHold
        }
        await hold(100)
        let tapIgnored = !model.shortcutOverlayVisible
        await hold(750)
        let shownByHold = lastHoldShowedBeforeRelease && model.shortcutOverlayVisible   // and still up after release
        captureScreenshots(suffix: "-shortcuts")
        await hold(100)
        let hiddenByTap = !model.shortcutOverlayVisible
        await hold(750)
        await press(keyCode: 53, character: "\u{1b}")
        let hiddenByEsc = !model.shortcutOverlayVisible
        await hold(750)
        let pageBefore = presentation.state.committedPage
        await click(on: presentation.currentSurface.view, at: (0.02, 0.02), awaitSample: false)   // outside the card
        try? await Task.sleep(for: .milliseconds(250))
        let hiddenByClick = !model.shortcutOverlayVisible, stayed = presentation.state.committedPage == pageBefore
        postFlags([.command])
        try? await Task.sleep(for: .milliseconds(200))
        await press(keyCode: 38, character: "j", modifiers: [.command])   // ⌘J: bound to nothing; cancels the hold
        try? await Task.sleep(for: .milliseconds(500))
        postFlags([])
        try? await Task.sleep(for: .milliseconds(200))
        let noFlash = !model.shortcutOverlayVisible
        await hold(750)
        if let next = ShortcutReference.shortcut(named: "Next build") { model.run(next) }
        try? await Task.sleep(for: .milliseconds(250))
        let rowRan = presentation.state.committedPage == pageBefore + 1 && !model.shortcutOverlayVisible
        if rowRan { _ = model.perform(.command(.previous)) }
        let ok = tapIgnored && shownByHold && hiddenByTap && hiddenByEsc && hiddenByClick && stayed && noFlash && rowRan
        print("SHORTCUTS \(ok ? "OK" : "FAIL"): short tap ignored \(tapIgnored); 750 ms hold shows and release keeps it \(shownByHold); tap hides \(hiddenByTap); Esc hides \(hiddenByEsc); click outside hides \(hiddenByClick) without advancing \(stayed); ⌘J during a hold does not show it \(noFlash); clicking the Next build row advanced and closed it \(rowRan)")
    }

    private var lastHoldShowedBeforeRelease = false

    /// Posts a click at a normalised point of a slide surface through the real event path; waits for the latency
    /// sample it produces when `awaitSample` is set.
    private func click(on view: SlideSurfaceView, at normalized: (Double, Double), awaitSample: Bool = true) async {
        guard let window = view.window else { return }
        let slide = view.slideFrame
        let point = NSPoint(x: slide.minX + slide.width * normalized.0, y: slide.minY + slide.height * (1 - normalized.1))
        let location = view.convert(point, to: nil)
        func event(_ type: NSEvent.EventType, pressure: Float) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 9, clickCount: 1, pressure: pressure)!
        }
        if awaitSample {
            await withCheckedContinuation { continuation in
                pending = continuation
                NSApp.postEvent(event(.leftMouseDown, pressure: 1), atStart: false)
                NSApp.postEvent(event(.leftMouseUp, pressure: 0), atStart: false)
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    if let c = self.pending { self.pending = nil; c.resume() }
                }
            }
        } else {
            NSApp.postEvent(event(.leftMouseDown, pressure: 1), atStart: false)
            NSApp.postEvent(event(.leftMouseUp, pressure: 0), atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(120))
    }

    /// Posts a modifier change (⌘ down or up) the way the keyboard would.
    private func postFlags(_ flags: NSEvent.ModifierFlags) {
        guard let window = NSApp.windows.first(where: { $0 is PresenterWindow }),
              let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)
        else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private func press(keyCode: UInt16, character: String, shift: Bool = false, modifiers: NSEvent.ModifierFlags = []) async {
        guard let window = NSApp.windows.first(where: { $0 is PresenterWindow }) else { return }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? modifiers.union(.shift) : modifiers,
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, characters: character, charactersIgnoringModifiers: character,
                                     isARepeat: false, keyCode: keyCode)!
        await withCheckedContinuation { continuation in
            pending = continuation
            NSApp.postEvent(event, atStart: false)
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if let c = self.pending { self.pending = nil; c.resume() }
            }
        }
        try? await Task.sleep(for: .milliseconds(120))
    }

    /// `-screenshot DIR` renders the presenter and audience windows in-process (no screen-recording permission needed).
    private func captureScreenshots(suffix: String = "") {
        guard let index = CommandLine.arguments.firstIndex(of: "-screenshot"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let dir = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for window in NSApp.windows where window.isVisible {
            let kind = window is PresenterWindow ? "presenter"
                : window is WelcomeWindow ? "welcome"
                : window.title == "Settings" ? "settings"
                : String(describing: type(of: window)).contains("Popover") ? "popover" : "audience"
            let file = dir.appendingPathComponent(kind + suffix + ".png")
            guard let view = window.contentView, let layer = view.layer else { continue }
            let scale = window.backingScaleFactor
            let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
            guard width > 0, height > 0 else { continue }
            func context() -> CGContext? {
                guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                else { return nil }
                ctx.scaleBy(x: scale, y: scale)
                if view.isFlipped || layer.isGeometryFlipped {
                    ctx.translateBy(x: 0, y: view.bounds.height)
                    ctx.scaleBy(x: 1, y: -1)
                }
                return ctx
            }
            // An NSScrollView fills its background with clear using copy compositing, which is harmless on
            // screen (its own layer) but erases everything underneath in one flattened render. So each
            // top-level sublayer is rendered on its own and the results are composited source-over.
            guard let final = context() else { continue }
            let sublayers = layer.sublayers ?? []
            if sublayers.count > 1 {
                let wasHidden = sublayers.map(\.isHidden)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for index in sublayers.indices where !wasHidden[index] {
                    for (j, sub) in sublayers.enumerated() { sub.isHidden = j != index }
                    guard let pass = context() else { continue }
                    layer.render(in: pass)
                    if let image = pass.makeImage() {
                        final.saveGState()
                        final.concatenate(final.ctm.inverted())   // draw in raw pixel space, unflipped
                        final.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                        final.restoreGState()
                    }
                }
                for (sub, hidden) in zip(sublayers, wasHidden) { sub.isHidden = hidden }
                CATransaction.commit()
            } else {
                layer.render(in: final)
            }
            guard let image = final.makeImage() else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
        }
    }

    private func report(presentation: Presentation) {
        let name = url.lastPathComponent
        let summary = Latency.shared.summary(of: samples)
        let misses = samples.enumerated().filter { $0.element.contents != nil && $0.element.hit != true }.map { "#\($0.offset)" }
        print("SELFTEST \(name): pages \(presentation.document.pageCount), frames \(presentation.frameCount)")
        print(summary)
        print("misses: \(misses.isEmpty ? "none" : misses.joined(separator: " "))")
        if CommandLine.arguments.contains("-verbose") {
            let missedPages = Set(samples.filter { $0.hit != true }.compactMap(\.page))
            if !missedPages.isEmpty {
                let events = presentation.cache.store.recentEvents.filter { missedPages.contains($0.page) }
                print("cache trace for missed pages: " + events.map(\.description).joined(separator: ", "))
            }
            for (i, s) in samples.enumerated() {
                print(String(format: "  #%d p%@ recv %.2f applied %@ contents %@ %@ frame %@", i, s.page.map { String($0 + 1) } ?? "?", s.inputToReceived,
                             s.inputToApplied.map { String(format: "%.2f", $0) } ?? "–",
                             s.inputToContents.map { String(format: "%.2f", $0) } ?? "–",
                             s.hit == true ? "hit" : "MISS",
                             s.inputToFrame.map { String(format: "%.1f", $0) } ?? "–"))
            }
        }
        let periods = samples.compactMap(\.refreshPeriod)
        let period = periods.isEmpty ? 0 : periods.sorted()[periods.count / 2]
        let overVsync = samples.compactMap(\.inputToVsync).filter { $0 > period }.count
        let overTarget = samples.compactMap(\.inputToFrame).filter { $0 > period * 2 }.count
        print(String(format: "display refresh period %.2f ms; samples whose first vsync is later than one refresh after input: %d; whose frame target is later than two: %d", period, overVsync, overTarget))
        let timer = presentation.state.timer
        print(String(format: "timer: running %@, elapsed %.1f s (auto-started on the first advance)", timer.isRunning ? "yes" : "no", timer.elapsed(at: Date())))
        print("store: \(presentation.cache.store.count) images, \(presentation.cache.store.bytesUsed / 1_048_576) MB of \(presentation.cache.store.budgetBytes / 1_048_576) MB, \(presentation.cache.store.evictions) evictions")
    }
}
