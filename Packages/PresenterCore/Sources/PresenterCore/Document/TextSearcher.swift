import Foundation
import PDFKit

/// One search hit, grouped by frame in the UI (SPEC §4.4).
public struct SearchHit: Hashable, Sendable, Identifiable {
    public let id: Int
    public let pageIndex: Int
    public let frameIndex: Int
    public let snippet: String
}

/// Full-text search over PDFKit's text layer. Owns its own `PDFDocument` because PDFKit is not thread-safe,
/// and caches page text so repeated searches of a 400-page deck stay quick.
public actor TextSearcher {
    private final class DocumentBox: @unchecked Sendable {
        let document: PDFDocument?
        init(url: URL) { document = PDFDocument(url: url) }
    }

    private let box: DocumentBox
    private let frames: FrameIndex
    private var pageText: [Int: String] = [:]

    public init(url: URL, frames: FrameIndex) {
        self.box = DocumentBox(url: url)
        self.frames = frames
    }

    public func text(ofPage index: Int) -> String {
        if let cached = pageText[index] { return cached }
        let text = box.document?.page(at: index)?.string ?? ""
        pageText[index] = text
        return text
    }

    /// Case- and diacritic-insensitive substring search; at most `limit` hits, in page order.
    public func search(_ query: String, limit: Int = 300) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let document = box.document else { return [] }
        var hits: [SearchHit] = []
        for page in 0..<min(document.pageCount, frames.pageCount) {
            let text = self.text(ofPage: page)
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                hits.append(SearchHit(id: hits.count, pageIndex: page, frameIndex: frames.frame(containing: page).index,
                                      snippet: TextSearcher.snippet(of: text, around: range)))
                if hits.count >= limit { return hits }
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return hits
    }

    static func snippet(of text: String, around range: Range<String.Index>, context: Int = 40) -> String {
        let start = text.index(range.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
        var s = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { s = "…" + s }
        if end < text.endIndex { s += "…" }
        return s
    }
}
