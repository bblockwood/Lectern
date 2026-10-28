import SwiftUI

/// One row of the shortcut card. `perform` runs it when the row is clicked (feedback round 2); a row without one
/// (typed digits) is plain text.
struct Shortcut: Identifiable {
    let keys: String
    let action: String
    let perform: (@MainActor (AppModel) -> Void)?
    var id: String { keys + action }

    init(_ keys: String, _ action: String, perform: (@MainActor (AppModel) -> Void)? = nil) {
        self.keys = keys
        self.action = action
        self.perform = perform
    }
}

struct ShortcutGroup: Identifiable {
    let title: String
    let shortcuts: [Shortcut]
    var id: String { title }
}

/// What the shortcut card lists, by column. Mirrors `KeyMap` and `MainMenu`; keep the three in step.
@MainActor
enum ShortcutReference {
    static let columns: [[ShortcutGroup]] = [
        [ShortcutGroup(title: "Navigate", shortcuts: [
            Shortcut("→ Space N PgDn", "Next build") { _ = $0.perform(.command(.next)) },
            Shortcut("← P PgUp", "Previous build") { _ = $0.perform(.command(.previous)) },
            Shortcut("⇧→", "Next frame") { _ = $0.perform(.command(.nextFrame)) },
            Shortcut("⇧←", "Previous frame") { _ = $0.perform(.command(.previousFrame)) },
            Shortcut("3 1 ⏎", "Go to frame 31"),
            Shortcut("⌫  ⌘[", "Back after a jump") { _ = $0.perform(.command(.back)) },
            Shortcut("Tab", "Overview on / off") { _ = $0.perform(.toggleOverview) },
            Shortcut("⌘F", "Search the deck") { _ = $0.perform(.focusSearch) },
            Shortcut("Esc", "Close overview / preview") { _ = $0.perform(.escape) },
        ])],
        [ShortcutGroup(title: "Audience", shortcuts: [
            Shortcut("B", "Black screen") { _ = $0.perform(.toggleAudience(.black)) },
            Shortcut("W", "White screen") { _ = $0.perform(.toggleAudience(.white)) },
            Shortcut("F", "Freeze the audience view") { _ = $0.perform(.toggleFreeze) },
            Shortcut("⌥⌘P", "Start presenting") { _ = $0.perform(.startPresenting) },
            Shortcut("Esc Esc", "End presenting") { $0.endPresenting() },
            Shortcut("⌘D", "Swap displays") { _ = $0.perform(.swapDisplays) },
        ]),
         ShortcutGroup(title: "App", shortcuts: [
            Shortcut("⌃⌘F", "Full screen") { $0.toggleFullScreen() },
            Shortcut("⌘/  ?", "This card") { $0.setShortcutOverlay(visible: false) },
            Shortcut("⌘,", "Settings") { $0.showSettings() },
            Shortcut("⌘O", "Open a deck") { $0.openPanel() },
            Shortcut("⌘W", "Close the deck") { $0.close() },
        ])],
        [ShortcutGroup(title: "Tools", shortcuts: [
            Shortcut("L", "Laser pointer") { _ = $0.perform(.togglePointer) },
            Shortcut("D", "Draw on the slide") { _ = $0.perform(.toggleDraw) },
            Shortcut("C", "Clear drawing, tools off") { _ = $0.perform(.command(.clearInk)) },
            Shortcut("T", "Start / pause the timer") { _ = $0.perform(.toggleTimer) },
            Shortcut("⌥T", "Reset the timer") { _ = $0.perform(.resetTimer) },
            Shortcut("⌘E", "Edit notes") { _ = $0.perform(.editNotes) },
            Shortcut("⌘+  ⌘−", "Notes size"),
            Shortcut("⌘R", "Reload the deck") { $0.presentation?.reloadDocument() },
        ])],
    ]

    static var groups: [ShortcutGroup] { columns.flatMap { $0 } }

    /// The row whose description is `action`, for the self-test.
    static func shortcut(named action: String) -> Shortcut? {
        groups.flatMap(\.shortcuts).first { $0.action == action }
    }
}

/// The keyboard-shortcut card. ⌘/ or ? (Help ▸ Keyboard Shortcuts) toggles it; it stays until Esc, a row click
/// (which runs that command), a click on the backdrop, or the app going to the background. The backdrop takes
/// the click so nothing underneath, such as a slide, reacts to it.
struct ShortcutOverlay: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { model.setShortcutOverlay(visible: false) }
            VStack(spacing: 18) {
                Text("Keyboard shortcuts").font(.system(size: 24, weight: .semibold, design: .rounded))
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(ShortcutReference.columns.enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(column) { group in
                                Text(group.title.uppercased())
                                    .font(.system(size: Theme.small, weight: .bold)).foregroundStyle(.secondary)
                                    .padding(.top, group.id == column.first?.id ? 0 : 14)
                                    .padding(.bottom, 4).padding(.horizontal, 8)
                                ForEach(group.shortcuts) { shortcut in
                                    ShortcutRow(shortcut: shortcut, model: model)
                                }
                            }
                        }
                    }
                }
                Text("Click a shortcut to run it. ⌘/ or ?, Esc, or a click outside closes this card.")
                    .font(.system(size: Theme.small)).foregroundStyle(.tertiary)
            }
            .padding(24)
            .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
            .onTapGesture {}   // clicks on the card itself (between rows) stay on the card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShortcutRow: View {
    let shortcut: Shortcut
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        let clickable = shortcut.perform != nil
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(shortcut.keys)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 140, alignment: .trailing)
                .fixedSize()
            Text(shortcut.action).font(.system(size: 16)).fixedSize()
        }
        .padding(.vertical, 3).padding(.horizontal, 8)
        // Opaque, so the slide behind the card does not show through the highlighted row (feedback round 3).
        .background(hovering && clickable ? Color(white: 0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        if clickable {
            Button { model.run(shortcut) } label: { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .accessibilityLabel(shortcut.action)
        } else {
            content
        }
    }
}
