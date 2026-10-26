import Foundation
import Testing
@testable import PresenterCore

/// Writes a ZIP with stored or deflated entries so tests can build a .pptx in memory.
enum ZipWriter {
    static func make(_ entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let payload = entry.deflate ? (try! (entry.data as NSData).compressed(using: .zlib)) as Data : entry.data
            let method: UInt16 = entry.deflate ? 8 : 0
            let crc = crc32(entry.data)
            let name = Data(entry.name.utf8)
            let offset = UInt32(out.count)
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0)); out.append(le16(method))
            out.append(le16(0)); out.append(le16(0)); out.append(le32(crc))
            out.append(le32(UInt32(payload.count))); out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(name.count))); out.append(le16(0)); out.append(name); out.append(payload)
            central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(method))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(crc))
            central.append(le32(UInt32(payload.count))); central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(0)); central.append(le32(offset)); central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]) }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffffffff
    }
}

enum SamplePPTX {
    static func notesSlide(_ text: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr/><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr></p:sp>
            <p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
              <p:txBody><a:bodyPr/><a:lstStyle/>\(text.split(separator: "\n").map { "<a:p><a:r><a:rPr lang=\"en-US\"/><a:t>\($0)</a:t></a:r></a:p>" }.joined())</p:txBody></p:sp>
            <p:sp><p:nvSpPr><p:cNvPr id="4" name="Slide Number Placeholder 3"/><p:cNvSpPr/><p:nvPr><p:ph type="sldNum" sz="quarter" idx="10"/></p:nvPr></p:nvSpPr>
              <p:txBody><a:bodyPr/><a:p><a:fld id="{X}" type="slidenum"><a:t>2</a:t></a:fld></a:p></p:txBody></p:sp>
          </p:spTree></p:cSld>
        </p:notes>
        """
    }

    static func slide(hidden: Bool) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"\(hidden ? " show=\"0\"" : "")>
          <p:cSld><p:spTree/></p:cSld>
        </p:sld>
        """
    }

    /// Three slides in sldIdLst order 1, 2 (hidden), 3; notes on 1 and 3.
    static func build(deflate: Bool) -> Data {
        let presentation = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:sldIdLst><p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId3"/><p:sldId id="258" r:id="rId4"/></p:sldIdLst>
        </p:presentation>
        """
        let presentationRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
          <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide3.xml"/>
        </Relationships>
        """
        func slideRels(_ n: Int) -> String {
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide\(n).xml"/>
            </Relationships>
            """
        }
        let parts: [(String, String)] = [
            ("[Content_Types].xml", "<Types/>"),
            ("ppt/presentation.xml", presentation),
            ("ppt/_rels/presentation.xml.rels", presentationRels),
            ("ppt/slides/slide1.xml", slide(hidden: false)),
            ("ppt/slides/slide2.xml", slide(hidden: true)),
            ("ppt/slides/slide3.xml", slide(hidden: false)),
            ("ppt/slides/_rels/slide1.xml.rels", slideRels(1)),
            ("ppt/slides/_rels/slide3.xml.rels", slideRels(3)),
            ("ppt/notesSlides/notesSlide1.xml", notesSlide("Notes for slide one.\nSecond paragraph.")),
            ("ppt/notesSlides/notesSlide3.xml", notesSlide("Notes for slide three.")),
        ]
        return ZipWriter.make(parts.map { ($0.0, Data($0.1.utf8), deflate) })
    }
}

@Suite struct PowerPointNotes {
    @Test(arguments: [false, true]) func mapsVisibleSlidesToPages(deflate: Bool) throws {
        let pptx = try PPTXNotes.parse(data: SamplePPTX.build(deflate: deflate))
        #expect(pptx.slides.count == 3)
        #expect(pptx.slides.map(\.hidden) == [false, true, false])
        #expect(pptx.visibleSlides.count == 2)
        let mapped = pptx.notesByPage(pageCount: 2)
        #expect(mapped.warning == nil)
        #expect(mapped.notes == [0: "Notes for slide one.\nSecond paragraph.", 1: "Notes for slide three."])
    }

    @Test func countMismatchWarnsInsteadOfGuessing() throws {
        let pptx = try PPTXNotes.parse(data: SamplePPTX.build(deflate: false))
        let mapped = pptx.notesByPage(pageCount: 3)
        #expect(mapped.notes.isEmpty)
        #expect(mapped.warning?.contains("2 visible slides") == true)
    }

    @Test func zipReaderRejectsGarbage() {
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(data: Data("hello".utf8)) }
        #expect(throws: ZipArchive.ZipError.entryNotFound("nope")) { try ZipArchive(data: SamplePPTX.build(deflate: false)).contents(of: "nope") }
    }

    @Test func relationshipPathResolution() {
        #expect(Relationships.resolve("slides/slide1.xml", relativeTo: "ppt/presentation.xml") == "ppt/slides/slide1.xml")
        #expect(Relationships.resolve("../notesSlides/notesSlide1.xml", relativeTo: "ppt/slides/slide1.xml") == "ppt/notesSlides/notesSlide1.xml")
        #expect(Relationships.resolve("/ppt/slides/slide2.xml", relativeTo: "ppt/presentation.xml") == "ppt/slides/slide2.xml")
        #expect(Relationships.relsPart(for: "ppt/slides/slide1.xml") == "ppt/slides/_rels/slide1.xml.rels")
    }

    @Test func fixtureNineWhenPresent() throws {
        let url = Fixtures.url("ppt-export.pptx")
        guard FileManager.default.fileExists(atPath: url.path) else { return }   // Ben supplies this one
        let pptx = try PPTXNotes.parse(data: Data(contentsOf: url))
        #expect(pptx.slides.contains { $0.hidden }, "fixture 9 must contain one hidden slide")
        let doc = try PresentationDocument.load(url: Fixtures.url("ppt-export.pdf"))
        let mapped = pptx.notesByPage(pageCount: doc.pageCount)
        #expect(mapped.warning == nil)
        #expect(!mapped.notes.isEmpty)
    }
}
