import AppKit
import SwiftUI

/// Settings (⌘,). Each control edits a UserDefaults key from `AppSettings`; the app reads the keys when it needs them.
struct SettingsView: View {
    @AppStorage(AppSettings.previousLandsOnFrameStartKey) private var previousLandsOnFrameStart = false
    @AppStorage(AppSettings.shortcutOverlayKey) private var shortcutOverlay = true
    @AppStorage(AppSettings.notesFontSizeKey) private var notesFontSize = Theme.notesDefault
    @AppStorage(AppSettings.opensURILinksKey) private var opensURILinks = false

    var body: some View {
        Form {
            Section("Going back") {
                Picker("When ← leaves a frame, land on", selection: $previousLandsOnFrameStart) {
                    Text("the previous frame's last build (pdfpc behaviour)").tag(false)
                    Text("the previous frame's first build").tag(true)
                }
                .pickerStyle(.radioGroup)
                Text("Inside a frame, ← always steps back one build. ⇧← always lands on the previous frame's last build.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Presenter") {
                Toggle("Hold ⌘ for half a second to show the keyboard shortcuts", isOn: $shortcutOverlay)
                Stepper("Notes size: \(Int(notesFontSize)) pt  (⌘+ / ⌘− while presenting)", value: $notesFontSize, in: 10...48, step: 2)
            }
            Section("Links") {
                Toggle("Open web links in the browser, after confirming", isOn: $opensURILinks)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SettingsView())
        window.contentView = host
        let fitting = host.fittingSize
        window.setContentSize(NSSize(width: 560, height: max(fitting.height, 320)))
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
