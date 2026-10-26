import Foundation
import Network

/// Length-prefixed framing over a TCP byte stream: one length byte, then the payload.
/// Every spike message is under 255 bytes, so a single byte suffices.
enum SpikeFraming {
    static func frame(_ payload: Data) -> Data {
        precondition(payload.count < 256, "spike frames are tiny")
        var out = Data(capacity: payload.count + 1)
        out.append(UInt8(payload.count))
        out.append(payload)
        return out
    }

    /// Reads frames until the connection ends; `onFrame` runs on the connection's queue.
    static func receiveFrames(on connection: NWConnection,
                              onFrame: @escaping @Sendable (Data) -> Void,
                              onEnd: @escaping @Sendable (NWError?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { header, _, isComplete, error in
            guard let header, header.count == 1, error == nil else {
                onEnd(error)
                return
            }
            let length = Int(header[header.startIndex])
            guard length > 0 else {
                receiveFrames(on: connection, onFrame: onFrame, onEnd: onEnd)
                return
            }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { payload, _, isComplete, error in
                guard let payload, payload.count == length, error == nil else {
                    onEnd(error)
                    return
                }
                onFrame(payload)
                if isComplete {
                    onEnd(nil)
                } else {
                    receiveFrames(on: connection, onFrame: onFrame, onEnd: onEnd)
                }
            }
            _ = isComplete
        }
    }

    static func send(_ payload: Data, on connection: NWConnection) {
        connection.send(content: frame(payload), completion: .contentProcessed { _ in })
    }
}
