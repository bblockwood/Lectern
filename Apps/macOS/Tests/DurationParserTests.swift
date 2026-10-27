import Testing
@testable import Lectern

@Suite struct CountdownInput {
    @Test func minutesAndClockForms() {
        #expect(DurationParser.seconds(from: "45") == 2700)
        #expect(DurationParser.seconds(from: " 20 ") == 1200)
        #expect(DurationParser.seconds(from: "2.5") == 150)
        #expect(DurationParser.seconds(from: "45:30") == 2730)
        #expect(DurationParser.seconds(from: "1:05:00") == 3900)
        #expect(DurationParser.seconds(from: "0:30") == 30)
    }

    @Test func unitForms() {
        #expect(DurationParser.seconds(from: "90m") == 5400)
        #expect(DurationParser.seconds(from: "1h") == 3600)
        #expect(DurationParser.seconds(from: "1h30") == 5400)
        #expect(DurationParser.seconds(from: "1h 30m") == 5400)
        #expect(DurationParser.seconds(from: "1.5h") == 5400)
        #expect(DurationParser.seconds(from: "30s") == 30)
        #expect(DurationParser.seconds(from: "2m30") == 150)
    }

    @Test func rejectsNonsense() {
        #expect(DurationParser.seconds(from: "") == nil)
        #expect(DurationParser.seconds(from: "abc") == nil)
        #expect(DurationParser.seconds(from: "0") == nil)
        #expect(DurationParser.seconds(from: "-5") == nil)
        #expect(DurationParser.seconds(from: "1:2:3:4") == nil)
        #expect(DurationParser.seconds(from: "1:xx") == nil)
        #expect(DurationParser.seconds(from: "5x") == nil)
        #expect(DurationParser.seconds(from: "30") != nil)
    }
}
