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

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: status, style: iconStyle))
    }

    /// Charging wins over the noise mode; Off and ANC show the plain glyph.
    private var status: MenuBarIcon.Status {
        guard let device = manager.selected, device.connection == .connected else { return .disconnected }
        let battery = device.battery
        if [battery.left, battery.right].contains(where: { $0?.charging == true }) { return .charging }
        if device.ancMode == .transparency { return .transparency }
        if device.ancMode == .adaptive { return .adaptive }
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
        // Login-item launches stay quiet in the menu bar; any other launch (Finder,
        // Launchpad, `open`) shows the window. SwiftUI menu bar apps don't receive the
        // launch Apple event, so a login launch is recognised by timing instead.
        if !launchedAsLoginItem { showWindow() }
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
