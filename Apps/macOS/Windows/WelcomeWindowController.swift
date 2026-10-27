import AppKit
import SwiftUI

final class WelcomeWindow: NSWindow {}

/// The deck chooser window (feedback round 3): a separate, modest window like iWork's chooser. It hides while a
/// deck is open and comes back when the deck closes; closing it with no deck open quits.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = WelcomeWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 360)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.title = "Lectern"
        window.setFrameAutosaveName("WelcomeWindow")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = FirstClickHostingView(rootView: WelcomeView(model: model))
        window.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard model.presentation == nil else { return }
        NSApp.terminate(nil)
    }
}
