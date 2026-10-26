import AppKit

/// Builds the main menu programmatically (nib-less app). Unmodified single keys (→, B, T …) are handled by
/// `KeyMap`, not by menu key equivalents, so they also work when a clicker sends them; the titles show them.
@MainActor
enum MainMenu {
    static func build(target: AppDelegate) -> (menu: NSMenu, recents: NSMenu) {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lectern", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Lectern", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Lectern", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Lectern")

        let file = NSMenu(title: "File")
        file.addItem(item("Open…", #selector(AppDelegate.openDocument(_:)), "o", target))
        let recents = NSMenu(title: "Open Recent")
        let recentsItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentsItem.submenu = recents
        file.addItem(recentsItem)
        file.addItem(.separator())
        file.addItem(item("Close Deck", #selector(AppDelegate.closeDocument(_:)), "w", target))
        main.addItem(submenu: file, title: "File")

        let presentation = NSMenu(title: "Presentation")
        presentation.addItem(item("Start Presenting", #selector(AppDelegate.startPresenting(_:)), "p", target, modifiers: [.command, .option]))
        presentation.addItem(item("End Presenting (Esc Esc)", #selector(AppDelegate.endPresenting(_:)), "", target))
        presentation.addItem(item("Swap Displays", #selector(AppDelegate.swapDisplays(_:)), "d", target, modifiers: [.command, .option]))
        presentation.addItem(item("Show Audience Window (rehearsal)", #selector(AppDelegate.toggleRehearsalAudienceWindow(_:)), "", target))
        presentation.addItem(item("Open Displays Settings…", #selector(AppDelegate.openDisplaySettings(_:)), "", target))
        presentation.addItem(.separator())
        presentation.addItem(item("Next Build (→, Space, Page Down)", #selector(AppDelegate.nextBuild(_:)), "", target))
        presentation.addItem(item("Previous Build (←, Page Up)", #selector(AppDelegate.previousBuild(_:)), "", target))
        presentation.addItem(item("Next Frame (⇧→)", #selector(AppDelegate.nextFrame(_:)), "", target))
        presentation.addItem(item("Previous Frame (⇧←)", #selector(AppDelegate.previousFrame(_:)), "", target))
        presentation.addItem(item("Back (Delete)", #selector(AppDelegate.goBack(_:)), "[", target))
        presentation.addItem(.separator())
        presentation.addItem(item("Black Screen (B)", #selector(AppDelegate.toggleBlack(_:)), "", target))
        presentation.addItem(item("White Screen (W)", #selector(AppDelegate.toggleWhite(_:)), "", target))
        presentation.addItem(item("Freeze Audience (F)", #selector(AppDelegate.toggleFreeze(_:)), "", target))
        presentation.addItem(.separator())
        presentation.addItem(item("Pointer Mode (L)", #selector(AppDelegate.togglePointer(_:)), "", target))
        presentation.addItem(item("Draw Mode (D)", #selector(AppDelegate.toggleDraw(_:)), "", target))
        presentation.addItem(item("Clear Ink (E)", #selector(AppDelegate.clearInk(_:)), "", target))
        presentation.addItem(.separator())
        presentation.addItem(item("Edit Notes", #selector(AppDelegate.editNotes(_:)), "e", target))
        presentation.addItem(item("Bigger Notes", #selector(AppDelegate.notesLarger(_:)), "=", target))
        presentation.addItem(item("Smaller Notes", #selector(AppDelegate.notesSmaller(_:)), "-", target))
        presentation.addItem(item("Reload Deck Now", #selector(AppDelegate.reloadDeck(_:)), "r", target))
        presentation.addItem(.separator())
        presentation.addItem(item("Start/Pause Timer (T)", #selector(AppDelegate.toggleTimer(_:)), "", target))
        presentation.addItem(item("Reset Timer (⌥T)", #selector(AppDelegate.resetTimer(_:)), "", target))
        let durations = NSMenu(title: "Target Duration")
        for minutes in [0, 15, 20, 30, 45, 60, 90] {
            let i = item(minutes == 0 ? "None" : "\(minutes) minutes", #selector(AppDelegate.setTargetDuration(_:)), "", target)
            i.representedObject = minutes
            durations.addItem(i)
        }
        durations.addItem(.separator())
        durations.addItem(item("Custom…", #selector(AppDelegate.setTargetDuration(_:)), "", target))
        let durationsItem = NSMenuItem(title: "Target Duration", action: nil, keyEquivalent: "")
        durationsItem.submenu = durations
        presentation.addItem(durationsItem)
        main.addItem(submenu: presentation, title: "Presentation")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        return (main, recents)
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, _ target: AnyObject,
                             modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
