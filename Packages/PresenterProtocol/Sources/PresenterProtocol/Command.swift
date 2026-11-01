import Foundation

/// Every input (keyboard, clicker, mouse, touch, Pencil, iPhone, Watch) becomes a `Command`
/// and is applied by the one `SessionController` (SPEC §3.2). Codable so remotes can send it.
public enum Command: Codable, Hashable, Sendable {
    // Navigation. `next`/`previous` step one page (one build); the frame commands jump between frames.
    case next
    case previous
    case nextFrame
    case previousFrame
    case goToPage(Int)
    case goToFrameLabel(String)
    case followLink(LinkID)
    case back
    /// Returns to the page `back` left (⌘]); the Back / Forward buttons under the slide (feedback round 7).
    case forward

    // Private browsing on the presenter screen (SPEC §6.3).
    case beginBrowse
    case browseTo(Int)
    case commitBrowse
    case cancelBrowse

    // Audience surface.
    case setAudienceMode(AudienceMode)

    // Pointer.
    case pointerMove(NormalizedPoint)
    case pointerHide

    // Ink.
    case inkBegin(NormalizedPoint, InkMode)
    case inkAppend(NormalizedPoint)
    case inkEnd
    case clearInk
    case insertWhiteboard

    // Timer.
    case timerStart
    case timerPause
    case timerReset
}

/// Identifies a link annotation on a page: the page index and the link's position in that page's link list.
public struct LinkID: Codable, Hashable, Sendable {
    public var page: Int
    public var index: Int
    public init(page: Int, index: Int) { self.page = page; self.index = index }
}

/// What the audience display shows (SPEC §3.2).
public enum AudienceMode: Codable, Hashable, Sendable {
    case live
    case frozen(page: Int)
    case black
    case white
}

public enum InkMode: String, Codable, Hashable, Sendable {
    case ephemeral
    case persistent
}

/// A point in the slide's crop rect, 0...1 on both axes, origin top-left (SPEC §8).
public struct NormalizedPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
