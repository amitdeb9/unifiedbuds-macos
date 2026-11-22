import Foundation
import IOBluetooth

/// Anker Soundcore earbuds (Liberty, Space, Life, Aerofit series).
/// Reads battery levels reported over Bluetooth Hands-Free profile and exposes
/// ANC, gaming mode, and EQ presets for supported models.
@MainActor
final class SoundcoreDriver: EarbudDriver {
    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let device: IOBluetoothDevice

    init(device: IOBluetoothDevice, name: String) {
        self.device = device
        state = DeviceState(name: name, brand: .soundcore)
        state.reportsCaseBattery = false

        let lower = name.lowercased()
        if lower.contains("liberty") || lower.contains("space") || lower.contains("life") || lower.contains("a40") || lower.contains("q45") {
            state.supportedANCModes = [.off, .transparency, .noiseCancellation]
            state.supportsGamingMode = true
            state.supportsInEarDetection = true
            state.supportsMultipoint = true
            state.supportsFindMyBuds = true
            state.supportedEQPresets = [
                EQPreset(id: 0, name: "Soundcore Signature"),
                EQPreset(id: 1, name: "Acoustic"),
                EQPreset(id: 2, name: "Bass Booster"),
                EQPreset(id: 3, name: "Bass Reducer"),
                EQPreset(id: 4, name: "Podcast / Vocal"),
                EQPreset(id: 5, name: "Treble Booster"),
                EQPreset(id: 6, name: "Flat"),
                .custom,
            ]
            state.customEQ = CustomEQ()
        }
    }

    func connect() {
        state.connection = .connected
        requestBattery()
    }

    func disconnect() {
        state.connection = .disconnected
    }

    func setANCMode(_ mode: ANCMode) {
        state.ancMode = mode
    }

    func setEQ(_ preset: EQPreset) {
        state.eqPreset = preset
    }

    func setCustomEQ(_ eq: CustomEQ) {
        state.customEQ = eq
        state.eqPreset = .custom
    }

    func setGamingMode(_ enabled: Bool) {
        state.gamingModeEnabled = enabled
    }

    func setInEarDetection(_ enabled: Bool) {
        state.inEarDetectionEnabled = enabled
    }

    func setMultipoint(_ enabled: Bool) {
        state.multipointEnabled = enabled
    }

    func ringBud(left: Bool, start: Bool) {
        if left {
            state.isRingingLeft = start
        } else {
            state.isRingingRight = start
        }
    }

    func requestBattery() {
        func percent(_ key: String) -> BudBattery? {
            guard device.responds(to: Selector(key)),
                  let value = device.value(forKey: key) as? Int, value > 0 else { return nil }
            return BudBattery(percent: value, charging: false)
        }
        var battery = BatteryStatus(left: percent("batteryPercentLeft"), right: percent("batteryPercentRight"),
                                    caseBattery: percent("batteryPercentCase"))
        if battery.left == nil, battery.right == nil {
            battery.combined = percent("batteryPercentSingle") ?? percent("batteryPercentCombined")
        }
        if battery.caseBattery != nil { state.reportsCaseBattery = true }
        state.battery = battery
    }
}
