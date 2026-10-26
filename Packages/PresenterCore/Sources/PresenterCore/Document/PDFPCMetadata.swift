import CoreGraphics
import Foundation

/// Metadata written into the XMP packet by pdfpc.sty (`pdfpc:Duration`, `pdfpc:EndUserSlide`, …).
/// Verified against the fixture built with pdfpc.sty 0.6.0: element form, one value per element.
public struct PDFPCMetadata: Hashable, Sendable {
    /// Talk duration in minutes.
    public var durationMinutes: Int?
    /// 1-based number of the last user slide (frame) of the main talk.
    public var endUserSlide: Int?
    public var lastMinutes: Int?
    public var notesPosition: String?
    public var disableMarkdown: Bool?
    public var defaultTransition: String?

    public init() {}

    public var isEmpty: Bool {
        durationMinutes == nil && endUserSlide == nil && lastMinutes == nil && notesPosition == nil
            && disableMarkdown == nil && defaultTransition == nil
    }

    public var targetDuration: TimeInterval? {
        durationMinutes.flatMap { $0 > 0 ? TimeInterval($0 * 60) : nil }
    }

    /// Reads the catalog's /Metadata stream. Nil when there is none or it carries no pdfpc keys.
    public static func read(from document: CGPDFDocument) -> PDFPCMetadata? {
        guard let catalog = document.catalog else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(catalog, "Metadata", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?, let xml = String(data: data, encoding: .utf8) else { return nil }
        return parse(xmp: xml)
    }

    /// Parses `<pdfpc:Key>value</pdfpc:Key>` elements. Empty values are ignored.
    public static func parse(xmp: String) -> PDFPCMetadata? {
        guard xml(xmp, contains: "pdfpc:") else { return nil }
        var meta = PDFPCMetadata()
        func value(_ key: String) -> String? {
            let pattern = "<pdfpc:\(key)>([^<]*)</pdfpc:\(key)>"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: xmp, range: NSRange(xmp.startIndex..., in: xmp)),
                  let range = Range(match.range(at: 1), in: xmp) else { return nil }
            let text = xmp[range].trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        meta.durationMinutes = value("Duration").flatMap(Int.init)
        meta.endUserSlide = value("EndUserSlide").flatMap(Int.init)
        meta.lastMinutes = value("LastMinutes").flatMap(Int.init)
        meta.notesPosition = value("NotesPosition").map { $0.lowercased() }
        meta.disableMarkdown = value("DisableMarkdown").map { $0.lowercased() == "true" }
        meta.defaultTransition = value("DefaultTransition")
        return meta.isEmpty ? nil : meta
    }

    private static func xml(_ text: String, contains needle: String) -> Bool {
        text.range(of: needle) != nil
    }
}
