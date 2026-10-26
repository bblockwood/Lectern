import PresenterCore
import PresenterProtocol
import Testing
@testable import Lectern

@Suite struct LinkHitTesting {
    @Test func topmostContainingLinkWins() {
        let a = PageLink(id: LinkID(page: 0, index: 0), rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), action: .goToPage(3))
        let b = PageLink(id: LinkID(page: 0, index: 1), rect: NormalizedRect(x: 0.3, y: 0.3, width: 0.1, height: 0.1), action: .named(.nextPage))
        #expect(LinkHitTester.link(at: NormalizedPoint(x: 0.35, y: 0.35), in: [a, b])?.id == b.id)
        #expect(LinkHitTester.link(at: NormalizedPoint(x: 0.15, y: 0.15), in: [a, b])?.id == a.id)
        #expect(LinkHitTester.link(at: NormalizedPoint(x: 0.9, y: 0.9), in: [a, b]) == nil)
    }
}
