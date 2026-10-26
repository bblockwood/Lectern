import CoreBluetooth
import Foundation

/// Transport B host side: the Mac advertises one service with one characteristic.
/// The Watch writes a ping without response; the host immediately pushes the same
/// bytes back as a notification, so the Watch can time the round trip.
///
/// All CoreBluetooth callbacks and mutable state live on `queue`.
final class BLEPeripheralHost: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.lectern.spike.ble")
    private let sink: HostEventSink
    private var manager: CBPeripheralManager?
    private var characteristic: CBMutableCharacteristic?
    private var subscribers: Set<UUID> = []
    private var pendingNotifications: [Data] = []

    init(sink: @escaping HostEventSink) {
        self.sink = sink
        super.init()
    }

    func start() {
        queue.async { [self] in
            manager = CBPeripheralManager(delegate: self, queue: queue, options: [
                CBPeripheralManagerOptionShowPowerAlertKey: true,
            ])
        }
    }

    // MARK: CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            publishService(on: peripheral)
        case .unauthorized:
            sink(.bleState("unauthorized: allow Bluetooth for Lectern Spike Host in System Settings › Privacy & Security › Bluetooth"))
        case .poweredOff:
            sink(.bleState("Bluetooth is off"))
        case .unsupported:
            sink(.bleState("Bluetooth LE unsupported on this Mac"))
        case .resetting:
            sink(.bleState("resetting"))
        case .unknown:
            sink(.bleState("unknown"))
        @unknown default:
            sink(.bleState("state \(peripheral.state.rawValue)"))
        }
    }

    private func publishService(on peripheral: CBPeripheralManager) {
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: SpikeBLE.characteristicUUIDString),
            properties: [.writeWithoutResponse, .write, .notify],
            value: nil,
            permissions: [.writeable, .readable])
        let service = CBMutableService(type: CBUUID(string: SpikeBLE.serviceUUIDString), primary: true)
        service.characteristics = [characteristic]
        self.characteristic = characteristic
        peripheral.removeAllServices()
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        if let error {
            sink(.bleState("failed to add service: \(error)"))
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [service.uuid],
            CBAdvertisementDataLocalNameKey: SpikeBLE.localName,
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        if let error {
            sink(.bleState("advertising failed: \(error)"))
        } else {
            sink(.bleState("advertising \(SpikeBLE.localName), \(subscribers.count) subscribed"))
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.insert(central.identifier)
        sink(.bleSubscribers(subscribers.count))
        sink(.info("BLE central subscribed \(central.identifier), max notify \(central.maximumUpdateValueLength) bytes"))
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.remove(central.identifier)
        sink(.bleSubscribers(subscribers.count))
        sink(.info("BLE central unsubscribed \(central.identifier)"))
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let now = SpikeClock.nowNanos
        for request in requests {
            guard let value = request.value, let characteristic else { continue }
            // Echo first, log second.
            if !peripheral.updateValue(value, for: characteristic, onSubscribedCentrals: nil) {
                pendingNotifications.append(value)
            }
            sink(.bleMessage(value, receivedAtNanos: now))
        }
        // Writes-with-response need an answer; writes-without-response ignore it.
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let characteristic else { return }
        while let next = pendingNotifications.first {
            guard peripheral.updateValue(next, for: characteristic, onSubscribedCentrals: nil) else { return }
            pendingNotifications.removeFirst()
        }
    }
}
