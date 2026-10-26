// Prints the structure of each fixture PDF: page count, sizes, labels, annotations, /Trans, /Dur, outline, links.
// Usage: swift Fixtures/tools/inspect.swift Fixtures/*.pdf
import Foundation
import PDFKit
import CoreGraphics

func str(_ obj: CGPDFObjectRef?) -> String {
    guard let obj else { return "nil" }
    switch CGPDFObjectGetType(obj) {
    case .boolean: var b: CGPDFBoolean = 0; CGPDFObjectGetValue(obj, .boolean, &b); return b != 0 ? "true" : "false"
    case .integer: var i: CGPDFInteger = 0; CGPDFObjectGetValue(obj, .integer, &i); return "\(i)"
    case .real: var r: CGPDFReal = 0; CGPDFObjectGetValue(obj, .real, &r); return "\(r)"
    case .name: var n: UnsafePointer<CChar>? = nil; CGPDFObjectGetValue(obj, .name, &n); return "/" + (n.map { String(cString: $0) } ?? "?")
    case .string:
        var s: CGPDFStringRef? = nil; CGPDFObjectGetValue(obj, .string, &s)
        return "(" + ((s.flatMap { CGPDFStringCopyTextString($0) } as String?) ?? "?") + ")"
    case .array:
        var a: CGPDFArrayRef? = nil; CGPDFObjectGetValue(obj, .array, &a)
        guard let a else { return "[?]" }
        var parts: [String] = []
        for i in 0..<CGPDFArrayGetCount(a) { var o: CGPDFObjectRef? = nil; if CGPDFArrayGetObject(a, i, &o) { parts.append(str(o)) } }
        return "[" + parts.joined(separator: " ") + "]"
    case .dictionary:
        var d: CGPDFDictionaryRef? = nil; CGPDFObjectGetValue(obj, .dictionary, &d)
        guard let d else { return "<<?>>" }
        return dictStr(d)
    case .stream: return "<stream>"
    case .null: return "null"
    @unknown default: return "?"
    }
}

func dictStr(_ d: CGPDFDictionaryRef, keys: [String]? = nil) -> String {
    let holder = PartsBox([])
    let box = Unmanaged.passUnretained(holder).toOpaque()
    CGPDFDictionaryApplyBlock(d, { key, value, info in
        let k = String(cString: key)
        if k == "Parent" || k == "P" || k == "Popup" || k == "AP" { return true }
        let b = Unmanaged<PartsBox>.fromOpaque(info!).takeUnretainedValue()
        b.parts.append("/\(k) \(str(value))")
        return true
    }, box)
    return "<<" + holder.parts.joined(separator: " ") + ">>"
}
final class PartsBox { var parts: [String]; init(_ p: [String]) { parts = p } }

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    print("==== \(url.lastPathComponent)")
    guard let cg = CGPDFDocument(url as CFURL) else { print("  CGPDFDocument: FAILED to open"); continue }
    let pk = PDFDocument(url: url)
    print("  pages: \(cg.numberOfPages)  PDFKit pages: \(pk?.pageCount ?? -1)  encrypted: \(cg.isEncrypted)")
    if let pk, let outline = pk.outlineRoot {
        func walk(_ o: PDFOutline, depth: Int) {
            for i in 0..<o.numberOfChildren {
                let c = o.child(at: i)!
                let dest = c.destination.map { "-> page \((pk.index(for: $0.page!)) + 1)" } ?? ""
                print("  outline: " + String(repeating: "  ", count: depth) + "\(c.label ?? "?") \(dest)")
                walk(c, depth: depth + 1)
            }
        }
        walk(outline, depth: 0)
    } else { print("  outline: none") }
    for i in 1...cg.numberOfPages {
        guard let page = cg.page(at: i) else { print("  page \(i): nil"); continue }
        let box = page.getBoxRect(.mediaBox)
        let label = pk?.page(at: i - 1)?.label ?? "?"
        var line = "  p\(i) label=\(label) size=\(Int(box.width))x\(Int(box.height))"
        let d = page.dictionary!
        var trans: CGPDFDictionaryRef? = nil
        if CGPDFDictionaryGetDictionary(d, "Trans", &trans), let trans { let t = dictStr(trans); if t != "<</S /R>>" { line += " Trans=\(t)" } }
        var dur: CGPDFReal = 0
        if CGPDFDictionaryGetNumber(d, "Dur", &dur) { line += " Dur=\(dur)" }
        var navCount = 0; var navSeen = false
        var annotLines: [String] = []
        var annots: CGPDFArrayRef? = nil
        if CGPDFDictionaryGetArray(d, "Annots", &annots), let annots {
            for j in 0..<CGPDFArrayGetCount(annots) {
                var ad: CGPDFDictionaryRef? = nil
                guard CGPDFArrayGetDictionary(annots, j, &ad), let ad else { continue }
                var sub: UnsafePointer<CChar>? = nil
                CGPDFDictionaryGetName(ad, "Subtype", &sub)
                let subtype = sub.map { String(cString: $0) } ?? "?"
                if subtype == "Link" {
                    var a: CGPDFDictionaryRef? = nil
                    var desc = ""
                    if CGPDFDictionaryGetDictionary(ad, "A", &a), let a { desc = "A=" + dictStr(a) }
                    if desc.contains("(Navigation") || desc.contains("/GoToPage") || desc.contains("/Find") || (desc.contains("/GoBack") && navSeen) || (desc.contains("/GoForward") && navSeen) { navCount += 1; continue }
                    if desc.contains("/GoBack") || desc.contains("/GoForward") { navSeen = true }
                    var dest: CGPDFObjectRef? = nil
                    if CGPDFDictionaryGetObject(ad, "Dest", &dest) { desc += " Dest=" + str(dest) }
                    annotLines.append("     Link \(desc)")
                } else {
                    annotLines.append("     \(subtype) \(dictStr(ad))")
                }
            }
        }
        if navCount > 0 { line += " navlinks=\(navCount)" }
        print(line)
        annotLines.forEach { print($0) }
    }
    if let pk {
        let meta = pk.documentAttributes ?? [:]
        if !meta.isEmpty { print("  info: \(meta.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))") }
    }
}
