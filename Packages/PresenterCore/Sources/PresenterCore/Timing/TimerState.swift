import Foundation

/// Talk timer (SPEC §6.7). Elapsed time starts at the first advance or a manual start.
public struct TimerState: Hashable, Sendable {
    /// Seconds accumulated before `runningSince`.
    public var accumulated: TimeInterval = 0
    /// Non-nil while running.
    public var runningSince: Date? = nil
    public var target: TimeInterval? = nil
    /// False until the first start (manual or automatic); reset clears it. Drives auto-start on the first advance.
    public private(set) var hasStarted: Bool = false

    public init(accumulated: TimeInterval = 0, runningSince: Date? = nil, target: TimeInterval? = nil) {
        self.accumulated = accumulated
        self.runningSince = runningSince
        self.target = target
        self.hasStarted = accumulated > 0 || runningSince != nil
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
        hasStarted = true
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
        hasStarted = false
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
