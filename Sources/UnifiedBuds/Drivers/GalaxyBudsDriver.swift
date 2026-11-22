import Foundation
import IOBluetooth

/// Samsung Galaxy Buds (Buds, Buds+, Buds Live, Buds Pro, Buds2, Buds2 Pro, Buds FE, Buds3, Buds3 Pro).
/// Uses Galaxy Buds Protocol (GBP) over RFCOMM / Bluetooth.
@MainActor
final class GalaxyBudsDriver: EarbudDriver {
    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let device: IOBluetoothDevice

    init(device: IOBluetoothDevice, name: String) {
        self.device = device
        state = DeviceState(name: name, brand: .samsung)
        state.reportsCaseBattery = false

        let lower = name.lowercased()
        if lower.contains("pro") || lower.contains("buds2") || lower.contains("buds 2")
            || lower.contains("buds3") || lower.contains("buds 3") || lower.contains("fe") || lower.contains("live") {
            state.supportedANCModes = [.off, .transparency, .noiseCancellation]
            if lower.contains("buds3") || lower.contains("buds 3") || lower.contains("pro 2") || lower.contains("pro2") {
                state.supportedANCModes.append(.adaptive)
            }
            state.supportsGamingMode = true
            state.supportsInEarDetection = true
            state.supportsMultipoint = true
            state.supportsFindMyBuds = true
            state.supportedEQPresets = [
                EQPreset(id: 0, name: "Normal"),
                EQPreset(id: 1, name: "Bass Boost"),
                EQPreset(id: 2, name: "Soft"),
                EQPreset(id: 3, name: "Dynamic"),
                EQPreset(id: 4, name: "Clear"),
                EQPreset(id: 5, name: "Treble Boost"),
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
        connectionLog.info("Galaxy Buds ring \(left ? "left" : "right") bud: \(start ? "started" : "stopped")")
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
