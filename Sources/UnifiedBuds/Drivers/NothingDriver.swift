import Foundation
import IOBluetooth

/// Nothing and CMF earbuds over RFCOMM.
///
/// Frame (little-endian): `55 <control u16> <command u16> <len u16> <opId> <payload> <crc16 u16>`.
/// The CRC is CRC-16/MODBUS over everything before it and is present when
/// control has bit 0x20. Protocol from ear-web, nothing-x-macos and Gadgetbridge.
@MainActor
final class NothingDriver: EarbudDriver {
    private static let serviceUUID = UUID(uuidString: "AEAC4A03-DFF5-498F-843A-34487CF133EB")!

    private enum Command {
        static let getBattery: UInt16 = 0xC007
        static let getANC: UInt16 = 0xC01E
        static let setANC: UInt16 = 0xF00F
        static let getEQ: UInt16 = 0xC01F
        static let setEQ: UInt16 = 0xF010
        static let getListeningMode: UInt16 = 0xC050
        static let setListeningMode: UInt16 = 0xF01D
        static let batteryPush: UInt16 = 0xE001
        static let ancPush: UInt16 = 0xE003
    }

    private enum ANCByte {
        static let high: UInt8 = 0x01
        static let adaptive: UInt8 = 0x04
        static let off: UInt8 = 0x05
        static let transparency: UInt8 = 0x07
    }

    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let transport: RFCOMMTransport
    /// CMF models use the "listening mode" commands for EQ instead of 0xF010/0xC01F.
    private let usesListeningMode: Bool
    private var buffer: [UInt8] = []
    private var operationID: UInt8 = 0

    init(device: IOBluetoothDevice, name: String) {
        let lower = name.lowercased()
        usesListeningMode = lower.hasPrefix("cmf")
        transport = RFCOMMTransport(device: device, serviceUUIDs: [Self.serviceUUID], fallbackChannel: 15)
        state = DeviceState(name: name, brand: .nothing)
        state.supportedANCModes = Self.ancModes(forName: lower)
        state.supportedEQPresets = usesListeningMode
            ? [
                EQPreset(id: 0, name: "Dirac Opteo"),
                EQPreset(id: 1, name: "Rock"),
                EQPreset(id: 2, name: "Electronic"),
                EQPreset(id: 3, name: "Pop"),
                EQPreset(id: 4, name: "Enhance Vocals"),
                EQPreset(id: 5, name: "Classical"),
            ]
            : [
                EQPreset(id: 0, name: "Balanced"),
                EQPreset(id: 1, name: "Voice"),
                EQPreset(id: 2, name: "More Treble"),
                EQPreset(id: 3, name: "More Bass"),
            ]

        transport.onOpen = { [weak self] in
            MainActor.assumeIsolated { self?.channelOpened() }
        }
        transport.onData = { [weak self] data in
            MainActor.assumeIsolated { self?.receive(data) }
        }
        transport.onClose = { [weak self] error in
            MainActor.assumeIsolated {
                self?.state.connection = error.map { .failed($0.localizedDescription) } ?? .disconnected
            }
        }
    }

    /// Per-model ANC support, following the Gadgetbridge coordinators and nothing-x-macos.
    private static func ancModes(forName name: String) -> [ANCMode] {
        if name.contains("stick") || name.contains("open") { return [] }
        let adaptive = ["ear (2)", "ear (a)", "ear (3)", "buds pro 2", "buds 2 plus"].contains { name.contains($0) }
            || name == "nothing ear"
        return adaptive
            ? [.off, .transparency, .noiseCancellation, .adaptive]
            : [.off, .transparency, .noiseCancellation]
    }

    func connect() {
        state.connection = .connecting
        transport.open()
    }

    func disconnect() {
        transport.close()
        buffer = []
        state.connection = .disconnected
    }

    func setANCMode(_ mode: ANCMode) {
        let value: UInt8
        switch mode {
        case .off: value = ANCByte.off
        case .transparency: value = ANCByte.transparency
        case .noiseCancellation: value = ANCByte.high
        case .adaptive: value = ANCByte.adaptive
        }
        send(Command.setANC, payload: [0x01, value, 0x00])
        state.ancMode = mode
    }

    func setEQ(_ preset: EQPreset) {
        send(usesListeningMode ? Command.setListeningMode : Command.setEQ, payload: [preset.id, 0x00])
        state.eqPreset = preset
    }

    func requestBattery() {
        send(Command.getBattery)
    }

    // MARK: Protocol

    private func channelOpened() {
        state.connection = .connected
        send(Command.getBattery)
        if !state.supportedANCModes.isEmpty { send(Command.getANC) }
        send(usesListeningMode ? Command.getListeningMode : Command.getEQ)
    }

    private func send(_ command: UInt16, payload: [UInt8] = []) {
        operationID = operationID == 0xFF ? 1 : operationID + 1
        var frame: [UInt8] = [0x55, 0x60, 0x01]
        frame += [UInt8(command & 0xFF), UInt8(command >> 8)]
        frame += [UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)]
        frame.append(operationID)
        frame += payload
        let crc = Self.crc16(frame)
        frame += [UInt8(crc & 0xFF), UInt8(crc >> 8)]
        do {
            try transport.send(Data(frame))
        } catch {
            state.connection = .failed(error.localizedDescription)
        }
    }

    private func receive(_ data: Data) {
        buffer += data
        while let start = buffer.firstIndex(of: 0x55) {
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 8 else { return }
            let control = UInt16(buffer[1]) | UInt16(buffer[2]) << 8
            let command = UInt16(buffer[3]) | UInt16(buffer[4]) << 8
            let length = Int(UInt16(buffer[5]) | UInt16(buffer[6]) << 8)
            let total = 8 + length + (control & 0x20 != 0 ? 2 : 0)
            // A stray 0x55 inside garbage could claim a huge length and stall parsing.
            guard length <= 1024 else { buffer.removeFirst(); continue }
            guard buffer.count >= total else { return }
            let payload = Array(buffer[8..<(8 + length)])
            buffer.removeFirst(total)
            // Replies come back as 0x40xx and pushes as 0x60xx/0xE0xx; normalize to the request id.
            handle(command: command | 0x8000, payload: payload)
        }
        buffer.removeAll()
    }

    private func handle(command: UInt16, payload: [UInt8]) {
        switch command {
        case Command.getBattery, Command.batteryPush:
            handleBattery(payload)
        case Command.getANC, Command.ancPush:
            handleANC(payload)
        case Command.getEQ, Command.getListeningMode:
            if let id = payload.first {
                // Gadgetbridge numbers Dirac 7 where ear-web uses 0.
                let normalized = usesListeningMode && id == 7 ? 0 : id
                state.eqPreset = state.supportedEQPresets.first { $0.id == normalized }
            }
        default:
            break
        }
    }

    /// `[count, (id, level | 0x80 charging)…]`; id 2 = left, 3 = right, 4 = case.
    private func handleBattery(_ payload: [UInt8]) {
        guard let count = payload.first else { return }
        var battery = state.battery
        var i = 1
        for _ in 0..<count where i + 1 < payload.count {
            let value = BudBattery(percent: Int(payload[i + 1] & 0x7F), charging: payload[i + 1] & 0x80 != 0)
            switch payload[i] {
            case 0x02: battery.left = value
            case 0x03: battery.right = value
            case 0x04: battery.caseBattery = value
            default: break
            }
            i += 2
        }
        state.battery = battery
    }

    /// Repeated `[type, value, 0]` triples; type 1 carries the mode.
    private func handleANC(_ payload: [UInt8]) {
        var i = 0
        while i + 1 < payload.count {
            if payload[i] == 0x01 {
                switch payload[i + 1] {
                case 0x01, 0x02, 0x03: state.ancMode = .noiseCancellation
                case ANCByte.adaptive: state.ancMode = .adaptive
                case ANCByte.off, 0x00: state.ancMode = .off
                case ANCByte.transparency, 0xFE: state.ancMode = .transparency
                default: break
                }
                return
            }
            i += 3
        }
    }

    /// CRC-16/MODBUS: reflected poly 0xA001, init 0xFFFF.
    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }
}
