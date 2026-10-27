import Testing
@testable import PresenterCore

@Suite struct OutlineCurrentEntry {
    // Introduction p0 (Background p2, Setup p4), Results p7, Appendix p10; an entry with no page in between.
    private let outline = Outline(roots: [
        OutlineNode(id: 0, title: "Introduction", pageIndex: 0, children: [
            OutlineNode(id: 1, title: "Background", pageIndex: 2, children: []),
            OutlineNode(id: 2, title: "Setup", pageIndex: 4, children: []),
        ]),
        OutlineNode(id: 3, title: "Unlinked", pageIndex: nil, children: []),
        OutlineNode(id: 4, title: "Results", pageIndex: 7, children: []),
        OutlineNode(id: 5, title: "Appendix", pageIndex: 10, children: []),
    ])

    @Test func lastEntryStartingAtOrBeforeThePage() {
        #expect(outline.currentEntry(forPage: 0)?.id == 0)
        #expect(outline.currentEntry(forPage: 1)?.id == 0)
        #expect(outline.currentEntry(forPage: 2)?.id == 1)
        #expect(outline.currentEntry(forPage: 3)?.id == 1)
        #expect(outline.currentEntry(forPage: 4)?.id == 2)
        #expect(outline.currentEntry(forPage: 6)?.id == 2)   // "Unlinked" has no page and is skipped
        #expect(outline.currentEntry(forPage: 7)?.id == 4)
        #expect(outline.currentEntry(forPage: 9)?.id == 4)
        #expect(outline.currentEntry(forPage: 10)?.id == 5)
        #expect(outline.currentEntry(forPage: 99)?.id == 5)
    }

    @Test func nothingBeforeTheFirstEntryOrWithoutPages() {
        let late = Outline(roots: [OutlineNode(id: 0, title: "Late", pageIndex: 3, children: [])])
        #expect(late.currentEntry(forPage: 2) == nil)
        #expect(Outline.empty.currentEntry(forPage: 0) == nil)
        let unlinked = Outline(roots: [OutlineNode(id: 0, title: "No page", pageIndex: nil, children: [])])
        #expect(unlinked.currentEntry(forPage: 0) == nil)
    }
}
