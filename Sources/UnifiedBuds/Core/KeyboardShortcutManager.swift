import AppKit
import Carbon

/// Global keyboard shortcut listener for controlling earbuds from anywhere on macOS.
@MainActor
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var manager: BudsManager?

    private init() {}

    func install(manager: BudsManager) {
        self.manager = manager
        uninstall()

        guard Preferences.shared.globalShortcutsEnabled else { return }

        // Global monitor for events when other applications are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleKeyEvent(event)
            }
        }

        // Local monitor when our popover or window is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyEvent(event) {
                return nil // Consume event
            }
            return event
        }
    }

    func uninstall() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard Preferences.shared.globalShortcutsEnabled, let manager = manager else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Check for ⌘⇧ (Command + Shift)
        guard flags.contains([.command, .shift]) else { return false }

        let characters = event.charactersIgnoringModifiers?.lowercased()

        switch characters {
        case "a":
            // ⌘⇧A: Cycle ANC Mode (Off -> Transparency -> ANC -> Adaptive)
            cycleANC(manager: manager)
            return true

        case "g":
            // ⌘⇧G: Toggle Gaming / Low-Latency Mode
            toggleGamingMode(manager: manager)
            return true

        default:
            return false
        }
    }

    private func cycleANC(manager: BudsManager) {
        guard let device = manager.selected, !device.supportedANCModes.isEmpty else { return }
        let modes = device.supportedANCModes
        let current = device.ancMode ?? .off
        let currentIndex = modes.firstIndex(of: current) ?? 0
        let nextIndex = (currentIndex + 1) % modes.count
        let nextMode = modes[nextIndex]
        manager.setANCMode(nextMode)
    }

    private func toggleGamingMode(manager: BudsManager) {
        guard let device = manager.selected, device.supportsGamingMode else { return }
        manager.setGamingMode(!device.gamingModeEnabled)
    }
}
