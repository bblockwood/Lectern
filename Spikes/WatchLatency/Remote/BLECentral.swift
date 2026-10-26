import CoreBluetooth
import Foundation

/// Transport B on the Watch: central role. Finds the Mac's service, subscribes to its
/// characteristic, writes pings without response and receives echoes as notifications.
///
/// All CoreBluetooth callbacks and mutable state live on `queue`.
final class BLECentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.lectern.spike.watch.ble")
    private let sink: WatchEventSink
    private let serviceUUID = CBUUID(string: SpikeBLE.serviceUUIDString)
    private let characteristicUUID = CBUUID(string: SpikeBLE.characteristicUUIDString)
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var ready = false
    private var wanted = false

    init(sink: @escaping WatchEventSink) {
        self.sink = sink
        super.init()
    }

    /// Creates the manager (which triggers the Bluetooth permission prompt) and connects.
    func connect() {
        queue.async { [self] in
            wanted = true
            if manager == nil {
                manager = CBCentralManager(delegate: self, queue: queue)
            } else if let manager, manager.state == .poweredOn, !ready {
                scan(manager)
            }
        }
    }

    func disconnect() {
        queue.async { [self] in
            wanted = false
            if let peripheral, let manager { manager.cancelPeripheralConnection(peripheral) }
        }
    }

    /// Writes without response. Reports via `.info` if not connected; the model then reconnects.
    func write(_ data: Data) {
        queue.async { [self] in
            guard ready, let peripheral, let characteristic else {
                sink(.info("BLE write skipped: not connected"))
                return
            }
            if !peripheral.canSendWriteWithoutResponse {
                sink(.info("BLE: canSendWriteWithoutResponse is false, write may be delayed"))
            }
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }

    private func scan(_ manager: CBCentralManager) {
        sink(.bleState("scanning for \(SpikeBLE.localName)"))
        manager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if wanted && !ready { scan(central) }
        case .unsupported:
            sink(.bleState("Bluetooth unavailable (unsupported here, e.g. Simulator)"))
        case .unauthorized:
            sink(.bleState("Bluetooth unauthorized: allow it in Settings"))
        case .poweredOff:
            sink(.bleState("Bluetooth is off"))
        case .resetting:
            sink(.bleState("Bluetooth resetting"))
        case .unknown:
            sink(.bleState("Bluetooth state unknown"))
        @unknown default:
            sink(.bleState("Bluetooth state \(central.state.rawValue)"))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        sink(.bleState("found \(peripheral.name ?? "host") RSSI \(RSSI), connecting"))
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        sink(.bleState("connected, discovering service"))
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        sink(.bleState("connect failed: \(error.map { "\($0)" } ?? "unknown")"))
        lostConnection(central)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        sink(.bleState("disconnected\(error.map { ": \($0)" } ?? "")"))
        lostConnection(central)
    }

    private func lostConnection(_ central: CBCentralManager) {
        ready = false
        characteristic = nil
        peripheral = nil
        sink(.bleReady(false))
        if wanted && central.state == .poweredOn { scan(central) }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            sink(.bleState("service missing\(error.map { ": \($0)" } ?? "")"))
            return
        }
        peripheral.discoverCharacteristics([characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else {
            sink(.bleState("characteristic missing\(error.map { ": \($0)" } ?? "")"))
            return
        }
        self.characteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            sink(.bleState("subscribe failed: \(error)"))
            return
        }
        ready = characteristic.isNotifying
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        sink(.bleState(ready ? "subscribed (max write \(mtu) B)" : "unsubscribed"))
        sink(.bleReady(ready))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let now = SpikeClock.nowNanos
        guard let value = characteristic.value, error == nil else {
            sink(.info("BLE notify error: \(error.map { "\($0)" } ?? "no value")"))
            return
        }
        sink(.bleNotify(value, arrivedNanos: now))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {}
}
