import Foundation

/// A supported pair of earbuds seen on this Mac, kept after it disconnects.
struct KnownDevice: Codable, Identifiable, Equatable {
    let address: String
    var name: String
    var lastConnected: Date
    var left: Int?
    var right: Int?
    var caseBattery: Int?
    /// Single headset level from earbuds that don't report each bud.
    var combined: Int?

    var id: String { address }
    var brand: Brand? { Brand.detect(name: name) }
}

/// Persists `KnownDevice`s in UserDefaults, most recently connected first.
enum DeviceHistory {
    private static let key = "deviceHistory"

    static func load() -> [KnownDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let devices = try? JSONDecoder().decode([KnownDevice].self, from: data) else { return [] }
        // Older versions also listed every paired device that had never connected to
        // the app (stored with a distant-past date); drop those.
        return devices.filter { $0.lastConnected > .distantPast }
            .sorted { $0.lastConnected > $1.lastConnected }
    }

    static func save(_ devices: [KnownDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
