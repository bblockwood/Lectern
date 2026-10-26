import CoreGraphics
import Foundation
import PDFKit
import PresenterProtocol

public enum DocumentError: Error, Equatable, Sendable {
    /// CoreGraphics could not parse the file (malformed, truncated, encrypted with a password, not a PDF).
    case cannotOpen(URL)
    case noPages(URL)
}

/// Per-page facts needed for layout and rendering.
public struct PageInfo: Hashable, Sendable {
    public let index: Int
    public let label: String?
    /// Crop box size in PDF points after applying the page's /Rotate.
    public let size: CGSize
    public let rotation: Int

    public var aspectRatio: CGFloat { size.height > 0 ? size.width / size.height : 1 }
}

/// An immutable handle to the parsed PDF for the render path. `CGPDFDocument` is not formally
/// thread-safe, so `RenderCache` is the only reader after loading and it renders one page at a time.
public final class PDFSource: @unchecked Sendable {
    private let document: CGPDFDocument

    init(document: CGPDFDocument) { self.document = document }

    /// 0-based page access.
    public func page(at index: Int) -> CGPDFPage? {
        document.page(at: index + 1)
    }

    public var pageCount: Int { document.numberOfPages }
}

/// Everything PresenterCore knows about a loaded deck. Value type; the heavy parts are immutable references.
public struct PresentationDocument: Sendable {
    public let url: URL
    public let pages: [PageInfo]
    public let frames: FrameIndex
    public let source: PDFSource
    public let title: String?
    /// True when the PDF defines a /PageLabels tree. Without one, labels are page numbers and every page is a frame.
    public let hasPageLabels: Bool
    public let outline: Outline
    /// Link annotations per page (SPEC §4.3).
    public let links: [[PageLink]]
    public let pdfpc: PDFPCMetadata?
    /// Index of the last page of the main talk (SPEC §4.2), nil when unknown. The sidecar (M3) may override.
    public let endOfTalkPage: Int?

    public var pageCount: Int { pages.count }

    public func links(onPage page: Int) -> [PageLink] {
        links.indices.contains(page) ? links[page] : []
    }

    public func link(_ id: LinkID) -> PageLink? {
        let pageLinks = links(onPage: id.page)
        return pageLinks.indices.contains(id.index) ? pageLinks[id.index] : nil
    }

    /// True for pages after the end of the main talk.
    public func isAppendix(page: Int) -> Bool {
        guard let end = endOfTalkPage else { return false }
        return page > end
    }

    /// A copy with the sidecar's end-of-talk override applied (SPEC §4.2 order: pdfpc metadata still wins).
    public func overridingEndOfTalk(_ sidecarPage: Int?) -> PresentationDocument {
        let resolved = EndOfTalk.resolve(pdfpc: pdfpc, sidecar: sidecarPage, outline: outline, frames: frames)
        guard resolved != endOfTalkPage else { return self }
        return PresentationDocument(url: url, pages: pages, frames: frames, source: source, title: title, hasPageLabels: hasPageLabels,
                                    outline: outline, links: links, pdfpc: pdfpc, endOfTalkPage: resolved)
    }

    /// Frames in the main talk (all frames when the end is unknown).
    public var mainTalkFrameCount: Int {
        guard let end = endOfTalkPage else { return frames.frameCount }
        return frames.frame(containing: end).index + 1
    }

    /// Loads the PDF structure. Never throws for a merely odd PDF; throws `DocumentError` when CoreGraphics
    /// cannot open it or it has no pages. Safe to call off the main thread.
    public static func load(url: URL) throws -> PresentationDocument {
        guard let cgDocument = CGPDFDocument(url as CFURL) else { throw DocumentError.cannotOpen(url) }
        let count = cgDocument.numberOfPages
        guard count > 0 else { throw DocumentError.noPages(url) }

        let hasLabels = PresentationDocument.catalogHasPageLabels(cgDocument)
        // PDFKit does the /PageLabels number tree, outline, link destinations and text; CoreGraphics does the rendering.
        let pdfKit = PDFDocument(url: url)

        var pages: [PageInfo] = []
        pages.reserveCapacity(count)
        for i in 0..<count {
            guard let page = cgDocument.page(at: i + 1) else { continue }
            let box = page.getBoxRect(.cropBox)
            let rotation = ((Int(page.rotationAngle) % 360) + 360) % 360
            let size = rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
            let label = hasLabels ? pdfKit?.page(at: i)?.label : nil
            pages.append(PageInfo(index: i, label: label, size: size, rotation: rotation))
        }
        guard !pages.isEmpty else { throw DocumentError.noPages(url) }

        var title: String?
        if let info = cgDocument.info {
            var titleString: CGPDFStringRef?
            if CGPDFDictionaryGetString(info, "Title", &titleString), let titleString,
               let s = CGPDFStringCopyTextString(titleString) as String?, !s.isEmpty {
                title = s
            }
        }

        let frames = FrameIndex(labels: pages.map(\.label))
        var links: [[PageLink]] = []
        var outline = Outline.empty
        if let pdfKit {
            links = (0..<pages.count).map { i in
                guard let page = pdfKit.page(at: i) else { return [] }
                return PageLink.extract(from: page, pageIndex: i, in: pdfKit)
            }
            outline = Outline.build(from: pdfKit)
        }
        let pdfpc = PDFPCMetadata.read(from: cgDocument)

        return PresentationDocument(
            url: url,
            pages: pages,
            frames: frames,
            source: PDFSource(document: cgDocument),
            title: title,
            hasPageLabels: hasLabels,
            outline: outline,
            links: links,
            pdfpc: pdfpc,
            endOfTalkPage: EndOfTalk.resolve(pdfpc: pdfpc, sidecar: nil, outline: outline, frames: frames)
        )
    }

    private static func catalogHasPageLabels(_ document: CGPDFDocument) -> Bool {
        guard let catalog = document.catalog else { return false }
        var labels: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(catalog, "PageLabels", &labels)
    }
}
