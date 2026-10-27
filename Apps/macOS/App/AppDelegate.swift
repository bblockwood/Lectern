import AppKit
import PresenterCore
import PresenterProtocol

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var model: AppModel!
    private var welcomeWindow: WelcomeWindowController!
    private var presenterWindow: PresenterWindowController!
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var mouseMonitor: Any?
    /// Counting down while ⌘ is held alone; shows the shortcut card when it fires (feedback round 3).
    private var commandHoldTask: Task<Void, Never>?
    /// ⌘ went down alone while the card was up; releasing it with nothing in between closes the card.
    private var commandReleaseCloses = false
    static let shortcutHoldDelay: Duration = .milliseconds(500)
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
            self.cancelCommandHold()   // ⌘ plus a key is a shortcut, not a hold
            if self.model.shortcutOverlayVisible, self.presenterIsKey, KeyMap.isEscape(event) {
                self.model.setShortcutOverlay(visible: false)
                return nil
            }
            return self.handle(keyEvent: event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.modifiersChanged(event)
            return event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.cancelCommandHold()   // ⌘-click is not a hold either
            return event
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

    /// Holding ⌘ on its own for half a second shows the shortcut card, which then stays up (feedback rounds 2
    /// and 3). While it is up, pressing and releasing ⌘ alone closes it. A key, a click or another modifier in
    /// between cancels either, so ⌘-shortcuts and ⌘-clicks never touch the card.
    private func modifiersChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if flags == [.command] {
            guard presenterIsKey else { return }
            if model.shortcutOverlayVisible {
                commandReleaseCloses = true
            } else if model.presentation != nil, AppSettings.showsShortcutOverlay {
                commandHoldTask?.cancel()
                commandHoldTask = Task { [weak self] in
                    try? await Task.sleep(for: AppDelegate.shortcutHoldDelay)
                    guard !Task.isCancelled, let self else { return }
                    self.commandHoldTask = nil
                    self.model.setShortcutOverlay(visible: true)
                }
            }
        } else if flags.isEmpty {
            commandHoldTask?.cancel()
            commandHoldTask = nil
            if commandReleaseCloses {
                commandReleaseCloses = false
                model.setShortcutOverlay(visible: false)
            }
        } else {
            cancelCommandHold()
        }
    }

    private func cancelCommandHold() {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        commandReleaseCloses = false
    }

    // MARK: - Menu actions

    @objc func openDocument(_ sender: Any?) { model.openPanel() }
    @objc func showSettings(_ sender: Any?) { model.showSettings() }
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
    @objc func editNotes(_ sender: Any?) { _ = model.perform(.editNotes) }
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
        case #selector(editNotes(_:)):
            item.state = model.notesEditing ? .on : .off
            return model.presentation != nil
        case #selector(closeDocument(_:)):
            let otherWindowIsKey = NSApp.keyWindow.map { !($0 is PresenterWindow) } ?? false
            return model.presentation != nil || otherWindowIsKey
        case #selector(nextBuild(_:)), #selector(previousBuild(_:)), #selector(nextFrame(_:)),
             #selector(previousFrame(_:)), #selector(goBack(_:)), #selector(toggleBlack(_:)), #selector(toggleWhite(_:)),
             #selector(toggleFreeze(_:)), #selector(toggleTimer(_:)), #selector(resetTimer(_:)), #selector(clearInk(_:)),
             #selector(notesLarger(_:)), #selector(notesSmaller(_:)), #selector(reloadDeck(_:)):
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
