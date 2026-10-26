import Foundation

/// The subset of Markdown the notes pane renders (SPEC §5.2): paragraphs with line breaks, bullet and numbered
/// lists. Inline emphasis and code are left to the platform's inline Markdown parser per block.
public enum MarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case bullet(String, level: Int)
    case numbered(String, number: Int)
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); continue }
            let indent = line.prefix { $0 == " " }.count
            if let item = bulletItem(trimmed) {
                flush()
                blocks.append(.bullet(item, level: indent / 2))
            } else if let (number, item) = numberedItem(trimmed) {
                flush()
                blocks.append(.numbered(item, number: number))
            } else {
                paragraph.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), let number = Int(line[..<dot]),
              line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " else { return nil }
        return (number, String(line[line.index(dot, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces))
    }
}
