import CoreGraphics
import Observation
import PresenterCore

/// Thumbnails for the overview: the last page of each frame (SPEC §4.1) from a small separate cache.
@MainActor
@Observable
final class ThumbnailProvider {
    static let bounds = PixelSize(width: 640, height: 360)

    private let document: PresentationDocument
    @ObservationIgnored private let cache: RenderCache
    @ObservationIgnored private var inFlight: Set<Int> = []
    private(set) var images: [Int: CGImage] = [:]

    init(document: PresentationDocument) {
        self.document = document
        cache = RenderCache(document: document, budgetBytes: 96 << 20)
    }

    private func request(forFrame frame: Int) -> RenderRequest {
        let page = document.frames.frames[frame].lastPage
        return SurfaceSpec(role: .preview, bounds: ThumbnailProvider.bounds).request(for: document.pages[page])
    }

    /// Returns the thumbnail if ready; otherwise starts rendering it and returns nil. Views re-render when `images` changes.
    func image(forFrame frame: Int) -> CGImage? {
        guard document.frames.frames.indices.contains(frame) else { return nil }
        if let image = images[frame] { return image }
        let request = request(forFrame: frame)
        if let cached = cache.cachedImage(for: request) {
            images[frame] = cached
            return cached
        }
        guard !inFlight.contains(frame) else { return nil }
        inFlight.insert(frame)
        let cache = self.cache
        Task { [weak self] in
            let image = await cache.image(for: request, priority: .prefetch(distance: 0))
            guard let self else { return }
            self.inFlight.remove(frame)
            if let image { self.images[frame] = image }
        }
        return nil
    }

    /// Drops decoded references so the cache budget alone bounds memory; the overview re-requests on demand.
    func releaseAll() {
        images.removeAll()
        cache.store.setFocusPages([])
    }

    func setFocus(frame: Int) {
        cache.store.setFocusPages([document.frames.frames[min(max(frame, 0), document.frames.frameCount - 1)].lastPage])
    }
}
