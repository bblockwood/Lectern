import Foundation
import PresenterProtocol
import Testing
@testable import PresenterCore

/// Labels: pages 0 | 1 2 3 | 4 5 | 6 (four frames, like a small overlays deck).
private let frames = FrameIndex(labels: ["1", "2", "2", "2", "3", "3", "4"])
private let reducer = SessionReducer(frames: frames)
private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func run(_ commands: [Command], from state: SessionState = SessionState()) -> SessionState {
    var s = state
    for c in commands { reducer.apply(c, to: &s, now: t0) }
    return s
}

@Suite struct Stepping {
    @Test func nextAndPreviousMoveOnePageWithoutHistory() {
        let s = run([.next, .next, .previous])
        #expect(s.committedPage == 1)
        #expect(s.history.isEmpty)
    }

    @Test func stepsClampAtTheEnds() {
        #expect(run([.previous]).committedPage == 0)
        #expect(run(Array(repeating: .next, count: 20)).committedPage == 6)
        #expect(run(Array(repeating: .next, count: 20) + [.nextFrame]).committedPage == 6)
    }

    @Test func nextFrameGoesToFirstPageOfNextFrame() {
        #expect(run([.nextFrame]).committedPage == 1)
        #expect(run([.next, .next, .nextFrame]).committedPage == 4)
    }

    @Test func previousFrameGoesToLastPageOfPreviousFrameFullyBuilt() {
        #expect(run([.goToPage(5), .previousFrame]).committedPage == 3)
        #expect(run([.goToPage(2), .previousFrame]).committedPage == 0)
        #expect(run([.goToPage(0), .previousFrame]).committedPage == 0)
    }

    @Test func frameStepsDoNotPushHistory() {
        let s = run([.nextFrame, .nextFrame, .previousFrame])
        #expect(s.history.isEmpty)
    }
}

@Suite struct JumpsAndHistory {
    @Test func goToPagePushesHistoryAndBackPops() {
        var s = run([.next, .goToPage(5)])
        #expect(s.committedPage == 5)
        #expect(s.history == [1])
        s = run([.back], from: s)
        #expect(s.committedPage == 1)
        #expect(s.history.isEmpty)
    }

    @Test func goToSamePageDoesNotPushHistory() {
        #expect(run([.goToPage(0)]).history.isEmpty)
    }

    @Test func goToFrameLabelJumpsToFirstPageOfThatFrame() {
        let s = run([.goToFrameLabel("3")])
        #expect(s.committedPage == 4)
        #expect(s.history == [0])
        #expect(run([.goToFrameLabel("nope")]).committedPage == 0)
    }

    @Test func backWithEmptyHistoryIsANoOp() {
        let s = run([.next, .back])
        #expect(s.committedPage == 1)
    }

    @Test func historyIsAStack() {
        var s = run([.goToPage(2), .goToPage(5), .goToPage(6)])
        #expect(s.history == [0, 2, 5])
        s = run([.back, .back], from: s)
        #expect(s.committedPage == 2)
        #expect(s.history == [0])
    }

    @Test func jumpsAreClamped() {
        #expect(run([.goToPage(99)]).committedPage == 6)
        #expect(run([.goToPage(-3)]).committedPage == 0)
    }
}

@Suite struct Browsing {
    @Test func browsingNeverTouchesTheCommittedPage() {
        let s = run([.beginBrowse, .next, .next, .browseTo(5)])
        #expect(s.committedPage == 0)
        #expect(s.browsePage == 5)
        #expect(s.presenterPage == 5)
        #expect(s.audiencePage == 0)
    }

    @Test func commitPushesHistoryAndEndsBrowsing() {
        let s = run([.beginBrowse, .browseTo(4), .commitBrowse])
        #expect(s.committedPage == 4)
        #expect(s.browsePage == nil)
        #expect(s.history == [0])
    }

    @Test func committingTheSamePageDoesNotPushHistory() {
        let s = run([.beginBrowse, .commitBrowse])
        #expect(s.history.isEmpty)
        #expect(s.browsePage == nil)
    }

    @Test func cancelRestoresNothingButTheView() {
        let s = run([.next, .beginBrowse, .browseTo(6), .cancelBrowse])
        #expect(s.committedPage == 1)
        #expect(s.browsePage == nil)
    }

    @Test func frameStepsWhileBrowsingMoveTheBrowsePage() {
        let s = run([.beginBrowse, .nextFrame, .nextFrame])
        #expect(s.browsePage == 4)
        #expect(s.committedPage == 0)
    }
}

@Suite struct AudienceAndTimer {
    @Test func audienceModes() {
        #expect(run([.next, .setAudienceMode(.black)]).audiencePage == nil)
        #expect(run([.next, .setAudienceMode(.frozen(page: 1)), .next, .next]).audiencePage == 1)
        #expect(run([.next, .setAudienceMode(.frozen(page: 1)), .next, .setAudienceMode(.live)]).audiencePage == 2)
    }

    @Test func timerAutoStartsOnFirstAdvanceOnly() {
        #expect(run([.previous]).timer.isRunning == false)
        #expect(run([.next]).timer.isRunning == true)
        #expect(run([.nextFrame]).timer.isRunning == true)
        let paused = run([.next, .timerPause, .next])
        #expect(paused.timer.isRunning == false, "an advance after a manual pause must not restart the timer")
    }

    @Test func timerStartPauseReset() {
        var s = SessionState()
        reducer.apply(.timerStart, to: &s, now: t0)
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(30)) == 30)
        reducer.apply(.timerPause, to: &s, now: t0.addingTimeInterval(30))
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(100)) == 30)
        reducer.apply(.timerStart, to: &s, now: t0.addingTimeInterval(100))
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(110)) == 40)
        reducer.apply(.timerReset, to: &s, now: t0.addingTimeInterval(110))
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(200)) == 0)
        #expect(!s.timer.hasStarted)
    }

    @Test func inkIsClearedWhenThePageChanges() {
        let drawn = run([.inkBegin(NormalizedPoint(x: 0.1, y: 0.1), .ephemeral), .inkAppend(NormalizedPoint(x: 0.2, y: 0.2)), .inkEnd])
        #expect(drawn.ink.strokes.count == 1)
        #expect(run([.next], from: drawn).ink.strokes.isEmpty)
    }
}

@Suite struct Pacing {
    @Test func paceThresholds() {
        // 40 frames in 40 minutes: one frame per minute.
        #expect(PaceIndicator.pace(framesDone: 10, framesTotal: 40, elapsed: 600, target: 2400) == .ahead)
        #expect(PaceIndicator.pace(framesDone: 10, framesTotal: 40, elapsed: 720, target: 2400) == .slightlyBehind)
        #expect(PaceIndicator.pace(framesDone: 10, framesTotal: 40, elapsed: 900, target: 2400) == .behind)
        #expect(PaceIndicator.pace(framesDone: 30, framesTotal: 40, elapsed: 900, target: 2400) == .ahead)
    }
}

@Suite struct ControllerBehaviour {
    @MainActor @Test func controllerNotifiesOnlyOnChange() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        let controller = SessionController(document: doc)
        var changes: [(Int, Int)] = []
        controller.onChange = { old, new in changes.append((old.committedPage, new.committedPage)) }
        controller.apply(.previous) // no-op at page 0
        controller.apply(.next)
        controller.apply(.nextFrame)
        #expect(changes.map { $0.1 } == [1, 4])
        #expect(controller.state.committedPage == 4)
    }

    @MainActor @Test func replacingTheDocumentRestoresByLabelAndBuild() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        let controller = SessionController(document: doc)
        controller.apply(.goToPage(6)) // frame "3", build 2 (pages 4,5,6,7)
        #expect(doc.frames.frame(containing: 6).label == "3")
        #expect(doc.frames.buildIndex(of: 6) == 2)
        // Pretend the recompiled deck lost one build of frame 2: same labels for frame 3 but shifted pages.
        let shifted = FrameIndex(labels: ["1", "2", "2", "3", "3", "3", "3", "4"])
        #expect(SessionController.restoredPage(label: "3", build: 2, oldPage: 6, in: shifted) == 5)
        // Label gone: nearest page index, clamped.
        let shorter = FrameIndex(labels: ["1", "2"])
        #expect(SessionController.restoredPage(label: "3", build: 2, oldPage: 6, in: shorter) == 1)
    }
}
