import Foundation

/// A frame is a maximal run of consecutive pages with identical page labels (SPEC §4.1).
public struct Frame: Hashable, Sendable {
    /// 0-based position of the frame in the deck.
    public let index: Int
    /// The page label shared by the frame's pages. For label-less PDFs this is the 1-based page number.
    public let label: String
    /// Page indices (0-based) belonging to the frame, always non-empty and consecutive.
    public let pages: Range<Int>

    public var firstPage: Int { pages.lowerBound }
    public var lastPage: Int { pages.upperBound - 1 }
    public var buildCount: Int { pages.count }
}

/// Maps pages to frames and back. Pure data; built once per document.
public struct FrameIndex: Hashable, Sendable {
    public let frames: [Frame]
    private let frameOfPage: [Int]

    public var pageCount: Int { frameOfPage.count }
    public var frameCount: Int { frames.count }

    /// `labels[i]` is page i's label, or nil when the PDF defines no label for it.
    public init(labels: [String?]) {
        let frames = FrameIndex.group(labels: labels)
        var frameOfPage = [Int](repeating: 0, count: labels.count)
        for frame in frames {
            for page in frame.pages { frameOfPage[page] = frame.index }
        }
        self.frames = frames
        self.frameOfPage = frameOfPage
    }

    /// Consecutive pages with the same non-nil label form one frame; a nil label never joins a run,
    /// so a label-less PDF (or one where every label is unique) yields one frame per page.
    public static func group(labels: [String?]) -> [Frame] {
        var frames: [Frame] = []
        var start = 0
        while start < labels.count {
            var end = start + 1
            if let label = labels[start] {
                while end < labels.count, labels[end] == label { end += 1 }
            }
            let label = labels[start] ?? String(start + 1)
            frames.append(Frame(index: frames.count, label: label, pages: start..<end))
            start = end
        }
        return frames
    }

    public func frame(containing page: Int) -> Frame {
        frames[frameOfPage[clamp(page)]]
    }

    /// 0-based position of the page within its frame.
    public func buildIndex(of page: Int) -> Int {
        let p = clamp(page)
        return p - frames[frameOfPage[p]].firstPage
    }

    public func frame(withLabel label: String) -> Frame? {
        frames.first { $0.label == label }
    }

    /// First page of the frame after the one containing `page`, or nil in the last frame.
    public func nextFrameFirstPage(after page: Int) -> Int? {
        let f = frame(containing: page)
        guard f.index + 1 < frames.count else { return nil }
        return frames[f.index + 1].firstPage
    }

    /// Last page of the frame before the one containing `page`, so it arrives fully built (pdfpc behaviour).
    public func previousFrameLastPage(before page: Int) -> Int? {
        let f = frame(containing: page)
        guard f.index > 0 else { return nil }
        return frames[f.index - 1].lastPage
    }

    private func clamp(_ page: Int) -> Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }
}
