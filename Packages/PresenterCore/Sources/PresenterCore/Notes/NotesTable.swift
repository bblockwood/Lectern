import Foundation

/// Where a note came from, in SPEC §5.1 priority order.
public enum NoteSource: String, Codable, Hashable, Sendable, CaseIterable {
    case sidecar, pdfpcFile, embedded, secondScreen, pptx

    public var displayName: String {
        switch self {
        case .sidecar: "your notes"
        case .pdfpcFile: ".pdfpc file"
        case .embedded: "PDF annotations"
        case .secondScreen: "Beamer notes"
        case .pptx: "PowerPoint notes"
        }
    }
}

public struct PageNote: Hashable, Sendable {
    public let text: String
    public let source: NoteSource
    public init(text: String, source: NoteSource) { self.text = text; self.source = source }
}

/// Merged notes per page. Earlier sources win per page (SPEC §5.1).
public struct NotesTable: Hashable, Sendable {
    public private(set) var byPage: [Int: PageNote]

    public init(byPage: [Int: PageNote] = [:]) { self.byPage = byPage }

    public static let empty = NotesTable()
    public var isEmpty: Bool { byPage.isEmpty }

    /// The page's own note, else its frame's (the closest earlier build, then any build) per SPEC §5.2.
    public func note(for page: Int, frames: FrameIndex) -> PageNote? {
        if let own = byPage[page] { return own }
        guard frames.pageCount > 0 else { return nil }
        let frame = frames.frame(containing: page)
        if let earlier = frame.pages.filter({ $0 < page }).reversed().lazy.compactMap({ byPage[$0] }).first { return earlier }
        return frame.pages.lazy.compactMap { byPage[$0] }.first
    }

    public mutating func set(_ note: PageNote?, forPage page: Int) {
        byPage[page] = note
    }
}

public enum NotesMerger {
    /// Layers in priority order; blank texts never shadow lower layers.
    public static func merge(_ layers: [(source: NoteSource, notes: [Int: String])]) -> NotesTable {
        var byPage: [Int: PageNote] = [:]
        for layer in layers {
            for (page, text) in layer.notes where byPage[page] == nil {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { byPage[page] = PageNote(text: text, source: layer.source) }
            }
        }
        return NotesTable(byPage: byPage)
    }
}
