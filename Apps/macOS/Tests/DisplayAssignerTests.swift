import PresenterCore
import Testing
@testable import Lectern

private let builtin = DisplayInfo(id: "Built-in@3024x1964", name: "Built-in", pixelSize: PixelSize(width: 3024, height: 1964), isBuiltin: true, isMain: true)
private let projector = DisplayInfo(id: "Projector@1920x1080", name: "Projector", pixelSize: PixelSize(width: 1920, height: 1080), isBuiltin: false)
private let monitor = DisplayInfo(id: "Studio@5120x2880", name: "Studio", pixelSize: PixelSize(width: 5120, height: 2880), isBuiltin: false)

@Suite struct DisplayAssignment_ {
    @Test func singleDisplayHasNoAudienceDisplay() {
        let a = DisplayAssigner.assign(displays: [builtin], remembered: [:])
        #expect(a.presenter == builtin)
        #expect(a.audience == nil)
        #expect(!a.hasAudienceDisplay)
    }

    @Test func builtinPresentsAndLargestExternalIsAudience() {
        let a = DisplayAssigner.assign(displays: [projector, builtin, monitor], remembered: [:])
        #expect(a.presenter == builtin)
        #expect(a.audience == monitor)
    }

    @Test func rememberedRolesWin() {
        let a = DisplayAssigner.assign(displays: [builtin, projector, monitor],
                                       remembered: [projector.id: .audience, builtin.id: .presenter])
        #expect(a.audience == projector)
        #expect(a.presenter == builtin)
    }

    @Test func swappedRolesAreHonoured() {
        let a = DisplayAssigner.assign(displays: [builtin, projector],
                                       remembered: [projector.id: .presenter, builtin.id: .audience])
        #expect(a.presenter == projector)
        #expect(a.audience == builtin)
    }

    @Test func noBuiltinUsesMainDisplayAsPresenter() {
        let main = DisplayInfo(id: "A@2560x1440", name: "A", pixelSize: PixelSize(width: 2560, height: 1440), isBuiltin: false, isMain: true)
        let other = DisplayInfo(id: "B@1920x1080", name: "B", pixelSize: PixelSize(width: 1920, height: 1080), isBuiltin: false)
        let a = DisplayAssigner.assign(displays: [other, main], remembered: [:])
        #expect(a.presenter == main)
        #expect(a.audience == other)
    }

    @Test func hotPlugRemovesAudienceAndRestoresIt() {
        let remembered: [String: DisplayRole] = [projector.id: .audience, builtin.id: .presenter]
        let during = DisplayAssigner.assign(displays: [builtin, projector], remembered: remembered)
        #expect(during.audience == projector)
        let unplugged = DisplayAssigner.assign(displays: [builtin], remembered: remembered)
        #expect(unplugged.audience == nil)
        #expect(unplugged.presenter == builtin)
        let replugged = DisplayAssigner.assign(displays: [projector, builtin], remembered: remembered)
        #expect(replugged == during)
    }

    @Test func staleMemoryForOnlyOneDisplayStillPicksAnAudience() {
        let a = DisplayAssigner.assign(displays: [builtin, projector], remembered: [monitor.id: .audience])
        #expect(a.presenter == builtin)
        #expect(a.audience == projector)
    }
}
