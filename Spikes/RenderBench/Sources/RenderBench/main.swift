// Spike C: render benchmark. See README.md. Throwaway code: favours directness over structure.
import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Arguments

let argv = CommandLine.arguments
let fixturesDir = URL(fileURLWithPath: argv.count > 1 && !argv[1].hasPrefix("--") ? argv[1] : "Fixtures")
let quick = argv.contains("--quick")
let dumpDir: URL? = argv.firstIndex(of: "--dump").flatMap { i in argv.indices.contains(i + 1) ? URL(fileURLWithPath: argv[i + 1]) : nil }

struct Target: Sendable { let name: String; let width: Int; let height: Int }
let targets = [Target(name: "1080p", width: 1920, height: 1080),
               Target(name: "1440p", width: 2560, height: 1440),
               Target(name: "4K", width: 3840, height: 2160)]

let fixtureNames = ["basic-169", "overlays", "notes-right", "notes-bottom", "pdfpc-notes", "pdfcomment-notes",
                    "links-appendix", "tikz-heavy", "transitions", "ppt-export", "huge", "malformed"]

// MARK: - Timing helpers

@inline(__always) func nowNs() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
@inline(__always) func elapsedMs(since t0: UInt64) -> Double { Double(nowNs() - t0) / 1_000_000 }

struct Stats {
    let count: Int, min: Double, median: Double, p95: Double, max: Double, total: Double
    init(_ xs: [Double]) {
        let s = xs.sorted()
        count = s.count; min = s.first ?? 0; max = s.last ?? 0; total = s.reduce(0, +)
        median = Stats.pct(s, 0.5); p95 = Stats.pct(s, 0.95)
    }
    static func pct(_ s: [Double], _ p: Double) -> Double {
        guard !s.isEmpty else { return 0 }
        return s[Int((Double(s.count - 1) * p).rounded())]
    }
    var cells: String { String(format: "%.1f | %.1f | %.1f | %.1f | %.0f", min, median, p95, max, total) }
}

// MARK: - Renderer (the shape RenderCache will use)

struct Renderer {
    let colorSpace: CGColorSpace

    func makeContext(width: Int, height: Int) -> CGContext {
        // BGRX, no alpha: the cheapest format for CALayer.contents on Apple GPUs.
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { fatalError("CGContext creation failed") }
        return ctx
    }

    /// Letterboxes `page` into a width×height bitmap: black surround, white page background, then the page content.
    /// Returns the image and the fitted rect.
    @discardableResult
    func render(_ page: CGPDFPage, width: Int, height: Int, into existing: CGContext? = nil) -> CGImage {
        let ctx = existing ?? makeContext(width: width, height: height)
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(full)
        let fit = fitRect(for: page, width: width, height: height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(fit)
        ctx.interpolationQuality = .high
        ctx.concatenate(pageTransform(page, onto: fit))
        ctx.drawPDFPage(page)
        ctx.restoreGState()
        guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
        return image
    }

    func fitRect(for page: CGPDFPage, width: Int, height: Int) -> CGRect {
        let box = page.getBoxRect(.cropBox)
        let rotated = (page.rotationAngle % 180) != 0
        let bw = rotated ? box.height : box.width, bh = rotated ? box.width : box.height
        let scale = min(CGFloat(width) / bw, CGFloat(height) / bh)
        return CGRect(x: (CGFloat(width) - bw * scale) / 2, y: (CGFloat(height) - bh * scale) / 2,
                      width: bw * scale, height: bh * scale).integral
    }
}

struct DocBox: @unchecked Sendable { let doc: CGPDFDocument }   // spike only: CGPDFDocument is not Sendable

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let renderer = Renderer(colorSpace: srgb)

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func pixelDiff(_ a: CGImage, _ b: CGImage) -> Int {
    guard a.width == b.width, a.height == b.height, a.bytesPerRow == b.bytesPerRow,
          let da = a.dataProvider?.data, let db = b.dataProvider?.data else { return -1 }
    let pa = CFDataGetBytePtr(da)!, pb = CFDataGetBytePtr(db)!
    var diff = 0
    for y in 0..<a.height {
        let row = y * a.bytesPerRow
        for x in 0..<a.width {
            let i = row + x * 4
            if pa[i] != pb[i] || pa[i + 1] != pb[i + 1] || pa[i + 2] != pb[i + 2] { diff += 1 }
        }
    }
    return diff
}

print("# RenderBench results\n")
print("Machine: \(ProcessInfo.processInfo.hostName), \(ProcessInfo.processInfo.processorCount) cores, \(ProcessInfo.processInfo.physicalMemory / (1 << 30)) GiB; macOS \(ProcessInfo.processInfo.operatingSystemVersionString). Colour space sRGB, BGRX 8-bit, fresh CGContext per render, `interpolationQuality = .high`. Times in ms.\n")

// MARK: - 1. Open + per-page render timing

print("## 1. Per-page render time (cold = first render of the page, warm = immediate second render)\n")
print("| Fixture | Pages | Size | Pass | min | median | p95 | max | total | slowest page |")
print("|---|---|---|---|---|---|---|---|---|---|")

var openedDocs: [String: CGPDFDocument] = [:]
for name in fixtureNames {
    let url = fixturesDir.appendingPathComponent(name + ".pdf")
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("| \(name) | – | – | – | not present | | | | | |"); continue
    }
    let t0 = nowNs()
    guard let doc = CGPDFDocument(url as CFURL) else {
        print("| \(name) | – | – | open | FAILED cleanly (CGPDFDocument returned nil) in \(String(format: "%.2f", elapsedMs(since: t0))) ms | | | | | |")
        let pk = PDFDocument(url: url)
        print("| \(name) | – | – | PDFKit | \(pk == nil ? "PDFDocument also nil" : "PDFDocument opened with \(pk!.pageCount) pages") | | | | | |")
        continue
    }
    openedDocs[name] = doc
    let openMs = elapsedMs(since: t0)
    let n = doc.numberOfPages
    print("| \(name) | \(n) | – | open | \(String(format: "%.2f", openMs)) | | | | | |")
    for target in targets {
        if quick && name == "huge" && target.name != "1080p" { continue }
        var cold: [Double] = [], warm: [Double] = []
        var slowest = (page: 0, ms: 0.0)
        for i in 1...n {
            guard let page = doc.page(at: i) else { continue }
            let a = nowNs(); let img = renderer.render(page, width: target.width, height: target.height); let c = elapsedMs(since: a)
            let b = nowNs(); _ = renderer.render(page, width: target.width, height: target.height); let w = elapsedMs(since: b)
            cold.append(c); warm.append(w)
            if c > slowest.ms { slowest = (i, c) }
            if let dumpDir, target.name == "1080p" {
                try? FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
                writePNG(img, to: dumpDir.appendingPathComponent("\(name)-p\(String(format: "%03d", i)).png"))
            }
        }
        print("| \(name) | \(n) | \(target.name) | cold | \(Stats(cold).cells) | p\(slowest.page) |")
        print("| \(name) | \(n) | \(target.name) | warm | \(Stats(warm).cells) | |")
    }
}

// MARK: - 2. Context allocation cost (part of every fresh render above)

print("\n## 2. Cost of allocating a fresh bitmap context and filling it (included in §1 numbers)\n")
print("| Size | bytes | alloc+fill median ms |")
print("|---|---|---|")
for target in targets {
    var xs: [Double] = []
    for _ in 0..<20 {
        let t = nowNs()
        let ctx = renderer.makeContext(width: target.width, height: target.height)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: target.width, height: target.height))
        _ = ctx.makeImage()
        xs.append(elapsedMs(since: t))
    }
    print("| \(target.name) | \(target.width * target.height * 4) | \(String(format: "%.2f", Stats(xs).median)) |")
}

// MARK: - 3. Annotations must never reach the bitmap (fixtures 4 and 5)

print("\n## 3. Annotation check: CoreGraphics vs PDFKit rendering (1080p)\n")
print("CG = `CGContext.drawPDFPage`. PK+A = `PDFPage.draw(with:to:)` with `displaysAnnotations = true`. PK−A = same with `displaysAnnotations = false`. Cells are differing pixel counts vs CG.\n")
print("| Fixture | Page | annots (subtype /F) | PK+A vs CG | PK−A vs CG |")
print("|---|---|---|---|---|")
for name in ["pdfpc-notes", "pdfcomment-notes"] {
    let url = fixturesDir.appendingPathComponent(name + ".pdf")
    guard let doc = openedDocs[name], let pk = PDFDocument(url: url) else { continue }
    for i in 1...doc.numberOfPages {
        guard let page = doc.page(at: i), let pkPage = pk.page(at: i - 1) else { continue }
        var annotDesc: [String] = []
        if let d = page.dictionary {
            var annots: CGPDFArrayRef? = nil
            if CGPDFDictionaryGetArray(d, "Annots", &annots), let annots {
                for j in 0..<CGPDFArrayGetCount(annots) {
                    var ad: CGPDFDictionaryRef? = nil
                    guard CGPDFArrayGetDictionary(annots, j, &ad), let ad else { continue }
                    var sub: UnsafePointer<CChar>? = nil
                    CGPDFDictionaryGetName(ad, "Subtype", &sub)
                    let s = sub.map { String(cString: $0) } ?? "?"
                    if s == "Link" { continue }
                    var f: CGPDFInteger = 0
                    CGPDFDictionaryGetInteger(ad, "F", &f)
                    annotDesc.append("\(s) /F \(f)")
                }
            }
        }
        let cg = renderer.render(page, width: 1920, height: 1080)
        func pkRender(annotations: Bool) -> CGImage {
            let ctx = renderer.makeContext(width: 1920, height: 1080)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let fit = renderer.fitRect(for: page, width: 1920, height: 1080)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(fit)
            ctx.interpolationQuality = .high
            ctx.concatenate(pageTransform(page, onto: fit))
            pkPage.displaysAnnotations = annotations
            pkPage.draw(with: .cropBox, to: ctx)
            return ctx.makeImage()!
        }
        let withA = pkRender(annotations: true), withoutA = pkRender(annotations: false)
        if let dumpDir, !annotDesc.isEmpty { writePNG(withA, to: dumpDir.appendingPathComponent("\(name)-p\(String(format: "%03d", i))-pdfkit-annots.png")) }
        print("| \(name) | \(i) | \(annotDesc.isEmpty ? "none" : annotDesc.joined(separator: ", ")) | \(pixelDiff(withA, cg)) | \(pixelDiff(withoutA, cg)) |")
    }
}

// MARK: - 4. Thumbnails (huge.pdf, all pages, 256 px tall)

print("\n## 4. Thumbnails: every page at 256 px height\n")
print("| Fixture | Pages | median ms | p95 ms | total ms | MB (BGRX) |")
print("|---|---|---|---|---|---|")
for name in ["huge", "tikz-heavy", "basic-169"] {
    guard let doc = openedDocs[name], let first = doc.page(at: 1) else { continue }
    let box = first.getBoxRect(.cropBox)
    let h = 256, w = Int((box.width / box.height * 256).rounded())
    var xs: [Double] = []
    for i in 1...doc.numberOfPages {
        guard let page = doc.page(at: i) else { continue }
        let t = nowNs(); _ = renderer.render(page, width: w, height: h); xs.append(elapsedMs(since: t))
    }
    let s = Stats(xs)
    print("| \(name) | \(doc.numberOfPages) | \(String(format: "%.2f", s.median)) | \(String(format: "%.2f", s.p95)) | \(String(format: "%.0f", s.total)) | \(String(format: "%.1f", Double(w * h * 4 * doc.numberOfPages) / 1_048_576)) |")
}

// MARK: - 5. Concurrency: does rendering scale across threads, and is one CGPDFDocument safe to share?

print("\n## 5. Concurrency at 1080p (all pages of the fixture, wall-clock ms)\n")
print("| Fixture | Pages | sequential | 4 threads, shared CGPDFDocument | 4 threads, one CGPDFDocument per thread | 8 threads, one doc per thread |")
print("|---|---|---|---|---|---|")
for name in ["basic-169", "tikz-heavy", "overlays"] {
    let url = fixturesDir.appendingPathComponent(name + ".pdf")
    guard let doc = openedDocs[name] else { continue }
    let n = doc.numberOfPages
    // warm up
    for i in 1...n { if let p = doc.page(at: i) { renderer.render(p, width: 1920, height: 1080) } }
    let tSeq = nowNs()
    for i in 1...n { if let p = doc.page(at: i) { renderer.render(p, width: 1920, height: 1080) } }
    let seq = elapsedMs(since: tSeq)

    let shared = DocBox(doc: doc)
    let tShared = nowNs()
    DispatchQueue.concurrentPerform(iterations: n) { k in
        if let p = shared.doc.page(at: k + 1) { renderer.render(p, width: 1920, height: 1080) }
    }
    let sharedMs = elapsedMs(since: tShared)

    func perThread(_ threads: Int) -> Double {
        let docs = (0..<threads).map { _ in DocBox(doc: CGPDFDocument(url as CFURL)!) }
        let t = nowNs()
        DispatchQueue.concurrentPerform(iterations: threads) { t in
            var i = t + 1
            while i <= n { if let p = docs[t].doc.page(at: i) { renderer.render(p, width: 1920, height: 1080) }; i += threads }
        }
        return elapsedMs(since: t)
    }
    let four = perThread(4), eight = perThread(8)
    print("| \(name) | \(n) | \(String(format: "%.0f", seq)) | \(String(format: "%.0f", sharedMs)) | \(String(format: "%.0f", four)) | \(String(format: "%.0f", eight)) |")
}

// MARK: - 6. Colour space

print("\n## 6. Colour space cost (tikz-heavy, all pages, 1080p, warm, ms total)\n")
print("| Colour space | total ms |")
print("|---|---|")
if let doc = openedDocs["tikz-heavy"] {
    for (label, cs) in [("sRGB", CGColorSpace(name: CGColorSpace.sRGB)!), ("Display P3", CGColorSpace(name: CGColorSpace.displayP3)!), ("Generic RGB linear", CGColorSpace(name: CGColorSpace.genericRGBLinear)!), ("Device RGB", CGColorSpaceCreateDeviceRGB())] {
        let r = Renderer(colorSpace: cs)
        for i in 1...doc.numberOfPages { if let p = doc.page(at: i) { r.render(p, width: 1920, height: 1080) } }
        let t = nowNs()
        for i in 1...doc.numberOfPages { if let p = doc.page(at: i) { r.render(p, width: 1920, height: 1080) } }
        print("| \(label) | \(String(format: "%.0f", elapsedMs(since: t))) |")
    }
}

// MARK: - 7. Warm-cache handoff: cache lookup + CALayer.contents + CATransaction commit (headless)

print("\n## 7. Warm-cache advance: dictionary lookup + `layer.contents = image` + `CATransaction.commit()`, headless\n")
if let doc = openedDocs["basic-169"] {
    var cache: [Int: CGImage] = [:]
    for i in 1...doc.numberOfPages { if let p = doc.page(at: i) { cache[i] = renderer.render(p, width: 3840, height: 2160) } }
    let layer = CALayer()
    layer.frame = CGRect(x: 0, y: 0, width: 3840, height: 2160)
    var xs: [Double] = []
    for k in 0..<200 {
        let t = nowNs()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.contents = cache[(k % doc.numberOfPages) + 1]
        CATransaction.commit()
        xs.append(elapsedMs(since: t) * 1000)   // µs
    }
    let s = Stats(xs)
    print("4K images, 200 advances: median \(String(format: "%.1f", s.median)) µs, p95 \(String(format: "%.1f", s.p95)) µs, max \(String(format: "%.1f", s.max)) µs. One frame at 60 Hz is 16 667 µs; at 120 Hz 8 333 µs.")
    print("\nThis is the CPU-side cost only; there is no window or render server here. Input→glass latency is measured with os_signpost in M1.")
}

// MARK: - 8. Memory footprint of the prefetch set

print("\n## 8. Memory per cached image and per prefetch set (committed ±2, next frame, back target ≈ 6 images per surface)\n")
print("| Size | MB per image | MB for 6 images | MB for 2 surfaces (audience + presenter current) |")
print("|---|---|---|---|")
for t in targets {
    let mb = Double(t.width * t.height * 4) / 1_048_576
    print("| \(t.name) | \(String(format: "%.1f", mb)) | \(String(format: "%.0f", mb * 6)) | \(String(format: "%.0f", mb * 12)) |")
}

/// Maps the page's rotated crop box exactly onto `rect`. `CGPDFPageGetDrawingTransform` only scales *down* into the
/// rect it is given (CGPDFPage.h), so go through the unit square and stretch onto `rect` ourselves.
func pageTransform(_ page: CGPDFPage, onto rect: CGRect) -> CGAffineTransform {
    let toUnit = page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: 1, height: 1), rotate: 0, preserveAspectRatio: false)
    let unitToRect = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
    return toUnit.concatenating(unitToRect)
}
