import AppKit
import SwiftUI

final class PresenterWindow: NSWindow {}

/// The first click on an inactive Lectern window acts at once instead of only activating the app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The presenter window: SwiftUI chrome in an AppKit window, dark (SPEC §6.2). It exists only while a deck is
/// open: it fills the screen's visible area when a deck opens and hides when the deck closes, independent of the
/// chooser window's size (feedback round 3). Its title bar is AppKit's own, with the deck's name and a real
/// proxy icon (`representedURL`): Ben prefers native behaviour over a centred, drawn title.
@MainActor
final class PresenterWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var hideAfterExitingFullScreen = false
    /// A full-screen transition is animating; requests made meanwhile are applied when it finishes.
    private var transitioning = false
    private var pendingFullScreen: Bool?
    private var pendingHide = false
    /// Full screen was entered for presenting, so ending presenting leaves it again.
    private var enteredFullScreenForPresenting = false

    init(model: AppModel) {
        self.model = model
        let window = PresenterWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 540)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.title = "Lectern"
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self
        window.contentView = FirstClickHostingView(rootView: PresenterRootView(model: model))
        window.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Fills the visible frame of `screen` (the chooser's screen, else the main one) and comes to the front.
    func show(deck url: URL, on screen: NSScreen?) {
        guard let window else { return }
        window.title = url.lastPathComponent
        window.representedURL = url
        if !window.isVisible, let screen = screen ?? NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// Hides the window; a full-screen window leaves full screen first and hides when that finishes.
    func hide() {
        guard let window else { return }
        enteredFullScreenForPresenting = false
        pendingFullScreen = nil
        if transitioning {
            pendingHide = true
        } else if window.styleMask.contains(.fullScreen) {
            hideAfterExitingFullScreen = true
            window.toggleFullScreen(nil)
        } else {
            window.orderOut(nil)
        }
        window.representedURL = nil
        window.title = "Lectern"
    }

    /// Presenting puts the window into full screen (when the setting is on) and ending presenting leaves it again,
    /// but only if it was entered this way; full screen entered by hand is left alone. Live with one display is the
    /// exception: the audience view is a window on this screen, which full screen would hide (feedback round 7).
    /// Switching between live and rehearsal applies the same rule.
    func presentingChanged(_ mode: AppModel.PresentingMode?, hasAudienceDisplay: Bool) {
        guard AppSettings.fullScreenWhilePresenting else { return }
        let wants: Bool
        switch mode {
        case .rehearsal: wants = true
        case .live: wants = hasAudienceDisplay
        case nil: wants = false
        }
        setFullScreenForPresenting(wants)
    }

    private func setFullScreenForPresenting(_ wants: Bool) {
        guard let window else { return }
        if transitioning { pendingFullScreen = wants; return }
        let fullScreen = window.styleMask.contains(.fullScreen)
        if wants, !fullScreen {
            enteredFullScreenForPresenting = true
            window.toggleFullScreen(nil)
        } else if !wants, fullScreen, enteredFullScreenForPresenting {
            enteredFullScreenForPresenting = false
            window.toggleFullScreen(nil)
        } else if !wants {
            enteredFullScreenForPresenting = false
        }
    }

    private func transitionFinished() {
        transitioning = false
        if pendingHide {
            pendingHide = false
            hide()
            return
        }
        if let wants = pendingFullScreen {
            pendingFullScreen = nil
            setFullScreenForPresenting(wants)
        }
    }

    func windowWillEnterFullScreen(_ notification: Notification) { transitioning = true }
    func windowWillExitFullScreen(_ notification: Notification) { transitioning = true }

    func windowDidEnterFullScreen(_ notification: Notification) { transitionFinished() }

    func windowDidExitFullScreen(_ notification: Notification) {
        if hideAfterExitingFullScreen {
            hideAfterExitingFullScreen = false
            window?.orderOut(nil)
        }
        transitionFinished()
    }

    /// The red button closes the deck (feedback round 1); the window itself stays around, hidden, for the next deck.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.close()
        return false
    }
}
