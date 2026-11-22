import CoreAudio
import Foundation

/// The Mac's audio output devices and which one is the default, kept current
/// through CoreAudio property listeners.
@MainActor
final class AudioOutput: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let isBuiltIn: Bool
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var defaultDeviceID: AudioDeviceID = 0
    @Published private(set) var defaultInputDeviceID: AudioDeviceID = 0
    @Published private(set) var inputDevices: [Device] = []

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(systemObject, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.enforceInputPolicy()
                }
            }
        }
    }

    /// The output device belonging to the named earbuds (CoreAudio uses the Bluetooth name).
    func device(named name: String) -> Device? {
        devices.first { $0.name == name } ?? devices.first { !$0.isBuiltIn && $0.name.localizedCaseInsensitiveContains(name) }
    }

    var builtInDevice: Device? {
        devices.first(where: \.isBuiltIn)
    }

    var builtInInputDevice: Device? {
        inputDevices.first(where: \.isBuiltIn)
    }

    /// Checks if input switched to Bluetooth and reverts to built-in mic if preventHFPSwitch is enabled.
    func enforceInputPolicy() {
        guard Preferences.shared.preventHFPSwitch else { return }
        let currentTransport = Self.transport(of: defaultInputDeviceID)
        // If default input is Bluetooth, switch back to built-in mic to preserve A2DP high quality.
        if currentTransport == kAudioDeviceTransportTypeBluetooth || currentTransport == kAudioDeviceTransportTypeBluetoothLE {
            if let builtIn = builtInInputDevice {
                selectInput(builtIn)
                connectionLog.info("Prevented HFP mic switch: restored default input to \(builtIn.name, privacy: .public)")
            }
        }
    }

    /// Makes `device` the default system input (microphone).
    func selectInput(_ device: Device) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectSetPropertyData(systemObject, &address, 0, nil, size, &id)
        defaultInputDeviceID = id
    }

    /// Makes `device` the output for both media and system sounds (alerts).
    func select(_ device: Device) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = Self.address(selector)
            AudioObjectSetPropertyData(systemObject, &address, 0, nil, size, &id)
        }
        refresh()
    }

    private func refresh() {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return }

        devices = ids.compactMap { id in
            guard Self.hasOutput(id), let name = Self.name(of: id) else { return nil }
            return Device(id: id, name: name, isBuiltIn: Self.transport(of: id) == kAudioDeviceTransportTypeBuiltIn)
        }

        inputDevices = ids.compactMap { id in
            guard Self.hasInput(id), let name = Self.name(of: id) else { return nil }
            return Device(id: id, name: name, isBuiltIn: Self.transport(of: id) == kAudioDeviceTransportTypeBuiltIn)
        }

        var defaultID: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(systemObject, &defaultAddress, 0, nil, &defaultSize, &defaultID)
        defaultDeviceID = defaultID

        var defaultInID: AudioDeviceID = 0
        var defaultInSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultInAddress = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectGetPropertyData(systemObject, &defaultInAddress, 0, nil, &defaultInSize, &defaultInID)
        defaultInputDeviceID = defaultInID
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }
}
