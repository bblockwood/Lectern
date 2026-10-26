import CoreGraphics
import Foundation
import Testing
@testable import PresenterCore

@Suite struct EmbeddedNoteAnnotations {
    @Test func pdfpcNotesOnFixtureFour() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("pdfpc-notes.pdf"))
        let notes = EmbeddedNotes.extract(from: doc.source, pageCount: doc.pageCount)
        #expect(notes[0] == "Title page note. Welcome everyone.")
        #expect(notes[1] == "First line of the note.\nSecond line of the note.\n- a markdown list item\n- another item")
        #expect(notes[2] == notes[3] && notes[3] == notes[4], "an un-wrapped \\pdfpcnote repeats on every build")
        #expect(notes[5] == "Note for build one only.")
        #expect(notes[6] == "Note for build two only.")
        #expect(notes[8] == "Backup note.")
        #expect(notes[9] == nil)
    }

    @Test func pdfcommentNotesOnFixtureFive() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("pdfcomment-notes.pdf"))
        let notes = EmbeddedNotes.extract(from: doc.source, pageCount: doc.pageCount)
        #expect(notes[0] == "Title page note via pdfcomment with the default icon.")
        #expect(notes[1] == "A note with the Note icon, a colour and a subject.")
        #expect(notes[2] == "A margin note (pdfmargincomment).")
        #expect(notes[4]?.contains("popup is open") == true)
        #expect(notes[5] == nil, "FreeText is visible content, never a note")
        #expect(notes[6] == nil)
    }

    @Test func decksWithoutNotesHaveNone() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        #expect(EmbeddedNotes.extract(from: doc.source, pageCount: doc.pageCount).isEmpty)
    }
}

@Suite struct PDFPCFiles {
    @Test func jsonFixtureMatchesByLabelAndOverlay() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("pdfpc-notes.pdf"))
        let file = try #require(PDFPCFile.load(forDeck: doc.url))
        #expect(file.format == 2)
        #expect(file.durationMinutes == 30 && file.targetDuration == 1800)
        #expect(file.endSlide == 4)
        #expect(file.noteFontSize == 14)
        let notes = file.notesByPage(frames: doc.frames, labels: doc.pages.map(\.label))
        #expect(notes[1]?.hasPrefix("Sidecar note for frame 2") == true)
        #expect(notes[4]?.hasPrefix("Sidecar note for build 3 of frame 3") == true)
        #expect(notes[9]?.hasPrefix("Sidecar-only note for the last backup frame") == true)
        #expect(notes.count == 3)
    }

    @Test func labelMatchingSurvivesShiftedPages() {
        // The deck gained a build in frame 2, so idx 4 is now build 1 of frame 3; the label+overlay must win.
        let labels: [String?] = ["1", "2", "2", "2", "3", "3", "3"]
        let frames = FrameIndex(labels: labels)
        var file = PDFPCFile()
        file.pages = [PDFPCFile.PageEntry(idx: 4, label: "3", overlay: 2, note: "third build of frame 3")]
        #expect(file.notesByPage(frames: frames, labels: labels) == [6: "third build of frame 3"])
        // An entry whose label no longer exists falls back to idx.
        file.pages = [PDFPCFile.PageEntry(idx: 1, label: "9", overlay: 0, note: "fallback")]
        #expect(file.notesByPage(frames: frames, labels: labels) == [1: "fallback"])
        // No label at all: idx.
        file.pages = [PDFPCFile.PageEntry(idx: 2, note: "plain")]
        #expect(file.notesByPage(frames: frames, labels: labels) == [2: "plain"])
    }

    @Test func legacyFormatIsStillRead() throws {
        let text = """
        [duration]
        25
        [end_user_slide]
        3
        [notes]
        ### 1
        Welcome everyone.
        ### 3
        The key result.
        Second line.
        [font_size]
        20
        """
        let file = try PDFPCFile.parse(data: Data(text.utf8))
        #expect(file.isLegacy)
        #expect(file.durationMinutes == 25)
        #expect(file.endSlide == 2, "legacy end_user_slide is 1-based")
        #expect(file.noteFontSize == 20)
        let labels: [String?] = ["1", "2", "3", "3", "4"]
        let notes = file.notesByPage(frames: FrameIndex(labels: labels), labels: labels)
        #expect(notes[0] == "Welcome everyone.")
        #expect(notes[2] == "The key result.\nSecond line." && notes[3] == notes[2], "legacy notes cover every build of the user slide")
        #expect(notes[1] == nil)
    }

    @Test func garbageIsRejected() {
        #expect(throws: PDFPCFile.ParseError.self) { try PDFPCFile.parse(data: Data("not a pdfpc file".utf8)) }
    }
}

@Suite struct SecondScreen {
    @Test func detectsBeamerLayouts() throws {
        let right = try PresentationDocument.load(url: Fixtures.url("notes-right.pdf"))
        #expect(SecondScreenDetector.detect(pageSize: right.pages[0].size) == .right)
        #expect(SecondScreenDetector.detect(pageSize: right.pages[0].size, hint: "left") == .left)
        let bottom = try PresentationDocument.load(url: Fixtures.url("notes-bottom.pdf"))
        #expect(SecondScreenDetector.detect(pageSize: bottom.pages[0].size) == .bottom)
        #expect(SecondScreenDetector.detect(pageSize: bottom.pages[0].size, hint: "top") == .top)
        for name in ["basic-169.pdf", "overlays.pdf", "tikz-heavy.pdf"] {
            let doc = try PresentationDocument.load(url: Fixtures.url(name))
            #expect(SecondScreenDetector.detect(pageSize: doc.pages[0].size) == nil, Comment(rawValue: name))
        }
        #expect(SecondScreenDetector.detect(pageSize: CGSize(width: 907, height: 255), hint: "none") == .right, "a 'none' hint does not suppress the aspect heuristic")
    }

    @Test func cropsFollowTheLayout() {
        #expect(NotesSplit.right.slideCrop == .leftHalf && NotesSplit.right.notesCrop == .rightHalf)
        #expect(NotesSplit.bottom.slideCrop == .topHalf && NotesSplit.bottom.notesCrop == .bottomHalf)
        #expect(NotesSplit.none.slideCrop == .full && NotesSplit.none.notesCrop == nil)
    }
}

@Suite struct Merging {
    @Test func priorityOrderAndFrameFallback() {
        let frames = FrameIndex(labels: ["1", "2", "2", "2", "3"])
        let table = NotesMerger.merge([
            (.sidecar, [1: "mine", 4: "   "]),
            (.pdfpcFile, [1: "from file", 2: "file build 2"]),
            (.embedded, [1: "embedded", 4: "embedded last"]),
            (.pptx, [0: "ppt"]),
        ])
        #expect(table.byPage[1] == PageNote(text: "mine", source: .sidecar))
        #expect(table.byPage[2] == PageNote(text: "file build 2", source: .pdfpcFile))
        #expect(table.byPage[4] == PageNote(text: "embedded last", source: .embedded), "blank sidecar text does not shadow")
        #expect(table.byPage[0] == PageNote(text: "ppt", source: .pptx))
        // Build 3 of frame 2 has no note: the closest earlier build in the frame supplies it.
        #expect(table.note(for: 3, frames: frames)?.text == "file build 2")
        // Build 1 of frame 2: no earlier build, so any build of the frame.
        #expect(NotesMerger.merge([(.embedded, [3: "late"])]).note(for: 1, frames: frames)?.text == "late")
        #expect(NotesMerger.merge([(.embedded, [0: "x"])]).note(for: 2, frames: frames) == nil)
    }

    @Test func bundleFromFixtureFour() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("pdfpc-notes.pdf"))
        let bundle = NotesLoader.load(document: doc, sidecarNotes: [8: "my backup note"])
        #expect(bundle.table.byPage[1]?.source == .pdfpcFile)
        #expect(bundle.table.byPage[0]?.source == .embedded)
        #expect(bundle.table.byPage[8] == PageNote(text: "my backup note", source: .sidecar))
        #expect(bundle.table.byPage[9]?.source == .pdfpcFile)
        #expect(bundle.detectedSplit == nil)
        #expect(bundle.warnings.isEmpty)
        #expect(bundle.pdfpcFile?.endSlide == 4)
    }

    @Test func bundleFromSecondScreenDeck() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("notes-bottom.pdf"))
        let bundle = NotesLoader.load(document: doc, sidecarNotes: [:])
        #expect(bundle.detectedSplit == .bottom)
        #expect(bundle.table.isEmpty)
    }
}

@Suite struct Markdown {
    @Test func blocks() {
        let text = """
        First line
        second line of the same paragraph

        - one
        - two
          - nested
        1. first
        2) second
        Tail paragraph with *emphasis*
        """
        let blocks = MarkdownBlocks.parse(text)
        #expect(blocks == [
            .paragraph("First line\nsecond line of the same paragraph"),
            .bullet("one", level: 0), .bullet("two", level: 0), .bullet("nested", level: 1),
            .numbered("first", number: 1), .numbered("second", number: 2),
            .paragraph("Tail paragraph with *emphasis*"),
        ])
        #expect(MarkdownBlocks.parse("").isEmpty)
    }
}

@Suite struct Sidecars {
    private func temporaryDeck() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lectern-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let deck = dir.appendingPathComponent("talk.pdf")
        try FileManager.default.copyItem(at: Fixtures.url("overlays.pdf"), to: deck)
        return deck
    }

    @Test func roundTripBesideTheDeck() throws {
        let deck = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: deck.deletingLastPathComponent()) }
        var sidecar = SidecarDocument()
        sidecar.settings.targetDuration = 2400
        sidecar.settings.notesSplit = .right
        sidecar.settings.notesSplitConfirmed = true
        sidecar.settings.endOfTalkPage = 12
        sidecar.setUserNote("Remember the joke", forPage: 3, frameLabel: "3")
        sidecar.ink = [SidecarDocument.PageInk(pageIndex: 2, strokes: [InkStroke(points: [.init(x: 0.1, y: 0.2), .init(x: 0.3, y: 0.4)], mode: .persistent, startedAt: Date(timeIntervalSince1970: 1_000))])]
        sidecar.rehearsal.lastPosition = .init(frameLabel: "3", pageIndex: 3)
        try SidecarStore.save(sidecar, forDeck: deck)
        let url = SidecarStore.url(forDeck: deck)
        #expect(url.lastPathComponent == "talk.lectern.json")
        #expect(url.deletingLastPathComponent().path == deck.deletingLastPathComponent().path)
        let loaded = try #require(SidecarStore.load(forDeck: deck))
        #expect(loaded == sidecar)
        #expect(loaded.userNote(forPage: 3)?.text == "Remember the joke")
        #expect(loaded.notesByPage == [3: "Remember the joke"])
    }

    @Test func unknownKeysAndMissingKeysAreTolerated() throws {
        let json = """
        {"version": 7, "settings": {"targetDuration": 600, "futureSetting": true}, "notes": [{"frameLabel": "2", "pageIndex": 1, "text": "hi", "extra": 1}], "somethingNew": [1, 2, 3]}
        """
        let doc = try JSONDecoder().decode(SidecarDocument.self, from: Data(json.utf8))
        #expect(doc.version == 7)
        #expect(doc.settings.targetDuration == 600)
        #expect(doc.notes.count == 1 && doc.ink.isEmpty && doc.rehearsal.logs.isEmpty)
        #expect(doc.settings.notesSplitConfirmed == false)
    }

    @Test func corruptSidecarIsIgnoredNotFatal() throws {
        let deck = try temporaryDeck()
        defer { try? FileManager.default.removeItem(at: deck.deletingLastPathComponent()) }
        try Data("{ this is not json".utf8).write(to: SidecarStore.url(forDeck: deck))
        #expect(SidecarStore.load(forDeck: deck) == nil)
        #expect(throws: (any Error).self) { try SidecarStore.load(from: SidecarStore.url(forDeck: deck)) }
    }

    @Test func fallsBackToTheContainerWhenTheDirectoryIsReadOnly() throws {
        let deck = try temporaryDeck()
        let dir = deck.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path); try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("lectern-container-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }
        let url = SidecarStore.url(forDeck: deck, container: container)
        #expect(url.deletingLastPathComponent().path == container.path)
        try SidecarStore.save(SidecarDocument(), forDeck: deck, container: container)
        #expect(SidecarStore.load(forDeck: deck, container: container) != nil)
    }
}
