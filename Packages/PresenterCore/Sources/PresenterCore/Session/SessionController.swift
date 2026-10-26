import Foundation
import PresenterProtocol

/// Owns the one `SessionState` for a loaded deck and applies every `Command` to it (SPEC §3.2).
/// Views observe `onChange`; they never mutate state themselves.
@MainActor
public final class SessionController {
    public private(set) var document: PresentationDocument
    public private(set) var state: SessionState
    private var reducer: SessionReducer
    /// Preferences from the app's settings; read on every command so changes apply immediately.
    public var navigationOptions = NavigationOptions()

    /// Called synchronously after every change, with the old and new state, on the main actor.
    public var onChange: ((SessionState, SessionState) -> Void)?

    public init(document: PresentationDocument, initialState: SessionState = SessionState()) {
        self.document = document
        self.state = initialState
        self.reducer = SessionReducer(document: document)
    }

    public func apply(_ command: Command, now: Date = Date()) {
        let old = state
        var new = state
        reducer.apply(command, to: &new, now: now, options: navigationOptions)
        commit(old: old, new: new)
    }

    // Settings that are not commands (they come from UI, sidecar or metadata rather than from input devices).

    public func setTimerTarget(_ target: TimeInterval?) {
        var new = state
        new.timer.target = target
        commit(old: state, new: new)
    }

    /// Drops ephemeral strokes older than `maxAge` (SPEC §8). Returns true when something was removed.
    @discardableResult
    public func pruneEphemeralInk(now: Date, maxAge: TimeInterval) -> Bool {
        var new = state
        new.ink.strokes.removeAll { $0.mode == .ephemeral && now.timeIntervalSince($0.startedAt) > maxAge }
        guard new != state else { return false }
        commit(old: state, new: new)
        return true
    }

    public func setDisplayConfig(_ config: DisplayConfig) {
        var new = state
        new.displayConfig = config
        commit(old: state, new: new)
    }

    /// Live reload (M3): swap the document and restore the position by (frame label, build index),
    /// falling back to the nearest page index.
    public func replaceDocument(_ newDocument: PresentationDocument) {
        let oldFrame = document.frames.frame(containing: state.committedPage)
        let build = document.frames.buildIndex(of: state.committedPage)
        document = newDocument
        reducer = SessionReducer(document: newDocument)
        var new = state
        new.committedPage = SessionController.restoredPage(label: oldFrame.label, build: build,
                                                          oldPage: state.committedPage, in: newDocument.frames)
        new.browsePage = nil
        new.history = new.history.map { min($0, newDocument.pageCount - 1) }
        commit(old: state, new: new)
    }

    static func restoredPage(label: String, build: Int, oldPage: Int, in frames: FrameIndex) -> Int {
        if let frame = frames.frame(withLabel: label) {
            return frame.firstPage + min(build, frame.buildCount - 1)
        }
        return min(max(oldPage, 0), frames.pageCount - 1)
    }

    private func commit(old: SessionState, new: SessionState) {
        guard new != old else { return }
        state = new
        onChange?(old, new)
    }
}
