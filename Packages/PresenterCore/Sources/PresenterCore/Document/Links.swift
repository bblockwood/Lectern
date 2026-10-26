import CoreGraphics
import Foundation
import PDFKit
import PresenterProtocol

/// Named actions (PDF 32000 §12.6.4.11) as beamer emits them for navigation symbols and `\Acrobatmenu`.
public enum NamedAction: String, Hashable, Sendable {
    case nextPage, previousPage, firstPage, lastPage, goBack, goForward, goToPage, find, other
}

public enum LinkAction: Hashable, Sendable {
    /// GoTo an explicit page or a resolved named destination.
    case goToPage(Int)
    case named(NamedAction)
    /// Ignored by default; a setting may open it on the presenter device after confirmation (SPEC §4.3).
    case uri(URL)
    /// Launch / `run:` links, reserved for video (M9).
    case launch(String)
    case unsupported
}

/// A rectangle in normalised coordinates of the rotated page, origin top-left (like `NormalizedPoint`).
public struct NormalizedRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

public struct PageLink: Hashable, Sendable, Identifiable {
    public let id: LinkID
    public let rect: NormalizedRect
    public let action: LinkAction

    public init(id: LinkID, rect: NormalizedRect, action: LinkAction) {
        self.id = id
        self.rect = rect
        self.action = action
    }

    /// Link annotations of one page, in annotation order, with rects normalised to the rotated page.
    static func extract(from page: PDFPage, pageIndex: Int, in document: PDFDocument) -> [PageLink] {
        guard let cgPage = page.pageRef else { return [] }
        // Maps PDF user space onto the unit square of the rotated, cropped page (CG orientation, origin bottom-left).
        let toUnit = cgPage.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: 1, height: 1), rotate: 0, preserveAspectRatio: false)
        var links: [PageLink] = []
        for annotation in page.annotations where annotation.type == "Link" {
            let unit = annotation.bounds.applying(toUnit)
            let rect = NormalizedRect(x: unit.minX, y: 1 - unit.maxY, width: unit.width, height: unit.height)
            let action = PageLink.action(of: annotation, in: document)
            links.append(PageLink(id: LinkID(page: pageIndex, index: links.count), rect: rect, action: action))
        }
        return links
    }

    private static func action(of annotation: PDFAnnotation, in document: PDFDocument) -> LinkAction {
        if let action = annotation.action {
            switch action {
            case let goTo as PDFActionGoTo:
                if let page = goTo.destination.page { return .goToPage(document.index(for: page)) }
                return .unsupported
            case let named as PDFActionNamed:
                return .named(NamedAction(named.name))
            case let url as PDFActionURL:
                guard let target = url.url else { return .unsupported }
                if target.isFileURL || target.scheme == nil { return .launch(target.path) }
                return .uri(target)
            case is PDFActionRemoteGoTo:
                return .unsupported
            default:
                return .unsupported
            }
        }
        if let destination = annotation.destination, let page = destination.page {
            return .goToPage(document.index(for: page))
        }
        return .unsupported
    }
}

extension NamedAction {
    init(_ name: PDFActionNamedName) {
        switch name {
        case .nextPage: self = .nextPage
        case .previousPage: self = .previousPage
        case .firstPage: self = .firstPage
        case .lastPage: self = .lastPage
        case .goBack: self = .goBack
        case .goForward: self = .goForward
        case .goToPage: self = .goToPage
        case .find: self = .find
        default: self = .other
        }
    }
}
