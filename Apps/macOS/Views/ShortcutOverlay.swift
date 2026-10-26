import SwiftUI

struct Shortcut: Identifiable {
    let keys: String
    let action: String
    var id: String { keys + action }
}

struct ShortcutGroup: Identifiable {
    let title: String
    let shortcuts: [Shortcut]
    var id: String { title }
}

/// What the hold-⌘ overlay lists. Mirrors `KeyMap` and `MainMenu`; keep the three in step.
enum ShortcutReference {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Navigate", shortcuts: [
            Shortcut(keys: "→ Space N PgDn", action: "Next build"),
            Shortcut(keys: "← P PgUp", action: "Previous build"),
            Shortcut(keys: "⇧→  ⇧←", action: "Next / previous frame"),
            Shortcut(keys: "3 1 ⏎", action: "Go to frame 31"),
            Shortcut(keys: "⌫  ⌘[", action: "Back to where you jumped from"),
            Shortcut(keys: "Tab", action: "Overview on / off"),
            Shortcut(keys: "⌘F", action: "Search the deck"),
            Shortcut(keys: "Esc", action: "Close overview, cancel preview"),
        ]),
        ShortcutGroup(title: "Audience", shortcuts: [
            Shortcut(keys: "B  .", action: "Black screen"),
            Shortcut(keys: "W", action: "White screen"),
            Shortcut(keys: "F", action: "Freeze what the audience sees"),
            Shortcut(keys: "⌥⌘P", action: "Start presenting"),
            Shortcut(keys: "Esc Esc", action: "End presenting"),
            Shortcut(keys: "⌥⌘D", action: "Swap displays"),
        ]),
        ShortcutGroup(title: "Tools", shortcuts: [
            Shortcut(keys: "L", action: "Laser pointer"),
            Shortcut(keys: "D", action: "Pen"),
            Shortcut(keys: "E", action: "Clear ink"),
            Shortcut(keys: "T  ⌥T", action: "Start / pause timer, reset"),
            Shortcut(keys: "⌘E", action: "Edit notes"),
            Shortcut(keys: "⌘+  ⌘−", action: "Notes size"),
            Shortcut(keys: "⌘R", action: "Reload the deck"),
            Shortcut(keys: "⌘O  ⌘W", action: "Open / close a deck"),
            Shortcut(keys: "⌘,", action: "Settings"),
        ]),
    ]
}

/// Translucent reference card shown while ⌘ is held (feedback round 1). Purely visual; it never takes input.
struct ShortcutOverlay: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Keyboard shortcuts").font(.system(size: 26, weight: .semibold, design: .rounded))
            HStack(alignment: .top, spacing: 32) {
                ForEach(ShortcutReference.groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(group.title.uppercased())
                            .font(.system(size: Theme.small, weight: .bold)).foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                        ForEach(group.shortcuts) { shortcut in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(shortcut.keys)
                                    .font(.system(size: Theme.body, weight: .semibold, design: .rounded))
                                    .frame(width: 170, alignment: .trailing)
                                    .fixedSize()
                                Text(shortcut.action).font(.system(size: Theme.body)).fixedSize()
                            }
                        }
                    }
                }
            }
            Text("Release ⌘ to dismiss. Turn this off in Settings (⌘,).").font(.system(size: Theme.small)).foregroundStyle(.tertiary)
        }
        .padding(30)
        .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
