import Foundation
import IOBluetooth

/// Xiaomi and Redmi Buds (Redmi Buds 3/4/5/6 Pro, Xiaomi Buds 3/4/5 Pro).
@MainActor
final class XiaomiDriver: EarbudDriver {
    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let device: IOBluetoothDevice

    init(device: IOBluetoothDevice, name: String) {
        self.device = device
        state = DeviceState(name: name, brand: .xiaomi)
        state.reportsCaseBattery = false

        let lower = name.lowercased()
        if lower.contains("pro") || lower.contains("anc") || lower.contains("buds 4") || lower.contains("buds 5") || lower.contains("buds 6") {
            state.supportedANCModes = [.off, .transparency, .noiseCancellation]
            state.supportsGamingMode = true
            state.supportsInEarDetection = true
            state.supportsMultipoint = true
            state.supportsFindMyBuds = true
            state.supportedEQPresets = [
                EQPreset(id: 0, name: "Standard"),
                EQPreset(id: 1, name: "Enhance Bass"),
                EQPreset(id: 2, name: "Enhance Treble"),
                EQPreset(id: 3, name: "Voice"),
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
