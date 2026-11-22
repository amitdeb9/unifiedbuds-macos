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
                if device.supportsInEarDetection || device.supportsMultipoint || device.supportsGamingMode || device.supportsFindMyBuds {
                    Section("Features") {
                        if device.supportsGamingMode {
                            Toggle("Low-Latency / Gaming Mode", isOn: Binding(
                                get: { device.gamingModeEnabled },
                                set: { manager.setGamingMode($0) }
                            ))
                        }
                        if device.supportsInEarDetection {
                            Toggle("In-Ear Wear Detection", isOn: Binding(
                                get: { device.inEarDetectionEnabled },
                                set: { manager.setInEarDetection($0) }
                            ))
                        }
                        if device.supportsMultipoint {
                            Toggle("Dual-Device Multipoint Connection", isOn: Binding(
                                get: { device.multipointEnabled },
                                set: { manager.setMultipoint($0) }
                            ))
                        }
                        if device.supportsFindMyBuds {
                            HStack {
                                Text("Find My Buds")
                                Spacer()
                                Button {
                                    manager.ringBud(left: true, start: !device.isRingingLeft)
                                } label: {
                                    Label(device.isRingingLeft ? "Stop Left" : "Ring Left",
                                          systemImage: device.isRingingLeft ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                }
                                .controlSize(.small)
                                .tint(device.isRingingLeft ? .red : .accentColor)
                                Button {
                                    manager.ringBud(left: false, start: !device.isRingingRight)
                                } label: {
                                    Label(device.isRingingRight ? "Stop Right" : "Ring Right",
                                          systemImage: device.isRingingRight ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                }
                                .controlSize(.small)
                                .tint(device.isRingingRight ? .red : .accentColor)
                            }
                        }
                    }
                }
                if !device.supportedANCModes.isEmpty {
                    Section("Noise Control") { noiseControl(device) }
                }
                if !device.supportedEQPresets.isEmpty {
                    Section("Equalizer") { equalizer(device) }
                }
                if let map = device.touchMap, !map.isEmpty {
                    Section("Touch Controls") {
                        TouchControls(map: map, collapsible: false) { action, gesture in
                            manager.setTouchAction(action, forGesture: gesture)
                        }
                    }
                }
            }
        } else {
            Form { Section { NoDevicesView() } }
        }
    }

    private func header(_ device: DeviceState) -> some View {
        let iconName = device.formFactor == .neckband ? "beats.earphones" : "earbuds"
        return HStack(spacing: 14) {
            Image(systemName: iconName)
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

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom EQ Profiles").font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach(Preferences.shared.savedEQProfiles) { profile in
                        Button(profile.name) {
                            manager.setCustomEQ(profile.eq)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

/// Left, right and case battery with a level bar under each.
private struct BatteryRow: View {
    let device: DeviceState

    private var budSymbol: String {
        device.formFactor == .neckband ? "beats.earphones" : "earbuds"
    }

    var body: some View {
        HStack(spacing: 12) {
            if let combined = device.battery.combined, device.battery.left == nil, device.battery.right == nil {
                cell("Earbuds", symbol: budSymbol, battery: combined, unavailable: false)
            } else {
                cell("Left", symbol: budSymbol, battery: device.battery.left, unavailable: false)
                cell("Right", symbol: budSymbol, battery: device.battery.right, unavailable: false)
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
    @ObservedObject private var prefs = Preferences.shared

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
                    HStack(spacing: 14) {
                        preview(.connected, "Normal")
                        preview(.ancOn, "ANC")
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

            Section("Menu Bar Battery") {
                Toggle("Show battery % next to icon", isOn: $prefs.showBatteryInMenuBar)
                Text("Displays the lowest earbud battery percentage right in the menu bar so you don't need to click to check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Low-Battery Notifications") {
                Toggle("Native low battery warnings", isOn: $prefs.lowBatteryNotificationsEnabled)
                if prefs.lowBatteryNotificationsEnabled {
                    Picker("Notify when battery drops below", selection: $prefs.lowBatteryThreshold) {
                        Text("10%").tag(10)
                        Text("15%").tag(15)
                        Text("20%").tag(20)
                        Text("25%").tag(25)
                    }
                }
            }

            Section("Audio Routing & Quality") {
                Toggle("Auto-switch audio output to earbuds on connect", isOn: $prefs.autoSwitchAudioOutput)
                Toggle("Prevent mic from switching to Bluetooth HFP", isOn: $prefs.preventHFPSwitch)
                Text("Prevents macOS from switching your input microphone to Bluetooth Hands-Free Profile, preserving pristine 48kHz stereo output instead of dropping to 8/16kHz mono voice mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global Keyboard Shortcuts") {
                Toggle("Enable keyboard shortcuts", isOn: $prefs.globalShortcutsEnabled)
                LabeledContent("Cycle ANC (Off → Transparency → ANC → Adaptive)") {
                    Text("⌘⇧A").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
                LabeledContent("Toggle Low-Latency / Gaming Mode") {
                    Text("⌘⇧G").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text("Shortcuts work system-wide across any app or game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Per-App ANC Automation") {
                Toggle("Automate ANC based on active application", isOn: $prefs.perAppANCEnabled)
                if prefs.perAppANCEnabled {
                    ForEach(prefs.perAppANCRules) { rule in
                        HStack {
                            Text(rule.appName)
                            Spacer()
                            Text(rule.mode.rawValue).foregroundStyle(.secondary)
                        }
                    }
                    Text("Automatically engages ANC for music (Spotify, Apple Music) and Transparency for video calls (Zoom, Teams, FaceTime).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    @EnvironmentObject private var manager: BudsManager
    private static let repo = URL(string: "https://github.com/amitdeb9/unifiedbuds-macos")!
    @State private var copyStatus: String?
    @State private var updateStatus: String?
    @State private var isCheckingUpdates = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.3.0"
        let build = info?["CFBundleVersion"] as? String ?? "3"
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
                    Text("Battery, noise control, EQ and touch controls for QCY, Nothing / CMF, realme, OnePlus, boAt, Soundcore, Samsung Galaxy Buds, Sony, and Xiaomi earbuds.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section {
                HStack {
                    Button {
                        checkForUpdates()
                    } label: {
                        Label(isCheckingUpdates ? "Checking…" : "Check for Updates…", systemImage: "arrow.down.circle")
                    }
                    .disabled(isCheckingUpdates)

                    if let updateStatus = updateStatus {
                        Text(updateStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button {
                        let text = manager.exportBluetoothDebugInfo()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copyStatus = "Copied to clipboard!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            copyStatus = nil
                        }
                    } label: {
                        Label("Copy Bluetooth Debug Info", systemImage: "doc.on.clipboard")
                    }

                    if let copyStatus = copyStatus {
                        Text(copyStatus)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Updates & Diagnostics")
            } footer: {
                Text("Bluetooth debug info includes connected device names, SDP channels, and advertised services—handy for opening a GitHub issue or requesting a new model.")
            }

            Section {
                Link(destination: Self.repo) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.repo.appendingPathComponent("issues/new/choose")) {
                    Label("Request Model Support / Report Bug", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }
            } footer: {
                Text("Open source under the MIT License.")
            }
        }
    }

    private func checkForUpdates() {
        isCheckingUpdates = true
        updateStatus = "Checking GitHub…"
        let url = URL(string: "https://api.github.com/repos/amitdeb9/unifiedbuds-macos/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isCheckingUpdates = false
                if let error = error {
                    self.updateStatus = "Failed: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.updateStatus = "Could not check latest release"
                    return
                }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
                let latest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if latest.compare(current, options: .numeric) == .orderedDescending {
                    self.updateStatus = "New version \(tagName) available!"
                    if let htmlUrl = json["html_url"] as? String, let target = URL(string: htmlUrl) {
                        NSWorkspace.shared.open(target)
                    }
                } else {
                    self.updateStatus = "UnifiedBuds is up to date (v\(current))"
                }
            }
        }.resume()
    }
}
