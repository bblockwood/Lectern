import Foundation
import Observation
import os

/// UI state for the host window. Transports call `sink` from their own queues;
/// the sink hops to the main actor, off the echo path.
@MainActor
@Observable
final class HostModel {
    struct LogLine: Identifiable {
        let id: Int
        let text: String
    }

    var tcpState = "starting"
    var tcpClients = 0
    var tcpPings = 0
    var bleState = "starting"
    var bleSubscribers = 0
    var blePings = 0
    var lastSummary: [SpikeMessage.Transport: String] = [:]
    var log: [LogLine] = []
    var csvDirectory = ""

    private var nextLogID = 0
    private var tcp: TCPEchoServer?
    private var ble: BLEPeripheralHost?
    private let csv = CSVLogger()
    private let logger = Logger(subsystem: "dev.lectern.spike", category: "host")

    func start() {
        guard tcp == nil else { return }
        let sink: HostEventSink = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let tcp = TCPEchoServer(sink: sink)
        let ble = BLEPeripheralHost(sink: sink)
        self.tcp = tcp
        self.ble = ble
        tcp.start()
        ble.start()
        Task { csvDirectory = await csv.directoryPath; append("CSV directory: \(csvDirectory)") }
    }

    private func handle(_ event: HostEvent) {
        switch event {
        case .tcpState(let state):
            tcpState = state
            append("TCP: \(state)")
        case .tcpClients(let count):
            tcpClients = count
        case let .tcpMessage(data, receivedAt):
            tcpPings += 1
            record(data, receivedAt: receivedAt, via: .aViaMac)
        case .bleState(let state):
            bleState = state
            append("BLE: \(state)")
        case .bleSubscribers(let count):
            bleSubscribers = count
        case let .bleMessage(data, receivedAt):
            blePings += 1
            record(data, receivedAt: receivedAt, via: .bBluetooth)
        case .info(let text):
            append(text)
        }
    }

    private func record(_ data: Data, receivedAt: UInt64, via transport: SpikeMessage.Transport) {
        guard let message = SpikeMessage(data: data) else {
            append("\(transport.code): unparseable \(data.count) bytes")
            return
        }
        switch message {
        case let .ping(route, id, tSend):
            let code = route == .phoneEcho ? SpikeMessage.Transport.aPhoneOnly.code : transport.code
            Task { await csv.append(transport: code, fields: ["ping", "\(id)", "\(tSend)", "\(receivedAt)"]) }
            if id % 10 == 0 { append("\(code): ping #\(id)") }
        case let .summary(reported, count, medianMicros, p95Micros):
            let median = Double(medianMicros) / 1000
            let p95 = Double(p95Micros) / 1000
            let text = String(format: "n=%d  RTT median %.1f ms  p95 %.1f ms  (one-way ≈ %.1f / %.1f ms)",
                              Int(count), median, p95, median / 2, p95 / 2)
            lastSummary[reported] = text
            append("\(reported.code) summary: \(text)")
            Task { await csv.append(transport: reported.code, fields: ["summary", "\(count)", String(format: "%.3f", median), String(format: "%.3f", p95)]) }
        case .nack:
            append("\(transport.code): nack")
        }
    }

    private func append(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        log.append(LogLine(id: nextLogID, text: text))
        nextLogID += 1
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}
