import Foundation

/// Talk timer (SPEC §6.7). It runs only while presenting: `SessionController` starts or resumes it when presenting
/// starts and pauses it when presenting ends; T pauses and resumes it by hand in between (feedback round 7).
public struct TimerState: Hashable, Sendable {
    /// Seconds accumulated before `runningSince`.
    public var accumulated: TimeInterval = 0
    /// Non-nil while running.
    public var runningSince: Date? = nil
    public var target: TimeInterval? = nil

    public init(accumulated: TimeInterval = 0, runningSince: Date? = nil, target: TimeInterval? = nil) {
        self.accumulated = accumulated
        self.runningSince = runningSince
        self.target = target
    }

    public var isRunning: Bool { runningSince != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        if let since = runningSince { return accumulated + max(0, now.timeIntervalSince(since)) }
        return accumulated
    }

    /// Target minus elapsed; negative once over time. Nil without a target.
    public func remaining(at now: Date) -> TimeInterval? {
        target.map { $0 - elapsed(at: now) }
    }

    public mutating func start(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        accumulated += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    public mutating func toggle(at now: Date) {
        if isRunning { pause(at: now) } else { start(at: now) }
    }

    public mutating func reset() {
        accumulated = 0
        runningSince = nil
    }
}

/// Green/amber/red pace against the target (SPEC §6.7).
public enum Pace: Hashable, Sendable {
    case ahead           // green
    case slightlyBehind  // amber
    case behind          // red
}

public enum PaceIndicator {
    /// Compares progress through the main-talk frames with the elapsed fraction of the target.
    /// Behind by up to one minute is green, up to three minutes amber, more is red.
    public static func pace(framesDone: Int, framesTotal: Int, elapsed: TimeInterval, target: TimeInterval) -> Pace {
        guard framesTotal > 0, target > 0 else { return .ahead }
        let expectedFraction = elapsed / target
        let actualFraction = Double(framesDone) / Double(framesTotal)
        let behindSeconds = (expectedFraction - actualFraction) * target
        if behindSeconds <= 60 { return .ahead }
        if behindSeconds <= 180 { return .slightlyBehind }
        return .behind
    }
}
