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

/// A state that is presenting, since the clock only runs then.
private var presenting: SessionState {
    var s = SessionState()
    s.displayConfig.isPresenting = true
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

    @Test func backAfterSteppingAwayStillReturnsToWhereTheJumpStarted() {
        // Jump to the appendix, show a few builds there, come back: feedback round 7's main case.
        var s = run([.next, .goToPage(4), .next, .next])
        #expect(s.committedPage == 6)
        #expect(s.backTarget == 1)
        s = run([.back], from: s)
        #expect(s.committedPage == 1)
        #expect(s.forwardTarget == 6, "forward returns to where the talk had got to, not to the jump target")
        s = run([.forward], from: s)
        #expect(s.committedPage == 6)
        #expect(s.history == [1])
    }

    @Test func backSkipsEntriesForThePageAlreadyShown() {
        // Jump 0 → 5, then step back by hand to page 0: the entry is spent, so back is not a no-op that eats a press.
        var s = run([.goToPage(5), .goToPage(6)] + Array(repeating: .previous, count: 6))
        #expect(s.committedPage == 0)
        #expect(s.history == [0, 5])
        #expect(s.backTarget == 5, "the button offers the entry that would actually move")
        s = run([.back], from: s)
        #expect(s.committedPage == 5)
        #expect(s.history == [0], "the entry for page 0 stays until it is spent or used")
        s = run(Array(repeating: .previous, count: 5) + [.back], from: s)
        #expect(s.committedPage == 0, "only spent entries remained, so nothing moved")
        #expect(s.history.isEmpty)
        #expect(s.backTarget == nil)
    }

    @Test func forwardWithNothingToGoToIsANoOp() {
        let s = run([.goToPage(3), .forward])
        #expect(s.committedPage == 3)
        #expect(s.forwardTarget == nil)
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

    @Test func advancesNeverStartTheClock() {
        // Feedback round 7: the clock runs only while presenting, so stepping through a deck beforehand leaves it at zero.
        #expect(run([.next, .nextFrame, .next]).timer.isRunning == false)
        #expect(run([.next, .nextFrame], from: presenting).timer.isRunning == false, "presenting starts it via the controller, not an advance")
        let paused = run([.timerStart, .timerPause, .next], from: presenting)
        #expect(paused.timer.isRunning == false, "an advance after a manual pause must not restart the timer")
    }

    @Test func timerStartIsRefusedOutsidePresenting() {
        #expect(run([.timerStart]).timer.isRunning == false)
        #expect(run([.timerStart], from: presenting).timer.isRunning == true)
    }

    @Test func timerStartPauseReset() {
        var s = presenting
        reducer.apply(.timerStart, to: &s, now: t0)
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(30)) == 30)
        reducer.apply(.timerPause, to: &s, now: t0.addingTimeInterval(30))
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(100)) == 30)
        reducer.apply(.timerStart, to: &s, now: t0.addingTimeInterval(100))
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(110)) == 40)
        reducer.apply(.timerReset, to: &s, now: t0.addingTimeInterval(110))
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(110)) == 0)
        #expect(s.timer.isRunning, "a reset mid-talk restarts the clock at once")
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(170)) == 60)
        s.displayConfig.isPresenting = false
        reducer.apply(.timerReset, to: &s, now: t0.addingTimeInterval(170))
        #expect(!s.timer.isRunning, "a reset outside presenting leaves the clock at zero, stopped")
        #expect(s.timer.elapsed(at: t0.addingTimeInterval(400)) == 0)
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

    @MainActor @Test func presentingStartsTheClockAndEndingPausesIt() throws {
        // Feedback round 7: leaving presenting pauses, re-entering (live or rehearsal) resumes with the elapsed time kept.
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        let controller = SessionController(document: doc)
        var live = DisplayConfig()
        live.isPresenting = true
        live.audienceDisplayID = "tv"
        var rehearsal = DisplayConfig()
        rehearsal.isPresenting = true
        controller.setDisplayConfig(live, now: t0)
        #expect(controller.state.timer.isRunning)
        controller.setDisplayConfig(live, now: t0.addingTimeInterval(5))   // a display change while presenting: no effect
        #expect(controller.state.timer.elapsed(at: t0.addingTimeInterval(60)) == 60)
        controller.setDisplayConfig(DisplayConfig(), now: t0.addingTimeInterval(60))
        #expect(!controller.state.timer.isRunning)
        #expect(controller.state.timer.elapsed(at: t0.addingTimeInterval(300)) == 60)
        controller.apply(.next, now: t0.addingTimeInterval(300))
        #expect(!controller.state.timer.isRunning, "an advance outside presenting does not start the clock")
        controller.setDisplayConfig(rehearsal, now: t0.addingTimeInterval(300))
        #expect(controller.state.timer.elapsed(at: t0.addingTimeInterval(310)) == 70)
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

@Suite struct PreviousLandingOnFrameStart {
    private let options = NavigationOptions(previousLandsOnFrameStart: true)

    private func run(_ commands: [Command], from page: Int) -> Int {
        var s = SessionState()
        s.committedPage = page
        for c in commands { reducer.apply(c, to: &s, now: t0, options: options) }
        return s.committedPage
    }

    @Test func insideAFrameItStillStepsOneBuild() {
        #expect(run([.previous], from: 3) == 2)
        #expect(run([.previous], from: 5) == 4)
    }

    @Test func atTheStartOfAFrameItLandsOnThePreviousFramesFirstBuild() {
        #expect(run([.previous], from: 4) == 1)   // frame 3 → frame 2's first build, not its last (page 3)
        #expect(run([.previous], from: 6) == 4)
        #expect(run([.previous], from: 1) == 0)
        #expect(run([.previous], from: 0) == 0)
    }

    @Test func shiftLeftStillLandsOnTheLastBuild() {
        #expect(run([.previousFrame], from: 4) == 3)
    }

    @Test func theDefaultKeepsTheSpecBehaviour() {
        var s = SessionState()
        s.committedPage = 4
        reducer.apply(.previous, to: &s, now: t0)
        #expect(s.committedPage == 3)
    }
}
