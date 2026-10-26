import CoreGraphics
import Foundation
import os

/// LRU bitmap store with a byte budget and a lock-protected synchronous lookup, so a warm-cache
/// advance never needs an `await`. Pinned entries (the committed page) are never evicted.
public final class ImageStore: @unchecked Sendable {
    private struct Entry {
        let image: CGImage
        let bytes: Int
        var lastUsed: UInt64
    }

    private let lock = NSLock()
    private var entries: [RenderRequest: Entry] = [:]
    private var pinned: Set<RenderRequest> = []
    private var tick: UInt64 = 0
    private var totalBytes = 0
    public let budgetBytes: Int

    public init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    public func image(for request: RenderRequest) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[request] else { return nil }
        tick += 1
        entry.lastUsed = tick
        entries[request] = entry
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
        evictIfNeeded()
    }

    /// Replaces the pinned set. Pinned entries survive eviction; everything else is fair game.
    public func pin(_ requests: Set<RenderRequest>) {
        lock.lock(); defer { lock.unlock() }
        pinned = requests
        evictIfNeeded()
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

    private func evictIfNeeded() {
        while totalBytes > budgetBytes {
            guard let victim = entries.filter({ !pinned.contains($0.key) }).min(by: { $0.value.lastUsed < $1.value.lastUsed }) else { return }
            totalBytes -= victim.value.bytes
            entries[victim.key] = nil
        }
    }
}
