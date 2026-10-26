import Foundation

/// User preferences that change how navigation commands move (Settings → Going back).
public struct NavigationOptions: Hashable, Sendable {
    /// `previous` at the first build of a frame lands on the previous frame's *first* build instead of its last
    /// (the SPEC §3.2 default, which steps back through every build). Inside a frame it still steps one build.
    public var previousLandsOnFrameStart: Bool

    public init(previousLandsOnFrameStart: Bool = false) {
        self.previousLandsOnFrameStart = previousLandsOnFrameStart
    }
}
