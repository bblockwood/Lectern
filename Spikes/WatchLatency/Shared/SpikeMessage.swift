import Foundation

/// Wire format shared by the Watch, the iPhone relay and the Mac host.
///
/// Fixed-size big-endian binary so a message fits in one BLE write-without-response
/// and needs no parser beyond a few byte reads.
///
///     ping:    0x01 | route | id: UInt32 | tSend: UInt64            (14 bytes)
///     summary: 0x02 | transport | count: UInt32 | median µs: UInt32 | p95 µs: UInt32  (14 bytes)
///     nack:    0x7F | reason                                         (2 bytes)
///
/// `tSend` is the sender's own monotonic clock; only the sender interprets it.
enum SpikeMessage: Equatable, Sendable {
    /// How the relay should treat a ping it receives from the Watch.
    enum Route: UInt8, Sendable {
        /// The iPhone replies immediately (Transport A′).
        case phoneEcho = 0
        /// The iPhone forwards to the Mac and relays the Mac's echo (Transport A).
        case macEcho = 1
        /// Direct Bluetooth LE to the Mac (Transport B); the relay never sees these.
        case bluetooth = 2
    }

    enum Transport: UInt8, CaseIterable, Sendable, Identifiable {
        case aViaMac = 0
        case aPhoneOnly = 1
        case bBluetooth = 2

        var id: UInt8 { rawValue }

        var code: String {
            switch self {
            case .aViaMac: "A"
            case .aPhoneOnly: "A-phone"
            case .bBluetooth: "B"
            }
        }

        var title: String {
            switch self {
            case .aViaMac: "A: iPhone → Mac"
            case .aPhoneOnly: "A′: iPhone only"
            case .bBluetooth: "B: Bluetooth"
            }
        }

        var route: Route {
            switch self {
            case .aViaMac: .macEcho
            case .aPhoneOnly: .phoneEcho
            case .bBluetooth: .bluetooth
            }
        }
    }

    enum NackReason: UInt8, Sendable {
        case hostUnreachable = 1
        case malformed = 2
    }

    case ping(route: Route, id: UInt32, tSend: UInt64)
    case summary(transport: Transport, count: UInt32, medianMicros: UInt32, p95Micros: UInt32)
    case nack(reason: NackReason)

    static let pingLength = 14
    static let summaryLength = 14

    var encoded: Data {
        var data = Data()
        switch self {
        case let .ping(route, id, tSend):
            data.reserveCapacity(Self.pingLength)
            data.append(0x01)
            data.append(route.rawValue)
            data.appendBigEndian(id)
            data.appendBigEndian(tSend)
        case let .summary(transport, count, median, p95):
            data.reserveCapacity(Self.summaryLength)
            data.append(0x02)
            data.append(transport.rawValue)
            data.appendBigEndian(count)
            data.appendBigEndian(median)
            data.appendBigEndian(p95)
        case let .nack(reason):
            data.append(0x7F)
            data.append(reason.rawValue)
        }
        return data
    }

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard let tag = bytes.first else { return nil }
        switch tag {
        case 0x01:
            guard bytes.count == Self.pingLength, let route = Route(rawValue: bytes[1]) else { return nil }
            self = .ping(route: route,
                         id: bytes.readBigEndian(UInt32.self, at: 2),
                         tSend: bytes.readBigEndian(UInt64.self, at: 6))
        case 0x02:
            guard bytes.count == Self.summaryLength, let transport = Transport(rawValue: bytes[1]) else { return nil }
            self = .summary(transport: transport,
                            count: bytes.readBigEndian(UInt32.self, at: 2),
                            medianMicros: bytes.readBigEndian(UInt32.self, at: 6),
                            p95Micros: bytes.readBigEndian(UInt32.self, at: 10))
        case 0x7F:
            guard bytes.count == 2, let reason = NackReason(rawValue: bytes[1]) else { return nil }
            self = .nack(reason: reason)
        default:
            return nil
        }
    }

    /// The ping id if this is a ping; used to match echoes to outstanding requests.
    var pingID: UInt32? {
        if case let .ping(_, id, _) = self { return id }
        return nil
    }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
}

extension Array where Element == UInt8 {
    func readBigEndian<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value = (value << 8) | T(self[offset + i])
        }
        return value
    }
}

/// Monotonic nanoseconds on the local device. Never compare across devices.
enum SpikeClock {
    static var nowNanos: UInt64 { DispatchTime.now().uptimeNanoseconds }
}

/// Order statistics for a set of round-trip samples, in milliseconds.
struct LatencyStats: Sendable {
    private(set) var samplesMs: [Double] = []

    var count: Int { samplesMs.count }
    var last: Double? { samplesMs.last }
    var median: Double? { percentile(50) }
    var p95: Double? { percentile(95) }

    mutating func add(_ ms: Double) { samplesMs.append(ms) }
    mutating func reset() { samplesMs.removeAll() }

    /// Nearest-rank percentile; `p` in 0...100.
    func percentile(_ p: Double) -> Double? {
        guard !samplesMs.isEmpty else { return nil }
        let sorted = samplesMs.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }

    func summary(for transport: SpikeMessage.Transport) -> SpikeMessage {
        .summary(transport: transport,
                 count: UInt32(count),
                 medianMicros: UInt32(((median ?? 0) * 1000).rounded()),
                 p95Micros: UInt32(((p95 ?? 0) * 1000).rounded()))
    }
}

/// Bluetooth LE identifiers shared by the Mac peripheral and the Watch central.
enum SpikeBLE {
    static let serviceUUIDString = "7E3C0C10-5A1B-4E0C-9F3D-1C2B4A5D6E70"
    static let characteristicUUIDString = "7E3C0C11-5A1B-4E0C-9F3D-1C2B4A5D6E70"
    static let localName = "LecternSpike"
}

/// TCP port the Mac host listens on, so a relay can fall back to `-host 127.0.0.1:52777`
/// when Bonjour is unavailable (for example in the Simulator before local-network consent).
enum SpikeTCP {
    static let port: UInt16 = 52777
    static let bonjourType = "_lectern-spike._tcp"
}
