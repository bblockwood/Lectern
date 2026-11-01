import AppKit
import Observation
import PresenterCore
import PresenterProtocol
import UniformTypeIdentifiers
import os

/// What the key map produces: either a session `Command` or an app-level action.
enum AppAction: Equatable {
    case command(Command)
    case toggleAudience(AudienceMode)
    case toggleFreeze
    case toggleTimer
    case resetTimer
    case startPresenting
    case swapDisplays
    case escape
    /// Tab: overview on/off (SPEC §6.3).
    case toggleOverview
    /// A typed digit for jump-by-number.
    case digit(Character)
    /// Return: jump if digits were typed, commit a browse in the overview, otherwise next.
    case returnKey
    /// ↑/↓: next/previous normally, a row move in the overview grid.
    case verticalArrow(up: Bool)
    /// ⌘F: open the overview with the search field focused.
    case focusSearch
    /// A link clicked on a slide surface.
    case followLink(LinkID)
    case togglePointer
    case toggleDraw
    case notesFontLarger
    case notesFontSmaller
    /// ⌘/ or ?: the keyboard-shortcut card on / off.
    case toggleShortcutCard
}

struct Banner: Identifiable, Equatable {
    enum Kind { case info, warning, error }
    enum Action: Equatable { case openDisplaySettings }
    let id = UUID()
    var kind: Kind
    var text: String
    var action: Action? = nil
    var actionTitle: String? = nil
}

/// App-level state: the open deck, presenting mode, displays, banners. Views read it; menus and keys drive it.
@MainActor
@Observable
final class AppModel {
    private(set) var presentation: Presentation?
    private(set) var isPresenting = false
    private(set) var banners: [Banner] = []
    private(set) var rehearsalAudienceWindowVisible = false
    /// The overview replaces the next-slide and notes column; every key keeps its presenting meaning there, so
    /// the talk can go on with it open (feedback round 6).
    private(set) var overviewVisible = false
    /// Digits typed for jump-by-number; shown as an overlay until Return or a timeout.
    private(set) var jumpBuffer = ""
    /// Bumped to ask the overview to focus its search field.
    private(set) var searchFocusRequest = 0
    /// The keyboard-shortcut card: ⌘/ or ? toggles it; Esc, a click outside or a row click closes it.
    private(set) var shortcutOverlayVisible = false
    /// One Esc was pressed while presenting; the Present button shows "Esc again to end" until this clears.
    private(set) var escapeArmed = false
    /// Bumped to ask the status bar to open the countdown editor on the timer (menu "Custom…").
    private(set) var countdownEditorRequest = 0
    /// The notes pane shows the contents instead of notes. Chosen once when a deck opens (contents if the first
    /// slide has no notes), then only by the user (feedback round 3).
    private(set) var notesShowsContents = false
    /// The app delegate swaps the chooser and presenter windows on these (feedback round 3).
    @ObservationIgnored var onDeckOpened: ((URL) -> Void)?
    @ObservationIgnored var onDeckClosed: (() -> Void)?
    /// Presenting started, stopped, or gained an audience display; the delegate drives the window's full screen.
    @ObservationIgnored var onPresentingChanged: ((_ presenting: Bool, _ hasAudienceDisplay: Bool) -> Void)?
    /// Notes font size in points, persisted per device (SPEC §5.2).
    var notesFontSize: Double {
        get { UserDefaults.standard.object(forKey: AppSettings.notesFontSizeKey) as? Double ?? Theme.notesDefault }
        set { UserDefaults.standard.set(min(48, max(10, newValue)), forKey: AppSettings.notesFontSizeKey) }
    }
    private(set) var notesFontTick = 0
    let recents = RecentsStore()
    let displays = DisplayManager()

    @ObservationIgnored private var audienceWindow: AudienceWindowController?
    @ObservationIgnored private var power: PowerAssertion?
    @ObservationIgnored private var escapeArmedUntil: Date?
    @ObservationIgnored private var escapeArmTask: Task<Void, Never>?
    @ObservationIgnored private var audienceDisplayLostBanner: Banner?
    @ObservationIgnored private var jumpBufferTimeout: Task<Void, Never>?
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var settingsObserver: NSObjectProtocol?
    @ObservationIgnored private var observedNotesFontSize: Double = 0
    @ObservationIgnored private let log = Logger(subsystem: "dev.lectern", category: "app")

    /// SPEC §4.3: URI links are ignored unless this is on (`defaults write dev.lectern.mac LecternOpenURILinks -bool YES`).
    var opensURILinks: Bool { UserDefaults.standard.bool(forKey: AppSettings.opensURILinksKey) }

    /// Surround colour for letterboxing (SPEC §3.3; default black).
    var surroundColor: CGColor = CGColor(gray: 0, alpha: 1)

    init() {
        displays.onChange = { [weak self] in self?.displaysChanged() }
        // The notes size can change from ⌘+/⌘− or from the Settings window; either way the notes pane re-reads it.
        observedNotesFontSize = notesFontSize
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.notesFontSize != self.observedNotesFontSize else { return }
                self.observedNotesFontSize = self.notesFontSize
                self.notesFontTick += 1
            }
        }
    }

    // MARK: - Documents

    func open(url: URL) {
        do {
            let document = try PresentationDocument.load(url: url)
            endPresenting()
            overviewVisible = false
            jumpBuffer = ""
            presentation?.flushSidecar()
            presentation?.stopWatching()
            let presentation = Presentation(document: document, surroundColor: surroundColor)
            self.presentation = presentation
            for surface in [presentation.audienceSurface, presentation.currentSurface] {
                surface.view.onLinkActivate = { [weak self] id in _ = self?.perform(.followLink(id)) }
            }
            for surface in [presentation.currentSurface, presentation.previewSurface] {
                surface.view.onClick = { [weak self] timestamp in self?.slideClicked(at: timestamp) }
            }
            presentation.onNotice = { [weak self] banner in self?.show(banner, autoDismissAfter: banner.kind == .info ? 4 : nil) }
            for warning in presentation.notes.warnings { show(Banner(kind: .warning, text: warning)) }
            notesShowsContents = !document.outline.isEmpty && presentation.currentNote == nil && presentation.notesSplit == .none
            recents.add(url)
            dismissBanners(kind: .error)
            onDeckOpened?(url)
            log.notice("opened \(url.lastPathComponent, privacy: .public): \(document.pageCount) pages, \(document.frames.frameCount) frames")
        } catch {
            log.error("failed to open \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            show(Banner(kind: .error, text: "Could not open \(url.lastPathComponent): it is not a readable PDF."))
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a PDF deck"
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }

    func close() {
        endPresenting()
        overviewVisible = false
        shortcutOverlayVisible = false
        jumpBuffer = ""
        presentation?.flushSidecar()
        presentation?.stopWatching()
        presentation = nil
        onDeckClosed?()
    }

    // MARK: - Actions

    /// Returns true when the action was consumed.
    func perform(_ action: AppAction) -> Bool {
        switch action {
        case .startPresenting:
            if presentation != nil { startPresenting() }
            return true
        case .swapDisplays:
            swapDisplays()
            return true
        case .escape:
            return handleEscape()
        default:
            break
        }
        guard let presentation else { return false }
        switch action {
        case .command(let command):
            if command == .clearInk { presentation.deactivateTools() }
            presentation.apply(command)
        case .verticalArrow(let up):
            presentation.apply(up ? .previous : .next)
        case .toggleOverview:
            setOverview(visible: !overviewVisible)
        case .digit(let digit):
            guard jumpBuffer.count < 5 else { break }
            jumpBuffer.append(digit)
            jumpBufferTimeout?.cancel()
            jumpBufferTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.jumpBuffer = ""
            }
        case .returnKey:
            if !jumpBuffer.isEmpty {
                let label = jumpBuffer
                jumpBuffer = ""
                jumpBufferTimeout?.cancel()
                if presentation.document.frames.frame(withLabel: label) != nil {
                    presentation.apply(.goToFrameLabel(label))
                    setOverview(visible: false)
                } else {
                    show(Banner(kind: .info, text: "No frame labelled \(label)."), autoDismissAfter: 2)
                }
            } else {
                presentation.apply(.next)
            }
        case .focusSearch:
            setOverview(visible: true)
            searchFocusRequest += 1
        case .followLink(let id):
            follow(link: id, in: presentation)
        case .togglePointer:
            presentation.togglePointerMode()
        case .toggleDraw:
            presentation.toggleDrawMode()
        case .notesFontLarger:
            notesFontSize += 2
        case .notesFontSmaller:
            notesFontSize -= 2
        case .toggleShortcutCard:
            setShortcutOverlay(visible: !shortcutOverlayVisible)
        case .toggleAudience(let mode):
            guard isPresenting else { break }   // no audience window, nothing to black out (feedback round 6)
            presentation.apply(.setAudienceMode(presentation.state.audienceMode == mode ? .live : mode))
        case .toggleFreeze:
            guard isPresenting else { break }
            if case .frozen = presentation.state.audienceMode {
                presentation.apply(.setAudienceMode(.live))
            } else {
                presentation.apply(.setAudienceMode(.frozen(page: presentation.state.committedPage)))
            }
        case .toggleTimer:
            presentation.apply(presentation.state.timer.isRunning ? .timerPause : .timerStart)
        case .resetTimer:
            presentation.apply(.timerReset)
        case .startPresenting, .swapDisplays, .escape:
            break
        }
        return true
    }

    // MARK: - Overview and jumping (SPEC §6.3)

    func setOverview(visible: Bool) {
        guard visible != overviewVisible else { return }
        overviewVisible = visible
    }

    /// Jump straight to `page` (a click on a frame, an outline entry or a search hit). The audience follows at
    /// once; the overview stays open until Tab or Esc; ⌫ returns to where the jump started.
    func jump(to page: Int) {
        presentation?.apply(.goToPage(page))
    }

    private func follow(link id: LinkID, in presentation: Presentation) {
        guard let link = presentation.document.link(id) else { return }
        switch link.action {
        case .uri(let url):
            guard opensURILinks else {
                log.notice("ignored URI link \(url.absoluteString, privacy: .public)")
                show(Banner(kind: .info, text: "Link to \(url.host() ?? url.absoluteString) ignored (web links are off)."), autoDismissAfter: 2)
                return
            }
            let alert = NSAlert()
            alert.messageText = "Open link in the browser?"
            alert.informativeText = url.absoluteString
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        case .launch(let path):
            log.notice("launch link ignored until M9: \(path, privacy: .public)")
        case .unsupported:
            break
        case .goToPage, .named:
            presentation.apply(.followLink(id))
        }
    }

    /// Esc: clears typed digits, then turns Laser / Draw off, then closes the overview; twice within a second
    /// ends presenting.
    private func handleEscape() -> Bool {
        if !jumpBuffer.isEmpty {
            jumpBuffer = ""
            jumpBufferTimeout?.cancel()
            return true
        }
        if let presentation, presentation.pointerMode || presentation.drawMode {
            presentation.deactivateTools()
            disarmEscape()
            return true
        }
        if overviewVisible {
            setOverview(visible: false)
            disarmEscape()
            return true
        }
        guard isPresenting else { return false }
        let now = Date()
        if let armed = escapeArmedUntil, now <= armed {
            endPresenting()
        } else {
            // Shown in place on the Present button rather than as a banner (Ben: a banner is not Mac-like).
            escapeArmedUntil = now.addingTimeInterval(1)
            escapeArmed = true
            escapeArmTask?.cancel()
            escapeArmTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.disarmEscape()
            }
        }
        return true
    }

    private func disarmEscape() {
        escapeArmedUntil = nil
        escapeArmed = false
        escapeArmTask?.cancel()
        escapeArmTask = nil
    }

    /// Setting a countdown starts the timer at once if it is not already running (feedback round 3); a deck's
    /// own duration still waits for the first advance.
    func setTargetDuration(_ target: TimeInterval?) {
        guard let presentation else { return }
        presentation.setTargetDuration(target)
        if target != nil, !presentation.state.timer.isRunning { presentation.apply(.timerStart) }
    }

    func setNotesShowsContents(_ contents: Bool) {
        notesShowsContents = contents
    }

    func requestCountdownEditor() {
        guard presentation != nil else { return }
        countdownEditorRequest += 1
    }

    func setShortcutOverlay(visible: Bool) {
        guard visible != shortcutOverlayVisible else { return }
        shortcutOverlayVisible = visible
    }

    /// A row of the shortcut card was clicked: close the card, then do what the key would do.
    func run(_ shortcut: Shortcut) {
        setShortcutOverlay(visible: false)
        shortcut.perform?(self)
    }

    func toggleFullScreen() {
        NSApp.windows.first { $0 is PresenterWindow }?.toggleFullScreen(nil)
    }

    /// A plain click on the current or next slide advances (feedback round 2). While the shortcut card is up the
    /// click only closes it, in case it reached the slide underneath.
    private func slideClicked(at timestamp: TimeInterval) {
        if shortcutOverlayVisible {
            setShortcutOverlay(visible: false)
            return
        }
        Latency.shared.inputReceived(at: timestamp)
        _ = perform(.command(.next))
    }

    func showSettings() {
        let controller = settingsWindow ?? SettingsWindowController()
        settingsWindow = controller
        controller.show()
    }

    // MARK: - Presenting

    func startPresenting() {
        guard let presentation, !isPresenting else { return }
        isPresenting = true
        power = PowerAssertion(reason: "Lectern is presenting")
        Latency.shared.primaryRole = .audience
        configureAudienceWindow(for: presentation)
        presentation.setPresenting(true, audienceDisplay: displays.assignment.audience?.id, presenterDisplay: displays.assignment.presenter?.id)
        warnIfMirrored()
        NSCursor.setHiddenUntilMouseMoves(true)
        log.notice("presenting started; audience display: \(self.displays.assignment.audience?.name ?? "none (rehearsal)", privacy: .public)")
        onPresentingChanged?(true, displays.assignment.audience != nil)
    }

    func endPresenting() {
        guard isPresenting else { return }
        isPresenting = false
        if let presentation, presentation.state.audienceMode != .live { presentation.apply(.setAudienceMode(.live)) }
        audienceWindow?.hide()
        rehearsalAudienceWindowVisible = false
        power = nil
        disarmEscape()
        Latency.shared.primaryRole = .presenterCurrent
        presentation?.setPresenting(false, audienceDisplay: nil, presenterDisplay: displays.assignment.presenter?.id)
        if let banner = audienceDisplayLostBanner { dismiss(banner); audienceDisplayLostBanner = nil }
        log.notice("presenting ended")
        onPresentingChanged?(false, displays.assignment.audience != nil)
    }

    func swapDisplays() {
        displays.swap()
        // displaysChanged() runs from the manager's onChange.
    }

    func toggleRehearsalAudienceWindow() {
        guard isPresenting, displays.assignment.audience == nil, let audienceWindow else { return }
        if rehearsalAudienceWindowVisible { audienceWindow.hide() } else { audienceWindow.show() }
        rehearsalAudienceWindowVisible.toggle()
    }

    private func configureAudienceWindow(for presentation: Presentation) {
        let controller = audienceWindow ?? AudienceWindowController()
        audienceWindow = controller
        controller.attach(surface: presentation.audienceSurface.view)
        if let audience = displays.assignment.audience, let screen = displays.screen(for: audience) {
            controller.configure(.fullScreen(screen: screen, display: audience))
            controller.show()
            rehearsalAudienceWindowVisible = false
        } else {
            let aspect = presentation.document.pages.first?.aspectRatio ?? 16.0 / 9.0
            controller.configure(.rehearsal(aspectRatio: aspect, near: displays.screen(for: displays.assignment.presenter)))
            controller.show()
            rehearsalAudienceWindowVisible = true
        }
    }

    private func displaysChanged() {
        guard isPresenting, let presentation else { return }
        if let audience = displays.assignment.audience {
            if let banner = audienceDisplayLostBanner {
                dismiss(banner)
                audienceDisplayLostBanner = nil
                log.notice("audience display is back: \(audience.name, privacy: .public)")
            }
            configureAudienceWindow(for: presentation)
            onPresentingChanged?(true, true)   // a display that arrives mid-talk also gets the full-screen treatment
        } else if audienceWindow?.mode?.isFullScreen == true {
            // The audience display went away mid-talk: keep presenting, say so, wait for it to return (SPEC §6.1).
            audienceWindow?.hide()
            let banner = Banner(kind: .warning, text: "The audience display was disconnected. Presenting continues; the audience window returns when it is plugged back in.")
            audienceDisplayLostBanner = banner
            show(banner)
            log.notice("audience display lost")
        }
        presentation.setPresenting(true, audienceDisplay: displays.assignment.audience?.id, presenterDisplay: displays.assignment.presenter?.id)
        warnIfMirrored()
    }

    private func warnIfMirrored() {
        dismissBanners(action: .openDisplaySettings)
        guard displays.hasMirroring else { return }
        show(Banner(kind: .warning,
                    text: "Your displays are mirrored, so the audience would see this presenter screen. Use separate displays.",
                    action: .openDisplaySettings, actionTitle: "Open Displays Settings"))
    }

    // MARK: - Banners

    func show(_ banner: Banner, autoDismissAfter seconds: TimeInterval? = nil) {
        banners.append(banner)
        if let seconds {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.dismiss(banner)
            }
        }
    }

    func dismiss(_ banner: Banner) {
        banners.removeAll { $0.id == banner.id }
    }

    func run(_ action: Banner.Action) {
        switch action {
        case .openDisplaySettings: DisplayManager.openDisplaySettings()
        }
    }

    private func dismissBanners(kind: Banner.Kind) { banners.removeAll { $0.kind == kind } }
    private func dismissBanners(action: Banner.Action) { banners.removeAll { $0.action == action } }
}
