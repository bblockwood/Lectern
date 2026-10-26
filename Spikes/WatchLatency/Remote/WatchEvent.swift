import Foundation

enum WatchEvent: Sendable {
    case wcState(String)
    case wcReachable(Bool)
    case bleState(String)
    case bleReady(Bool)
    /// Notification payload and the monotonic time it arrived on the Bluetooth queue.
    case bleNotify(Data, arrivedNanos: UInt64)
    case info(String)
}

typealias WatchEventSink = @Sendable (WatchEvent) -> Void
