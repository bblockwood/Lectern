import AppKit
import SwiftUI

final class PresenterWindow: NSWindow {}

/// The presenter window: SwiftUI chrome in an AppKit window, dark, with a remembered frame (SPEC §6.2).
@MainActor
final class PresenterWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = PresenterWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 540)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.title = "Lectern"
        window.setFrameAutosaveName("PresenterWindow")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PresenterRootView(model: model))
        window.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The red button closes the deck and returns to the welcome screen (feedback round 1); closing the welcome
    /// screen quits.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.presentation != nil else { return true }
        model.close()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        model.endPresenting()
        NSApp.terminate(nil)
    }
}
