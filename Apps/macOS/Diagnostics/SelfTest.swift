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
        model.open(url: url)
        guard let presentation = model.presentation else {
            print("SELFTEST FAIL: could not open \(url.path)")
            exit(2)
        }
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
        for _ in 0..<forward { await press(keyCode: 124, character: "\u{F703}") }   // → next
        captureScreenshots()
        if CommandLine.arguments.contains("-shortcuts"), let model = (NSApp.delegate as? AppDelegate)?.model {
            // Hold ⌘ through the real path: flagsChanged → monitor → 350 ms delay → overlay; release hides it.
            postFlags([.command])
            try? await Task.sleep(for: .milliseconds(650))
            let shown = model.shortcutOverlayVisible
            captureScreenshots(suffix: "-shortcuts")
            postFlags([])
            try? await Task.sleep(for: .milliseconds(200))
            let hidden = !model.shortcutOverlayVisible
            print("SHORTCUTS overlay \(shown ? "shown after holding ⌘" : "NOT shown after holding ⌘"); \(hidden ? "hidden on release" : "NOT hidden on release")")
        }
        if CommandLine.arguments.contains("-closebutton"), let model = (NSApp.delegate as? AppDelegate)?.model,
           let window = NSApp.windows.first(where: { $0 is PresenterWindow }) {
            // The red button: performClose asks windowShouldClose, which closes the deck and keeps the window.
            window.performClose(nil)
            try? await Task.sleep(for: .milliseconds(400))
            let closed = model.presentation == nil, stillOpen = window.isVisible
            print("CLOSEBUTTON \(closed ? "deck closed" : "deck NOT closed"); window \(stillOpen ? "still open on the welcome screen" : "GONE")")
            captureScreenshots(suffix: "-welcome")
            model.open(url: url)
            try? await Task.sleep(for: .milliseconds(400))
        }
        if CommandLine.arguments.contains("-settings"), let model = (NSApp.delegate as? AppDelegate)?.model {
            model.showSettings()
            try? await Task.sleep(for: .milliseconds(500))
            captureScreenshots(suffix: "-settings")
            NSApp.windows.first(where: { $0.title == "Settings" })?.close()
        }
        if CommandLine.arguments.contains("-overview") {
            await press(keyCode: 48, character: "\t")                               // Tab: overview
            await press(keyCode: 124, character: "\u{F703}")                        // → browse one frame on
            try? await Task.sleep(for: .seconds(1.5))                                 // thumbnails
            captureScreenshots(suffix: "-overview")
            await press(keyCode: 53, character: "\u{1b}")                           // Esc: cancel + close
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
        print("INK fade: strokes after 3.5 s = \(presentation.state.ink.strokes.count) (expected 0)")
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

    /// Posts a modifier change (⌘ down or up) the way the keyboard would.
    private func postFlags(_ flags: NSEvent.ModifierFlags) {
        guard let window = NSApp.windows.first(where: { $0 is PresenterWindow }),
              let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)
        else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private func press(keyCode: UInt16, character: String, shift: Bool = false) async {
        guard let window = NSApp.windows.first(where: { $0 is PresenterWindow }) else { return }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
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
            guard let view = window.contentView, let layer = view.layer else { continue }
            let scale = window.backingScaleFactor
            let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
            guard width > 0, height > 0,
                  let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { continue }
            ctx.scaleBy(x: scale, y: scale)
            if view.isFlipped || layer.isGeometryFlipped {
                ctx.translateBy(x: 0, y: view.bounds.height)
                ctx.scaleBy(x: 1, y: -1)
            }
            layer.render(in: ctx)
            guard let image = ctx.makeImage() else { continue }
            let kind = window is PresenterWindow ? "presenter" : (window.title == "Settings" ? "settings" : "audience")
            let name = kind + suffix + ".png"
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
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
