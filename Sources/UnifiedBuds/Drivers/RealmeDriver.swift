import Foundation
import IOBluetooth

/// realme, OPPO and OnePlus earbuds over RFCOMM using the HeyMelody protocol.
///
/// Frame: `AA <len LEB128 = 7 + payload> 00 00 <command u16 LE> <seq> <payload len u16 LE> <payload>`,
/// no checksum. Replies use `command | 0x8000`. Protocol from BudsControl and Gadgetbridge.
@MainActor
final class RealmeDriver: EarbudDriver {
    private static let serviceUUIDs = [
        UUID(uuidString: "0000079A-D102-11E1-9B23-00025B00A5A5")!,
        UUID(uuidString: "00001107-D102-11E1-9B23-00025B00A5A5")!,
        UUID(uuidString: "00001101-0000-1000-8000-00805F9B34FB")!,
    ]

    private enum Command {
        static let hello: UInt16 = 0x0100
        static let battery: UInt16 = 0x0106
        static let ancQuery: UInt16 = 0x010C
        static let statusPush: UInt16 = 0x0204
        static let subscribe: UInt16 = 0x0205
        static let ancSet: UInt16 = 0x0404
    }

    /// realme noise-control bitmask values.
    private enum ANCMask {
        static let off: UInt16 = 0x01
        static let transparency: UInt16 = 0x02
        static let max: UInt16 = 0x08
        static let smart: UInt16 = 0x20
    }

    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let transport: RFCOMMTransport
    private var buffer: [UInt8] = []
    private var sequence: UInt8 = 0

    init(device: IOBluetoothDevice, name: String, brand: Brand) {
        transport = RFCOMMTransport(device: device, serviceUUIDs: Self.serviceUUIDs, fallbackChannel: 15)
        state = DeviceState(name: name, brand: brand)
        state.supportedANCModes = [.off, .transparency, .noiseCancellation]
        // Built-in EQ preset ids aren't reported by the buds or documented for
        // realme, so EQ stays hidden until they're mapped per model.

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
        let mask: UInt16
        switch mode {
        case .off: mask = ANCMask.off
        case .transparency: mask = ANCMask.transparency
        case .noiseCancellation: mask = ANCMask.max
        case .adaptive: mask = ANCMask.smart
        }
        send(Command.ancSet, payload: [0x01, 0x01, UInt8(mask)])
        state.ancMode = mode
    }

    func setEQ(_ preset: EQPreset) {}

    func requestBattery() {
        send(Command.battery)
    }

    // MARK: Protocol

    private func channelOpened() {
        state.connection = .connected
        send(Command.hello)
        // First byte is the number of subscription types: battery, wear status, noise control.
        send(Command.subscribe, payload: [0x03, 0x01, 0x02, 0x03])
        send(Command.battery)
        send(Command.ancQuery, payload: [0x01, 0x01])
    }

    private func send(_ command: UInt16, payload: [UInt8] = []) {
        sequence &+= 1
        var frame: [UInt8] = [0xAA]
        frame += Self.leb128(7 + payload.count)
        frame += [0x00, 0x00, UInt8(command & 0xFF), UInt8(command >> 8), sequence]
        frame += [UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)]
        frame += payload
        do {
            try transport.send(Data(frame))
        } catch {
            state.connection = .failed(error.localizedDescription)
        }
    }

    private func receive(_ data: Data) {
        buffer += data
        while let start = buffer.firstIndex(of: 0xAA) {
            if start > 0 { buffer.removeFirst(start) }
            var position = 1
            var length = 0
            var shift = 0
            var lengthComplete = false
            while position < buffer.count, shift < 28 {
                let byte = buffer[position]
                length |= Int(byte & 0x7F) << shift
                position += 1
                shift += 7
                if byte & 0x80 == 0 { lengthComplete = true; break }
            }
            if !lengthComplete {
                // Four continuation bytes is not a length: skip this 0xAA. Otherwise wait for more.
                if shift >= 28 { buffer.removeFirst(); continue }
                return
            }
            // A garbage length would otherwise wait for megabytes that never arrive.
            guard length >= 7, length <= 1024 else { buffer.removeFirst(); continue }
            guard buffer.count >= position + length else { return }
            let body = Array(buffer[position..<(position + length)])
            buffer.removeFirst(position + length)
            let command = UInt16(body[2]) | UInt16(body[3]) << 8
            let payloadLength = Int(UInt16(body[5]) | UInt16(body[6]) << 8)
            handle(command: command, payload: Array(body.dropFirst(7).prefix(payloadLength)))
        }
        buffer.removeAll()
    }

    private func handle(command: UInt16, payload: [UInt8]) {
        switch command {
        case Command.battery | 0x8000:
            handleBattery(payload)
        case Command.ancQuery | 0x8000:
            handleANC(payload)
        case Command.statusPush:
            // Pushes start with the subscription type; the rest matches the reply layout.
            switch payload.first {
            case 0x01: handleBattery(payload)
            case 0x03: handleANC(payload)
            default: break
            }
        default:
            break
        }
    }

    /// `<status> <count> (<id> <level | 0x80 charging>)…`; id 1 = left, 2 = right, 3 = case.
    private func handleBattery(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return }
        var battery = state.battery
        var i = 2
        for _ in 0..<Int(payload[1]) where i + 1 < payload.count {
            let value = BudBattery(percent: Int(payload[i + 1] & 0x7F), charging: payload[i + 1] & 0x80 != 0)
            switch payload[i] {
            case 1: battery.left = value
            case 2: battery.right = value
            case 3: battery.caseBattery = value.percent > 0 || value.charging ? value : nil
            default: break
            }
            i += 2
        }
        state.battery = battery
    }

    /// Finds `01 01 <mask lo> [<mask hi>]`; the lowest set bit is the active mode.
    private func handleANC(_ payload: [UInt8]) {
        guard payload.count >= 3 else { return }
        for i in 0..<(payload.count - 2) where payload[i] == 0x01 && payload[i + 1] == 0x01 {
            let mask = UInt16(payload[i + 2]) | (i + 3 < payload.count ? UInt16(payload[i + 3]) << 8 : 0)
            guard mask != 0 else { continue }
            switch mask & (~mask &+ 1) {
            case ANCMask.off: state.ancMode = .off
            case ANCMask.transparency: state.ancMode = .transparency
            case ANCMask.smart:
                if !state.supportedANCModes.contains(.adaptive) { state.supportedANCModes.append(.adaptive) }
                state.ancMode = .adaptive
            default: state.ancMode = .noiseCancellation
            }
            return
        }
    }

    private static func leb128(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value > 0
        return bytes
    }
}
