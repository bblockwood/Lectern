import Foundation
import os

/// Everything notes-related for a deck, assembled in SPEC §5.1 priority: sidecar > .pdfpc > embedded >
/// (Beamer second-screen, as a crop rather than text) > PowerPoint.
public struct NotesBundle: Sendable {
    public var table: NotesTable
    public var pdfpcFile: PDFPCFile?
    public var pptx: PPTXNotes?
    /// Second-screen layout guess (from pdfpc's hint or the aspect ratio), before the user confirms.
    public var detectedSplit: NotesSplit?
    public var warnings: [String]

    public init(table: NotesTable = .empty, pdfpcFile: PDFPCFile? = nil, pptx: PPTXNotes? = nil, detectedSplit: NotesSplit? = nil, warnings: [String] = []) {
        self.table = table; self.pdfpcFile = pdfpcFile; self.pptx = pptx; self.detectedSplit = detectedSplit; self.warnings = warnings
    }
}

public enum NotesLoader {
    private static let log = Logger(subsystem: "dev.lectern", category: "notes")

    /// Pure assembly from already-read sources, for tests and for the app's reload path.
    public static func assemble(document: PresentationDocument, sidecarNotes: [Int: String], pdfpcFile: PDFPCFile?,
                                embedded: [Int: String], pptx: PPTXNotes?) -> NotesBundle {
        var warnings: [String] = []
        var layers: [(source: NoteSource, notes: [Int: String])] = [(.sidecar, sidecarNotes)]
        if let pdfpcFile {
            layers.append((.pdfpcFile, pdfpcFile.notesByPage(frames: document.frames, labels: document.pages.map(\.label))))
        }
        layers.append((.embedded, embedded))
        if let pptx {
            let mapped = pptx.notesByPage(pageCount: document.pageCount)
            if let warning = mapped.warning { warnings.append(warning) }
            layers.append((.pptx, mapped.notes))
        }
        let hint = pdfpcFile?.beamerNotePosition ?? document.pdfpc?.notesPosition
        let split = document.pages.first.flatMap { SecondScreenDetector.detect(pageSize: $0.size, hint: hint) }
        return NotesBundle(table: NotesMerger.merge(layers), pdfpcFile: pdfpcFile, pptx: pptx, detectedSplit: split, warnings: warnings)
    }

    /// Reads the companion files beside the deck and the embedded annotations. Safe off the main thread.
    public static func load(document: PresentationDocument, sidecarNotes: [Int: String]) -> NotesBundle {
        let pdfpcFile = PDFPCFile.load(forDeck: document.url)
        if pdfpcFile == nil, FileManager.default.fileExists(atPath: PDFPCFile.url(forDeck: document.url).path) {
            log.error("could not parse \(PDFPCFile.url(forDeck: document.url).lastPathComponent, privacy: .public)")
        }
        let pptx = PPTXNotes.load(forDeck: document.url)
        if pptx == nil, FileManager.default.fileExists(atPath: PPTXNotes.url(forDeck: document.url).path) {
            log.error("could not parse \(PPTXNotes.url(forDeck: document.url).lastPathComponent, privacy: .public)")
        }
        let embedded = EmbeddedNotes.extract(from: document.source, pageCount: document.pageCount)
        return assemble(document: document, sidecarNotes: sidecarNotes, pdfpcFile: pdfpcFile, embedded: embedded, pptx: pptx)
    }
}
