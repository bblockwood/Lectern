import Foundation
import Network

/// Transport A host side: a Bonjour-advertised TCP listener that echoes every frame
/// straight back on the connection's own queue, before anything else happens.
///
/// Mutable state is confined to `queue`; hence `@unchecked Sendable`.
final class TCPEchoServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.lectern.spike.tcp")
    private let sink: HostEventSink
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(sink: @escaping HostEventSink) {
        self.sink = sink
    }

    func start() {
        queue.async { [self] in startOnQueue() }
    }

    private func startOnQueue() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: SpikeTCP.port)!)
        } catch {
            sink(.tcpState("failed to listen on \(SpikeTCP.port): \(error)"))
            return
        }
        listener.service = NWListener.Service(name: "Lectern Spike Host", type: SpikeTCP.bonjourType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                sink(.tcpState("listening on port \(listener.port?.rawValue ?? 0), advertising \(SpikeTCP.bonjourType)"))
            case .failed(let error):
                sink(.tcpState("failed: \(error)"))
            case .waiting(let error):
                sink(.tcpState("waiting: \(error)"))
            case .cancelled:
                sink(.tcpState("cancelled"))
            default:
                break
            }
        }
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            self?.sink(.info("Bonjour registration: \(change)"))
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        sink(.tcpClients(connections.count))
        sink(.info("TCP client connected: \(connection.endpoint)"))
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                sink(.info("TCP client failed: \(error)"))
                drop(key)
            case .cancelled:
                drop(key)
            default:
                break
            }
        }
        connection.start(queue: queue)
        SpikeFraming.receiveFrames(on: connection) { [weak self] payload in
            // Echo first, log second: the echo is the thing being timed.
            let now = SpikeClock.nowNanos
            SpikeFraming.send(payload, on: connection)
            self?.sink(.tcpMessage(payload, receivedAtNanos: now))
        } onEnd: { [weak self] error in
            if let error { self?.sink(.info("TCP client ended: \(error)")) }
            connection.cancel()
            self?.drop(key)
        }
    }

    private func drop(_ key: ObjectIdentifier) {
        guard connections.removeValue(forKey: key) != nil else { return }
        sink(.tcpClients(connections.count))
    }
}
