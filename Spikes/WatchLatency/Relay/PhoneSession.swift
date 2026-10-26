import Foundation
import WatchConnectivity

/// WatchConnectivity on the iPhone: receives pings from the Watch and either echoes
/// them itself (A′) or relays them to the Mac and returns the Mac's echo (A).
final class PhoneSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let link: HostLink
    private let sink: RelayEventSink

    init(link: HostLink, sink: @escaping RelayEventSink) {
        self.link = link
        self.sink = sink
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            sink(.wcState("WatchConnectivity unsupported on this device"))
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let paired = session.isPaired ? "paired" : "not paired"
        let installed = session.isWatchAppInstalled ? "watch app installed" : "watch app NOT installed"
        sink(.wcState("activation \(activationState.rawValue) (\(paired), \(installed))\(error.map { ": \($0)" } ?? "")"))
        sink(.wcReachable(session.isReachable))
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        sink(.wcState("inactive"))
    }

    func sessionDidDeactivate(_ session: WCSession) {
        sink(.wcState("deactivated, re-activating"))
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        sink(.wcReachable(session.isReachable))
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        guard let message = SpikeMessage(data: messageData) else {
            replyHandler(SpikeMessage.nack(reason: .malformed).encoded)
            return
        }
        switch message {
        case let .ping(route: .phoneEcho, id, _):
            replyHandler(messageData)
            sink(.phoneEchoed)
            if id % 10 == 0 { sink(.info("A′ echoed #\(id)")) }
        case let .ping(route: .macEcho, id, _):
            link.send(messageData, reply: replyHandler)
            sink(.forwarded)
            if id % 10 == 0 { sink(.info("A forwarded #\(id)")) }
        case .ping(route: .bluetooth, _, _):
            replyHandler(SpikeMessage.nack(reason: .malformed).encoded)
        case .summary:
            link.sendNoReply(messageData)
            replyHandler(messageData)
        case .nack:
            replyHandler(messageData)
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        link.sendNoReply(messageData)
    }
}
