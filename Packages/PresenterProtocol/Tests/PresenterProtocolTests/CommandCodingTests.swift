import Foundation
import Testing
@testable import PresenterProtocol

@Test func commandsRoundTripThroughJSON() throws {
    let commands: [Command] = [
        .next, .previousFrame, .goToPage(12), .goToFrameLabel("7"), .followLink(LinkID(page: 3, index: 1)), .back,
        .browseTo(4), .setAudienceMode(.frozen(page: 9)), .setAudienceMode(.black),
        .pointerMove(NormalizedPoint(x: 0.25, y: 0.75)), .inkBegin(NormalizedPoint(x: 0, y: 1), .ephemeral),
        .timerStart, .insertWhiteboard,
    ]
    let data = try JSONEncoder().encode(commands)
    let decoded = try JSONDecoder().decode([Command].self, from: data)
    #expect(decoded == commands)
}
