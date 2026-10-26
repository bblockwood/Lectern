import CoreGraphics
import Foundation
import os

/// Bitmap store with a byte budget and a lock-protected synchronous lookup, so a warm-cache advance never
/// needs an `await`. Eviction prefers pages far from the focus pages (committed, presenter, back target),
/// breaking ties by least recent use; pinned entries (the pages on screen) are never evicted.
public final class ImageStore: @unchecked Sendable {
    private struct Entry {
        let image: CGImage
        let bytes: Int
        var lastUsed: UInt64
    }

    /// Debug trace of cache activity, for the self-test and bug reports.
    public struct Event: Sendable, CustomStringConvertible {
        public enum Kind: String, Sendable { case hit, miss, insert, evict }
        public let kind: Kind
        public let page: Int
        public let width: Int
        public let tick: UInt64
        public var description: String { "\(kind.rawValue) p\(page + 1)@\(width) t\(tick)" }
    }

    private let lock = NSLock()
    private var entries: [RenderRequest: Entry] = [:]
    private var pinned: Set<RenderRequest> = []
    private var focusPages: [Int] = []
    private var tick: UInt64 = 0
    private var totalBytes = 0
    private var evictionCount = 0
    private var trace: [Event] = []
    private let traceLimit = 600
    public let budgetBytes: Int

    public init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    public func image(for request: RenderRequest) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        tick += 1
        guard var entry = entries[request] else {
            record(.miss, request)
            return nil
        }
        entry.lastUsed = tick
        entries[request] = entry
        record(.hit, request)
        return entry.image
    }

    public func contains(_ request: RenderRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return entries[request] != nil
    }

    public func insert(_ image: CGImage, for request: RenderRequest) {
        lock.lock(); defer { lock.unlock() }
        let bytes = image.bytesPerRow * image.height
        if let old = entries[request] { totalBytes -= old.bytes }
        tick += 1
        entries[request] = Entry(image: image, bytes: bytes, lastUsed: tick)
        totalBytes += bytes
        record(.insert, request)
        evictIfNeeded()
    }

    /// Replaces the pinned set. Pinned entries survive eviction; everything else is fair game.
    public func pin(_ requests: Set<RenderRequest>) {
        lock.lock(); defer { lock.unlock() }
        pinned = requests
        evictIfNeeded()
    }

    /// Pages that eviction should keep closest: the committed page, the presenter page and the back target.
    public func setFocusPages(_ pages: [Int]) {
        lock.lock(); defer { lock.unlock() }
        focusPages = pages
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
        totalBytes = 0
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    public var bytesUsed: Int {
        lock.lock(); defer { lock.unlock() }
        return totalBytes
    }

    /// Number of entries evicted for budget so far.
    public var evictions: Int {
        lock.lock(); defer { lock.unlock() }
        return evictionCount
    }

    public var recentEvents: [Event] {
        lock.lock(); defer { lock.unlock() }
        return trace
    }

    private func record(_ kind: Event.Kind, _ request: RenderRequest) {
        trace.append(Event(kind: kind, page: request.pageIndex, width: request.pixelSize.width, tick: tick))
        if trace.count > traceLimit { trace.removeFirst(trace.count - traceLimit) }
    }

    private func distance(_ request: RenderRequest) -> Int {
        focusPages.map { abs($0 - request.pageIndex) }.min() ?? 0
    }

    private func evictIfNeeded() {
        while totalBytes > budgetBytes {
            // The victim is the farthest unpinned entry from any focus page; among equals, the least recently used.
            let victim = entries.lazy.filter { !self.pinned.contains($0.key) }.max { a, b in
                let da = self.distance(a.key), db = self.distance(b.key)
                if da != db { return da < db }
                return a.value.lastUsed > b.value.lastUsed
            }
            guard let victim else { return }
            totalBytes -= victim.value.bytes
            entries[victim.key] = nil
            evictionCount += 1
            record(.evict, victim.key)
        }
    }
}
