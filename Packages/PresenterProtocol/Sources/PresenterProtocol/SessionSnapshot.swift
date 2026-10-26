import Foundation

/// The part of the session a remote needs to show (SPEC §9.1). Sent by the host, never mutated by remotes.
public struct SessionSnapshot: Codable, Hashable, Sendable {
    public var pageIndex: Int
    public var pageCount: Int
    public var frameLabel: String
    public var frameNumber: Int
    public var frameCount: Int
    public var buildIndex: Int
    public var buildCount: Int
    public var nextPageIndex: Int?
    public var notesText: String?
    public var audienceMode: AudienceMode
    public var timer: TimerSnapshot

    public init(pageIndex: Int, pageCount: Int, frameLabel: String, frameNumber: Int, frameCount: Int,
                buildIndex: Int, buildCount: Int, nextPageIndex: Int?, notesText: String?,
                audienceMode: AudienceMode, timer: TimerSnapshot) {
        self.pageIndex = pageIndex; self.pageCount = pageCount; self.frameLabel = frameLabel
        self.frameNumber = frameNumber; self.frameCount = frameCount; self.buildIndex = buildIndex
        self.buildCount = buildCount; self.nextPageIndex = nextPageIndex; self.notesText = notesText
        self.audienceMode = audienceMode; self.timer = timer
    }
}

public struct TimerSnapshot: Codable, Hashable, Sendable {
    /// Seconds elapsed at `capturedAt`.
    public var elapsed: TimeInterval
    public var isRunning: Bool
    public var target: TimeInterval?
    public var capturedAt: Date

    public init(elapsed: TimeInterval, isRunning: Bool, target: TimeInterval?, capturedAt: Date) {
        self.elapsed = elapsed; self.isRunning = isRunning; self.target = target; self.capturedAt = capturedAt
    }
}
