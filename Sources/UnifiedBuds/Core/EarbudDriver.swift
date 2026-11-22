import Foundation

enum Brand: String {
    case qcy = "QCY"
    case nothing = "Nothing"
    case realme = "realme"
    case oneplus = "OnePlus"
    case boat = "boAt"
}

enum ANCMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case transparency = "Transparency"
    case noiseCancellation = "ANC"
    case adaptive = "Adaptive"

    var id: String { rawValue }
}

struct EQPreset: Hashable, Identifiable {
    let id: UInt8
    let name: String
}

/// User-tuned EQ on top of the buds' own curve, in whole dB.
struct CustomEQ: Codable, Equatable {
    var bass = 0
    var mid = 0
    var treble = 0
}

/// Touch gestures in QCY's numbering: odd ids are the left bud, even the right.
enum TouchGesture: UInt8, CaseIterable, Identifiable {
    case singleTap = 1, doubleTap = 3, tripleTap = 5, quadrupleTap = 7, longPress = 9

    var id: UInt8 { rawValue }
    var leftID: UInt8 { rawValue }
    var rightID: UInt8 { rawValue + 1 }

    var name: String {
        switch self {
        case .singleTap: return "Single tap"
        case .doubleTap: return "Double tap"
        case .tripleTap: return "Triple tap"
        case .quadrupleTap: return "4× tap"
        case .longPress: return "Long press"
        }
    }
}

/// Actions a touch gesture can trigger, in QCY's numbering.
enum TouchAction: UInt8, CaseIterable, Identifiable {
    case none = 0, playPause = 1, previous = 2, next = 3, voiceAssistant = 4
    case volumeUp = 5, volumeDown = 6, gameMode = 7, noiseControl = 11

    var id: UInt8 { rawValue }

    var name: String {
        switch self {
        case .none: return "None"
        case .playPause: return "Play / Pause"
        case .previous: return "Previous"
        case .next: return "Next"
        case .voiceAssistant: return "Voice assistant"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .gameMode: return "Game mode"
        case .noiseControl: return "Noise control"
        }
    }
}

struct BudBattery: Equatable {
    var percent: Int
    var charging: Bool
}

struct BatteryStatus: Equatable {
    var left: BudBattery?
    var right: BudBattery?
    var caseBattery: BudBattery?
    /// One level for both buds, from earbuds that only report a single headset battery.
    var combined: BudBattery?
}

enum DriverConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Everything the UI needs to render one device. Drivers mutate this and
/// BudsManager republishes it.
struct DeviceState: Equatable {
    var name: String
    var brand: Brand
    var connection: DriverConnectionState = .connecting
    var battery = BatteryStatus()
    var ancMode: ANCMode?
    /// Names of the ANC strength steps, weakest first; empty when not adjustable.
    var ancLevels: [String] = []
    var ancLevel: Int?
    var eqPreset: EQPreset?
    var supportedANCModes: [ANCMode] = []
    var supportedEQPresets: [EQPreset] = []
    /// Non-nil when the driver supports the "Custom" preset's bass/mid/treble sliders.
    var customEQ: CustomEQ?
    /// Gesture id → action id, once the buds report their touch table; nil when unsupported.
    var touchMap: [UInt8: UInt8]?
    /// False when the buds never report the case's battery.
    var reportsCaseBattery = true
}

extension EQPreset {
    /// Preset id drivers use for `CustomEQ`.
    static let custom = EQPreset(id: 100, name: "Custom")
}

/// The only interface the UI layer talks to. Each brand implements it on top of
/// its own transport (BLE GATT or RFCOMM).
@MainActor
protocol EarbudDriver: AnyObject {
    var state: DeviceState { get }
    /// Called on the main actor whenever `state` changes.
    var onStateChange: ((DeviceState) -> Void)? { get set }

    func connect()
    func disconnect()
    func setANCMode(_ mode: ANCMode)
    func setEQ(_ preset: EQPreset)
    func setANCLevel(_ level: Int)
    func setCustomEQ(_ eq: CustomEQ)
    func setTouchAction(_ action: UInt8, forGesture gesture: UInt8)
    func requestBattery()
}

extension EarbudDriver {
    func setANCLevel(_ level: Int) {}
    func setCustomEQ(_ eq: CustomEQ) {}
    func setTouchAction(_ action: UInt8, forGesture gesture: UInt8) {}
}
