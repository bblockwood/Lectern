import CoreGraphics
import Foundation
import Testing
@testable import PresenterCore

@Suite struct FrameGrouping {
    @Test func consecutiveEqualLabelsFormOneFrame() {
        let frames = FrameIndex.group(labels: ["1", "2", "2", "2", "3", "3", "4"])
        #expect(frames.map(\.label) == ["1", "2", "3", "4"])
        #expect(frames.map(\.pages) == [0..<1, 1..<4, 4..<6, 6..<7])
        #expect(frames.map(\.index) == [0, 1, 2, 3])
    }

    @Test func noLabelsMeansOneFramePerPage() {
        let frames = FrameIndex.group(labels: [nil, nil, nil])
        #expect(frames.count == 3)
        #expect(frames.map(\.label) == ["1", "2", "3"])
    }

    @Test func uniqueLabelsMeansOneFramePerPage() {
        let frames = FrameIndex.group(labels: ["i", "ii", "1", "2"])
        #expect(frames.count == 4)
    }

    @Test func nilLabelsNeverJoinARun() {
        let frames = FrameIndex.group(labels: ["2", nil, nil, "2"])
        #expect(frames.map(\.pages) == [0..<1, 1..<2, 2..<3, 3..<4])
        #expect(frames.map(\.label) == ["2", "2", "3", "2"])
    }

    @Test func nonConsecutiveEqualLabelsAreSeparateFrames() {
        let frames = FrameIndex.group(labels: ["5", "6", "5"])
        #expect(frames.count == 3)
    }

    @Test func navigationHelpers() {
        let index = FrameIndex(labels: ["1", "2", "2", "2", "3", "3"])
        #expect(index.frame(containing: 2).label == "2")
        #expect(index.buildIndex(of: 2) == 1)
        #expect(index.buildIndex(of: 0) == 0)
        #expect(index.nextFrameFirstPage(after: 1) == 4)
        #expect(index.nextFrameFirstPage(after: 5) == nil)
        #expect(index.previousFrameLastPage(before: 4) == 3)
        #expect(index.previousFrameLastPage(before: 0) == nil)
        #expect(index.frame(withLabel: "3")?.pages == 4..<6)
        #expect(index.frame(withLabel: "9") == nil)
    }

    @Test func emptyDocumentIsSafe() {
        let index = FrameIndex(labels: [])
        #expect(index.frameCount == 0)
        #expect(index.pageCount == 0)
    }
}

@Suite struct FixtureDocuments {
    @Test func overlaysGroupByLabel() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        #expect(doc.pageCount == 23)
        #expect(doc.hasPageLabels)
        #expect(doc.frames.frameCount == 9)
        #expect(doc.frames.frames.map(\.buildCount) == [1, 3, 4, 3, 2, 1, 3, 5, 1])
        #expect(doc.frames.frames.map(\.label) == (1...9).map(String.init))
        #expect(doc.pages[0].size.width > doc.pages[0].size.height) // 4:3 landscape
        #expect(abs(doc.pages[0].aspectRatio - 4.0 / 3.0) < 0.01)
    }

    @Test func basicDeckHasOneFramePerPage() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        #expect(doc.pageCount == 20)
        #expect(doc.frames.frameCount == 20)
        #expect(abs(doc.pages[3].aspectRatio - 16.0 / 9.0) < 0.01)
        #expect(doc.title == "Basic 16:9 deck - Fixture 1")
    }

    @Test func hugeDeck() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("huge.pdf"))
        #expect(doc.pageCount == 401)
        #expect(doc.frames.frameCount == 321)
    }

    @Test func appendixDoesNotRestartLabels() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("links-appendix.pdf"))
        #expect(doc.frames.frames.map(\.label) == (1...8).map(String.init))
    }

    @Test func malformedFailsCleanly() {
        #expect(throws: DocumentError.cannotOpen(Fixtures.url("malformed.pdf"))) {
            try PresentationDocument.load(url: Fixtures.url("malformed.pdf"))
        }
    }

    @Test func missingFileFailsCleanly() {
        let url = Fixtures.url("does-not-exist.pdf")
        #expect(throws: DocumentError.cannotOpen(url)) { try PresentationDocument.load(url: url) }
    }

    /// A PDF written by CoreGraphics has no /PageLabels tree: every page must be its own frame.
    @Test func labelLessPDFHasOneFramePerPage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lectern-nolabels-\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        for _ in 0..<3 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 10, y: 10, width: 100, height: 100))
            ctx.endPDFPage()
        }
        ctx.closePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try PresentationDocument.load(url: url)
        #expect(!doc.hasPageLabels)
        #expect(doc.pages.map(\.label) == [nil, nil, nil])
        #expect(doc.frames.frameCount == 3)
        #expect(doc.frames.frames.map(\.label) == ["1", "2", "3"])
    }
}
