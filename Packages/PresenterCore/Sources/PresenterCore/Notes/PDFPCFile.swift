import Foundation

/// pdfpc's `.pdfpc` companion file (same basename as the PDF). Current pdfpc writes JSON with
/// `pdfpcFormat: 2`; older versions wrote a bracketed text format, parsed here as a fallback.
/// Facts verified against pdfpc's `src/classes/metadata/pdf.vala` (2026-10-25).
public struct PDFPCFile: Hashable, Sendable {
    public struct PageEntry: Hashable, Sendable {
        /// 0-based real page index.
        public var idx: Int
        public var label: String?
        /// 0-based position within the run of pages sharing the label.
        public var overlay: Int
        public var note: String?
        public var hidden: Bool?
        public var forcedOverlay: Bool?
        public init(idx: Int, label: String? = nil, overlay: Int = 0, note: String? = nil, hidden: Bool? = nil, forcedOverlay: Bool? = nil) {
            self.idx = idx; self.label = label; self.overlay = overlay; self.note = note; self.hidden = hidden; self.forcedOverlay = forcedOverlay
        }
    }

    public var format: Int?
    /// Minutes.
    public var durationMinutes: Int?
    /// 0-based user slide (frame) index of the last main-talk slide.
    public var endSlide: Int?
    public var lastSavedSlide: Int?
    public var beamerNotePosition: String?
    public var disableMarkdown: Bool?
    public var noteFontSize: Int?
    public var pages: [PageEntry] = []
    /// True when the legacy bracketed format was parsed (its notes are plain text, not Markdown).
    public var isLegacy = false

    public init() {}

    public static func url(forDeck deck: URL) -> URL {
        deck.deletingPathExtension().appendingPathExtension("pdfpc")
    }

    public var targetDuration: TimeInterval? {
        durationMinutes.flatMap { $0 > 0 ? TimeInterval($0 * 60) : nil }
    }

    /// Reads the file beside the deck if present. Unparseable files yield nil (and are logged by the caller).
    public static func load(forDeck deck: URL) -> PDFPCFile? {
        let url = url(forDeck: deck)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? parse(data: data)
    }

    public enum ParseError: Error { case unreadable }

    public static func parse(data: Data) throws -> PDFPCFile {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseJSON(json)
        }
        guard let text = String(data: data, encoding: .utf8), let legacy = parseLegacy(text: text) else { throw ParseError.unreadable }
        return legacy
    }

    static func parseJSON(_ json: [String: Any]) -> PDFPCFile {
        var file = PDFPCFile()
        func int(_ key: String) -> Int? { (json[key] as? NSNumber)?.intValue }
        file.format = int("pdfpcFormat")
        file.durationMinutes = int("duration")
        file.endSlide = int("endSlide")
        file.lastSavedSlide = int("savedSlide")
        file.beamerNotePosition = (json["beamerNotePosition"] as? String)?.lowercased()
        file.disableMarkdown = json["disableMarkdown"] as? Bool
        file.noteFontSize = int("noteFontSize")
        if let pages = json["pages"] as? [[String: Any]] {
            for page in pages {
                guard let idx = (page["idx"] as? NSNumber)?.intValue else { continue }
                file.pages.append(PageEntry(idx: idx,
                                            label: page["label"] as? String,
                                            overlay: (page["overlay"] as? NSNumber)?.intValue ?? 0,
                                            note: page["note"] as? String,
                                            hidden: page["hidden"] as? Bool,
                                            forcedOverlay: page["forcedOverlay"] as? Bool))
            }
        }
        return file
    }

    /// Legacy format: `[section]` headers; `[notes]` holds `### N` blocks where N is a 1-based user slide.
    static func parseLegacy(text: String) -> PDFPCFile? {
        var file = PDFPCFile()
        file.isLegacy = true
        var sections: [String: String] = [:]
        var current: String?
        var buffer: [String] = []
        var sawSection = false
        for line in text.components(separatedBy: .newlines) {
            if let match = line.range(of: #"^\[[A-Za-z_]+\]$"#, options: .regularExpression) {
                if let current { sections[current] = buffer.joined(separator: "\n") }
                current = String(line[match]).dropFirst().dropLast().lowercased()
                buffer = []
                sawSection = true
            } else if current != nil {
                buffer.append(line)
            }
        }
        if let current { sections[current] = buffer.joined(separator: "\n") }
        guard sawSection else { return nil }
        file.durationMinutes = sections["duration"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let end = sections["end_user_slide"].flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
            file.endSlide = end - 1   // legacy stored the 1-based user slide
        }
        file.lastSavedSlide = sections["last_saved_slide"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        file.noteFontSize = sections["font_size"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        file.beamerNotePosition = sections["notes_position"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let notes = sections["notes"] {
            for block in notes.components(separatedBy: "### ").dropFirst() {
                guard let newline = block.firstIndex(of: "\n") else { continue }
                guard let userSlide = Int(block[..<newline].trimmingCharacters(in: .whitespaces)) else { continue }
                let body = String(block[block.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Marked with a negative idx: resolved per frame in notesByPage.
                file.pages.append(PageEntry(idx: -userSlide, label: nil, overlay: 0, note: body))
            }
        }
        return file
    }

    /// Notes per real page, applying pdfpc's matching: label and overlay first, then idx.
    public func notesByPage(frames: FrameIndex, labels: [String?]) -> [Int: String] {
        var notes: [Int: String] = [:]
        for entry in pages {
            guard let note = entry.note, !note.isEmpty else { continue }
            if entry.idx < 0 {
                // Legacy: 1-based user slide → every page of that frame.
                let frameIndex = -entry.idx - 1
                guard frames.frames.indices.contains(frameIndex) else { continue }
                for page in frames.frames[frameIndex].pages { notes[page] = note }
                continue
            }
            if let page = PDFPCFile.resolvePage(entry, frames: frames, labels: labels) { notes[page] = note }
        }
        return notes
    }

    static func resolvePage(_ entry: PageEntry, frames: FrameIndex, labels: [String?]) -> Int? {
        func label(_ page: Int) -> String? { labels.indices.contains(page) ? labels[page] : nil }
        guard let wanted = entry.label, !wanted.isEmpty else {
            return labels.indices.contains(entry.idx) ? entry.idx : nil
        }
        if label(entry.idx) == wanted, frames.buildIndex(of: entry.idx) == entry.overlay { return entry.idx }
        if let first = labels.firstIndex(where: { $0 == wanted }) {
            let candidate = first + entry.overlay
            if label(candidate) == wanted { return candidate }
        }
        return labels.indices.contains(entry.idx) ? entry.idx : nil
    }
}
