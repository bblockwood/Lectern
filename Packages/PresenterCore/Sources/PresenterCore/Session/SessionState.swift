import Foundation
import PresenterProtocol

public struct PointerState: Hashable, Sendable {
    public var position: NormalizedPoint
    public var updatedAt: Date
    public init(position: NormalizedPoint, updatedAt: Date) { self.position = position; self.updatedAt = updatedAt }
}

/// A stroke in normalised slide coordinates with its width relative to the slide height (SPEC §8).
public struct InkStroke: Codable, Hashable, Sendable {
    public struct Color: Codable, Hashable, Sendable {
        public var red: Double, green: Double, blue: Double, alpha: Double
        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
        public static let red = Color(red: 0.9, green: 0.1, blue: 0.1)
    }

    public var points: [NormalizedPoint]
    public var mode: InkMode
    public var startedAt: Date
    /// Line width as a fraction of the slide height.
    public var width: Double
    public var color: Color

    public init(points: [NormalizedPoint], mode: InkMode, startedAt: Date, width: Double = 0.006, color: Color = .red) {
        self.points = points; self.mode = mode; self.startedAt = startedAt; self.width = width; self.color = color
    }
}

public struct InkState: Hashable, Sendable {
    /// Finished strokes on the visible page.
    public var strokes: [InkStroke] = []
    /// Stroke being drawn.
    public var active: InkStroke? = nil
    public init() {}
}

public struct DisplayConfig: Hashable, Sendable {
    /// Identifier of the display carrying the audience window (app-defined string), nil in rehearsal mode.
    public var audienceDisplayID: String? = nil
    public var presenterDisplayID: String? = nil
    public var isPresenting: Bool = false
    public init() {}
}

/// Single source of truth (SPEC §3.2). Every view renders from this; only `SessionController` mutates it.
public struct SessionState: Hashable, Sendable {
    /// What the audience sees (when `audienceMode` is `.live`).
    public var committedPage: Int = 0
    /// Presenter-only preview; nil when not browsing.
    public var browsePage: Int? = nil
    public var audienceMode: AudienceMode = .live
    public var pointer: PointerState? = nil
    public var ink: InkState = InkState()
    /// Back stack of page indices from jumps (links, jump-by-number, committed browses).
    public var history: [Int] = []
    /// Pages `back` left, for the GoForward named action. Cleared by any new jump.
    public var forwardHistory: [Int] = []
    public var timer: TimerState = TimerState()
    public var displayConfig: DisplayConfig = DisplayConfig()

    public init() {}

    /// The page the presenter's current-slide pane shows.
    public var presenterPage: Int { browsePage ?? committedPage }
    /// Where `back` would go: the latest history entry that is not the page already shown (feedback round 7).
    public var backTarget: Int? { history.last(where: { $0 != committedPage }) }
    /// Where `forward` would go.
    public var forwardTarget: Int? { forwardHistory.last(where: { $0 != committedPage }) }
    public var isBrowsing: Bool { browsePage != nil }

    /// The page the audience surface shows, or nil for black/white.
    public var audiencePage: Int? {
        switch audienceMode {
        case .live: return committedPage
        case .frozen(let page): return page
        case .black, .white: return nil
        }
    }
}
