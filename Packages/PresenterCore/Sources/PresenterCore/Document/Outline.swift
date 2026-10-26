import Foundation
import PDFKit

/// A PDF outline (bookmark) entry (SPEC §4.4).
public struct OutlineNode: Hashable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let pageIndex: Int?
    public let children: [OutlineNode]

    public init(id: Int, title: String, pageIndex: Int?, children: [OutlineNode]) {
        self.id = id
        self.title = title
        self.pageIndex = pageIndex
        self.children = children
    }
}

public struct Outline: Hashable, Sendable {
    public let roots: [OutlineNode]

    public init(roots: [OutlineNode]) { self.roots = roots }

    public static let empty = Outline(roots: [])
    public var isEmpty: Bool { roots.isEmpty }

    /// Depth-first list with depths, for flat list views.
    public var flattened: [(node: OutlineNode, depth: Int)] {
        var result: [(OutlineNode, Int)] = []
        func walk(_ nodes: [OutlineNode], _ depth: Int) {
            for node in nodes {
                result.append((node, depth))
                walk(node.children, depth + 1)
            }
        }
        walk(roots, 0)
        return result
    }

    /// The first entry titled Appendix, Backup or Supplementary (case-insensitive, SPEC §4.2), depth-first.
    public func appendixEntry() -> OutlineNode? {
        let markers = ["appendix", "backup", "supplementary"]
        return flattened.first { entry in
            let title = entry.node.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return markers.contains { title == $0 || title.hasPrefix($0 + " ") || title.hasPrefix($0 + ":") }
        }?.node
    }

    static func build(from document: PDFDocument) -> Outline {
        guard let root = document.outlineRoot else { return .empty }
        var nextID = 0
        func convert(_ outline: PDFOutline) -> [OutlineNode] {
            var nodes: [OutlineNode] = []
            for i in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: i) else { continue }
                let id = nextID
                nextID += 1
                var page: Int?
                if let destinationPage = child.destination?.page ?? (child.action as? PDFActionGoTo)?.destination.page {
                    page = document.index(for: destinationPage)
                }
                nodes.append(OutlineNode(id: id, title: child.label ?? "", pageIndex: page, children: convert(child)))
            }
            return nodes
        }
        return Outline(roots: convert(root))
    }
}

/// Where the main talk ends (SPEC §4.2): pdfpc metadata, then the sidecar (M3), then the outline heuristic.
public enum EndOfTalk {
    /// Returns the index of the last page of the main talk, or nil when nothing says.
    public static func resolve(pdfpc: PDFPCMetadata?, sidecar: Int?, outline: Outline, frames: FrameIndex) -> Int? {
        if let userSlide = pdfpc?.endUserSlide, userSlide >= 1, userSlide <= frames.frameCount {
            return frames.frames[userSlide - 1].lastPage
        }
        if let sidecar, sidecar >= 0, sidecar < frames.pageCount {
            return sidecar
        }
        if let appendix = outline.appendixEntry(), let page = appendix.pageIndex, page > 0, page <= frames.pageCount {
            return page - 1
        }
        return nil
    }
}
