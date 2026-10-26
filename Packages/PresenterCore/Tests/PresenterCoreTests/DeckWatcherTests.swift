import Foundation
import Testing
@testable import PresenterCore

@Suite(.serialized) struct LiveReloadWatching {
    private func makeDeck() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lectern-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let deck = dir.appendingPathComponent("talk.pdf")
        try FileManager.default.copyItem(at: Fixtures.url("overlays.pdf"), to: deck)
        return deck
    }

    /// Collects watcher reports so tests can await them.
    private final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var reports: [Set<String>] = []
        func add(_ s: Set<String>) { lock.lock(); reports.append(s); lock.unlock() }
        var all: [Set<String>] { lock.lock(); defer { lock.unlock() }; return reports }
        /// Waits for a report after the first `skip` ones that contains `name`.
        func waitForReport(containing name: String, after skip: Int = 0, timeout: TimeInterval = 5) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if all.dropFirst(skip).contains(where: { $0.contains(name) }) { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }
    }

    @Test func atomicReplaceInPlaceWriteAndCompanionAreReported() async throws {
        let deck = try makeDeck()
        defer { try? FileManager.default.removeItem(at: deck.deletingLastPathComponent()) }
        let inbox = Inbox()
        let watcher = DeckWatcher(deck: deck, debounce: 0.1, settle: 0.1) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))

        // 1. latexmk-style atomic replace: write a temp file, then rename over the deck.
        let temp = deck.deletingLastPathComponent().appendingPathComponent("talk.pdf.tmp")
        try FileManager.default.copyItem(at: Fixtures.url("basic-169.pdf"), to: temp)
        _ = try FileManager.default.replaceItemAt(deck, withItemAt: temp)
        #expect(await inbox.waitForReport(containing: "talk.pdf"))
        let after1 = inbox.all.count

        // 2. In-place write (cp onto the file): the directory does not change, the file does.
        let handle = try FileHandle(forWritingTo: deck)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x20, count: 2048))
        try handle.close()
        #expect(await inbox.waitForReport(containing: "talk.pdf", after: after1))
        let after2 = inbox.all.count

        // 3. A companion file appears.
        try Data("{\"pdfpcFormat\": 2}".utf8).write(to: deck.deletingLastPathComponent().appendingPathComponent("talk.pdfpc"))
        #expect(await inbox.waitForReport(containing: "talk.pdfpc", after: after2))
        #expect(!inbox.all.flatMap { $0 }.contains("talk.pdf.tmp"), "unrelated files are not reported")
    }

    @Test func slowWritesAreReportedOnceWhenSettled() async throws {
        let deck = try makeDeck()
        defer { try? FileManager.default.removeItem(at: deck.deletingLastPathComponent()) }
        let inbox = Inbox()
        let watcher = DeckWatcher(deck: deck, debounce: 0.1, settle: 0.1) { inbox.add($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))
        // Grow the file in several steps 60 ms apart: a single report, after the last write.
        let handle = try FileHandle(forWritingTo: deck)
        try handle.seekToEnd()
        for _ in 0..<5 {
            try handle.write(contentsOf: Data(repeating: 0x20, count: 512))
            try await Task.sleep(for: .milliseconds(60))
        }
        try handle.close()
        #expect(await inbox.waitForReport(containing: "talk.pdf"))
        try await Task.sleep(for: .milliseconds(600))
        #expect(inbox.all.count == 1, "got \(inbox.all)")
    }
}
