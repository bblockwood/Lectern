import AppKit
import PresenterProtocol

/// Default key map (SPEC §6.5), including what clickers send: Page Up/Down, B or `.`, F5 and Esc.
enum KeyMap {
    static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}"
    }

    static func action(for event: NSEvent) -> AppAction? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = modifiers.contains(.shift)
        let command = modifiers.contains(.command)
        let option = modifiers.contains(.option)
        if modifiers.contains(.control) { return nil }

        if let special = event.specialKey {
            switch special {
            case .rightArrow: return .command(shift ? .nextFrame : .next)
            case .leftArrow: return .command(shift ? .previousFrame : .previous)
            case .pageDown: return .command(.next)
            case .pageUp: return .command(.previous)
            case .downArrow: return .verticalArrow(up: false)
            case .upArrow: return .verticalArrow(up: true)
            case .carriageReturn, .enter: return .returnKey
            case .delete, .backspace, .deleteForward: return .command(.back)
            case .f5: return .startPresenting
            case .tab, .backTab: return .toggleOverview
            default: return nil
            }
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased(), let key = characters.first else { return nil }
        if key == "\u{1b}" { return .escape }
        if key == "\t" { return .toggleOverview }
        if key == "\r" || key == "\u{3}" { return .returnKey }
        if command && option {
            switch key {
            case "p": return .startPresenting
            default: return nil
            }
        }
        if command {
            switch key {
            case "d": return .swapDisplays   // ⌘D; ⌥⌘D is the system's Dock toggle (feedback round 4)
            case "/": return .toggleShortcutCard
            case "[": return .command(.back)
            case "f": return .focusSearch
            case "=", "+": return .notesFontLarger
            case "-": return .notesFontSmaller
            case "e": return .editNotes
            default: return nil   // other ⌘ shortcuts belong to the menu
            }
        }
        if key.isNumber, !shift, !option { return .digit(key) }
        switch key {
        case " ", "n": return .command(.next)
        case "p": return .command(.previous)
        case "b", ".": return .toggleAudience(.black)
        case "w": return .toggleAudience(.white)
        case "f": return .toggleFreeze
        case "t": return option ? .resetTimer : .toggleTimer
        case "?": return .toggleShortcutCard
        case "l": return .togglePointer
        case "d": return .toggleDraw
        case "c": return .command(.clearInk)
        default: return nil
        }
    }
}
