import Foundation
import PresenterProtocol

/// Pure implementation of the §3.2 command semantics. No side effects; fully testable.
public struct SessionReducer: Sendable {
    public let frames: FrameIndex
    public let links: [[PageLink]]

    public init(frames: FrameIndex, links: [[PageLink]] = []) {
        self.frames = frames
        self.links = links
    }

    public init(document: PresentationDocument) {
        self.init(frames: document.frames, links: document.links)
    }

    public var pageCount: Int { frames.pageCount }

    public func apply(_ command: Command, to state: inout SessionState, now: Date) {
        switch command {
        case .next:
            autoStartTimer(&state, now: now)
            step(&state, by: 1)
        case .previous:
            step(&state, by: -1)
        case .nextFrame:
            autoStartTimer(&state, now: now)
            let current = state.presenterPage
            let target = frames.nextFrameFirstPage(after: current) ?? (pageCount - 1)
            setStepTarget(&state, target)
        case .previousFrame:
            let current = state.presenterPage
            let target = frames.previousFrameLastPage(before: current) ?? 0
            setStepTarget(&state, target)
        case .goToPage(let page):
            jump(&state, to: page)
        case .goToFrameLabel(let label):
            if let frame = frames.frame(withLabel: label) { jump(&state, to: frame.firstPage) }
        case .followLink(let id):
            follow(id, &state, now: now)
        case .back:
            goBack(&state)

        case .beginBrowse:
            if state.browsePage == nil { state.browsePage = state.committedPage }
        case .browseTo(let page):
            state.browsePage = clamp(page)
        case .commitBrowse:
            guard let page = state.browsePage else { return }
            state.browsePage = nil
            if page != state.committedPage {
                state.history.append(state.committedPage)
                state.forwardHistory = []
                state.committedPage = page
                clearPageScopedState(&state)
            }
        case .cancelBrowse:
            state.browsePage = nil

        case .setAudienceMode(let mode):
            state.audienceMode = mode

        case .pointerMove(let point):
            state.pointer = PointerState(position: point, updatedAt: now)
        case .pointerHide:
            state.pointer = nil

        case .inkBegin(let point, let mode):
            state.ink.active = InkStroke(points: [point], mode: mode, startedAt: now)
        case .inkAppend(let point):
            state.ink.active?.points.append(point)
        case .inkEnd:
            if let stroke = state.ink.active { state.ink.strokes.append(stroke) }
            state.ink.active = nil
        case .clearInk:
            state.ink = InkState()
        case .insertWhiteboard:
            break // M3/M5.

        case .timerStart:
            state.timer.start(at: now)
        case .timerPause:
            state.timer.pause(at: now)
        case .timerReset:
            state.timer.reset()
        }
    }

    // MARK: - Links and history

    private func follow(_ id: LinkID, _ state: inout SessionState, now: Date) {
        guard links.indices.contains(id.page), links[id.page].indices.contains(id.index) else { return }
        switch links[id.page][id.index].action {
        case .goToPage(let page):
            jump(&state, to: page)
        case .named(let action):
            switch action {
            case .nextPage: step(&state, by: 1)
            case .previousPage: step(&state, by: -1)
            case .firstPage: jump(&state, to: 0)
            case .lastPage: jump(&state, to: pageCount - 1)
            case .goBack: goBack(&state)
            case .goForward: goForward(&state)
            case .goToPage, .find, .other: break
            }
        case .uri, .launch, .unsupported:
            break   // URIs are the app's business (confirmation, settings); launch is M9.
        }
    }

    private func goBack(_ state: inout SessionState) {
        guard let previous = state.history.popLast() else { return }
        state.forwardHistory.append(state.committedPage)
        state.browsePage = nil
        state.committedPage = clamp(previous)
        clearPageScopedState(&state)
    }

    private func goForward(_ state: inout SessionState) {
        guard let next = state.forwardHistory.popLast() else { return }
        state.history.append(state.committedPage)
        state.browsePage = nil
        state.committedPage = clamp(next)
        clearPageScopedState(&state)
    }

    // MARK: - Helpers

    /// Steps move the browse page while browsing, otherwise the committed page. Never push history.
    private func step(_ state: inout SessionState, by delta: Int) {
        setStepTarget(&state, state.presenterPage + delta)
    }

    private func setStepTarget(_ state: inout SessionState, _ page: Int) {
        let target = clamp(page)
        if state.browsePage != nil {
            state.browsePage = target
        } else if target != state.committedPage {
            state.committedPage = target
            clearPageScopedState(&state)
        }
    }

    /// Any jump that is not a step pushes the current page onto history.
    private func jump(_ state: inout SessionState, to page: Int) {
        let target = clamp(page)
        state.browsePage = nil
        guard target != state.committedPage else { return }
        state.history.append(state.committedPage)
        state.forwardHistory = []
        state.committedPage = target
        clearPageScopedState(&state)
    }

    private func clearPageScopedState(_ state: inout SessionState) {
        // Ephemeral ink belongs to the page it was drawn on. Persistent ink per page arrives with the sidecar in M3.
        state.ink = InkState()
    }

    private func autoStartTimer(_ state: inout SessionState, now: Date) {
        if !state.timer.hasStarted { state.timer.start(at: now) }
    }

    private func clamp(_ page: Int) -> Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }
}
