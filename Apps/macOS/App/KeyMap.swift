import AppKit
import PresenterProtocol

/// Default key map (SPEC §6.5), including what clickers send: Page Up/Down, B or `.`, F5 and Esc.
enum KeyMap {
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
            case .downArrow, .pageDown: return .command(.next)
            case .upArrow, .pageUp: return .command(.previous)
            case .carriageReturn, .enter: return .command(.next)   // M2: digits + Return jumps instead
            case .delete, .backspace, .deleteForward: return .command(.back)
            case .f5: return .startPresenting
            default: return nil
            }
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased(), let key = characters.first else { return nil }
        if key == "\u{1b}" { return .escape }
        if command && option {
            switch key {
            case "d": return .swapDisplays
            case "p": return .startPresenting
            default: return nil
            }
        }
        if command {
            return key == "[" ? .command(.back) : nil   // other ⌘ shortcuts belong to the menu
        }
        switch key {
        case " ", "n": return .command(.next)
        case "p": return .command(.previous)
        case "b", ".": return .toggleAudience(.black)
        case "w": return .toggleAudience(.white)
        case "f": return .toggleFreeze
        case "t": return option ? .resetTimer : .toggleTimer
        default: return nil
        }
    }
}
