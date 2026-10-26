import Foundation
import PresenterProtocol

/// Per-deck persistence (SPEC §3.4): `<deck>.lectern.json`. Versioned; unknown keys are ignored and missing
/// keys take defaults, so older and newer apps can share a file. A bad file never prevents opening a deck.
public struct SidecarDocument: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int = SidecarDocument.currentVersion
    public var settings = Settings()
    /// Notes authored in the app, keyed by frame label plus page index.
    public var notes: [UserNote] = []
    /// Persistent ink per page (SPEC §8).
    public var ink: [PageInk] = []
    public var whiteboards: [Whiteboard] = []
    public var rehearsal = Rehearsal()

    public init() {}

    public struct Settings: Codable, Hashable, Sendable {
        /// Second-screen notes layout; nil when never decided.
        public var notesSplit: NotesSplit?
        /// True once the user answered the one-time question (SPEC §5.1.4).
        public var notesSplitConfirmed = false
        public var targetDuration: TimeInterval?
        public var endOfTalkPage: Int?
        public var sectionTargets: [SectionTarget] = []

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            notesSplit = try c.decodeIfPresent(NotesSplit.self, forKey: .notesSplit)
            notesSplitConfirmed = try c.decodeIfPresent(Bool.self, forKey: .notesSplitConfirmed) ?? false
            targetDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .targetDuration)
            endOfTalkPage = try c.decodeIfPresent(Int.self, forKey: .endOfTalkPage)
            sectionTargets = try c.decodeIfPresent([SectionTarget].self, forKey: .sectionTargets) ?? []
        }
    }

    public struct SectionTarget: Codable, Hashable, Sendable {
        public var frameLabel: String
        public var elapsedAtEnd: TimeInterval
        public init(frameLabel: String, elapsedAtEnd: TimeInterval) { self.frameLabel = frameLabel; self.elapsedAtEnd = elapsedAtEnd }
    }

    public struct UserNote: Codable, Hashable, Sendable {
        public var frameLabel: String
        public var pageIndex: Int
        public var text: String
        public init(frameLabel: String, pageIndex: Int, text: String) { self.frameLabel = frameLabel; self.pageIndex = pageIndex; self.text = text }
    }

    public struct PageInk: Codable, Hashable, Sendable {
        public var pageIndex: Int
        public var strokes: [InkStroke]
        public init(pageIndex: Int, strokes: [InkStroke]) { self.pageIndex = pageIndex; self.strokes = strokes }
    }

    public struct Whiteboard: Codable, Hashable, Sendable {
        public enum Style: String, Codable, Hashable, Sendable { case white, grid }
        public var id: UUID
        public var afterPage: Int
        public var style: Style
        public init(id: UUID = UUID(), afterPage: Int, style: Style) { self.id = id; self.afterPage = afterPage; self.style = style }
    }

    public struct Rehearsal: Codable, Hashable, Sendable {
        public struct Position: Codable, Hashable, Sendable {
            public var frameLabel: String
            public var pageIndex: Int
            public init(frameLabel: String, pageIndex: Int) { self.frameLabel = frameLabel; self.pageIndex = pageIndex }
        }
        public struct Log: Codable, Hashable, Sendable {
            public struct Entry: Codable, Hashable, Sendable {
                public var pageIndex: Int
                public var seconds: TimeInterval
                public init(pageIndex: Int, seconds: TimeInterval) { self.pageIndex = pageIndex; self.seconds = seconds }
            }
            public var date: Date
            public var entries: [Entry]
            public init(date: Date, entries: [Entry]) { self.date = date; self.entries = entries }
        }
        public var lastPosition: Position?
        public var logs: [Log] = []

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lastPosition = try c.decodeIfPresent(Position.self, forKey: .lastPosition)
            logs = try c.decodeIfPresent([Log].self, forKey: .logs) ?? []
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        notes = try c.decodeIfPresent([UserNote].self, forKey: .notes) ?? []
        ink = try c.decodeIfPresent([PageInk].self, forKey: .ink) ?? []
        whiteboards = try c.decodeIfPresent([Whiteboard].self, forKey: .whiteboards) ?? []
        rehearsal = try c.decodeIfPresent(Rehearsal.self, forKey: .rehearsal) ?? Rehearsal()
    }

    // MARK: - Convenience

    public func userNote(forPage page: Int) -> UserNote? {
        notes.first { $0.pageIndex == page }
    }

    public mutating func setUserNote(_ text: String, forPage page: Int, frameLabel: String) {
        notes.removeAll { $0.pageIndex == page }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { notes.append(UserNote(frameLabel: frameLabel, pageIndex: page, text: text)) }
        notes.sort { $0.pageIndex < $1.pageIndex }
    }

    /// User notes by page, for the merger.
    public var notesByPage: [Int: String] {
        Dictionary(notes.map { ($0.pageIndex, $0.text) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Beamer second-screen layout (SPEC §5.1.4): which part of each page is the slide.
public enum NotesSplit: String, Codable, Hashable, Sendable, CaseIterable {
    case none, left, right, top, bottom

    /// The crop the audience (and the presenter's slide panes) use.
    public var slideCrop: CropRect {
        switch self {
        case .none: .full
        case .left: .rightHalf     // notes on the left, slide on the right
        case .right: .leftHalf
        case .top: .bottomHalf
        case .bottom: .topHalf
        }
    }

    /// The crop that shows the notes panel, nil when there is none.
    public var notesCrop: CropRect? {
        switch self {
        case .none: nil
        case .left: .leftHalf
        case .right: .rightHalf
        case .top: .topHalf
        case .bottom: .bottomHalf
        }
    }
}
