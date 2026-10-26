import AppKit
import PresenterProtocol
import Testing
@testable import Lectern

@MainActor
private func key(_ characters: String, keyCode: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
}

@Suite struct KeyMapping {
    @MainActor @Test func clickerKeys() {
        #expect(KeyMap.action(for: key("\u{F72D}")) == .command(.next))       // Page Down
        #expect(KeyMap.action(for: key("\u{F72C}")) == .command(.previous))   // Page Up
        #expect(KeyMap.action(for: key("b")) == .toggleAudience(.black))
        #expect(KeyMap.action(for: key(".")) == .toggleAudience(.black))
        #expect(KeyMap.action(for: key("\u{F708}")) == .startPresenting)      // F5
        #expect(KeyMap.action(for: key("\u{1b}")) == .escape)
    }

    @MainActor @Test func navigationKeys() {
        #expect(KeyMap.action(for: key("\u{F703}")) == .command(.next))
        #expect(KeyMap.action(for: key("\u{F703}", modifiers: .shift)) == .command(.nextFrame))
        #expect(KeyMap.action(for: key("\u{F702}", modifiers: .shift)) == .command(.previousFrame))
        #expect(KeyMap.action(for: key(" ")) == .command(.next))
        #expect(KeyMap.action(for: key("\r")) == .command(.next))
        #expect(KeyMap.action(for: key("n")) == .command(.next))
        #expect(KeyMap.action(for: key("p")) == .command(.previous))
        #expect(KeyMap.action(for: key("\u{7f}")) == .command(.back))
        #expect(KeyMap.action(for: key("[", modifiers: .command)) == .command(.back))
    }

    @MainActor @Test func timerAndDisplays() {
        #expect(KeyMap.action(for: key("t")) == .toggleTimer)
        #expect(KeyMap.action(for: key("t", modifiers: .option)) == .resetTimer)
        #expect(KeyMap.action(for: key("d", modifiers: [.command, .option])) == .swapDisplays)
        #expect(KeyMap.action(for: key("p", modifiers: [.command, .option])) == .startPresenting)
        #expect(KeyMap.action(for: key("f")) == .toggleFreeze)
        #expect(KeyMap.action(for: key("w")) == .toggleAudience(.white))
    }

    @MainActor @Test func unmappedKeysPassThrough() {
        #expect(KeyMap.action(for: key("x")) == nil)
        #expect(KeyMap.action(for: key("o", modifiers: .command)) == nil)
        #expect(KeyMap.action(for: key("n", modifiers: .control)) == nil)
    }
}
