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
    let recents = RecentsStore()
    let displays = DisplayManager()

    @ObservationIgnored private var audienceWindow: AudienceWindowController?
    @ObservationIgnored private var power: PowerAssertion?
    @ObservationIgnored private var escapeArmedUntil: Date?
    @ObservationIgnored private var audienceDisplayLostBanner: Banner?
    @ObservationIgnored private let log = Logger(subsystem: "dev.lectern", category: "app")

    /// Surround colour for letterboxing (SPEC §3.3; default black).
    var surroundColor: CGColor = CGColor(gray: 0, alpha: 1)

    init() {
        displays.onChange = { [weak self] in self?.displaysChanged() }
    }

    // MARK: - Documents

    func open(url: URL) {
        do {
            let document = try PresentationDocument.load(url: url)
            endPresenting()
            presentation = Presentation(document: document, surroundColor: surroundColor)
            recents.add(url)
            dismissBanners(kind: .error)
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
        presentation = nil
    }

    var windowTitle: String {
        guard let presentation else { return "Lectern" }
        return presentation.document.url.lastPathComponent
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
            presentation.apply(command)
        case .toggleAudience(let mode):
            presentation.apply(.setAudienceMode(presentation.state.audienceMode == mode ? .live : mode))
        case .toggleFreeze:
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

    /// Single Esc cancels a browse; Esc twice within one second ends presenting (SPEC §6.5).
    private func handleEscape() -> Bool {
        if let presentation, presentation.state.isBrowsing {
            presentation.apply(.cancelBrowse)
            escapeArmedUntil = nil
            return true
        }
        guard isPresenting else { return false }
        let now = Date()
        if let armed = escapeArmedUntil, now <= armed {
            escapeArmedUntil = nil
            endPresenting()
        } else {
            escapeArmedUntil = now.addingTimeInterval(1)
            show(Banner(kind: .info, text: "Press Esc again to end presenting."), autoDismissAfter: 1.2)
        }
        return true
    }

    func setTargetDuration(_ target: TimeInterval?) {
        presentation?.controller.setTimerTarget(target)
        presentation?.refreshState()
    }

    func askForTargetDuration() {
        let alert = NSAlert()
        alert.messageText = "Target duration"
        alert.informativeText = "Minutes for the main talk."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        if let target = presentation?.state.timer.target { field.stringValue = String(Int(target / 60)) }
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, let minutes = Int(field.stringValue), minutes > 0 {
            setTargetDuration(TimeInterval(minutes * 60))
        }
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
    }

    func endPresenting() {
        guard isPresenting else { return }
        isPresenting = false
        audienceWindow?.hide()
        rehearsalAudienceWindowVisible = false
        power = nil
        escapeArmedUntil = nil
        Latency.shared.primaryRole = .presenterCurrent
        presentation?.setPresenting(false, audienceDisplay: nil, presenterDisplay: displays.assignment.presenter?.id)
        if let banner = audienceDisplayLostBanner { dismiss(banner); audienceDisplayLostBanner = nil }
        log.notice("presenting ended")
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
