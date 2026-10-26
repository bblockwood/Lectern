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
        for _ in 0..<forward { await press(keyCode: 123, character: "\u{F702}") }   // ← previous
        // A few frame jumps and a back, which may legitimately miss.
        await press(keyCode: 124, character: "\u{F703}", shift: true)
        await press(keyCode: 124, character: "\u{F703}", shift: true)
        await press(keyCode: 123, character: "\u{F702}", shift: true)
        report(presentation: presentation)
        exit(0)
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

    private func report(presentation: Presentation) {
        let name = url.lastPathComponent
        let summary = Latency.shared.summary(of: samples)
        let misses = samples.enumerated().filter { $0.element.hit != true }.map { "#\($0.offset)" }
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
        let over = samples.compactMap(\.inputToFrame).filter { $0 > 16.7 }.count
        print("samples over one 60 Hz frame (16.7 ms) to frame target: \(over)")
        print("store: \(presentation.cache.store.count) images, \(presentation.cache.store.bytesUsed / 1_048_576) MB of \(presentation.cache.store.budgetBytes / 1_048_576) MB, \(presentation.cache.store.evictions) evictions")
    }
}
