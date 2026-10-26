import Foundation
import Network

/// The relay's TCP leg to the Mac host: Bonjour discovery (or a manual `host:port`),
/// one persistent connection, and a table of outstanding pings awaiting their echo.
///
/// Mutable state is confined to `queue`.
final class HostLink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.lectern.spike.relay.net")
    private let sink: RelayEventSink
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pending: [UInt32: SendableBox<(Data) -> Void>] = [:]
    private var manualEndpoint: NWEndpoint?
    private var connected = false

    init(sink: @escaping RelayEventSink) {
        self.sink = sink
    }

    /// `manual` is `host:port`, used when Bonjour is unavailable.
    func start(manual: String?) {
        queue.async { [self] in
            if let manual, let colon = manual.lastIndex(of: ":"),
               let port = NWEndpoint.Port(String(manual[manual.index(after: colon)...])) {
                let host = NWEndpoint.Host(String(manual[..<colon]))
                manualEndpoint = .hostPort(host: host, port: port)
                sink(.info("manual host \(manual)"))
                connect(to: manualEndpoint!)
            } else {
                browse()
            }
        }
    }

    func send(_ payload: Data, reply: @escaping (Data) -> Void) {
        let boxed = SendableBox(value: reply)
        queue.async { [self] in
            guard connected, let connection, let id = SpikeMessage(data: payload)?.pingID else {
                boxed.value(SpikeMessage.nack(reason: .hostUnreachable).encoded)
                return
            }
            pending[id] = boxed
            SpikeFraming.send(payload, on: connection)
        }
    }

    func sendNoReply(_ payload: Data) {
        queue.async { [self] in
            guard connected, let connection else { return }
            SpikeFraming.send(payload, on: connection)
        }
    }

    private func browse() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: SpikeTCP.bonjourType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.sink(.hostState("browsing for \(SpikeTCP.bonjourType)", connected: false))
            case .failed(let error): self?.sink(.hostState("browse failed: \(error)", connected: false))
            case .waiting(let error): self?.sink(.hostState("browse waiting: \(error)", connected: false))
            default: break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, connection == nil, let first = results.first else { return }
            sink(.info("found \(first.endpoint)"))
            connect(to: first.endpoint)
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func connect(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                connected = true
                sink(.hostState("connected to \(endpoint)", connected: true))
            case .failed(let error):
                sink(.hostState("connection failed: \(error)", connected: false))
                tearDown(retry: true)
            case .waiting(let error):
                sink(.hostState("waiting: \(error)", connected: false))
            case .cancelled:
                tearDown(retry: false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        self.connection = connection
        SpikeFraming.receiveFrames(on: connection) { [weak self] payload in
            guard let self else { return }
            guard let id = SpikeMessage(data: payload)?.pingID, let waiter = pending.removeValue(forKey: id) else { return }
            waiter.value(payload)
        } onEnd: { [weak self] error in
            self?.sink(.info("host connection ended: \(error.map { "\($0)" } ?? "closed")"))
            self?.tearDown(retry: true)
        }
    }

    private func tearDown(retry: Bool) {
        connected = false
        connection?.cancel()
        connection = nil
        let nack = SpikeMessage.nack(reason: .hostUnreachable).encoded
        for waiter in pending.values { waiter.value(nack) }
        pending.removeAll()
        guard retry else { return }
        queue.asyncAfter(deadline: .now() + 1) { [self] in
            guard connection == nil else { return }
            if let manualEndpoint { connect(to: manualEndpoint) } else if browser == nil { browse() }
            else { browser?.cancel(); browser = nil; browse() }
        }
    }
}
