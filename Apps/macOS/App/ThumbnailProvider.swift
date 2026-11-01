import CoreGraphics
import Observation
import PresenterCore

/// Thumbnails for the overview from a small separate cache (SPEC §3.3), by page: Frames mode shows the last page of
/// each frame (SPEC §4.1) except the current frame's build on screen; Builds mode shows every page (feedback round 7).
@MainActor
@Observable
final class ThumbnailProvider {
    static let bounds = PixelSize(width: 640, height: 360)

    private let document: PresentationDocument
    @ObservationIgnored private let cache: RenderCache
    @ObservationIgnored private var inFlight: Set<Int> = []
    private(set) var images: [Int: CGImage] = [:]
    /// Slide half for second-screen decks; changing it drops the decoded thumbnails.
    var crop: CropRect = .full {
        didSet { if crop != oldValue { images.removeAll(); inFlight.removeAll() } }
    }

    init(document: PresentationDocument) {
        self.document = document
        cache = RenderCache(document: document, budgetBytes: 96 << 20)
    }

    private func request(forPage page: Int) -> RenderRequest {
        SurfaceSpec(role: .preview, bounds: ThumbnailProvider.bounds, crop: crop).request(for: document.pages[page])
    }

    /// Returns the thumbnail if ready; otherwise starts rendering it and returns nil. Views re-render when `images` changes.
    func image(forPage page: Int) -> CGImage? {
        guard document.pages.indices.contains(page) else { return nil }
        if let image = images[page] { return image }
        let request = request(forPage: page)
        if let cached = cache.cachedImage(for: request) {
            images[page] = cached
            return cached
        }
        guard !inFlight.contains(page) else { return nil }
        inFlight.insert(page)
        let cache = self.cache
        Task { [weak self] in
            let image = await cache.image(for: request, priority: .prefetch(distance: 0))
            guard let self else { return }
            self.inFlight.remove(page)
            if let image { self.images[page] = image }
        }
        return nil
    }

    /// Drops decoded references so the cache budget alone bounds memory; the overview re-requests on demand.
    func releaseAll() {
        images.removeAll()
        cache.store.setFocusPages([])
    }

    /// Eviction keeps the pages near the one on screen.
    func setFocus(page: Int) {
        cache.store.setFocusPages([min(max(page, 0), document.pageCount - 1)])
    }
}
