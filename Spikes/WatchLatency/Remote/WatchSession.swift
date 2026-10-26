import Foundation
import WatchConnectivity

/// WatchConnectivity on the Watch: interactive messages to the paired iPhone.
final class WatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    typealias Reply = @Sendable (Data, _ arrivedNanos: UInt64) -> Void
    typealias Failure = @Sendable (any Error) -> Void

    private let sink: WatchEventSink

    init(sink: @escaping WatchEventSink) {
        self.sink = sink
        super.init()
    }

    var isReachable: Bool { WCSession.default.isReachable }

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ data: Data, reply: @escaping Reply, failure: @escaping Failure) {
        WCSession.default.sendMessageData(data, replyHandler: { replyData in
            reply(replyData, SpikeClock.nowNanos)
        }, errorHandler: { error in
            failure(error)
        })
    }

    func sendNoReply(_ data: Data) {
        WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let companion = session.isCompanionAppInstalled ? "iPhone app installed" : "iPhone app NOT installed"
        sink(.wcState("activation \(activationState.rawValue) (\(companion))\(error.map { ": \($0)" } ?? "")"))
        sink(.wcReachable(session.isReachable))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        sink(.wcReachable(session.isReachable))
    }
}
