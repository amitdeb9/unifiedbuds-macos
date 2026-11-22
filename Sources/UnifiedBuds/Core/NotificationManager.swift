import Foundation
import UserNotifications

/// Dispatches native macOS notifications when earbuds drop below configured threshold.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Tracks addresses where a notification was already posted to avoid repeat spam.
    private var notifiedBuds: Set<String> = []

    private init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                connectionLog.error("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    /// Evaluates current battery levels and sends a native alert if below threshold.
    func checkBattery(for device: DeviceState, address: String) {
        let prefs = Preferences.shared
        guard prefs.lowBatteryNotificationsEnabled else { return }
        let threshold = prefs.lowBatteryThreshold

        var warnings: [String] = []

        if let left = device.battery.left, !left.charging, left.percent > 0 {
            let key = "\(address)-left"
            if left.percent <= threshold {
                if !notifiedBuds.contains(key) {
                    notifiedBuds.insert(key)
                    warnings.append("Left: \(left.percent)%")
                }
            } else {
                notifiedBuds.remove(key)
            }
        }

        if let right = device.battery.right, !right.charging, right.percent > 0 {
            let key = "\(address)-right"
            if right.percent <= threshold {
                if !notifiedBuds.contains(key) {
                    notifiedBuds.insert(key)
                    warnings.append("Right: \(right.percent)%")
                }
            } else {
                notifiedBuds.remove(key)
            }
        }

        if let combined = device.battery.combined, !combined.charging, combined.percent > 0 {
            let key = "\(address)-combined"
            if combined.percent <= threshold {
                if !notifiedBuds.contains(key) {
                    notifiedBuds.insert(key)
                    warnings.append("Battery: \(combined.percent)%")
                }
            } else {
                notifiedBuds.remove(key)
            }
        }

        guard !warnings.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(device.name) Low Battery"
        content.body = "\(warnings.joined(separator: ", ")) remaining. Consider charging soon."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lowBattery-\(address)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                connectionLog.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    func reset(for address: String) {
        notifiedBuds.remove("\(address)-left")
        notifiedBuds.remove("\(address)-right")
        notifiedBuds.remove("\(address)-combined")
    }
}
