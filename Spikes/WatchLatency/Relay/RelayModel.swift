import Foundation
import Observation
import os

@MainActor
@Observable
final class RelayModel {
    struct LogLine: Identifiable {
        let id: Int
        let text: String
    }

    var hostState = "starting"
    var hostConnected = false
    var wcState = "starting"
    var wcReachable = false
    var forwarded = 0
    var phoneEchoed = 0
    var log: [LogLine] = []

    private var nextLogID = 0
    private var link: HostLink?
    private var session: PhoneSession?
    private let logger = Logger(subsystem: "dev.lectern.spike", category: "relay")

    func start(arguments: [String] = CommandLine.arguments) {
        guard link == nil else { return }
        let sink: RelayEventSink = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let link = HostLink(sink: sink)
        let session = PhoneSession(link: link, sink: sink)
        self.link = link
        self.session = session
        var manual: String?
        if let index = arguments.firstIndex(of: "-host"), index + 1 < arguments.count {
            manual = arguments[index + 1]
        }
        link.start(manual: manual)
        session.activate()
    }

    private func handle(_ event: RelayEvent) {
        switch event {
        case let .hostState(text, connected):
            hostState = text
            hostConnected = connected
            append("host: \(text)")
        case .wcState(let text):
            wcState = text
            append("WC: \(text)")
        case .wcReachable(let reachable):
            wcReachable = reachable
            append("WC reachable: \(reachable)")
        case .forwarded:
            forwarded += 1
        case .phoneEchoed:
            phoneEchoed += 1
        case .info(let text):
            append(text)
        }
    }

    private func append(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        log.append(LogLine(id: nextLogID, text: text))
        nextLogID += 1
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
