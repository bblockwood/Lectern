import AppKit

/// Borderless window that never takes keyboard focus, so keys keep going to the presenter window.
final class AudienceWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The audience window: full-screen and borderless on the audience display at shielding level (menu bar and
/// Dock stay off it), or a plain resizable window in rehearsal mode (SPEC §6.1).
@MainActor
final class AudienceWindowController: NSObject, NSWindowDelegate {
    enum Mode: Equatable {
        case fullScreen(screen: NSScreen, display: DisplayInfo)
        case rehearsal(aspectRatio: CGFloat, near: NSScreen?)

        var isFullScreen: Bool {
            if case .fullScreen = self { return true }
            return false
        }
    }

    private(set) var mode: Mode?
    private let window: AudienceWindow
    private var surface: NSView?

    override init() {
        window = AudienceWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.delegate = self
    }

    func attach(surface view: NSView) {
        guard surface !== view else { return }
        surface = view
        view.frame = window.contentView?.bounds ?? .zero
        view.autoresizingMask = [.width, .height]
        window.contentView = view
    }

    func configure(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .fullScreen(let screen, _):
            window.styleMask = [.borderless]
            window.title = "Audience"
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.contentAspectRatio = .zero
            window.setFrame(screen.frame, display: true)
        case .rehearsal(let aspect, let near):
            window.styleMask = [.titled, .resizable, .closable, .miniaturizable]
            window.title = "Audience (rehearsal)"
            // The self-test runs from a terminal that covers everything; an occluded window gets no display-link ticks.
            window.level = SelfTest.isActive ? .screenSaver : .normal
            window.collectionBehavior = [.managed, .participatesInCycle]
            window.contentAspectRatio = NSSize(width: aspect, height: 1)
            let width: CGFloat = 960
            let contentSize = NSSize(width: width, height: (width / aspect).rounded())
            window.setContentSize(contentSize)
            let screenFrame = (near ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window.setFrameOrigin(NSPoint(x: screenFrame.maxX - window.frame.width - 40, y: screenFrame.minY + 40))
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    // The close button in rehearsal mode hides the window; presenting continues.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
