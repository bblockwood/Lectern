import Foundation

enum RelayEvent: Sendable {
    case hostState(String, connected: Bool)
    case wcState(String)
    case wcReachable(Bool)
    case forwarded
    case phoneEchoed
    case info(String)
}

typealias RelayEventSink = @Sendable (RelayEvent) -> Void

/// WatchConnectivity hands us non-Sendable reply blocks; they are safe to call from any
/// thread, so we box them to carry them onto the network queue.
struct SendableBox<T>: @unchecked Sendable {
    let value: T
}
