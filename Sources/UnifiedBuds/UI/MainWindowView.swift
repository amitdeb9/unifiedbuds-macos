import SwiftUI

/// The full UnifiedBuds window: every control and setting, grouped in a sidebar
/// and laid out like System Settings. Opened from the gear in the menu bar panel
/// or by launching the app.
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

    @State private var page: Page? = .earbuds

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch page ?? .earbuds {
                case .earbuds: EarbudsPage()
                case .touch: TouchPage()
                case .devices: DevicesPage()
                case .general: GeneralPage()
                case .about: AboutPage()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(page?.rawValue ?? "UnifiedBuds")
        }
        .modifier(NoFocusRing())
        .frame(minWidth: 720, minHeight: 540)
    }
}

// MARK: Earbuds

private struct EarbudsPage: View {
    @EnvironmentObject private var manager: BudsManager
    @EnvironmentObject private var audio: AudioOutput

    var body: some View {
        if let device = manager.selected {
            Form {
                Section { header(device) }
                Section("Battery") { BatteryRow(device: device) }
                if let buds = audio.device(named: device.name), let mac = audio.builtInDevice {
                    Section("Sound Output") { soundOutput(buds: buds, mac: mac) }
                }
                if !device.supportedANCModes.isEmpty {
                    Section("Noise Control") { noiseControl(device) }
                }
                if !device.supportedEQPresets.isEmpty {
                    Section("Equalizer") { equalizer(device) }
                }
            }
        } else {
            Form { Section { NoDevicesView() } }
        }
    }

    private func header(_ device: DeviceState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "earbuds")
                .font(.system(size: 30))
                .foregroundStyle(device.connection == .connected ? Color.accentColor : .secondary)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                if manager.devices.count > 1 {
                    Picker("Device", selection: Binding(
                        get: { manager.selectedAddress ?? manager.order.first ?? "" },
                        set: { manager.selectedAddress = $0 }
                    )) {
                        ForEach(Array(zip(manager.order, manager.devices)), id: \.0) { address, state in
                            Text(state.name).tag(address)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(device.name).font(.title3.weight(.semibold))
                }
                Text(statusText(device)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                manager.reconnectSelected()
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
        }
        .padding(.vertical, 4)
    }

    private func statusText(_ device: DeviceState) -> String {
        switch device.connection {
        case .connected: return "\(device.brand.rawValue) · Connected"
        case .connecting: return "\(device.brand.rawValue) · Connecting…"
        case .disconnected: return "\(device.brand.rawValue) · Not connected"
        case .failed(let message): return message
        }
    }

    private func soundOutput(buds: AudioOutput.Device, mac: AudioOutput.Device) -> some View {
        Picker("Play sound through", selection: Binding(
            get: { audio.defaultDeviceID },
            set: { id in
                if let target = [buds, mac].first(where: { $0.id == id }) { audio.select(target) }
            }
        )) {
            Label("Earbuds", systemImage: "earbuds").tag(buds.id)
            Label("Mac Speakers", systemImage: "laptopcomputer").tag(mac.id)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func noiseControl(_ device: DeviceState) -> some View {
        let enabled = device.connection == .connected
        Picker("Mode", selection: Binding(
            get: { device.ancMode },
            set: { if let mode = $0 { manager.setANCMode(mode) } }
        )) {
            ForEach(device.supportedANCModes) { mode in
                Text(mode.rawValue).tag(Optional(mode))
            }
        }
        .pickerStyle(.segmented)
        .disabled(!enabled)
        if device.ancMode == .noiseCancellation, !device.ancLevels.isEmpty {
            Picker("Strength", selection: Binding(
                get: { device.ancLevel ?? device.ancLevels.count - 1 },
                set: { manager.setANCLevel($0) }
            )) {
                ForEach(Array(device.ancLevels.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!enabled)
        }
    }

    @ViewBuilder
    private func equalizer(_ device: DeviceState) -> some View {
        Picker("Preset", selection: Binding(
            get: { device.eqPreset },
            set: { if let preset = $0 { manager.setEQ(preset) } }
        )) {
            if device.eqPreset == nil { Text("—").tag(EQPreset?.none) }
            ForEach(device.supportedEQPresets) { preset in
                Text(preset.name).tag(Optional(preset))
            }
        }
        .disabled(device.connection != .connected)
        if device.eqPreset == .custom, let custom = device.customEQ {
            CustomEQSliders(initial: custom) { manager.setCustomEQ($0) }
                .disabled(device.connection != .connected)
        }
    }
}

/// Left, right and case battery with a level bar under each.
private struct BatteryRow: View {
    let device: DeviceState

    var body: some View {
        HStack(spacing: 12) {
            if let combined = device.battery.combined, device.battery.left == nil, device.battery.right == nil {
                cell("Earbuds", symbol: "earbuds", battery: combined, unavailable: false)
            } else {
                cell("Left", symbol: "earbuds", battery: device.battery.left, unavailable: false)
                cell("Right", symbol: "earbuds", battery: device.battery.right, unavailable: false)
            }
            cell("Case", symbol: "earbuds.case", battery: device.battery.caseBattery,
                 unavailable: !device.reportsCaseBattery)
        }
        .padding(.vertical, 6)
    }

    private func cell(_ label: String, symbol: String, battery: BudBattery?, unavailable: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                if battery?.charging == true {
                    Image(systemName: "bolt.fill").foregroundStyle(.green)
                }
                Text(battery.map { "\($0.percent)%" } ?? (unavailable ? "N/A" : "—"))
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
            }
            ProgressView(value: Double(battery?.percent ?? 0), total: 100)
                .tint(color(battery))
                .opacity(battery == nil ? 0.3 : 1)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(unavailable && battery == nil ? "These earbuds don't report the case's battery to a Mac." : "")
    }

    private func color(_ battery: BudBattery?) -> Color {
        guard let battery else { return .secondary }
        if battery.charging { return .green }
        return battery.percent <= 15 ? .red : .accentColor
    }
}

// MARK: Touch controls

private struct TouchPage: View {
    @EnvironmentObject private var manager: BudsManager

    var body: some View {
        Form {
            if let device = manager.selected, let map = device.touchMap {
                let enabled = device.connection == .connected
                Section {
                    ForEach(TouchGesture.allCases) { gesture in
                        actionPicker(gesture.name, gesture: gesture.leftID, map: map)
                    }
                } header: {
                    Label("Left Earbud", systemImage: "l.circle")
                } footer: {
                    Text("Changes are saved on the \(device.name) and work with any phone or computer.")
                }
                .disabled(!enabled)
                Section {
                    ForEach(TouchGesture.allCases) { gesture in
                        actionPicker(gesture.name, gesture: gesture.rightID, map: map)
                    }
                } header: {
                    Label("Right Earbud", systemImage: "r.circle")
                }
                .disabled(!enabled)
            } else {
                Section {
                    Text(manager.selected == nil
                         ? "Connect your earbuds to change their touch controls."
                         : "These earbuds don't support changing touch controls yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func actionPicker(_ title: String, gesture: UInt8, map: [UInt8: UInt8]) -> some View {
        Picker(title, selection: Binding(
            get: { map[gesture] ?? 0 },
            set: { manager.setTouchAction($0, forGesture: gesture) }
        )) {
            ForEach(TouchAction.allCases) { action in
                Text(action.name).tag(action.rawValue)
            }
            // Keep a value the app doesn't know selectable rather than showing it as None.
            if let current = map[gesture], TouchAction(rawValue: current) == nil {
                Text("Other (\(current))").tag(current)
            }
        }
    }
}

// MARK: Devices

private struct DevicesPage: View {
    @EnvironmentObject private var manager: BudsManager

    var body: some View {
        Form {
            Section {
                if manager.history.isEmpty {
                    Text("No supported earbuds have connected to this Mac yet.").foregroundStyle(.secondary)
                }
                ForEach(manager.history) { device in
                    row(device)
                }
            } footer: {
                Text("Right-click a disconnected device to remove it from this list. It stays paired with your Mac.")
            }
        }
    }

    private func row(_ device: KnownDevice) -> some View {
        let connected = manager.isConnected(device.address)
        return HStack(spacing: 12) {
            Image(systemName: "earbuds")
                .font(.title2)
                .foregroundStyle(connected ? Color.accentColor : .secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body.weight(.medium))
                Text(subtitle(device, connected: connected)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if manager.pendingAddresses.contains(device.address) {
                ProgressView().controlSize(.small)
            } else if connected {
                Button("Disconnect") { manager.disconnectDevice(address: device.address) }
            } else {
                Button("Connect") { manager.connectDevice(address: device.address) }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !connected {
                Button("Remove from List") { manager.forget(address: device.address) }
            }
        }
    }

    private func subtitle(_ device: KnownDevice, connected: Bool) -> String {
        var parts: [String] = []
        if connected {
            parts.append("Connected")
        } else if device.lastConnected > .distantPast {
            let formatter = RelativeDateTimeFormatter()
            parts.append("Last used " + formatter.localizedString(for: device.lastConnected, relativeTo: Date()))
        } else {
            parts.append("Paired")
        }
        let levels = [("Battery", device.combined), ("L", device.left), ("R", device.right), ("Case", device.caseBattery)]
            .compactMap { label, value in value.map { "\(label) \($0)%" } }
        if !levels.isEmpty { parts.append(levels.joined(separator: "  ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: General

private struct GeneralPage: View {
    @AppStorage("menuBarIconStyle") private var iconStyle = MenuBarIconStyle.appLogo

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $iconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Preview") {
                    HStack(spacing: 18) {
                        preview(.connected, "Normal")
                        preview(.adaptive, "Adaptive")
                        preview(.transparency, "Transparency")
                        preview(.charging, "Charging")
                    }
                }
            } header: {
                Text("Menu Bar Icon")
            } footer: {
                Text("The icon follows your earbuds' mode and dims when none are connected.")
            }
            Section("Startup") {
                LaunchAtLoginControl(compact: false)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Quit UnifiedBuds") { NSApplication.shared.terminate(nil) }
                }
            }
        }
    }

    private func preview(_ status: MenuBarIcon.Status, _ title: String) -> some View {
        let image = MenuBarIcon.image(for: status, style: iconStyle)
        return VStack(spacing: 4) {
            Image(nsImage: image)
                .resizable()
                .frame(width: image.size.width * 1.4, height: image.size.height * 1.4)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: About

private struct AboutPage: View {
    private static let repo = URL(string: "https://github.com/amitdeb9/unifiedbuds-macos")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
                    Text("UnifiedBuds").font(.largeTitle.weight(.semibold))
                    Text(version).foregroundStyle(.secondary)
                    Text("Battery, noise control, EQ and touch controls for QCY, Nothing / CMF, realme, OnePlus and boAt earbuds.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            Section {
                Link(destination: Self.repo) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.repo.appendingPathComponent("releases/latest")) {
                    Label("Check for updates", systemImage: "arrow.down.circle")
                }
            } footer: {
                Text("Open source under the MIT License.")
            }
        }
    }
}
