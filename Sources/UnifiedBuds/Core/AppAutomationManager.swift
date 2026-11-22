import AppKit
import Foundation

/// Automates ANC and Transparency switching based on the active foreground application.
@MainActor
final class AppAutomationManager {
    static let shared = AppAutomationManager()

    private weak var manager: BudsManager?
    private var observer: NSObjectProtocol?
    private var previousAppBundleID: String?

    private init() {}

    func start(manager: BudsManager) {
        self.manager = manager
        stop()

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.appDidActivate(notification)
            }
        }
    }

    func stop() {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            observer = nil
        }
    }

    private func appDidActivate(_ notification: Notification) {
        guard Preferences.shared.perAppANCEnabled, let manager = manager else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        guard bundleID != previousAppBundleID else { return }
        previousAppBundleID = bundleID

        let rules = Preferences.shared.perAppANCRules
        if let match = rules.first(where: { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            guard let device = manager.selected, device.connection == .connected else { return }
            if device.supportedANCModes.contains(match.mode) && device.ancMode != match.mode {
                connectionLog.info("Per-App ANC: Switched to \(match.mode.rawValue) for \(match.appName)")
                manager.setANCMode(match.mode)
            }
        }
    }
}
