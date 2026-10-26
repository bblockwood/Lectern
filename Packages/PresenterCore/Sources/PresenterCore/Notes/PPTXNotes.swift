import Foundation

/// Speaker notes from a `.pptx` next to the PDF (SPEC §5.1.5). Slide order comes from `ppt/presentation.xml`
/// (`p:sldIdLst`) resolved through the relationships; hidden slides (`show="0"`) are skipped because PowerPoint
/// leaves them out of PDF exports; each slide's notes slide supplies the text of its body placeholder.
public struct PPTXNotes: Hashable, Sendable {
    public struct Slide: Hashable, Sendable {
        public let part: String
        public let hidden: Bool
        public let notes: String?
    }

    public let slides: [Slide]

    public var visibleSlides: [Slide] { slides.filter { !$0.hidden } }

    public static func url(forDeck deck: URL) -> URL {
        deck.deletingPathExtension().appendingPathExtension("pptx")
    }

    public static func load(forDeck deck: URL) -> PPTXNotes? {
        guard let data = try? Data(contentsOf: url(forDeck: deck)) else { return nil }
        return try? parse(data: data)
    }

    public enum ParseError: Error, Equatable { case missingPart(String) }

    public static func parse(data: Data) throws -> PPTXNotes {
        let archive = try ZipArchive(data: data)
        let presentation = try MiniXML.parse(archive.contents(of: "ppt/presentation.xml"))
        let presentationRels = try Relationships(MiniXML.parse(archive.contents(of: "ppt/_rels/presentation.xml.rels")))
        let slideIDs = presentation.descendants(named: "sldId").compactMap { $0.attribute("id", namespace: "r") ?? $0.attributes["r:id"] }
        var slides: [Slide] = []
        for relID in slideIDs {
            guard let target = presentationRels.target(for: relID) else { continue }
            let part = Relationships.resolve(target, relativeTo: "ppt/presentation.xml")
            guard let slideData = try? archive.contents(of: part) else { throw ParseError.missingPart(part) }
            let slide = try MiniXML.parse(slideData)
            let hidden = slide.attributes["show"] == "0"
            var notes: String?
            let relsPart = Relationships.relsPart(for: part)
            if let relsData = try? archive.contents(of: relsPart), let rels = try? Relationships(MiniXML.parse(relsData)),
               let notesTarget = rels.target(ofTypeEndingWith: "/notesSlide"),
               let notesData = try? archive.contents(of: Relationships.resolve(notesTarget, relativeTo: part)) {
                notes = PPTXNotes.notesText(try MiniXML.parse(notesData))
            }
            slides.append(Slide(part: part, hidden: hidden, notes: notes))
        }
        return PPTXNotes(slides: slides)
    }

    /// Maps visible slides to PDF pages in order. On a count mismatch returns no notes and a warning (SPEC §5.1.5).
    public func notesByPage(pageCount: Int) -> (notes: [Int: String], warning: String?) {
        let visible = visibleSlides
        guard visible.count == pageCount else {
            return ([:], "The PowerPoint file has \(visible.count) visible slide\(visible.count == 1 ? "" : "s") but the PDF has \(pageCount) page\(pageCount == 1 ? "" : "s"); its notes are not shown to avoid mismatching them.")
        }
        var notes: [Int: String] = [:]
        for (page, slide) in visible.enumerated() {
            if let text = slide.notes, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes[page] = text }
        }
        return (notes, nil)
    }

    /// Text of the body placeholder(s) of a notes slide: paragraphs joined by newlines, runs concatenated.
    static func notesText(_ root: MiniXML.Node) -> String? {
        var paragraphs: [String] = []
        for shape in root.descendants(named: "sp") {
            let placeholder = shape.descendants(named: "ph").first
            let type = placeholder?.attributes["type"]
            // The notes text placeholder is type="body"; "sldImg" is the slide picture, "sldNum" the number.
            guard type == "body" || (type == nil && placeholder != nil) else { continue }
            for paragraph in shape.descendants(named: "p") {
                var runs: [String] = []
                for child in paragraph.children {
                    if child.name == "br" { runs.append("\n") }
                    for t in child.descendants(named: "t") { runs.append(t.text) }
                    if child.name == "t" { runs.append(child.text) }
                }
                paragraphs.append(runs.joined())
            }
        }
        let text = paragraphs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// OPC relationships (`*.rels`).
struct Relationships {
    private var byID: [String: (type: String, target: String)] = [:]

    init(_ root: MiniXML.Node) {
        for rel in root.descendants(named: "Relationship") {
            if let id = rel.attributes["Id"], let target = rel.attributes["Target"] {
                byID[id] = (rel.attributes["Type"] ?? "", target)
            }
        }
    }

    func target(for id: String) -> String? { byID[id]?.target }

    func target(ofTypeEndingWith suffix: String) -> String? {
        byID.values.first { $0.type.hasSuffix(suffix) }?.target
    }

    /// `ppt/slides/slide1.xml` → `ppt/slides/_rels/slide1.xml.rels`.
    static func relsPart(for part: String) -> String {
        let components = part.split(separator: "/").map(String.init)
        guard let name = components.last else { return part }
        return (components.dropLast() + ["_rels", name + ".rels"]).joined(separator: "/")
    }

    /// Resolves a relative target against the part that owns the relationship.
    static func resolve(_ target: String, relativeTo part: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var base = part.split(separator: "/").map(String.init).dropLast()
        for component in target.split(separator: "/") {
            if component == ".." { if !base.isEmpty { base.removeLast() } }
            else if component != "." { base.append(String(component)) }
        }
        return base.joined(separator: "/")
    }
}

/// A tiny DOM over `XMLParser`, enough for OOXML parts.
enum MiniXML {
    final class Node {
        let name: String        // local name without prefix
        let qualifiedName: String
        var attributes: [String: String]
        var children: [Node] = []
        var text = ""

        init(name: String, qualifiedName: String, attributes: [String: String]) {
            self.name = name
            self.qualifiedName = qualifiedName
            self.attributes = attributes
        }

        func attribute(_ name: String, namespace prefix: String) -> String? {
            attributes["\(prefix):\(name)"]
        }

        func descendants(named name: String) -> [Node] {
            var result: [Node] = []
            func walk(_ node: Node) {
                for child in node.children {
                    if child.name == name { result.append(child) }
                    walk(child)
                }
            }
            walk(self)
            return result
        }
    }

    enum XMLError: Error { case malformed }

    static func parse(_ data: Data) throws -> Node {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = builder.root else { throw XMLError.malformed }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: Node?
        private var stack: [Node] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            let node = Node(name: local, qualifiedName: elementName, attributes: attributeDict)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }
    }
}
