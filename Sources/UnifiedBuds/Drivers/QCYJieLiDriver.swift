import Foundation
import IOBluetooth

/// QCY earbuds built on JieLi chips (e.g. MeloBuds N20), over the JL_SPP RFCOMM
/// channel using JieLi RCSP framing.
///
/// Frame: `FE DC BA <flag> <opcode> <len u16 BE> <body> EF`. Commands from us use
/// flag C0 and body `<seq> <payload>`; replies use flag 00 and body
/// `<status> <seq> <payload>`. QCY settings ride on opcode FF as the same TLVs the
/// A001 BLE protocol uses (`<id> <len> <data>`, reads are `FE 01 <id>`).
/// Protocol from tsnery/h3-control and checked against a MeloBuds N20.
@MainActor
final class QCYJieLiDriver: EarbudDriver {
    private static let serviceUUIDs = [UUID(uuidString: "00001101-0000-1000-8000-00805F9B34FB")!]

    private enum Opcode {
        static let targetInfo: UInt8 = 0x03
        static let findDevice: UInt8 = 0x19
        static let advNotify: UInt8 = 0xC2
        static let custom: UInt8 = 0xFF
    }

    private enum Setting {
        static let inEar: UInt8 = 0x06
        static let gaming: UInt8 = 0x09
        static let anc: UInt8 = 0x17
        static let eq: UInt8 = 0x22
        static let keys: UInt8 = 0x2B
        static let battery: UInt8 = 0x2F
        static let tonePlay: UInt8 = 0x3D
        static let read: UInt8 = 0xFE
    }

    /// One parametric EQ band as the buds encode it: frequency (Hz, u16 LE),
    /// gain (dB × 100, s16 LE), Q (× 100, u16 LE), filter type (u8).
    private struct Band: Equatable {
        var frequency: UInt16
        var gain: Int16
        var q: UInt16
        var type: UInt8
    }

    private struct Curve: Equatable {
        var index: UInt8
        var masterGain: Int16
        var bands: [Band]
    }

    /// QCY's factory tuning, read from a MeloBuds N20 (preset index 0x0A).
    /// Band 1 is a low shelf and band 8 a high shelf; the rest are peaking.
    private static let factoryCurve = Curve(index: 0x0A, masterGain: -850, bands: [
        Band(frequency: 24, gain: -660, q: 150, type: 4),
        Band(frequency: 43, gain: 200, q: 72, type: 2),
        Band(frequency: 150, gain: -1080, q: 79, type: 2),
        Band(frequency: 455, gain: 150, q: 80, type: 2),
        Band(frequency: 3000, gain: 500, q: 100, type: 2),
        Band(frequency: 5600, gain: -300, q: 150, type: 2),
        Band(frequency: 8800, gain: 600, q: 150, type: 2),
        Band(frequency: 13500, gain: 400, q: 110, type: 3),
    ])

    /// Presets as dB offsets on factory bands 2…8 (43, 150, 455, 3k, 5.6k, 8.8k, 13.5k Hz).
    /// The factory curve cuts 150 Hz by ~11 dB, so the bass presets lift it hard.
    private static let presetOffsets: [(EQPreset, [Int16])] = [
        (EQPreset(id: 0, name: "Default"), [0, 0, 0, 0, 0, 0, 0]),
        (EQPreset(id: 1, name: "Bass Boost"), [6, 8, 2, 0, 0, 0, 0]),
        (EQPreset(id: 7, name: "Extra Bass"), [9, 12, 4, 0, 0, -1, 0]),
        (EQPreset(id: 2, name: "Treble Boost"), [0, 0, 0, 2, 5, 4, 5]),
        (EQPreset(id: 3, name: "Vocal"), [-3, 0, 2, 4, 4, -1, -2]),
        (EQPreset(id: 4, name: "Rock"), [5, 6, -1, 2, 4, 2, 3]),
        (EQPreset(id: 5, name: "Pop"), [1, 4, 2, 3, 2, 1, 1]),
        (EQPreset(id: 6, name: "Classical"), [3, 4, 0, 0, 1, 1, 3]),
    ]

    /// Bass lifts 43 and 150 Hz, mid 455 Hz and 3 kHz, treble the top three bands.
    private static func offsets(for custom: CustomEQ) -> [Int16] {
        let bass = Int16(custom.bass), mid = Int16(custom.mid), treble = Int16(custom.treble)
        return [bass, bass, mid, mid, treble, treble, treble]
    }

    private static func curve(offsets: [Int16]) -> Curve {
        guard offsets.contains(where: { $0 != 0 }) else { return factoryCurve }
        var curve = factoryCurve
        curve.index = 0x80  // custom slot
        for (i, offset) in offsets.enumerated() {
            curve.bands[i + 1].gain = max(-1200, min(1200, curve.bands[i + 1].gain + offset * 100))
        }
        // Lower the master gain only by how far the loudest band now exceeds the
        // factory curve's loudest band, so boosts stay audible without clipping.
        let factoryPeak = factoryCurve.bands.map(\.gain).max() ?? 0
        let peak = curve.bands.map(\.gain).max() ?? 0
        curve.masterGain -= max(0, peak - factoryPeak)
        return curve
    }

    private func curve(for preset: EQPreset) -> Curve? {
        if preset == .custom { return Self.curve(offsets: Self.offsets(for: state.customEQ ?? CustomEQ())) }
        return Self.presetOffsets.first(where: { $0.0 == preset }).map { Self.curve(offsets: $0.1) }
    }

    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let transport: RFCOMMTransport
    /// The buds' ANC read-back doesn't follow writes, so the last mode set (from
    /// the app or the buds' button) is remembered per device instead.
    private let ancDefaultsKey: String
    private let ancLevelDefaultsKey: String
    private let customEQDefaultsKey: String
    private let touchPairsDefaultsKey: String
    private var receivedReply = false
    /// Bumped on every channel open so a previous connection's retry loop stops.
    private var connectionGeneration = 0
    /// The touch table exactly as the buds last reported it (`<gesture> <action>` pairs),
    /// including entries the app doesn't show, so writes change only one pair.
    private var touchPairs: [UInt8] = []
    private var buffer: [UInt8] = []
    private var sequence: UInt8 = 0

    init(device: IOBluetoothDevice, name: String) {
        transport = RFCOMMTransport(device: device, serviceUUIDs: Self.serviceUUIDs, fallbackChannel: 1)
        let address = device.addressString ?? name
        ancDefaultsKey = "ancMode.\(address)"
        ancLevelDefaultsKey = "ancLevel.\(address)"
        customEQDefaultsKey = "customEQ.\(address)"
        touchPairsDefaultsKey = "touchPairs.\(address)"
        state = DeviceState(name: name, brand: .qcy)
        state.supportedANCModes = [.off, .transparency, .noiseCancellation, .adaptive]
        state.ancMode = UserDefaults.standard.string(forKey: ancDefaultsKey).flatMap(ANCMode.init(rawValue:))
        // ANC levels 0…2; the buds' strongest (2) is the default.
        state.ancLevels = ["Low", "Medium", "High"]
        state.ancLevel = UserDefaults.standard.object(forKey: ancLevelDefaultsKey) as? Int ?? 2
        state.customEQ = UserDefaults.standard.data(forKey: customEQDefaultsKey)
            .flatMap { try? JSONDecoder().decode(CustomEQ.self, from: $0) } ?? CustomEQ()

        if let savedPairs = UserDefaults.standard.array(forKey: touchPairsDefaultsKey) as? [UInt8],
           savedPairs.count >= 2, savedPairs.count % 2 == 0 {
            touchPairs = savedPairs
            var map: [UInt8: UInt8] = [:]
            for i in stride(from: 0, to: savedPairs.count - 1, by: 2) { map[savedPairs[i]] = savedPairs[i + 1] }
            state.touchMap = map
        }

        // The N20 never reports the case (0 in every battery reply, nothing over BLE).
        state.reportsCaseBattery = false
        state.supportsGamingMode = true
        state.supportsInEarDetection = true
        state.supportsFindMyBuds = true
        // EQ presets appear once the buds report the factory band layout (see handleEQ).

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

    /// JieLi-based QCY models name their SDP records `JL_SPP`, `JL_A2DP`, …
    static func matches(_ device: IOBluetoothDevice) -> Bool {
        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        return records.contains { $0.getServiceName()?.hasPrefix("JL_") == true }
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
        // [mode, scene, level]: mode 1 = ANC, 2 = off, 3 = transparency.
        // Scene 1 = noisy, 5 = adaptive.
        let payload: [UInt8]
        switch mode {
        case .off: payload = [2, 0, 0]
        case .noiseCancellation: payload = [1, 1, UInt8(state.ancLevel ?? 2)]
        case .adaptive: payload = [1, 5, 0]
        case .transparency: payload = [3, 1, 4]
        }
        send(Opcode.custom, payload: [Setting.anc, UInt8(payload.count)] + payload)
        rememberANC(mode)
    }

    private func rememberANC(_ mode: ANCMode) {
        state.ancMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: ancDefaultsKey)
    }

    func setANCLevel(_ level: Int) {
        state.ancLevel = level
        UserDefaults.standard.set(level, forKey: ancLevelDefaultsKey)
        setANCMode(.noiseCancellation)
    }

    func setEQ(_ preset: EQPreset) {
        guard let curve = curve(for: preset) else { return }
        send(Opcode.custom, payload: Self.eqPayload(for: curve))
        state.eqPreset = preset
    }

    func setTouchAction(_ action: UInt8, forGesture gesture: UInt8) {
        guard let index = stride(from: 0, to: touchPairs.count - 1, by: 2).first(where: { touchPairs[$0] == gesture })
        else { return }
        var pairs = touchPairs
        pairs[index + 1] = action
        send(Opcode.custom, payload: [Setting.keys, UInt8(pairs.count)] + pairs)
        touchPairs = pairs
        UserDefaults.standard.set(pairs, forKey: touchPairsDefaultsKey)
        state.touchMap?[gesture] = action
        // Read back so the menu shows what the buds actually stored.
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.keys])
    }

    func setCustomEQ(_ eq: CustomEQ) {
        state.customEQ = eq
        UserDefaults.standard.set(try? JSONEncoder().encode(eq), forKey: customEQDefaultsKey)
        setEQ(.custom)
    }

    func setGamingMode(_ enabled: Bool) {
        state.gamingModeEnabled = enabled
        send(Opcode.custom, payload: [Setting.gaming, 0x01, enabled ? 0x01 : 0x02])
    }

    func setInEarDetection(_ enabled: Bool) {
        state.inEarDetectionEnabled = enabled
        send(Opcode.custom, payload: [Setting.inEar, 0x01, enabled ? 0x01 : 0x02])
    }

    func ringBud(left: Bool, start: Bool) {
        if left {
            state.isRingingLeft = start
        } else {
            state.isRingingRight = start
        }
        let sound: UInt8 = start ? 0x01 : 0x00
        let timeout: [UInt8] = start ? [0x00, 0x3C] : [0x00, 0x00] // 60s ring, or 0s to stop
        let way: UInt8 = left ? 0x01 : 0x02 // 1 = left, 2 = right

        // Maximize earbud internal hardware volume (Opcode 0x08 = SystemVolume)
        if start {
            send(0x08, payload: [0xFF, 0x02, 0x01, 0x10])
        }

        // JieLi RCSP kJL_FIND_DEVICE opcode 0x19
        // Send both device-side player (0x01) and app-side player (0x00)
        send(Opcode.findDevice, payload: [0x01, sound, timeout[0], timeout[1], way, 0x01])
        send(Opcode.findDevice, payload: [0x01, sound, timeout[0], timeout[1], way, 0x00])

        // QCY vendor settings on opcode 0xFF
        if start {
            send(Opcode.custom, payload: [0x05, 0x01, left ? 0x01 : 0x02])
            send(Opcode.custom, payload: [Setting.tonePlay, 0x01, left ? 0x01 : 0x02])
        } else {
            send(Opcode.custom, payload: [0x05, 0x01, 0x00])
            send(Opcode.custom, payload: [Setting.tonePlay, 0x01, 0x00])
        }
    }

    /// The `22 <len> <index> <master> <bands>` TLV that writes `curve`.
    private static func eqPayload(for curve: Curve) -> [UInt8] {
        var data: [UInt8] = [curve.index] + le(UInt16(bitPattern: curve.masterGain))
        for band in curve.bands {
            data += le(band.frequency) + le(UInt16(bitPattern: band.gain)) + le(band.q) + [band.type]
        }
        return [Setting.eq, UInt8(data.count)] + data
    }

    private static func le(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }

    func requestBattery() {
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.battery])
    }

    // MARK: Protocol

    private func channelOpened() {
        state.connection = .connected
        receivedReply = false
        connectionGeneration += 1
        requestInitialState(attempt: 1, generation: connectionGeneration)
    }

    /// Right after the Bluetooth link comes up the buds ignore requests for a few
    /// seconds, so repeat the reads until something answers.
    private func requestInitialState(attempt: Int, generation: Int) {
        send(Opcode.targetInfo, payload: [0xFF, 0xFF, 0xFF, 0xFF])
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.anc])
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.eq])
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.keys])
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.gaming])
        send(Opcode.custom, payload: [Setting.read, 0x01, Setting.inEar])
        requestBattery()
        guard attempt < 25 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, generation == self.connectionGeneration,
                  !self.receivedReply, self.state.connection == .connected else { return }
            self.requestInitialState(attempt: attempt + 1, generation: generation)
        }
    }

    private func send(_ opcode: UInt8, payload: [UInt8]) {
        sequence &+= 1
        let length = payload.count + 1
        let frame: [UInt8] = [0xFE, 0xDC, 0xBA, 0xC0, opcode, UInt8(length >> 8), UInt8(length & 0xFF), sequence]
            + payload + [0xEF]
        do {
            try transport.send(Data(frame))
        } catch {
            state.connection = .failed(error.localizedDescription)
        }
    }

    private func receive(_ data: Data) {
        buffer += data
        while buffer.count >= 8 {
            guard let start = (0...(buffer.count - 3)).first(where: {
                buffer[$0] == 0xFE && buffer[$0 + 1] == 0xDC && buffer[$0 + 2] == 0xBA
            }) else {
                buffer.removeFirst(buffer.count - 2)
                return
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 8 else { return }
            let length = Int(buffer[5]) << 8 | Int(buffer[6])
            guard length <= 530 else { buffer.removeFirst(3); continue }
            guard buffer.count >= length + 8 else { return }
            let frame = Array(buffer[0..<(length + 8)])
            buffer.removeFirst(length + 8)
            guard frame.last == 0xEF else { continue }
            if !receivedReply { connectionLog.info("first reply from buds") }
            receivedReply = true
            let flag = frame[3]
            let body = Array(frame[7..<(7 + length)])
            if flag & 0x80 != 0 {
                // Pushed by the buds: body is <seq> <payload>.
                handle(opcode: frame[4], payload: Array(body.dropFirst()), pushed: true)
            } else if body.first == 0 {
                // Successful reply: body is <status> <seq> <payload>.
                handle(opcode: frame[4], payload: Array(body.dropFirst(2)), pushed: false)
            }
        }
    }

    private func handle(opcode: UInt8, payload: [UInt8], pushed: Bool) {
        switch opcode {
        case Opcode.custom:
            var i = 0
            while i + 1 < payload.count {
                let id = payload[i]
                let length = Int(payload[i + 1])
                guard i + 2 + length <= payload.count else { break }
                handleSetting(id: id, data: Array(payload[(i + 2)..<(i + 2 + length)]), pushed: pushed)
                i += 2 + length
            }
        case Opcode.findDevice where payload.count >= 2:
            let sound = payload[1]
            if sound == 0x00 {
                state.isRingingLeft = false
                state.isRingingRight = false
            }
        case Opcode.advNotify where payload.count >= 17:
            // vid, uid, pid (u16 each), chip, EDR address[6], action, then L, R, case.
            handleBattery(Array(payload[14..<17]))
        default:
            break
        }
    }

    private func handleSetting(id: UInt8, data: [UInt8], pushed: Bool) {
        switch id {
        case Setting.gaming where !data.isEmpty:
            state.gamingModeEnabled = (data[0] == 0x01)
        case Setting.inEar where !data.isEmpty:
            state.inEarDetectionEnabled = (data[0] == 0x01)
        case Setting.anc where data.count >= 2:
            let mode: ANCMode
            switch data[0] {
            case 1: mode = data[1] == 5 ? .adaptive : .noiseCancellation
            case 2: mode = .off
            case 3: mode = .transparency
            default: return
            }
            // A push comes from the buds' own button and is current; a read reply
            // is only trusted when nothing has been remembered yet.
            if pushed {
                rememberANC(mode)
            } else if state.ancMode == nil {
                state.ancMode = mode
            }
            if data[0] == 1, data[1] != 5, data.count >= 3, pushed {
                state.ancLevel = Int(min(data[2], 2))
            }
        case Setting.eq:
            handleEQ(data)
        case Setting.battery:
            handleBattery(data)
        case Setting.keys where data.count >= 2 && data.count % 2 == 0:
            connectionLog.info("touch table: \(data.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
            touchPairs = data
            UserDefaults.standard.set(data, forKey: touchPairsDefaultsKey)
            var map: [UInt8: UInt8] = [:]
            for i in stride(from: 0, to: data.count - 1, by: 2) { map[data[i]] = data[i + 1] }
            state.touchMap = map
        default:
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            connectionLog.info("unhandled setting 0x\(String(format: "%02X", id), privacy: .public): \(hex, privacy: .public)")
        }
    }

    /// `<index> <master gain s16 LE> (<band>)…`, 7 bytes per band.
    private func handleEQ(_ data: [UInt8]) {
        guard data.count >= 3, (data.count - 3) % 7 == 0 else { return }
        func u16(_ i: Int) -> UInt16 { UInt16(data[i]) | UInt16(data[i + 1]) << 8 }
        let bands = stride(from: 3, to: data.count, by: 7).map {
            Band(frequency: u16($0), gain: Int16(bitPattern: u16($0 + 2)), q: u16($0 + 4), type: data[$0 + 6])
        }
        let curve = Curve(index: data[0], masterGain: Int16(bitPattern: u16(1)), bands: bands)
        // Only offer presets on buds whose band layout matches the factory curve,
        // since the presets are offsets on it.
        let layout = { (curve: Curve) in curve.bands.map { [$0.frequency, $0.q, UInt16($0.type)] } }
        guard layout(curve) == layout(Self.factoryCurve) else { return }
        state.supportedEQPresets = Self.presetOffsets.map(\.0) + [.custom]
        state.eqPreset = state.supportedEQPresets.first { self.curve(for: $0) == curve }
    }

    /// `[L, R, case]`, bit 7 = charging, 0 = not reported.
    private func handleBattery(_ bytes: [UInt8]) {
        func level(_ index: Int) -> BudBattery? {
            guard index < bytes.count, bytes[index] & 0x7F > 0 else { return nil }
            return BudBattery(percent: Int(bytes[index] & 0x7F), charging: bytes[index] & 0x80 != 0)
        }
        state.battery = BatteryStatus(left: level(0), right: level(1), caseBattery: level(2))
    }
}
