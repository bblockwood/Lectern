import CoreGraphics
import Foundation

/// Notes stored as `/Text` annotations by pdfpc.sty (hidden, zero-size) and pdfcomment (`\pdfcomment`,
/// `\pdfmargincomment`): the `/Contents` string. Visible annotation types (FreeText, markup, shapes) are never notes.
public enum EmbeddedNotes {
    public static func extract(from source: PDFSource, pageCount: Int) -> [Int: String] {
        var notes: [Int: String] = [:]
        for index in 0..<pageCount {
            guard let page = source.page(at: index), let dictionary = page.dictionary else { continue }
            let texts = textAnnotations(in: dictionary)
            if !texts.isEmpty { notes[index] = texts.joined(separator: "\n\n") }
        }
        return notes
    }

    static func textAnnotations(in page: CGPDFDictionaryRef) -> [String] {
        var annots: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(page, "Annots", &annots), let annots else { return [] }
        var texts: [String] = []
        for i in 0..<CGPDFArrayGetCount(annots) {
            var annotation: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annots, i, &annotation), let annotation else { continue }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype, String(cString: subtype) == "Text" else { continue }
            var contents: CGPDFStringRef?
            guard CGPDFDictionaryGetString(annotation, "Contents", &contents), let contents,
                  let text = CGPDFStringCopyTextString(contents) as String? else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { texts.append(trimmed) }
        }
        return texts
    }
}
