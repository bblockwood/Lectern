import AppKit
import PresenterCore

/// Decides what one `SlideSurfaceView` shows. Warm cache: the image is swapped in synchronously, in the same
/// run-loop pass as the input. Miss: the previous image stays up until the new render is complete (SPEC §3.3).
@MainActor
final class SurfaceController {
    let role: SurfaceSpec.Role
    let view: SlideSurfaceView
    var crop: CropRect = .full
    var onGeometryChange: (() -> Void)?

    private let document: PresentationDocument
    private let cache: RenderCache
    private var desiredPage: Int?
    private var desiredSolid: CGColor?
    private var shown: RenderRequest?
    private var fetch: Task<Void, Never>?
    private var fetching: RenderRequest?

    init(role: SurfaceSpec.Role, document: PresentationDocument, cache: RenderCache) {
        self.role = role
        self.document = document
        self.cache = cache
        self.view = SlideSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        view.onGeometryChange = { [weak self] in self?.geometryChanged() }
        view.onFrame = { [weak self] vsync, target in
            guard let self else { return }
            Latency.shared.framePresented(role: self.role, vsync: vsync, target: target)
        }
    }

    /// Render parameters for this surface right now, nil until it is laid out in a window.
    var spec: SurfaceSpec? {
        guard let bounds = view.pixelBounds else { return nil }
        return SurfaceSpec(role: role, bounds: bounds, colorSpace: view.colorSpaceID, crop: crop)
    }

    func show(page: Int?) {
        desiredSolid = nil
        desiredPage = page
        apply(debounce: false)
    }

    func show(solid color: CGColor) {
        fetch?.cancel()
        desiredSolid = color
        desiredPage = nil
        shown = nil
        view.showSolid(color)
        fetching = nil
        view.links = []
        Latency.shared.contentsShown(role: role, hit: true, page: nil)
        if Latency.shared.measuresFrames { view.requestFrameCallback() }
    }

    private func geometryChanged() {
        apply(debounce: true)
        onGeometryChange?()
    }

    private func apply(debounce: Bool) {
        guard desiredSolid == nil else { return }
        guard let page = desiredPage, document.pages.indices.contains(page), let spec else {
            if desiredPage == nil { view.showNothing() }
            return
        }
        let request = spec.request(for: document.pages[page])
        if request == shown { return }
        if request == fetching { return }   // already on its way; a layout pass must not restart it

        if let image = cache.cachedImage(for: request) {
            fetch?.cancel()
            fetching = nil
            present(image, for: request, hit: true)
            return
        }

        // Miss: keep the current image on screen, fetch, and show only if the page is still wanted.
        Latency.shared.contentsMissed(role: role, page: page)
        fetch?.cancel()
        fetching = request
        let cache = self.cache
        fetch = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(60)) }
            guard !Task.isCancelled else { return }
            guard let image = await cache.image(for: request) else { return }
            guard !Task.isCancelled, let self, self.desiredSolid == nil, self.desiredPage == page,
                  self.spec?.request(for: self.document.pages[page]) == request else { return }
            self.fetching = nil
            self.present(image, for: request, hit: false)
        }
    }

    private func present(_ image: CGImage, for request: RenderRequest, hit: Bool) {
        view.show(image: image)
        view.links = request.crop.isFull ? document.links(onPage: request.pageIndex) : []
        shown = request
        Latency.shared.contentsShown(role: role, hit: hit, page: request.pageIndex)
        if Latency.shared.measuresFrames { view.requestFrameCallback() }
    }
}
