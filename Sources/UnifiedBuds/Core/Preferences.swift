import Foundation
import Combine

struct SavedEQProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var eq: CustomEQ
}

struct PerAppANCRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    var mode: ANCMode
}

/// Centralized preferences for UnifiedBuds, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    // MARK: - Menu Bar
    @Published var showBatteryInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showBatteryInMenuBar, forKey: "showBatteryInMenuBar") }
    }

    // MARK: - Notifications
    @Published var lowBatteryNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(lowBatteryNotificationsEnabled, forKey: "lowBatteryNotificationsEnabled") }
    }
    @Published var lowBatteryThreshold: Int {
        didSet { UserDefaults.standard.set(lowBatteryThreshold, forKey: "lowBatteryThreshold") }
    }

    // MARK: - Audio Routing
    @Published var autoSwitchAudioOutput: Bool {
        didSet { UserDefaults.standard.set(autoSwitchAudioOutput, forKey: "autoSwitchAudioOutput") }
    }
    @Published var preventHFPSwitch: Bool {
        didSet { UserDefaults.standard.set(preventHFPSwitch, forKey: "preventHFPSwitch") }
    }

    // MARK: - Custom EQ Profiles
    @Published var savedEQProfiles: [SavedEQProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(savedEQProfiles) {
                UserDefaults.standard.set(data, forKey: "savedEQProfiles")
            }
        }
    }

    // MARK: - Per-App ANC Automation
    @Published var perAppANCEnabled: Bool {
        didSet { UserDefaults.standard.set(perAppANCEnabled, forKey: "perAppANCEnabled") }
    }
    @Published var perAppANCRules: [PerAppANCRule] {
        didSet {
            if let data = try? JSONEncoder().encode(perAppANCRules) {
                UserDefaults.standard.set(data, forKey: "perAppANCRules")
            }
        }
    }

    // MARK: - Global Keyboard Shortcuts
    @Published var globalShortcutsEnabled: Bool {
        didSet { UserDefaults.standard.set(globalShortcutsEnabled, forKey: "globalShortcutsEnabled") }
    }

    private init() {
        showBatteryInMenuBar = UserDefaults.standard.bool(forKey: "showBatteryInMenuBar")
        lowBatteryNotificationsEnabled = UserDefaults.standard.object(forKey: "lowBatteryNotificationsEnabled") as? Bool ?? true
        lowBatteryThreshold = UserDefaults.standard.object(forKey: "lowBatteryThreshold") as? Int ?? 20
        autoSwitchAudioOutput = UserDefaults.standard.bool(forKey: "autoSwitchAudioOutput")
        preventHFPSwitch = UserDefaults.standard.bool(forKey: "preventHFPSwitch")
        globalShortcutsEnabled = UserDefaults.standard.object(forKey: "globalShortcutsEnabled") as? Bool ?? true

        if let data = UserDefaults.standard.data(forKey: "savedEQProfiles"),
           let profiles = try? JSONDecoder().decode([SavedEQProfile].self, from: data) {
            savedEQProfiles = profiles
        } else {
            savedEQProfiles = Self.defaultEQProfiles
        }

        perAppANCEnabled = UserDefaults.standard.bool(forKey: "perAppANCEnabled")
        if let data = UserDefaults.standard.data(forKey: "perAppANCRules"),
           let rules = try? JSONDecoder().decode([PerAppANCRule].self, from: data) {
            perAppANCRules = rules
        } else {
            perAppANCRules = Self.defaultAppRules
        }
    }

    static let defaultEQProfiles: [SavedEQProfile] = [
        SavedEQProfile(name: "Podcast", eq: CustomEQ(bass: -2, mid: 4, treble: 1)),
        SavedEQProfile(name: "Bass Boost", eq: CustomEQ(bass: 6, mid: 0, treble: -1)),
        SavedEQProfile(name: "Focus", eq: CustomEQ(bass: -3, mid: 0, treble: -2)),
        SavedEQProfile(name: "Acoustic", eq: CustomEQ(bass: 2, mid: 2, treble: 4)),
    ]

    static let defaultAppRules: [PerAppANCRule] = [
        PerAppANCRule(bundleID: "com.spotify.client", appName: "Spotify", mode: .noiseCancellation),
        PerAppANCRule(bundleID: "com.apple.Music", appName: "Music", mode: .noiseCancellation),
        PerAppANCRule(bundleID: "us.zoom.xos", appName: "Zoom", mode: .transparency),
        PerAppANCRule(bundleID: "com.microsoft.teams2", appName: "Microsoft Teams", mode: .transparency),
        PerAppANCRule(bundleID: "com.apple.FaceTime", appName: "FaceTime", mode: .transparency),
    ]
}
