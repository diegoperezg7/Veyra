@preconcurrency import CoreBluetooth
import Foundation
import Observation
@Observable @MainActor final class BluetoothHeartRate: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    var devices: [CBPeripheral] = []
    var connectedName: String?
    var heartRate: Double?
    var state = "disconnected"
    var onValue: ((Double) -> Void)?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    func scan() { if central == nil { central = CBCentralManager(delegate: self, queue: .main) } else if central?.state == .poweredOn { central?.scanForPeripherals(withServices: [CBUUID(string: "180D")]); state = "scanning" } }
    func connect(_ device: CBPeripheral) { central?.stopScan(); peripheral = device; device.delegate = self; central?.connect(device); state = "connecting" }
    func disconnect() { if let peripheral { central?.cancelPeripheralConnection(peripheral) }; central?.stopScan(); connectedName = nil; heartRate = nil }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { if central.state == .poweredOn { scan() } else { state = "bluetoothUnavailable" } }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) { if !devices.contains(where: { $0.identifier == peripheral.identifier }) { devices.append(peripheral) } }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { connectedName = peripheral.name ?? L("heartRateSensor"); state = "connected"; peripheral.discoverServices([CBUUID(string: "180D")]) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) { connectedName = nil; state = "disconnected" }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) { for service in peripheral.services ?? [] { peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: service) } }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) { for characteristic in service.characteristics ?? [] where characteristic.uuid == CBUUID(string: "2A37") { peripheral.setNotifyValue(true, for: characteristic) } }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let data = characteristic.value, data.count >= 2 else { return }
        let bytes = Array(data), wide = bytes[0] & 1 != 0
        guard !wide || bytes.count >= 3 else { return }
        let value = wide ? Double(Int(bytes[1]) | Int(bytes[2]) << 8) : Double(bytes[1])
        guard (25...250).contains(value) else { return }; heartRate = value; onValue?(value)
    }
}
