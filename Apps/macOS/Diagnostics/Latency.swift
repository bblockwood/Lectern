import Foundation
import PresenterCore
import os

/// Input → command applied → contents set → next frame target (SPEC §3.3 signposts, Principle 3).
/// Timestamps share the `mach_absolute_time` base used by `NSEvent.timestamp` and `CADisplayLink`.
@MainActor
final class Latency {
    static let shared = Latency()

    struct Sample: Sendable {
        var input: TimeInterval
        /// When the app's event monitor saw the event; input → received is event delivery, not our code.
        var received: TimeInterval
        var applied: TimeInterval?
        var contents: TimeInterval?
        var hit: Bool?
        var page: Int?
        /// First display-link vsync after the swap: the earliest the frame can be on glass.
        var vsync: TimeInterval?
        /// That tick's target timestamp: the latest it will be on glass.
        var frameTarget: TimeInterval?

        var inputToReceived: Double { (received - input) * 1000 }
        var inputToApplied: Double? { applied.map { ($0 - input) * 1000 } }
        var receivedToContents: Double? { contents.map { ($0 - received) * 1000 } }
        var inputToContents: Double? { contents.map { ($0 - input) * 1000 } }
        var inputToVsync: Double? { vsync.map { ($0 - input) * 1000 } }
        var inputToFrame: Double? { frameTarget.map { ($0 - input) * 1000 } }
        var refreshPeriod: Double? { if let vsync, let frameTarget { (frameTarget - vsync) * 1000 } else { nil } }
    }

    /// The surface whose swap counts as "the audience saw it": the audience surface while presenting.
    var primaryRole: SurfaceSpec.Role = .presenterCurrent
    /// Arming a display link per advance is only worth it when someone reads the numbers (self-test, or
    /// `defaults write dev.lectern.mac LecternMeasureFrames -bool YES` with Console filtering `dev.lectern`).
    let measuresFrames = CommandLine.arguments.contains("-selftest") || UserDefaults.standard.bool(forKey: "LecternMeasureFrames")
    private(set) var samples: [Sample] = []
    var onSample: ((Sample) -> Void)?

    private var current: Sample?
    private var interval: OSSignpostIntervalState?
    private let signposter = OSSignposter(subsystem: "dev.lectern", category: "latency")
    private let log = Logger(subsystem: "dev.lectern", category: "latency")

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func inputReceived(at timestamp: TimeInterval) {
        finishCurrent()
        current = Sample(input: timestamp, received: Latency.now())
        interval = signposter.beginInterval("advance", id: signposter.makeSignpostID())
    }

    func commandApplied() {
        guard current != nil else { return }
        current?.applied = Latency.now()
        signposter.emitEvent("applied")
    }

    func contentsShown(role: SurfaceSpec.Role, hit: Bool, page: Int?) {
        guard role == primaryRole, current != nil, current?.contents == nil else { return }
        current?.contents = Latency.now()
        current?.hit = hit
        current?.page = page
        signposter.emitEvent(hit ? "contents-hit" : "contents-miss")
    }

    func contentsMissed(role: SurfaceSpec.Role, page: Int) {
        guard role == primaryRole, current != nil else { return }
        current?.hit = false
        current?.page = page
    }

    func framePresented(role: SurfaceSpec.Role, vsync: TimeInterval, target: TimeInterval) {
        guard role == primaryRole, current != nil, current?.contents != nil else { return }
        current?.vsync = vsync
        current?.frameTarget = target
        finishCurrent()
    }

    private func finishCurrent() {
        guard let sample = current else { return }
        current = nil
        if let interval { signposter.endInterval("advance", interval) }
        interval = nil
        samples.append(sample)
        if samples.count > 2000 { samples.removeFirst(samples.count - 2000) }
        let applied = sample.inputToApplied.map { String(format: "%.2f", $0) } ?? "–"
        let contents = sample.inputToContents.map { String(format: "%.2f", $0) } ?? "–"
        let frame = sample.inputToFrame.map { String(format: "%.1f", $0) } ?? "–"
        log.info("advance: applied \(applied, privacy: .public) ms, contents \(contents, privacy: .public) ms (\(sample.hit == true ? "hit" : "miss", privacy: .public)), frame target \(frame, privacy: .public) ms")
        onSample?(sample)
    }

    // MARK: - Summary

    struct Stats {
        var count: Int
        var median: Double
        var p95: Double
        var max: Double
    }

    static func stats(_ values: [Double]) -> Stats? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        func pct(_ p: Double) -> Double { sorted[Int((Double(sorted.count - 1) * p).rounded())] }
        return Stats(count: sorted.count, median: pct(0.5), p95: pct(0.95), max: sorted.last!)
    }

    func summary(of samples: [Sample]) -> String {
        // Presses that did not change the audience surface (overview keys, browsing) carry no contents event.
        let changed = samples.filter { $0.contents != nil }
        let hits = changed.filter { $0.hit == true }.count
        func line(_ name: String, _ values: [Double]) -> String {
            guard let s = Latency.stats(values) else { return "\(name): no data" }
            return String(format: "%@: median %.2f ms, p95 %.2f ms, max %.2f ms (n=%d)", name, s.median, s.p95, s.max, s.count)
        }
        return [
            "samples: \(samples.count) (\(samples.count - changed.count) without an audience change), warm-cache hits: \(hits)/\(changed.count)",
            line("input → event received by app", samples.map(\.inputToReceived)),
            line("input → command applied", samples.compactMap(\.inputToApplied)),
            line("received → audience contents set (our code)", samples.compactMap(\.receivedToContents)),
            line("input → audience contents set", samples.compactMap(\.inputToContents)),
            line("input → first vsync after the swap (earliest on glass)", samples.compactMap(\.inputToVsync)),
            line("input → that frame's target (latest on glass)", samples.compactMap(\.inputToFrame)),
        ].joined(separator: "\n")
    }
}
