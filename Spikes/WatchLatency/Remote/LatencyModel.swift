import Foundation
import Observation
import SwiftUI
import os

/// The Watch's state: which transport is selected, the samples per transport, the
/// connection status of both legs, and the auto-run driver.
@MainActor
@Observable
final class LatencyModel {
    typealias Transport = SpikeMessage.Transport

    var transport: Transport = .aViaMac {
        didSet { transportChanged() }
    }
    var stats: [Transport: LatencyStats] = [:]
    var failures: [Transport: Int] = [:]
    var inFlight = 0
    var wcState = "activating"
    var wcReachable = false
    var bleState = "idle"
    var bleReady = false
    var autorunTotal = 100
    var autorunRemaining = 0
    var lastReconnectMs: Double?
    var log: [String] = []

    private var nextID: UInt32 = 0
    private var outstandingBLE: [UInt32: UInt64] = [:]
    private var reconnectStartNanos: UInt64?
    private var pendingPressAfterReconnect = false
    private var autorunTask: Task<Void, Never>?
    private var wc: WatchSession?
    private var ble: BLECentral?
    private let logger = Logger(subsystem: "dev.lectern.spike", category: "watch")

    var currentStats: LatencyStats { stats[transport] ?? LatencyStats() }
    var currentFailures: Int { failures[transport] ?? 0 }

    var connectionText: String {
        switch transport {
        case .aViaMac, .aPhoneOnly: "iPhone \(wcReachable ? "reachable" : "unreachable")"
        case .bBluetooth: "BLE: \(bleState)"
        }
    }

    func start(arguments: [String] = CommandLine.arguments) {
        guard wc == nil else { return }
        let sink: WatchEventSink = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let wc = WatchSession(sink: sink)
        let ble = BLECentral(sink: sink)
        self.wc = wc
        self.ble = ble
        wc.activate()

        if let index = arguments.firstIndex(of: "-transport"), index + 1 < arguments.count {
            switch arguments[index + 1].lowercased() {
            case "a": transport = .aViaMac
            case "aphone", "a-phone", "a'": transport = .aPhoneOnly
            case "b": transport = .bBluetooth
            default: append("unknown -transport \(arguments[index + 1])")
            }
        }
        if let index = arguments.firstIndex(of: "-autorun"), index + 1 < arguments.count,
           let count = Int(arguments[index + 1]), count > 0 {
            autorunTotal = count
            append("autorun \(count) on \(transport.code) once ready")
            Task { await startAutorunWhenReady() }
        }
    }

    // MARK: Pressing

    /// The Next action: one timestamped ping on the selected transport.
    func press() {
        nextID += 1
        let id = nextID
        let tSend = SpikeClock.nowNanos
        let message = SpikeMessage.ping(route: transport.route, id: id, tSend: tSend)
        switch transport {
        case .aViaMac, .aPhoneOnly:
            guard let wc, wc.isReachable else {
                noteUnreachable("iPhone unreachable")
                return
            }
            inFlight += 1
            wc.send(message.encoded) { [weak self] reply, arrived in
                Task { @MainActor in self?.completed(id: id, tSend: tSend, reply: reply, arrivedNanos: arrived) }
            } failure: { [weak self] error in
                Task { @MainActor in self?.failed(id: id, reason: "\(error)") }
            }
        case .bBluetooth:
            guard bleReady, let ble else {
                noteUnreachable("BLE not connected")
                ble?.connect()
                return
            }
            inFlight += 1
            outstandingBLE[id] = tSend
            ble.write(message.encoded)
        }
    }

    private func noteUnreachable(_ why: String) {
        if reconnectStartNanos == nil {
            reconnectStartNanos = SpikeClock.nowNanos
            append("\(why); timing reconnect")
        }
        pendingPressAfterReconnect = true
    }

    private func completed(id: UInt32, tSend: UInt64, reply: Data, arrivedNanos: UInt64) {
        inFlight = max(0, inFlight - 1)
        guard let message = SpikeMessage(data: reply) else {
            failed(id: id, reason: "unparseable reply")
            return
        }
        switch message {
        case let .ping(_, replyID, _):
            guard replyID == id else {
                failed(id: id, reason: "reply id \(replyID) ≠ \(id)")
                return
            }
            record(rttNanos: arrivedNanos - tSend, arrivedNanos: arrivedNanos)
        case .nack(let reason):
            failed(id: id, reason: "nack \(reason)")
        case .summary:
            break
        }
    }

    private func failed(id: UInt32, reason: String) {
        inFlight = max(0, inFlight - 1)
        failures[transport, default: 0] += 1
        append("#\(id) failed: \(reason)")
    }

    private func record(rttNanos: UInt64, arrivedNanos: UInt64) {
        let ms = Double(rttNanos) / 1_000_000
        stats[transport, default: LatencyStats()].add(ms)
        if let start = reconnectStartNanos {
            lastReconnectMs = Double(arrivedNanos - start) / 1_000_000
            reconnectStartNanos = nil
            append(String(format: "reconnect → first echo %.0f ms", lastReconnectMs ?? 0))
        }
        let count = currentStats.count
        if count % 10 == 0 {
            sendSummary()
            append(String(format: "%@ n=%d med %.1f p95 %.1f", transport.code, count, currentStats.median ?? 0, currentStats.p95 ?? 0))
        }
    }

    private func sendSummary() {
        let summary = currentStats.summary(for: transport).encoded
        switch transport {
        case .aViaMac, .aPhoneOnly: wc?.sendNoReply(summary)
        case .bBluetooth: ble?.write(summary)
        }
    }

    func resetCurrent() {
        stats[transport] = LatencyStats()
        failures[transport] = 0
        lastReconnectMs = nil
    }

    // MARK: Auto-run

    func startAutorun() {
        autorunTask?.cancel()
        autorunRemaining = autorunTotal
        autorunTask = Task { [weak self] in
            guard let self else { return }
            while autorunRemaining > 0, !Task.isCancelled {
                press()
                autorunRemaining -= 1
                try? await Task.sleep(for: .milliseconds(250))
            }
            // Wait for outstanding echoes (up to 20 s), then publish a final summary.
            for _ in 0..<80 where inFlight > 0 {
                try? await Task.sleep(for: .milliseconds(250))
            }
            sendSummary()
            append("autorun done: \(transport.code) n=\(currentStats.count) fail=\(currentFailures) in-flight=\(inFlight)")
        }
    }

    func stopAutorun() {
        autorunTask?.cancel()
        autorunRemaining = 0
    }

    private func startAutorunWhenReady() async {
        if transport == .bBluetooth { ble?.connect() }
        for _ in 0..<60 {
            let ready = transport == .bBluetooth ? bleReady : wcReachable
            if ready { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        startAutorun()
    }

    // MARK: Events

    private func transportChanged() {
        append("transport → \(transport.code)")
        if transport == .bBluetooth { ble?.connect() }
    }

    private func handle(_ event: WatchEvent) {
        switch event {
        case .wcState(let text):
            wcState = text
            append("WC: \(text)")
        case .wcReachable(let reachable):
            wcReachable = reachable
            append("WC reachable: \(reachable)")
            if reachable, pendingPressAfterReconnect, transport != .bBluetooth {
                pendingPressAfterReconnect = false
                press()
            }
        case .bleState(let text):
            bleState = text
            append("BLE: \(text)")
        case .bleReady(let ready):
            bleReady = ready
            if ready, pendingPressAfterReconnect, transport == .bBluetooth {
                pendingPressAfterReconnect = false
                press()
            }
        case let .bleNotify(data, arrived):
            guard let message = SpikeMessage(data: data), case let .ping(_, id, tSend) = message else { return }
            guard outstandingBLE.removeValue(forKey: id) != nil else { return }
            inFlight = max(0, inFlight - 1)
            record(rttNanos: arrived - tSend, arrivedNanos: arrived)
        case .info(let text):
            append(text)
        }
    }

    func logPhase(_ phase: ScenePhase) {
        let name: String
        switch phase {
        case .active: name = "active"
        case .inactive: name = "inactive"
        case .background: name = "background"
        @unknown default: name = "phase \(phase)"
        }
        append("scene → \(name)")
    }

    private func append(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        let stamp = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(1)))
        log.append("\(stamp) \(text)")
        if log.count > 150 { log.removeFirst(log.count - 150) }
    }
}
