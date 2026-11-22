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

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(systemObject, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
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

        var defaultID: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(systemObject, &defaultAddress, 0, nil, &defaultSize, &defaultID)
        defaultDeviceID = defaultID
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
