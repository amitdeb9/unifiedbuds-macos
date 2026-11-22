import SwiftUI

/// The full UnifiedBuds window: every control and setting, grouped in a sidebar.
/// Opened from the gear in the menu bar panel or by launching the app.
struct MainWindowView: View {
    enum Page: String, CaseIterable, Identifiable {
        case earbuds = "Earbuds"
        case touch = "Touch Controls"
        case devices = "Devices"
        case general = "General"
        case about = "About"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .earbuds: return "earbuds"
            case .touch: return "hand.tap"
            case .devices: return "list.bullet"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    @EnvironmentObject private var manager: BudsManager
    @State private var page: Page? = .earbuds

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detail(page ?? .earbuds)
                }
                .padding(24)
                .frame(maxWidth: 460, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(page?.rawValue ?? "")
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    @ViewBuilder
    private func detail(_ page: Page) -> some View {
        switch page {
        case .earbuds:
            if let device = manager.selected {
                DeviceHeader(device: device)
                DeviceControls(device: device, showsTouchControls: false)
            } else {
                NoDevicesView()
            }
        case .touch:
            if let device = manager.selected, let map = device.touchMap {
                Text("Choose what each gesture does on the \(device.name).")
                    .foregroundStyle(.secondary)
                TouchControls(map: map, collapsible: false) { manager.setTouchAction($0, forGesture: $1) }
                    .disabled(device.connection != .connected)
            } else {
                Text(manager.selected == nil
                     ? "Connect your earbuds to change their touch controls."
                     : "These earbuds don't support touch control changes yet.")
                    .foregroundStyle(.secondary)
            }
        case .devices:
            if manager.history.isEmpty {
                Text("No supported earbuds have connected to this Mac yet.").foregroundStyle(.secondary)
            } else {
                DeviceHistoryList()
            }
        case .general:
            GeneralSettings()
        case .about:
            AboutView()
        }
    }
}

private struct GeneralSettings: View {
    @AppStorage("menuBarIconStyle") private var iconStyle = MenuBarIconStyle.appLogo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Menu bar icon").font(.headline)
            Picker("", selection: $iconStyle) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            HStack(spacing: 14) {
                ForEach([MenuBarIcon.Status.connected, .adaptive, .transparency, .charging], id: \.self) { status in
                    Image(nsImage: MenuBarIcon.image(for: status, style: iconStyle))
                }
            }
            .padding(.top, 4)
            Text("The icon shows charging, Transparency and Adaptive, and dims when no earbuds are connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Divider()
        VStack(alignment: .leading, spacing: 6) {
            Text("Startup").font(.headline)
            LaunchAtLoginControl()
        }
        Divider()
        Button("Quit UnifiedBuds") { NSApplication.shared.terminate(nil) }
    }
}

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text("UnifiedBuds").font(.title2.weight(.semibold))
                Text(version).foregroundStyle(.secondary)
                Text("Battery, noise control, EQ and touch controls for QCY, Nothing / CMF and realme earbuds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
