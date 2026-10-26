import CoreGraphics
import Foundation
import os

/// The render cache actor (SPEC §3.3). One render in flight at a time, ordered by priority; results land in
/// an `ImageStore` whose synchronous lookup serves the warm path. Misses are logged with `os_log`.
public actor RenderCache {
    public enum Priority: Comparable, Sendable {
        /// A surface needs it now (a miss on the audience or presenter surface).
        case interactive
        /// Prefetch; lower number = nearer to the current page.
        case prefetch(distance: Int)

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            switch (lhs, rhs) {
            case (.interactive, .interactive): return false
            case (.interactive, .prefetch): return true
            case (.prefetch, .interactive): return false
            case (.prefetch(let a), .prefetch(let b)): return a < b
            }
        }
    }

    private struct Pending {
        var priority: Priority
        var continuations: [CheckedContinuation<CGImage?, Never>] = []
        let sequence: UInt64
    }

    private let source: PDFSource
    private let pages: [PageInfo]
    public nonisolated let store: ImageStore
    private var pending: [RenderRequest: Pending] = [:]
    private var inFlight: RenderRequest?
    private var worker: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var generation: UInt64 = 0

    private static let log = Logger(subsystem: "dev.lectern", category: "render")
    private static let signposter = OSSignposter(subsystem: "dev.lectern", category: "render")

    public init(document: PresentationDocument, budgetBytes: Int = 256 << 20) {
        self.source = document.source
        self.pages = document.pages
        self.store = ImageStore(budgetBytes: budgetBytes)
    }

    // MARK: - Lookup

    /// Synchronous warm-path lookup. Safe from any thread; never renders.
    public nonisolated func cachedImage(for request: RenderRequest) -> CGImage? {
        store.image(for: request)
    }

    /// Returns the cached image, or renders it (ahead of all prefetches) and returns it. Nil only if the
    /// page is out of range, the render failed, or the request was cancelled.
    public func image(for request: RenderRequest, priority: Priority = .interactive) async -> CGImage? {
        if let image = store.image(for: request) { return image }
        guard pages.indices.contains(request.pageIndex) else { return nil }
        if priority == .interactive {
            RenderCache.log.notice("cache miss: page \(request.pageIndex + 1) at \(request.pixelSize.width)x\(request.pixelSize.height)")
        }
        return await withCheckedContinuation { continuation in
            enqueue(request, priority: priority, continuation: continuation)
        }
    }

    /// Queues renders for later. Order in the array is the priority order (nearest first).
    public func prefetch(_ requests: [RenderRequest]) {
        for (distance, request) in requests.enumerated() where !store.contains(request) {
            guard pages.indices.contains(request.pageIndex) else { continue }
            enqueue(request, priority: .prefetch(distance: distance), continuation: nil)
        }
    }

    /// Drops queued prefetches that are not in `keeping`. Interactive requests and the render in flight are untouched.
    public func cancelPrefetches(keeping: Set<RenderRequest> = []) {
        for (request, entry) in pending where entry.continuations.isEmpty && !keeping.contains(request) && request != inFlight {
            pending[request] = nil
        }
    }

    /// Forgets everything (live reload, memory warning). In-flight work completes but is discarded.
    public func clear() {
        generation += 1
        for (_, entry) in pending { entry.continuations.forEach { $0.resume(returning: nil) } }
        pending.removeAll()
        store.removeAll()
    }

    public var pendingCount: Int { pending.count }

    /// Waits until the queue is empty. For tests and shutdown.
    public func waitUntilIdle() async {
        while let task = worker {
            await task.value
        }
    }

    // MARK: - Queue

    private func enqueue(_ request: RenderRequest, priority: Priority, continuation: CheckedContinuation<CGImage?, Never>?) {
        if var existing = pending[request] {
            if priority < existing.priority { existing.priority = priority }
            if let continuation { existing.continuations.append(continuation) }
            pending[request] = existing
        } else {
            sequence += 1
            var entry = Pending(priority: priority, sequence: sequence)
            if let continuation { entry.continuations.append(continuation) }
            pending[request] = entry
        }
        if worker == nil {
            worker = Task { await self.drain() }
        }
    }

    private func nextRequest() -> RenderRequest? {
        pending.min { a, b in
            if a.value.priority != b.value.priority { return a.value.priority < b.value.priority }
            return a.value.sequence < b.value.sequence
        }?.key
    }

    private func drain() async {
        while let request = nextRequest() {
            let startGeneration = generation
            inFlight = request
            let image = await render(request)
            inFlight = nil
            guard generation == startGeneration, let entry = pending.removeValue(forKey: request) else { continue }
            if let image { store.insert(image, for: request) }
            entry.continuations.forEach { $0.resume(returning: image) }
        }
        worker = nil
    }

    private func render(_ request: RenderRequest) async -> CGImage? {
        let source = self.source
        let pageInfo = pages[request.pageIndex]
        return await Task.detached(priority: .userInitiated) {
            let state = RenderCache.signposter.beginInterval("render", id: RenderCache.signposter.makeSignpostID(),
                                                              "page \(request.pageIndex + 1) \(request.pixelSize.width)x\(request.pixelSize.height)")
            defer { RenderCache.signposter.endInterval("render", state) }
            guard let page = source.page(at: request.pageIndex) else { return nil }
            return PageRenderer.render(page: page, pageSize: pageInfo.size, request: request)
        }.value
    }
}
