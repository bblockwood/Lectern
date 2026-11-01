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
    private var exitingFullScreen = false
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
        if window.styleMask.contains(.fullScreen) {
            hideAfterExitingFullScreen = true
            if !exitingFullScreen { window.toggleFullScreen(nil) }
        } else {
            window.orderOut(nil)
        }
        window.representedURL = nil
        window.title = "Lectern"
    }

    /// Presenting on a second display puts the window into full screen (when the setting is on); ending
    /// presenting leaves full screen again, but only if it was entered this way. Rehearsal (no second display)
    /// is left alone so the rehearsal audience window stays visible.
    func presentingChanged(_ presenting: Bool, hasAudienceDisplay: Bool) {
        guard AppSettings.fullScreenWhilePresenting, let window else { return }
        let fullScreen = window.styleMask.contains(.fullScreen)
        if presenting, hasAudienceDisplay, !fullScreen {
            enteredFullScreenForPresenting = true
            window.toggleFullScreen(nil)
        } else if !presenting, enteredFullScreenForPresenting {
            enteredFullScreenForPresenting = false
            if fullScreen, !exitingFullScreen { window.toggleFullScreen(nil) }
        }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        exitingFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        exitingFullScreen = false
        guard hideAfterExitingFullScreen else { return }
        hideAfterExitingFullScreen = false
        window?.orderOut(nil)
    }

    /// Full screen left by the user (⌃⌘F, the green button) while presenting: nothing to undo later.
    func windowDidEnterFullScreen(_ notification: Notification) {}

    /// The red button closes the deck (feedback round 1); the window itself stays around, hidden, for the next deck.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.close()
        return false
    }
}
