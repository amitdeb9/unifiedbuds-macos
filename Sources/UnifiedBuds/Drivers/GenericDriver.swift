import Foundation
import IOBluetooth

/// Earbuds whose control protocol isn't known (e.g. boAt). Shows the battery level
/// the buds already report to macOS over the standard hands-free profile; there are
/// no noise, EQ or touch controls. Connect / disconnect and sound output still work.
@MainActor
final class GenericDriver: EarbudDriver {
    private(set) var state: DeviceState {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((DeviceState) -> Void)?

    private let device: IOBluetoothDevice

    init(device: IOBluetoothDevice, name: String, brand: Brand) {
        self.device = device
        state = DeviceState(name: name, brand: brand)
        state.reportsCaseBattery = false
    }

    func connect() {
        state.connection = .connected
        requestBattery()
    }

    func disconnect() {
        state.connection = .disconnected
    }

    func setANCMode(_ mode: ANCMode) {}
    func setEQ(_ preset: EQPreset) {}

    /// macOS keeps the headset's reported level on IOBluetoothDevice under keys that
    /// aren't public API, so read them only when present. 0 means "not reported".
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
