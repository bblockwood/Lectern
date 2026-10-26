import Foundation
import os

/// Watches a deck and its companions for changes (SPEC §6.6): the directory (atomic replaces by latexmk and
/// editors show up as directory writes), the PDF itself (in-place writes), and a slow poll as a safety net for
/// volumes without file events. Reports a set of changed file names after a debounce, once sizes have stabilised.
public final class DeckWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (Set<String>) -> Void

    private struct Signature: Equatable {
        let size: Int
        let modified: Date
    }

    private let directory: URL
    private let watched: [String]
    private let queue = DispatchQueue(label: "dev.lectern.deckwatcher", qos: .utility)
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var signatures: [String: Signature?] = [:]
    private var running = false
    private let handler: Handler
    private let log = Logger(subsystem: "dev.lectern", category: "reload")

    public let debounce: TimeInterval
    public let settle: TimeInterval

    /// `deck` is the PDF; the sidecar, `.pdfpc` and `.pptx` with the same basename are watched with it.
    public init(deck: URL, debounce: TimeInterval = 0.3, settle: TimeInterval = 0.15, handler: @escaping Handler) {
        self.directory = deck.deletingLastPathComponent()
        let base = deck.deletingPathExtension().lastPathComponent
        self.watched = [deck.lastPathComponent, base + ".lectern.json", base + ".pdfpc", base + ".pptx"]
        self.debounce = debounce
        self.settle = settle
        self.handler = handler
    }

    deinit { stop() }

    public func start() {
        queue.sync {
            guard !running else { return }
            running = true
            for name in watched { signatures[name] = signature(of: name) }
            armDirectory()
            armFile()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in self?.scheduleCheck() }
            timer.resume()
            pollTimer = timer
        }
    }

    public func stop() {
        queue.sync {
            running = false
            directorySource?.cancel(); directorySource = nil
            fileSource?.cancel(); fileSource = nil
            pollTimer?.cancel(); pollTimer = nil
            pending?.cancel(); pending = nil
        }
    }

    // MARK: - Sources

    private func armDirectory() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { log.error("cannot watch \(self.directory.path, privacy: .public)"); return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.scheduleCheck() }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source
    }

    private func armFile() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(directory.appendingPathComponent(watched[0]).path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.scheduleCheck()
            if flags.contains(.rename) || flags.contains(.delete) {
                // The old inode is gone (atomic replace): follow the new file once it exists.
                self.queue.asyncAfter(deadline: .now() + self.debounce) { [weak self] in self?.armFile() }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    // MARK: - Debounce and settle

    private func scheduleCheck() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.check(attempt: 0) }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func check(attempt: Int) {
        guard running else { return }
        var changed: Set<String> = []
        var unstable = false
        for name in watched {
            let now = signature(of: name)
            if now != signatures[name] ?? nil {
                changed.insert(name)
                // Require the same size and mtime twice `settle` apart before reporting.
                if attempt == 0 || now != lastSeen[name] ?? nil { unstable = true }
                lastSeen[name] = now
            }
        }
        guard !changed.isEmpty else { return }
        if unstable && attempt < 40 {
            let item = DispatchWorkItem { [weak self] in self?.check(attempt: attempt + 1) }
            pending = item
            queue.asyncAfter(deadline: .now() + settle, execute: item)
            return
        }
        for name in changed { signatures[name] = lastSeen[name] ?? nil }
        lastSeen.removeAll()
        log.notice("changed: \(changed.sorted().joined(separator: ", "), privacy: .public)")
        handler(changed)
    }

    private var lastSeen: [String: Signature?] = [:]

    private func signature(of name: String) -> Signature? {
        let path = directory.appendingPathComponent(name).path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        return Signature(size: size, modified: modified)
    }
}
