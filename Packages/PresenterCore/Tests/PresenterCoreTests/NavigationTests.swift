import Foundation
import PresenterProtocol
import Testing
@testable import PresenterCore

@Suite struct LinksAndOutline {
    @Test func fixtureSixLinksResolve() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("links-appendix.pdf"))
        let links = doc.links(onPage: 1)
        let actions = links.map(\.action)
        #expect(actions.contains(.goToPage(7)), "\\hyperlink{backup-proof} resolves to page 8")
        #expect(actions.contains(.goToPage(8)), "\\hyperlink{backup-data} resolves to page 9")
        for named in [NamedAction.nextPage, .previousPage, .firstPage, .lastPage, .goBack, .goForward, .goToPage, .find] {
            #expect(actions.contains(.named(named)), "missing named action \(named)")
        }
        #expect(actions.contains(.uri(URL(string: "https://example.org/")!)))
        #expect(links.allSatisfy { $0.rect.x >= 0 && $0.rect.y >= 0 && $0.rect.x + $0.rect.width <= 1.001 && $0.rect.y + $0.rect.height <= 1.001 })
        // The explicit NextPage button sits in the lower half of the slide (y measured from the top).
        let next = try #require(links.first { $0.action == .named(.nextPage) })
        #expect(next.rect.y > 0.4 && next.rect.y < 0.6, "got \(next.rect)")
        #expect(next.rect.x > 0.2 && next.rect.x < 0.3)
        // Navigation-bar links sit at the very bottom.
        let bar = try #require(links.first { $0.action == .named(.find) })
        #expect(bar.rect.y > 0.95)
        #expect(doc.link(LinkID(page: 1, index: links.count - 1))?.action == .uri(URL(string: "https://example.org/")!))
        #expect(doc.link(LinkID(page: 1, index: 999)) == nil)
    }

    @Test func fixtureSixOutlineAndAppendix() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("links-appendix.pdf"))
        #expect(doc.outline.roots.map(\.title) == ["Introduction", "Results", "Conclusion", "Appendix"])
        #expect(doc.outline.roots[1].children.map(\.title) == ["Main result", "Discussion"])
        #expect(doc.outline.roots[1].children[1].pageIndex == 5)
        #expect(doc.outline.appendixEntry()?.pageIndex == 7)
        #expect(doc.endOfTalkPage == 6, "last page of the main talk is the Conclusion, page 7")
        #expect(doc.isAppendix(page: 7) && !doc.isAppendix(page: 6))
        #expect(doc.mainTalkFrameCount == 5)
        #expect(doc.pdfpc == nil)
    }

    @Test func pdfpcMetadataWinsOverOutline() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("pdfpc-notes.pdf"))
        let meta = try #require(doc.pdfpc)
        #expect(meta.durationMinutes == 30)
        #expect(meta.endUserSlide == 5)
        #expect(meta.lastMinutes == 5)
        #expect(meta.notesPosition == "none")
        #expect(meta.disableMarkdown == false)
        #expect(meta.targetDuration == 1800)
        // Frame 5 is page index 7; the outline's Appendix entry (page 9) would say 8.
        #expect(doc.outline.appendixEntry()?.pageIndex == 8)
        #expect(doc.endOfTalkPage == 7)
        #expect(doc.mainTalkFrameCount == 5)
    }

    @Test func xmpParsing() {
        let xmp = """
        <rdf:Description xmlns:pdfpc="https://github.com/pdfpc/pdfpc">
          <pdfpc:Duration>45</pdfpc:Duration>
          <pdfpc:EndUserSlide></pdfpc:EndUserSlide>
          <pdfpc:DisableMarkdown>true</pdfpc:DisableMarkdown>
        </rdf:Description>
        """
        let meta = PDFPCMetadata.parse(xmp: xmp)
        #expect(meta?.durationMinutes == 45)
        #expect(meta?.endUserSlide == nil)
        #expect(meta?.disableMarkdown == true)
        #expect(PDFPCMetadata.parse(xmp: "<x:xmpmeta/>") == nil)
    }

    @Test func endOfTalkPrecedenceAndBounds() {
        let frames = FrameIndex(labels: ["1", "2", "2", "3", "4"])
        var meta = PDFPCMetadata()
        meta.endUserSlide = 2
        let outline = Outline(roots: [OutlineNode(id: 0, title: "Backup slides", pageIndex: 4, children: [])])
        #expect(EndOfTalk.resolve(pdfpc: meta, sidecar: 3, outline: outline, frames: frames) == 2)
        #expect(EndOfTalk.resolve(pdfpc: nil, sidecar: 3, outline: outline, frames: frames) == 3)
        #expect(EndOfTalk.resolve(pdfpc: nil, sidecar: nil, outline: outline, frames: frames) == 3)
        #expect(EndOfTalk.resolve(pdfpc: nil, sidecar: nil, outline: .empty, frames: frames) == nil)
        meta.endUserSlide = 99
        #expect(EndOfTalk.resolve(pdfpc: meta, sidecar: nil, outline: .empty, frames: frames) == nil)
    }

    @Test func labelLessDocumentsHaveNoLinksOrOutline() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        #expect(doc.outline.roots.count == 4)
        #expect(doc.endOfTalkPage == nil)
        #expect(doc.links(onPage: 0).allSatisfy { if case .goToPage = $0.action { return true }; if case .named = $0.action { return true }; return false })
    }
}

@Suite struct LinkFollowing {
    @MainActor @Test func appendixRoundTripIsOneActionEachWay() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("links-appendix.pdf"))
        let controller = SessionController(document: doc)
        controller.apply(.next)   // page 1, the Introduction with the links
        let proofLink = try #require(doc.links(onPage: 1).first { $0.action == .goToPage(7) })
        controller.apply(.followLink(proofLink.id))
        #expect(controller.state.committedPage == 7)
        #expect(controller.state.history == [1])
        controller.apply(.back)
        #expect(controller.state.committedPage == 1)
        #expect(controller.state.history.isEmpty)
        #expect(controller.state.forwardHistory == [7])
    }

    @MainActor @Test func namedActionsMapToCommands() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("links-appendix.pdf"))
        let controller = SessionController(document: doc)
        controller.apply(.next)
        func link(_ action: LinkAction) throws -> LinkID {
            try #require(doc.links(onPage: 1).first { $0.action == action }).id
        }
        controller.apply(.followLink(try link(.named(.nextPage))))
        #expect(controller.state.committedPage == 2 && controller.state.history.isEmpty)
        controller.apply(.followLink(try link(.named(.previousPage))))
        #expect(controller.state.committedPage == 1)
        controller.apply(.followLink(try link(.named(.lastPage))))
        #expect(controller.state.committedPage == 10 && controller.state.history == [1])
        controller.apply(.followLink(try link(.named(.goBack))))
        #expect(controller.state.committedPage == 1 && controller.state.forwardHistory == [10])
        controller.apply(.followLink(try link(.named(.goForward))))
        #expect(controller.state.committedPage == 10 && controller.state.history == [1] && controller.state.forwardHistory.isEmpty)
        controller.apply(.followLink(try link(.named(.firstPage))))
        #expect(controller.state.committedPage == 0 && controller.state.history == [1, 10])
        let before = controller.state
        controller.apply(.followLink(try link(.uri(URL(string: "https://example.org/")!))))
        #expect(controller.state == before, "URI links never move the talk")
        controller.apply(.followLink(LinkID(page: 50, index: 0)))
        #expect(controller.state == before)
    }

    @Test func newJumpsClearTheForwardStack() {
        let reducer = SessionReducer(frames: FrameIndex(labels: ["1", "2", "3", "4", "5"]))
        var s = SessionState()
        let now = Date()
        reducer.apply(.goToPage(3), to: &s, now: now)
        reducer.apply(.back, to: &s, now: now)
        #expect(s.forwardHistory == [3])
        reducer.apply(.goToPage(4), to: &s, now: now)
        #expect(s.forwardHistory.isEmpty)
        #expect(s.history == [0])
    }
}

@Suite struct Searching {
    @Test func findsHitsGroupedByFrame() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("links-appendix.pdf"))
        let searcher = TextSearcher(url: doc.url, frames: doc.frames)
        let hits = await searcher.search("backup")
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.snippet.lowercased().contains("backup") })
        #expect(hits.contains { $0.pageIndex == 1 }, "the Introduction links mention backup")
        #expect(hits.contains { $0.pageIndex == 7 && $0.frameIndex == 5 }, "frame 6 is the backup proof")
        #expect(hits.map(\.pageIndex) == hits.map(\.pageIndex).sorted())
        let none = await searcher.search("zzzz-not-there")
        #expect(none.isEmpty)
        let blank = await searcher.search("   ")
        #expect(blank.isEmpty)
    }

    @Test func diacriticAndCaseInsensitive() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        let searcher = TextSearcher(url: doc.url, frames: doc.frames)
        let hits = await searcher.search("FRAME 7")
        #expect(hits.contains { $0.pageIndex == 6 })
    }
}
