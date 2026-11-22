import SwiftUI

@main
struct UnifiedBudsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(appDelegate.manager)
                .environmentObject(appDelegate.audio)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.manager)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar glyph, redrawn whenever the selected device's state changes.
private struct MenuBarLabel: View {
    @EnvironmentObject private var manager: BudsManager
    @AppStorage("menuBarIconStyle") private var iconStyle = MenuBarIconStyle.appLogo
    @AppStorage("showBatteryInMenuBar") private var showBattery = false

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(for: status, style: effectiveStyle))
            if showBattery, let text = batteryText {
                Text(text)
                    .font(.system(.caption2, design: .rounded).monospacedDigit())
            }
        }
    }

    /// Lowest-bud battery percentage or combined headset battery.
    private var batteryText: String? {
        guard let device = manager.selected, device.connection == .connected else { return nil }
        let bat = device.battery
        var levels: [Int] = []
        if let l = bat.left?.percent, l > 0 { levels.append(l) }
        if let r = bat.right?.percent, r > 0 { levels.append(r) }
        if let c = bat.combined?.percent, c > 0 { levels.append(c) }
        guard let lowest = levels.min() else { return nil }
        return "\(lowest)%"
    }

    /// Automatically uses neckband icon for neckband models if default icon style is active.
    private var effectiveStyle: MenuBarIconStyle {
        if iconStyle == .earbuds, manager.selected?.formFactor == .neckband {
            return .neckband
        }
        return iconStyle
    }

    /// Charging wins over noise mode; noise modes update the glyph dynamically.
    private var status: MenuBarIcon.Status {
        guard let device = manager.selected, device.connection == .connected else { return .disconnected }
        let battery = device.battery
        if [battery.left, battery.right].contains(where: { $0?.charging == true }) { return .charging }
        if device.ancMode == .transparency { return .transparency }
        if device.ancMode == .noiseCancellation { return .ancOn }
        if device.ancMode == .adaptive { return .adaptive }
        if device.ancMode == .off { return .off }
        return .connected
    }
}

/// Owns the shared state and shows the full settings window when the app is opened
/// from Finder or Launchpad (a crowded menu bar or the notch can hide the menu bar
/// icon) or from the gear in the menu bar panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI wraps the delegate, so `NSApp.delegate` isn't this object; views reach it here.
    private(set) static weak var shared: AppDelegate?

    let manager = BudsManager()
    let audio = AudioOutput()
    private var window: NSWindow?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install global shortcuts and per-app automation
        KeyboardShortcutManager.shared.install(manager: manager)
        AppAutomationManager.shared.start(manager: manager)

        // Setup DistributedNotificationCenter for CLI / Apple Shortcuts integration
        setupIPC()

        // Handle direct command-line arguments if passed
        handleCLIArguments()

        // Login-item launches stay quiet in the menu bar; any other launch (Finder,
        // Launchpad, `open`) shows the window. SwiftUI menu bar apps don't receive the
        // launch Apple event, so a login launch is recognised by timing instead.
        if !launchedAsLoginItem && !isCLIInvocation { showWindow() }
    }

    private var isCLIInvocation: Bool {
        let args = CommandLine.arguments
        return args.contains("--anc") || args.contains("--battery") || args.contains("--gaming") || args.contains("--diagnostics") || args.contains("--help") || args.contains("-h")
    }

    private func handleCLIArguments() {
        let args = CommandLine.arguments
        if args.contains("--help") || args.contains("-h") {
            print("""
            UnifiedBuds CLI & Apple Shortcuts Helper
            Usage:
              UnifiedBuds [options]

            Options:
              --anc <off|transparency|anc|adaptive>   Set active noise cancellation mode
              --gaming <on|off>                       Toggle gaming/low-latency mode
              --battery                               Print current earbud battery levels
              --diagnostics                           Print Bluetooth debug report
              --help, -h                              Show this help message
            """)
            exit(0)
        }

        if let ancIdx = args.firstIndex(of: "--anc"), ancIdx + 1 < args.count {
            let modeStr = args[ancIdx + 1].lowercased()
            let targetMode: ANCMode?
            switch modeStr {
            case "off": targetMode = .off
            case "transparency", "ambient": targetMode = .transparency
            case "anc", "cancellation", "on": targetMode = .noiseCancellation
            case "adaptive", "smart": targetMode = .adaptive
            default: targetMode = nil
            }
            if let targetMode = targetMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.manager.setANCMode(targetMode)
                    print("Set ANC mode to \(targetMode.rawValue)")
                    exit(0)
                }
            }
        }

        if let gamingIdx = args.firstIndex(of: "--gaming"), gamingIdx + 1 < args.count {
            let enabled = ["on", "true", "1", "enable"].contains(args[gamingIdx + 1].lowercased())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.manager.setGamingMode(enabled)
                print("Gaming mode set to \(enabled)")
                exit(0)
            }
        }

        if args.contains("--battery") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let dev = self?.manager.selected {
                    let b = dev.battery
                    print("\(dev.name): L: \(b.left?.percent.description ?? "-")%  R: \(b.right?.percent.description ?? "-")%  Case: \(b.caseBattery?.percent.description ?? "-")%  Combined: \(b.combined?.percent.description ?? "-")%")
                } else {
                    print("No supported earbuds connected")
                }
                exit(0)
            }
        }

        if args.contains("--diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let info = self?.manager.exportBluetoothDebugInfo() {
                    print(info)
                }
                exit(0)
            }
        }
    }

    private func setupIPC() {
        // Apple Shortcuts & external scripts can post distributed notifications:
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.unifiedbuds.setANC"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let modeStr = notif.userInfo?["mode"] as? String else { return }
            Task { @MainActor [weak self] in
                switch modeStr.lowercased() {
                case "off": self?.manager.setANCMode(.off)
                case "transparency": self?.manager.setANCMode(.transparency)
                case "anc": self?.manager.setANCMode(.noiseCancellation)
                case "adaptive": self?.manager.setANCMode(.adaptive)
                default: break
                }
            }
        }
    }

    private var launchedAsLoginItem: Bool {
        guard LaunchAtLogin.isEnabled,
              let loginWindow = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.loginwindow").first?.launchDate else { return false }
        return Date().timeIntervalSince(loginWindow) < 120
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func showWindow() {
        if window == nil {
            let content = MainWindowView()
                .environmentObject(manager)
                .environmentObject(audio)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "UnifiedBuds"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
