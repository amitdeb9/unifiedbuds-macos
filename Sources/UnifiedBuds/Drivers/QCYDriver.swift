import CoreBluetooth
import Foundation

/// QCY earbuds over BLE GATT service A001.
///
/// Frames written to 1001 are `FF <bodyLen> { <id> <n> <payload> }…`; settings
/// arrive as the same TLV frames on 1002. Battery also has its own raw
/// characteristic 0008 (`[L, R, case]`). Protocol from qcy-control-macos and QCYBar.
///
/// Newer JieLi-based QCY models (service A002, RCSP framing) are not handled yet.
@MainActor
final class QCYDriver: NSObject, EarbudDriver {
    private enum UUIDs {
        static let service = CBUUID(string: "A001")
        static let command = CBUUID(string: "1001")
        static let settings = CBUUID(string: "1002")
        static let battery = CBUUID(string: "00000008-0000-1000-8000-00805F9B34FB")
        static let eq = CBUUID(string: "0000000B-0000-1000-8000-00805F9B34FB")
    }

    private enum Setting: UInt8 {
        case anc = 0x17
        case battery = 0x2F
        case requestData = 0xFE
    }

    /// Manufacturer company IDs QCY puts in advertisements (little-endian on air).
    private static let companyIDs: Set<UInt16> = [0x521C, 0x522C]

    /// Client-side presets written to the 10-band EQ characteristic
    /// (31 Hz … 16 kHz, -8…+8 dB). Gains taken from qcy-control-macos.
    private static let presetGains: [(EQPreset, [Int8])] = [
        (EQPreset(id: 0, name: "Flat"), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        (EQPreset(id: 1, name: "Bass Boost"), [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        (EQPreset(id: 2, name: "Pop"), [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2]),
        (EQPreset(id: 3, name: "Rock"), [4, 3, 1, -1, -2, -1, 1, 3, 4, 4]),
        (EQPreset(id: 4, name: "Soft"), [1, 1, 0, 0, 0, 0, -1, -2, -3, -3]),
        (EQPreset(id: 5, name: "Classical"), [3, 2, 1, 0, 0, 0, 0, 1, 2, 3]),
        (EQPreset(id: 6, name: "Vocal"), [-3, -2, 0, 2, 3, 3, 2, 1, 0, -1]),
    ]

    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var eqSlot: UInt8 = 1
    private var scanTimeout: DispatchWorkItem?

    init(name: String) {
        state = DeviceState(name: name, brand: .qcy)
        state.supportedANCModes = [.off, .transparency, .noiseCancellation, .adaptive]
        super.init()
    }

    func connect() {
        state.connection = .connecting
        if let central, central.state == .poweredOn {
            findPeripheral()
        } else if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func disconnect() {
        scanTimeout?.cancel()
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        characteristics = [:]
        state.connection = .disconnected
    }

    func setANCMode(_ mode: ANCMode) {
        // [mode, scene, level]: mode 1 = ANC, 2 = off, 3 = transparency.
        // Scene 1 = indoor, 5 = adaptive. Levels are 0-based.
        let payload: [UInt8]
        switch mode {
        case .off: payload = [2, 0, 0]
        case .noiseCancellation: payload = [1, 1, 2]
        case .adaptive: payload = [1, 5, 0]
        case .transparency: payload = [3, 1, 4]
        }
        write(tlvs: [(Setting.anc.rawValue, payload)])
        state.ancMode = mode
    }

    func setEQ(_ preset: EQPreset) {
        guard let peripheral, let characteristic = characteristics[UUIDs.eq],
              let gains = Self.presetGains.first(where: { $0.0 == preset })?.1 else { return }
        let bytes = [eqSlot] + gains.map { UInt8(bitPattern: $0) }
        peripheral.writeValue(Data(bytes), for: characteristic, type: .withoutResponse)
        state.eqPreset = preset
    }

    func requestBattery() {
        guard let peripheral else { return }
        if let battery = characteristics[UUIDs.battery] {
            peripheral.readValue(for: battery)
        } else {
            write(tlvs: [(Setting.requestData.rawValue, [Setting.battery.rawValue])])
        }
    }

    // MARK: Protocol

    private func write(tlvs: [(id: UInt8, payload: [UInt8])]) {
        guard let peripheral, let characteristic = characteristics[UUIDs.command] else { return }
        let body = tlvs.flatMap { [$0.id, UInt8($0.payload.count)] + $0.payload }
        peripheral.writeValue(Data([0xFF, UInt8(body.count)] + body), for: characteristic, type: .withoutResponse)
    }

    private func handleSettings(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF else { return }
        let end = min(bytes.count, 2 + Int(bytes[1]))
        var i = 2
        while i + 1 < end {
            let id = bytes[i]
            let length = Int(bytes[i + 1])
            guard i + 2 + length <= end else { break }
            handleSetting(id: id, payload: Array(bytes[(i + 2)..<(i + 2 + length)]))
            i += 2 + length
        }
    }

    private func handleSetting(id: UInt8, payload: [UInt8]) {
        switch Setting(rawValue: id) {
        case .anc where payload.count >= 2:
            switch payload[0] {
            case 1: state.ancMode = payload[1] == 5 ? .adaptive : .noiseCancellation
            case 2: state.ancMode = .off
            case 3: state.ancMode = .transparency
            default: break
            }
        case .battery:
            handleBattery(payload)
        default:
            break
        }
    }

    private func handleBattery(_ bytes: [UInt8]) {
        func level(_ index: Int) -> BudBattery? {
            guard index < bytes.count, bytes[index] & 0x7F > 0 else { return nil }
            return BudBattery(percent: Int(bytes[index] & 0x7F), charging: bytes[index] & 0x80 != 0)
        }
        state.battery = BatteryStatus(left: level(0), right: level(1), caseBattery: level(2))
    }

    private func handleEQ(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 11 else { return }
        eqSlot = bytes[0]
        let gains = bytes[1...10].map { Int8(bitPattern: $0) }
        state.eqPreset = Self.presetGains.first(where: { $0.1 == gains })?.0
    }

    // MARK: Discovery

    private func findPeripheral() {
        guard let central else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [UUIDs.service])
        if let match = connected.first(where: { namesMatch($0.name) }) ?? connected.first {
            attach(match)
            return
        }
        central.scanForPeripherals(withServices: nil, options: nil)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.peripheral == nil else { return }
            self.central?.stopScan()
            self.state.connection = .failed("QCY control service not found. Close the QCY app and reconnect.")
        }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    private func namesMatch(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        let target = state.name.lowercased()
        return name == target || name.contains(target) || target.contains(name)
    }

    private func attach(_ peripheral: CBPeripheral) {
        scanTimeout?.cancel()
        central?.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central?.connect(peripheral)
    }

    private func didDiscoverAll() {
        guard let peripheral else { return }
        guard characteristics[UUIDs.command] != nil else {
            state.connection = .failed("This QCY model uses an unsupported protocol.")
            return
        }
        for uuid in [UUIDs.settings, UUIDs.battery] {
            if let characteristic = characteristics[uuid] {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if let eq = characteristics[UUIDs.eq] {
            state.supportedEQPresets = Self.presetGains.map(\.0)
            peripheral.readValue(for: eq)
        }
        state.connection = .connected
        write(tlvs: [(Setting.requestData.rawValue, [Setting.anc.rawValue])])
        requestBattery()
    }
}

extension QCYDriver: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                if peripheral == nil, state.connection == .connecting { findPeripheral() }
            case .unauthorized:
                state.connection = .failed("Bluetooth permission denied in System Settings.")
            case .poweredOff:
                state.connection = .failed("Bluetooth is off.")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard self.peripheral == nil else { return }
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
            var isQCY = false
            if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
                let company = UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
                isQCY = Self.companyIDs.contains(company)
            }
            if namesMatch(localName) || isQCY {
                attach(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([UUIDs.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            state.connection = .failed(error?.localizedDescription ?? "Could not connect.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral == self.peripheral else { return }
            self.peripheral = nil
            characteristics = [:]
            state.connection = .disconnected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            // Look the characteristics up under A001 only: the OTA service reuses 1001/1002.
            guard let service = peripheral.services?.first(where: { $0.uuid == UUIDs.service }) else {
                state.connection = .failed("QCY control service not found.")
                return
            }
            peripheral.discoverCharacteristics(
                [UUIDs.command, UUIDs.settings, UUIDs.battery, UUIDs.eq], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] {
                characteristics[characteristic.uuid] = characteristic
            }
            didDiscoverAll()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let value = characteristic.value else { return }
            switch characteristic.uuid {
            case UUIDs.settings: handleSettings(value)
            case UUIDs.battery: handleBattery([UInt8](value))
            case UUIDs.eq: handleEQ(value)
            default: break
            }
        }
    }
}
