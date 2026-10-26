import AppKit
import Observation
import PresenterCore
import PresenterProtocol

/// One open deck: document, session controller, render cache and the three slide surfaces.
/// Applies commands, refreshes the surfaces synchronously, and keeps the prefetch plan current.
@MainActor
@Observable
final class Presentation {
    let document: PresentationDocument
    @ObservationIgnored let controller: SessionController
    @ObservationIgnored let cache: RenderCache
    @ObservationIgnored let audienceSurface: SurfaceController
    @ObservationIgnored let currentSurface: SurfaceController
    @ObservationIgnored let previewSurface: SurfaceController
    @ObservationIgnored private var planTask: Task<Void, Never>?

    /// Mirror of the controller's state for SwiftUI observation.
    private(set) var state: SessionState

    init(document: PresentationDocument, surroundColor: CGColor) {
        self.document = document
        controller = SessionController(document: document)
        // Macs have memory to spare; §3.3 asks for ±2 pages, next frame and back target on three surfaces.
        let budgetMB = CommandLine.arguments.first(where: { $0.hasPrefix("-cacheMB=") }).flatMap { Int($0.dropFirst(9)) } ?? 768
        cache = RenderCache(document: document, budgetBytes: budgetMB << 20)
        state = controller.state
        audienceSurface = SurfaceController(role: .audience, document: document, cache: cache)
        currentSurface = SurfaceController(role: .presenterCurrent, document: document, cache: cache)
        previewSurface = SurfaceController(role: .preview, document: document, cache: cache)
        for surface in [audienceSurface, currentSurface, previewSurface] {
            surface.view.surroundColor = surroundColor
            surface.onGeometryChange = { [weak self] in self?.replan() }
        }
        previewSurface.view.surroundColor = CGColor(gray: 0.08, alpha: 1)
        controller.onChange = { [weak self] old, new in self?.stateChanged(from: old, to: new) }
        refreshSurfaces()
        replan()
    }

    func apply(_ command: Command) {
        controller.apply(command)
        Latency.shared.commandApplied()
    }

    func setPresenting(_ presenting: Bool, audienceDisplay: String?, presenterDisplay: String?) {
        var config = DisplayConfig()
        config.isPresenting = presenting
        config.audienceDisplayID = audienceDisplay
        config.presenterDisplayID = presenterDisplay
        controller.setDisplayConfig(config)
    }

    /// Re-reads controller state after a non-command change (timer target etc.).
    func refreshState() {
        state = controller.state
    }

    // MARK: - Derived facts for the status bar

    var currentFrame: Frame { document.frames.frame(containing: state.presenterPage) }
    var currentBuild: Int { document.frames.buildIndex(of: state.presenterPage) }
    var frameCount: Int { document.frames.frameCount }
    var nextPage: Int? {
        let next = state.presenterPage + 1
        return next < document.pageCount ? next : nil
    }

    // MARK: - Surfaces and prefetch

    private func stateChanged(from old: SessionState, to new: SessionState) {
        state = new
        refreshSurfaces()
        if old.committedPage != new.committedPage || old.browsePage != new.browsePage
            || old.audienceMode != new.audienceMode || old.history != new.history {
            replan()
        }
    }

    private func refreshSurfaces() {
        // Audience first: it is the one that must land in this run-loop pass.
        switch state.audienceMode {
        case .black: audienceSurface.show(solid: CGColor(gray: 0, alpha: 1))
        case .white: audienceSurface.show(solid: CGColor(gray: 1, alpha: 1))
        case .live, .frozen: audienceSurface.show(page: state.audiencePage)
        }
        currentSurface.show(page: state.presenterPage)
        if let next = nextPage {
            previewSurface.show(page: next)
        } else {
            previewSurface.show(solid: CGColor(gray: 0.15, alpha: 1))
        }
    }

    private func replan() {
        let specs = [audienceSurface, currentSurface, previewSurface].compactMap(\.spec)
        guard !specs.isEmpty else { return }
        let plan = PrefetchPlanner.plan(state: state, document: document, surfaces: specs)
        // The focus request of every surface is pinned so eviction can never take the committed page,
        // and eviction prefers pages far from where the talk is.
        cache.store.pin(Set(plan.prefix(specs.count)))
        cache.store.setFocusPages([state.committedPage, state.presenterPage, state.history.last].compactMap { $0 })
        planTask?.cancel()
        let cache = self.cache
        planTask = Task {
            await cache.cancelPrefetches(keeping: Set(plan))
            guard !Task.isCancelled else { return }
            await cache.prefetch(plan)
        }
    }
}
