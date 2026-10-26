import Foundation

/// Everything the transports report to the UI/log, delivered on an arbitrary queue.
enum HostEvent: Sendable {
    case tcpState(String)
    case tcpClients(Int)
    case tcpMessage(Data, receivedAtNanos: UInt64)
    case bleState(String)
    case bleSubscribers(Int)
    case bleMessage(Data, receivedAtNanos: UInt64)
    case info(String)
}

typealias HostEventSink = @Sendable (HostEvent) -> Void
