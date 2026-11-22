import Foundation
import IOBluetooth
import os

/// Connection timeline, visible with `log stream --predicate 'subsystem == "com.unifiedbuds.app"'`.
let connectionLog = Logger(subsystem: "com.unifiedbuds.app", category: "connection")

extension Brand {
    /// Matches the name macOS shows for a paired device. Users can rename
    /// devices, so this is best effort.
    static func detect(name: String) -> Brand? {
        let lower = name.lowercased()
        if lower.contains("qcy") || lower.hasPrefix("melobuds") || lower.hasPrefix("ailybuds") {
            return .qcy
        }
        if lower.hasPrefix("nothing") || lower.hasPrefix("ear (") || lower.hasPrefix("ear(")
            || lower.hasPrefix("cmf") {
            return .nothing
        }
        if lower.hasPrefix("realme") || lower.hasPrefix("oppo enco") {
            return .realme
        }
        if lower.hasPrefix("oneplus") {
            return .oneplus
        }
        if lower.hasPrefix("boat") || lower.contains("airdopes") || lower.contains("rockerz")
            || lower.contains("nirvana") {
            return .boat
        }
        return nil
    }
}

/// Watches macOS Bluetooth connections, picks the right driver for any
/// supported earbuds, and republishes driver state to the UI.
@MainActor
final class BudsManager: NSObject, ObservableObject {
    @Published private(set) var devices: [DeviceState] = []
    @Published var selectedAddress: String?
    /// Supported earbuds that have connected while the app was running, most recent first.
    @Published private(set) var history: [KnownDevice] = DeviceHistory.load()
    /// Addresses with a connect or disconnect in flight.
    @Published private(set) var pendingAddresses: Set<String> = []
    /// QCY devices whose SDP records are being refreshed before a driver is chosen.
    private var sdpQueried: Set<String> = []

    private var drivers: [String: EarbudDriver] = [:]
    /// Bluetooth addresses, parallel to `devices`.
    @Published private(set) var order: [String] = []
    private var pollTimer: Timer?
    private var batteryTimer: Timer?
    private var connectNotification: IOBluetoothUserNotification?

    var selected: DeviceState? {
        guard let address = selectedAddress, let index = order.firstIndex(of: address),
              index < devices.count else { return devices.first }
        return devices[index]
    }

    private var selectedDriver: EarbudDriver? {
        if let address = selectedAddress, let driver = drivers[address] { return driver }
        return order.first.flatMap { drivers[$0] }
    }

    override init() {
        super.init()
        // The menu bar label renders at launch; start watching right after.
        DispatchQueue.main.async { self.start() }
    }

    private func start() {
        guard pollTimer == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        // Disconnect notifications are per device; a slow poll also catches
        // anything the notifications miss (sleep/wake, renamed devices).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshConnectedDevices() }
        }
        // Some buds (JieLi QCY) never push battery changes, so poll.
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            // Only connected drivers: sending on a closed channel would mark the device failed.
            Task { @MainActor in
                self?.drivers.values.filter { $0.state.connection == .connected }.forEach { $0.requestBattery() }
            }
        }
        refreshConnectedDevices()
    }

    func refreshConnectedDevices() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let connected = paired.filter { $0.isConnected() }
        let connectedAddresses = Set(connected.compactMap { $0.addressString })

        for address in order where !connectedAddresses.contains(address) {
            removeDriver(address: address)
        }
        for device in connected {
            guard let address = device.addressString, drivers[address] == nil,
                  let name = device.name, let brand = Brand.detect(name: name) else { continue }
            // QCY's JieLi-vs-BLE choice reads the SDP records, which can be missing on a
            // first connection. Refresh them once; the 2 s poll picks the device up after.
            if brand == .qcy, (device.services ?? []).isEmpty, !sdpQueried.contains(address) {
                sdpQueried.insert(address)
                device.performSDPQuery(nil)
                continue
            }
            addDriver(makeDriver(brand: brand, device: device, name: name), address: address)
        }
    }

    func refreshSelected() {
        selectedDriver?.requestBattery()
    }

    func setANCMode(_ mode: ANCMode) {
        selectedDriver?.setANCMode(mode)
    }

    func setEQ(_ preset: EQPreset) {
        selectedDriver?.setEQ(preset)
    }

    func setANCLevel(_ level: Int) {
        selectedDriver?.setANCLevel(level)
    }

    func setCustomEQ(_ eq: CustomEQ) {
        selectedDriver?.setCustomEQ(eq)
    }

    func setTouchAction(_ action: UInt8, forGesture gesture: UInt8) {
        selectedDriver?.setTouchAction(action, forGesture: gesture)
    }

    func reconnectSelected() {
        guard let driver = selectedDriver else { return }
        driver.disconnect()
        driver.connect()
    }

    // MARK: Connect / disconnect

    func isConnected(_ address: String) -> Bool {
        drivers[address] != nil
    }

    /// Asks macOS to drop the Bluetooth link, the same as Disconnect in System Settings.
    func disconnectDevice(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        pendingAddresses.insert(address)
        device.closeConnection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.pendingAddresses.remove(address)
            self?.refreshConnectedDevices()
        }
    }

    /// Opens the Bluetooth link to a paired device; macOS then brings up audio.
    func connectDevice(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        pendingAddresses.insert(address)
        if device.openConnection(self) != kIOReturnSuccess {
            pendingAddresses.remove(address)
            return
        }
        // Don't leave the spinner up if macOS never reports back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.pendingAddresses.remove(address)
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        connectionLog.info("link up: \(device.name ?? "?", privacy: .public) status \(status)")
        // IOBluetooth may call back off the main thread; a second concurrent refresh
        // would start a duplicate driver racing for the same RFCOMM channel.
        DispatchQueue.main.async { [weak self] in
            if let address = device.addressString { self?.pendingAddresses.remove(address) }
            // The transport retries quickly if the buds aren't ready for a control channel yet.
            self?.refreshConnectedDevices()
        }
    }

    /// Removes a disconnected device from the history list (it stays paired in macOS).
    func forget(address: String) {
        guard drivers[address] == nil else { return }
        history.removeAll { $0.address == address }
        DeviceHistory.save(history)
    }

    // MARK: History

    private func recordConnection(address: String, name: String) {
        if let index = history.firstIndex(where: { $0.address == address }) {
            history[index].name = name
            history[index].lastConnected = Date()
        } else {
            history.append(KnownDevice(address: address, name: name, lastConnected: Date()))
        }
        history.sort { $0.lastConnected > $1.lastConnected }
        DeviceHistory.save(history)
    }

    private func recordBattery(address: String, battery: BatteryStatus) {
        guard let index = history.firstIndex(where: { $0.address == address }) else { return }
        var entry = history[index]
        entry.left = battery.left?.percent ?? entry.left
        entry.right = battery.right?.percent ?? entry.right
        entry.caseBattery = battery.caseBattery?.percent ?? entry.caseBattery
        entry.combined = battery.combined?.percent ?? entry.combined
        entry.lastConnected = Date()
        guard entry.left != history[index].left || entry.right != history[index].right
            || entry.caseBattery != history[index].caseBattery || entry.combined != history[index].combined else { return }
        history[index] = entry
        DeviceHistory.save(history)
    }

    private func makeDriver(brand: Brand, device: IOBluetoothDevice, name: String) -> EarbudDriver {
        switch brand {
        case .qcy:
            if QCYJieLiDriver.matches(device) { return QCYJieLiDriver(device: device, name: name) }
            return QCYDriver(name: name)
        case .nothing: return NothingDriver(device: device, name: name)
        case .realme: return RealmeDriver(device: device, name: name, brand: .realme)
        // OnePlus Buds use the same HeyMelody protocol as realme and OPPO.
        case .oneplus: return RealmeDriver(device: device, name: name, brand: .oneplus)
        // boAt's protocol isn't documented, and models use different chips.
        case .boat: return GenericDriver(device: device, name: name, brand: .boat)
        }
    }

    private func addDriver(_ driver: EarbudDriver, address: String) {
        drivers[address] = driver
        order.append(address)
        devices.append(driver.state)
        recordConnection(address: address, name: driver.state.name)
        driver.onStateChange = { [weak self] state in
            guard let self, let index = self.order.firstIndex(of: address) else { return }
            self.devices[index] = state
            self.recordBattery(address: address, battery: state.battery)
        }
        if selectedAddress == nil { selectedAddress = address }
        driver.connect()
    }

    private func removeDriver(address: String) {
        guard let index = order.firstIndex(of: address) else { return }
        if let entry = history.firstIndex(where: { $0.address == address }) {
            history[entry].lastConnected = Date()
            DeviceHistory.save(history)
        }
        drivers[address]?.onStateChange = nil
        drivers[address]?.disconnect()
        drivers[address] = nil
        order.remove(at: index)
        devices.remove(at: index)
        if selectedAddress == address { selectedAddress = order.first }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        connectionLog.info("link up: \(device.name ?? "?", privacy: .public)")
        // Open the control channel right away (the transport retries if the buds
        // aren't ready), on the main thread so refreshes never overlap.
        DispatchQueue.main.async { [weak self] in self?.refreshConnectedDevices() }
    }
}
