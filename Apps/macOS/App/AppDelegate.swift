import AppKit
import PresenterCore
import PresenterProtocol

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var model: AppModel!
    private var welcomeWindow: WelcomeWindowController!
    private var presenterWindow: PresenterWindowController!
    private var keyMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?
    private var selfTest: SelfTest?
    private var recentsMenu: NSMenu?

    func applicationWillFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let (menu, recents) = MainMenu.build(target: self)
        recentsMenu = recents
        recents.delegate = self
        NSApp.mainMenu = menu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        welcomeWindow = WelcomeWindowController(model: model)
        presenterWindow = PresenterWindowController(model: model)
        model.onDeckOpened = { [weak self] url in self?.showPresenter(deck: url) }
        model.onDeckClosed = { [weak self] in self?.showWelcome() }
        welcomeWindow.show()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.model.shortcutOverlayVisible, self.presenterIsKey {
                self.model.setShortcutOverlay(visible: false)   // any key closes the card (feedback round 6)
                if KeyMap.isEscape(event) || KeyMap.action(for: event) == .toggleShortcutCard { return nil }
            }
            return self.handle(keyEvent: event) ? nil : event
        }
        // Switching away (⌘-Tab) closes the shortcut card, as a transient panel should.
        deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.setShortcutOverlay(visible: false) }
        }
        NSApp.activate()

        if let test = SelfTest.fromArguments(CommandLine.arguments) {
            selfTest = test
            test.run(in: model)
        } else if let path = CommandLine.arguments.dropFirst().first(where: { $0.lowercased().hasSuffix(".pdf") }) {
            model.open(url: URL(fileURLWithPath: path))
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.open(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model.endPresenting()
        model.presentation?.flushSidecar()
    }

    // MARK: - Windows (feedback round 3: the chooser and the presenter are separate windows)

    /// The presenter fills the screen the chooser was on; the chooser hides until the deck closes.
    private func showPresenter(deck url: URL) {
        let screen = welcomeWindow.window?.screen ?? presenterWindow.window?.screen
        welcomeWindow.hide()
        presenterWindow.show(deck: url, on: screen)
    }

    private func showWelcome() {
        presenterWindow.hide()
        welcomeWindow.show()
    }

    // MARK: - Keyboard

    private var presenterIsKey: Bool { NSApp.keyWindow == nil || NSApp.keyWindow is PresenterWindow }

    /// Every key press in the presenter window goes through `KeyMap`. Other windows (Settings, the countdown
    /// popover) keep their keys, as does text editing (M2 jump field, M3 notes editor). The audience window
    /// cannot become key.
    private func handle(keyEvent event: NSEvent) -> Bool {
        if let keyWindow = NSApp.keyWindow {
            guard keyWindow is PresenterWindow else { return false }
            if keyWindow.firstResponder is NSTextView { return false }
        }
        guard let action = KeyMap.action(for: event) else { return false }
        Latency.shared.inputReceived(at: event.timestamp)
        return model.perform(action)
    }

    // MARK: - Menu actions

    @objc func openDocument(_ sender: Any?) { model.openPanel() }
    @objc func showSettings(_ sender: Any?) { model.showSettings() }
    @objc func toggleShortcutCard(_ sender: Any?) { _ = model.perform(.toggleShortcutCard) }
    /// ⌘W closes whichever window is key (Settings, the chooser), else the deck.
    @objc func closeDocument(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow, !(keyWindow is PresenterWindow) { keyWindow.performClose(sender); return }
        model.close()
    }
    @objc func startPresenting(_ sender: Any?) { model.startPresenting() }
    @objc func endPresenting(_ sender: Any?) { model.endPresenting() }
    @objc func swapDisplays(_ sender: Any?) { model.swapDisplays() }
    @objc func toggleRehearsalAudienceWindow(_ sender: Any?) { model.toggleRehearsalAudienceWindow() }
    @objc func nextBuild(_ sender: Any?) { _ = model.perform(.command(.next)) }
    @objc func previousBuild(_ sender: Any?) { _ = model.perform(.command(.previous)) }
    @objc func nextFrame(_ sender: Any?) { _ = model.perform(.command(.nextFrame)) }
    @objc func previousFrame(_ sender: Any?) { _ = model.perform(.command(.previousFrame)) }
    @objc func goBack(_ sender: Any?) { _ = model.perform(.command(.back)) }
    @objc func toggleBlack(_ sender: Any?) { _ = model.perform(.toggleAudience(.black)) }
    @objc func toggleWhite(_ sender: Any?) { _ = model.perform(.toggleAudience(.white)) }
    @objc func toggleFreeze(_ sender: Any?) { _ = model.perform(.toggleFreeze) }
    @objc func toggleTimer(_ sender: Any?) { _ = model.perform(.toggleTimer) }
    @objc func togglePointer(_ sender: Any?) { _ = model.perform(.togglePointer) }
    @objc func toggleDraw(_ sender: Any?) { _ = model.perform(.toggleDraw) }
    @objc func clearInk(_ sender: Any?) { _ = model.perform(.command(.clearInk)) }
    @objc func notesLarger(_ sender: Any?) { _ = model.perform(.notesFontLarger) }
    @objc func notesSmaller(_ sender: Any?) { _ = model.perform(.notesFontSmaller) }
    @objc func reloadDeck(_ sender: Any?) { model.presentation?.reloadDocument() }
    @objc func resetTimer(_ sender: Any?) { _ = model.perform(.resetTimer) }
    @objc func openDisplaySettings(_ sender: Any?) { DisplayManager.openDisplaySettings() }

    /// Presets set the countdown directly; "Custom…" opens the editor on the status bar's timer.
    @objc func setTargetDuration(_ sender: NSMenuItem) {
        if let minutes = sender.representedObject as? Int {
            model.setTargetDuration(minutes > 0 ? TimeInterval(minutes * 60) : nil)
        } else {
            model.requestCountdownEditor()
        }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { model.open(url: url) }
    }

    @objc func clearRecents(_ sender: Any?) { model.recents.clear() }

    // MARK: - NSMenuDelegate (Open Recent)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentsMenu else { return }
        menu.removeAllItems()
        for url in model.recents.urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if !model.recents.urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecents(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !model.recents.urls.isEmpty
        menu.addItem(clear)
    }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(startPresenting(_:)): return model.presentation != nil && !model.isPresenting
        case #selector(endPresenting(_:)): return model.isPresenting
        case #selector(swapDisplays(_:)): return model.displays.assignment.audience != nil
        case #selector(toggleRehearsalAudienceWindow(_:)):
            item.state = model.rehearsalAudienceWindowVisible ? .on : .off
            return model.isPresenting && model.displays.assignment.audience == nil
        case #selector(togglePointer(_:)):
            item.state = model.presentation?.pointerMode == true ? .on : .off
            return model.presentation != nil
        case #selector(toggleDraw(_:)):
            item.state = model.presentation?.drawMode == true ? .on : .off
            return model.presentation != nil
        case #selector(toggleShortcutCard(_:)):
            item.state = model.shortcutOverlayVisible ? .on : .off
            return model.presentation != nil
        case #selector(closeDocument(_:)):
            let otherWindowIsKey = NSApp.keyWindow.map { !($0 is PresenterWindow) } ?? false
            return model.presentation != nil || otherWindowIsKey
        case #selector(toggleBlack(_:)), #selector(toggleWhite(_:)), #selector(toggleFreeze(_:)):
            return model.isPresenting   // audience modes mean nothing without an audience window
        case #selector(nextBuild(_:)), #selector(previousBuild(_:)), #selector(nextFrame(_:)),
             #selector(previousFrame(_:)), #selector(goBack(_:)), #selector(toggleTimer(_:)), #selector(resetTimer(_:)),
             #selector(clearInk(_:)), #selector(notesLarger(_:)), #selector(notesSmaller(_:)), #selector(reloadDeck(_:)):
            return model.presentation != nil
        case #selector(setTargetDuration(_:)):
            if let minutes = item.representedObject as? Int {
                let current = model.presentation?.state.timer.target
                item.state = (minutes == 0 && current == nil) || (minutes > 0 && current == TimeInterval(minutes * 60)) ? .on : .off
            }
            return model.presentation != nil
        default: return true
        }
    }
}
