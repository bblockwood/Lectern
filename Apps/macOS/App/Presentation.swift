import AppKit
import Observation
import PresenterCore
import PresenterProtocol
import os

/// One open deck: document, session controller, render caches, the slide surfaces, notes, sidecar,
/// live reload, pointer and ink. Applies commands, refreshes the surfaces synchronously, keeps the
/// prefetch plan current.
@MainActor
@Observable
final class Presentation {
    private(set) var document: PresentationDocument
    @ObservationIgnored let controller: SessionController
    @ObservationIgnored private(set) var cache: RenderCache
    @ObservationIgnored let audienceSurface: SurfaceController
    @ObservationIgnored let currentSurface: SurfaceController
    @ObservationIgnored let previewSurface: SurfaceController
    /// Shows the notes half of second-screen decks (SPEC §5.1.4).
    @ObservationIgnored let notesSurface: SurfaceController
    /// Separate low-res, memory-bounded cache for the overview (SPEC §3.3).
    @ObservationIgnored private(set) var thumbnails: ThumbnailProvider
    @ObservationIgnored private(set) var searcher: TextSearcher
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: DeckWatcher?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pointerHideTask: Task<Void, Never>?
    @ObservationIgnored private var inkPruneTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "dev.lectern", category: "presentation")

    /// Mirror of the controller's state for SwiftUI observation.
    private(set) var state: SessionState
    private(set) var sidecar: SidecarDocument
    private(set) var notes: NotesBundle
    /// The split in force (from the sidecar once confirmed; `.none` before that).
    private(set) var notesSplit: NotesSplit = .none
    /// A detected layout awaiting the user's one-time answer (SPEC §5.1.4).
    private(set) var pendingSplitQuestion: NotesSplit?
    private(set) var pointerMode = false
    private(set) var drawMode = false
    /// Last live-reload outcome for the UI.
    private(set) var reloadNotice: String?
    private(set) var reloadFailed = false
    /// Counts reload attempts that finished (success or failure), for the self-test.
    private(set) var reloadOutcomes = 0
    @ObservationIgnored var onNotice: ((Banner) -> Void)?

    /// Seconds before an ephemeral stroke fades, or nil to keep strokes until C clears them or the page changes
    /// (feedback round 3; SPEC §8's fade is off on the Mac).
    static let ephemeralInkLifetime: TimeInterval? = nil

    init(document loaded: PresentationDocument, surroundColor: CGColor) {
        let sidecar = SidecarStore.load(forDeck: loaded.url) ?? SidecarDocument()
        let document = loaded.overridingEndOfTalk(sidecar.settings.endOfTalkPage)
        self.document = document
        self.sidecar = sidecar
        var initial = SessionState()
        if let last = sidecar.rehearsal.lastPosition, document.pages.indices.contains(last.pageIndex) {
            initial.committedPage = last.pageIndex
        }
        initial.timer.target = sidecar.settings.targetDuration ?? document.pdfpc?.targetDuration
        controller = SessionController(document: document, initialState: initial)
        cache = RenderCache(document: document, budgetBytes: Presentation.cacheBudget)
        state = controller.state
        let notes = NotesLoader.load(document: document, sidecarNotes: sidecar.notesByPage)
        self.notes = notes
        thumbnails = ThumbnailProvider(document: document)
        searcher = TextSearcher(url: document.url, frames: document.frames)
        audienceSurface = SurfaceController(role: .audience, document: document, cache: cache)
        currentSurface = SurfaceController(role: .presenterCurrent, document: document, cache: cache)
        previewSurface = SurfaceController(role: .preview, document: document, cache: cache)
        notesSurface = SurfaceController(role: .preview, document: document, cache: cache)
        for surface in [audienceSurface, currentSurface, previewSurface, notesSurface] {
            surface.view.surroundColor = surroundColor
            surface.onGeometryChange = { [weak self] in self?.replan() }
        }
        previewSurface.view.surroundColor = CGColor(gray: 0.08, alpha: 1)
        notesSurface.view.surroundColor = CGColor(gray: 0.08, alpha: 1)
        controller.onChange = { [weak self] old, new in self?.stateChanged(from: old, to: new) }
        if initial.timer.target == nil, let target = notes.pdfpcFile?.targetDuration {
            controller.setTimerTarget(target)
            state = controller.state
        }
        applySplitFromSidecar()
        wirePointerAndInk()
        refreshSurfaces()
        replan()
        startWatching()
    }

    private static var cacheBudget: Int {
        // Macs have memory to spare; §3.3 asks for ±2 pages, next frame and back target on three surfaces.
        (CommandLine.arguments.first(where: { $0.hasPrefix("-cacheMB=") }).flatMap { Int($0.dropFirst(9)) } ?? 768) << 20
    }

    func apply(_ command: Command) {
        controller.navigationOptions = AppSettings.navigationOptions
        controller.apply(command)
        Latency.shared.commandApplied()
    }

    // MARK: - Geometry for the chrome

    /// Aspect ratio of what the current-slide pane shows: the presenter page, cropped for second-screen decks.
    var currentSlideAspectRatio: CGFloat { slideAspectRatio(ofPage: state.presenterPage) }
    var nextSlideAspectRatio: CGFloat { slideAspectRatio(ofPage: nextPage ?? state.presenterPage) }

    private func slideAspectRatio(ofPage page: Int) -> CGFloat {
        let crop = notesSplit.slideCrop
        let pageAspect = document.pages.indices.contains(page) ? document.pages[page].aspectRatio : 16.0 / 9.0
        return crop.height > 0 ? pageAspect * CGFloat(crop.width / crop.height) : pageAspect
    }

    // MARK: - Notes and sidecar (SPEC §3.4, §5)

    /// The note for the presenter's page, with the frame fallback.
    var currentNote: PageNote? { notes.table.note(for: state.presenterPage, frames: document.frames) }

    func userNoteText(forPage page: Int) -> String {
        sidecar.userNote(forPage: page)?.text ?? ""
    }

    func setUserNote(_ text: String, forPage page: Int) {
        let label = document.frames.frame(containing: page).label
        sidecar.setUserNote(text, forPage: page, frameLabel: label)
        reassembleNotes()
        scheduleSidecarSave()
    }

    private func reassembleNotes() {
        notes = NotesLoader.assemble(document: document, sidecarNotes: sidecar.notesByPage, pdfpcFile: notes.pdfpcFile,
                                     embedded: notes.embedded, pptx: notes.pptx)
    }

    func setTargetDuration(_ target: TimeInterval?) {
        controller.setTimerTarget(target)
        refreshState()
        sidecar.settings.targetDuration = target
        scheduleSidecarSave()
    }

    /// Writes any pending sidecar change now (quit, close). Errors are logged; nothing else to do at that point.
    func flushSidecar() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        do { try SidecarStore.save(sidecar, forDeck: document.url) } catch {
            log.error("sidecar flush failed: \(String(describing: error), privacy: .public)")
        }
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func scheduleSidecarSave(after delay: TimeInterval = 0.5) {
        saveTask?.cancel()
        let snapshot = sidecar
        let url = document.url
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            do {
                try SidecarStore.save(snapshot, forDeck: url)
            } catch {
                self?.log.error("sidecar save failed: \(String(describing: error), privacy: .public)")
                self?.onNotice?(Banner(kind: .warning, text: "Could not save notes and settings next to the deck (\(error.localizedDescription))."))
            }
        }
    }

    /// Second-screen notes: apply the sidecar's answer, or ask once if the deck looks split (SPEC §5.1.4).
    private func applySplitFromSidecar() {
        if sidecar.settings.notesSplitConfirmed {
            setSplit(sidecar.settings.notesSplit ?? .none)
            pendingSplitQuestion = nil
        } else if let detected = notes.detectedSplit {
            pendingSplitQuestion = detected
            setSplit(.none)
        } else {
            setSplit(.none)
        }
    }

    func answerSplitQuestion(useSplit: Bool) {
        guard let detected = pendingSplitQuestion else { return }
        pendingSplitQuestion = nil
        sidecar.settings.notesSplit = useSplit ? detected : NotesSplit.none
        sidecar.settings.notesSplitConfirmed = true
        setSplit(sidecar.settings.notesSplit ?? .none)
        scheduleSidecarSave()
    }

    private func setSplit(_ split: NotesSplit) {
        notesSplit = split
        for surface in [audienceSurface, currentSurface, previewSurface] { surface.setCrop(split.slideCrop) }
        notesSurface.setCrop(split.notesCrop ?? .full)
        thumbnails.crop = split.slideCrop
        refreshSurfaces()
        replan()
    }

    // MARK: - Pointer and ink (SPEC §6.4, §8)

    func togglePointerMode() {
        pointerMode.toggle()
        if !pointerMode { apply(.pointerHide) }
        if pointerMode { drawMode = false }
        updateTracking()
    }

    func toggleDrawMode() {
        drawMode.toggle()
        if drawMode { pointerMode = false; apply(.pointerHide) }
        updateTracking()
    }

    private func updateTracking() {
        for surface in [audienceSurface, currentSurface] {
            surface.view.pointerTrackingEnabled = pointerMode
        }
        currentSurface.view.inkTrackingEnabled = drawMode
    }

    private func wirePointerAndInk() {
        for surface in [audienceSurface, currentSurface] {
            surface.view.onPointerMove = { [weak self] point in self?.pointerMoved(to: point) }
            surface.view.onPointerExit = { [weak self] in self?.apply(.pointerHide) }
        }
        currentSurface.view.onInkBegin = { [weak self] point in self?.apply(.inkBegin(point, .ephemeral)) }
        currentSurface.view.onInkAppend = { [weak self] point in self?.apply(.inkAppend(point)) }
        currentSurface.view.onInkEnd = { [weak self] in self?.apply(.inkEnd) }
    }

    private func pointerMoved(to point: NormalizedPoint) {
        apply(.pointerMove(point))
        pointerHideTask?.cancel()
        pointerHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.apply(.pointerHide)
        }
    }

    private func refreshOverlays() {
        let pointer = state.pointer?.position
        let now = Date()
        let strokes = state.ink.strokes + (state.ink.active.map { [$0] } ?? [])
        let lifetime = Presentation.ephemeralInkLifetime
        for surface in [audienceSurface, currentSurface] {
            surface.view.showPointer(at: pointer)
            surface.view.showInk(strokes) { stroke in
                guard stroke.mode == .ephemeral, let lifetime else { return 1 }
                let remaining = lifetime - now.timeIntervalSince(stroke.startedAt)
                return Float(min(1, max(0, remaining)))   // fades over the last second
            }
        }
        if let lifetime, !strokes.isEmpty, inkPruneTask == nil {
            inkPruneTask = Task { [weak self] in
                while let self, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !self.controller.pruneEphemeralInk(now: Date(), maxAge: lifetime) {
                        self.refreshOverlays()   // repaint for the fade even when nothing was removed yet
                    }
                    if self.state.ink.strokes.isEmpty && self.state.ink.active == nil { break }
                }
                self?.inkPruneTask = nil
            }
        }
    }

    // MARK: - Live reload (SPEC §6.6)

    private func startWatching() {
        let watcher = DeckWatcher(deck: document.url) { [weak self] names in
            Task { @MainActor [weak self] in self?.filesChanged(names) }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func filesChanged(_ names: Set<String>) {
        let deckName = document.url.lastPathComponent
        if names.contains(deckName) {
            reloadDocument()
            return
        }
        if names.contains(SidecarStore.sidecarName(forDeck: document.url)) {
            if let fresh = SidecarStore.load(forDeck: document.url), fresh != sidecar {
                sidecar = fresh
                reassembleNotes()
                log.notice("sidecar changed on disk; notes and settings reloaded")
            }
        }
        if names.contains(PDFPCFile.url(forDeck: document.url).lastPathComponent) || names.contains(PPTXNotes.url(forDeck: document.url).lastPathComponent) {
            notes = NotesLoader.load(document: document, sidecarNotes: sidecar.notesByPage)
            onNotice?(Banner(kind: .info, text: "Notes files reloaded."))
        }
    }

    /// Parses the new PDF off the main thread; swaps only on success and only once renders are ready.
    func reloadDocument() {
        reloadTask?.cancel()
        let url = document.url
        reloadTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { () -> Result<PresentationDocument, Error> in
                Result { try PresentationDocument.load(url: url) }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch loaded {
            case .success(let fresh):
                self.install(reloaded: fresh)
            case .failure(let error):
                self.log.error("reload failed, keeping the previous deck: \(String(describing: error), privacy: .public)")
                self.reloadFailed = true
                self.reloadNotice = "The recompiled PDF could not be read; keeping the previous version. It will be retried on the next change."
                self.reloadOutcomes += 1
                self.onNotice?(Banner(kind: .warning, text: self.reloadNotice!))
            }
        }
    }

    private func install(reloaded fresh: PresentationDocument) {
        let document = fresh.overridingEndOfTalk(sidecar.settings.endOfTalkPage)
        let before = (page: state.committedPage, label: self.document.frames.frame(containing: state.committedPage).label,
                      build: self.document.frames.buildIndex(of: state.committedPage))
        self.document = document
        let newCache = RenderCache(document: document, budgetBytes: Presentation.cacheBudget)
        cache = newCache
        controller.replaceDocument(document)
        state = controller.state
        for surface in [audienceSurface, currentSurface, previewSurface, notesSurface] {
            surface.replace(document: document, cache: newCache)
        }
        thumbnails = ThumbnailProvider(document: document)
        thumbnails.crop = notesSplit.slideCrop
        searcher = TextSearcher(url: document.url, frames: document.frames)
        notes = NotesLoader.load(document: document, sidecarNotes: sidecar.notesByPage)
        refreshSurfaces()
        replan()
        reloadFailed = false
        let after = state.committedPage
        reloadNotice = "Deck reloaded: \(document.pageCount) pages, \(document.frames.frameCount) frames. Position kept at frame \(document.frames.frame(containing: after).label)."
        reloadOutcomes += 1
        log.notice("reloaded \(document.url.lastPathComponent, privacy: .public): page \(before.page + 1) (frame \(before.label, privacy: .public) build \(before.build + 1)) → page \(after + 1)")
        onNotice?(Banner(kind: .info, text: reloadNotice!))
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
    var committedFrame: Frame { document.frames.frame(containing: state.committedPage) }
    var isInAppendix: Bool { document.isAppendix(page: state.presenterPage) }
    var nextPage: Int? {
        let next = state.presenterPage + 1
        return next < document.pageCount ? next : nil
    }

    // MARK: - Surfaces and prefetch

    private func stateChanged(from old: SessionState, to new: SessionState) {
        state = new
        if old.committedPage != new.committedPage || old.browsePage != new.browsePage || old.audienceMode != new.audienceMode {
            refreshSurfaces()
        }
        if old.pointer != new.pointer || old.ink != new.ink {
            refreshOverlays()
        }
        if old.committedPage != new.committedPage || old.browsePage != new.browsePage
            || old.audienceMode != new.audienceMode || old.history != new.history {
            replan()
        }
        if old.committedPage != new.committedPage {
            sidecar.rehearsal.lastPosition = .init(frameLabel: document.frames.frame(containing: new.committedPage).label, pageIndex: new.committedPage)
            scheduleSidecarSave(after: 2)
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
        if notesSplit != .none { notesSurface.show(page: state.presenterPage) }
        refreshOverlays()
    }

    private func replan() {
        var specs = [audienceSurface, currentSurface, previewSurface].compactMap(\.spec)
        if notesSplit != .none, let notesSpec = notesSurface.spec { specs.append(notesSpec) }
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
