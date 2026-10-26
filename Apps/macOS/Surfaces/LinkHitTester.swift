import PresenterCore
import PresenterProtocol

/// Pure hit-testing so it can be unit-tested without views.
enum LinkHitTester {
    /// The topmost (last in annotation order) link containing the point.
    static func link(at point: NormalizedPoint, in links: [PageLink]) -> PageLink? {
        links.last { $0.rect.contains(point) }
    }
}
