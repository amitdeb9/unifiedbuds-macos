import SwiftUI

/// The full UnifiedBuds window: every control and setting, grouped in a sidebar
/// and laid out like System Settings. Opened from the gear in the menu bar panel
/// or by launching the app.
struct MainWindowView: View {
    enum Page: String, CaseIterable, Identifiable {
        case earbuds = "Earbuds"
        case devices = "Devices"
        case general = "General"
        case about = "About"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .earbuds: return "earbuds"
            case .devices: return "list.bullet"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    @EnvironmentObject private var manager: BudsManager
    @State private var page: Page? = .earbuds

    private var visiblePages: [Page] {
        Page.allCases
    }

    var body: some View {
        NavigationSplitView {
            List(visiblePages, selection: Binding(
                get: { page ?? .earbuds },
                set: { page = $0 }
            )) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch page ?? .earbuds {
                case .earbuds: EarbudsPage()
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
    @ObservedObject private var sleepTimer = SleepTimerManager.shared
    @State private var customSleepMinutes: Int = 45

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

                Section("Features") {
                    Toggle("Low-Latency / Gaming Mode", isOn: Binding(
                        get: { device.gamingModeEnabled },
                        set: { manager.setGamingMode($0) }
                    ))
                    .toggleStyle(.switch)

                    Toggle("In-Ear Wear Detection", isOn: Binding(
                        get: { device.inEarDetectionEnabled },
                        set: { manager.setInEarDetection($0) }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Dual-Device Multipoint Connection", isOn: Binding(
                        get: { device.multipointEnabled },
                        set: { manager.setMultipoint($0) }
                    ))
                    .toggleStyle(.switch)

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

                if !device.supportedEQPresets.isEmpty {
                    Section("Equalizer") { equalizer(device) }
                }

                Section("Touch Controls") {
                    if let map = device.touchMap, !map.isEmpty {
                        TouchControls(map: map, collapsible: false) { action, gesture in
                            manager.setTouchAction(action, forGesture: gesture)
                        }
                    } else {
                        Text("Touch controls are managed by hardware presets on this model.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sleep Timer") {
                    sleepTimerControls
                }
            }
        } else {
            Form { Section { NoDevicesView() } }
        }
    }

    @ViewBuilder
    private var sleepTimerControls: some View {
        if sleepTimer.isActive {
            HStack {
                Label("Pausing in \(sleepTimer.formattedRemaining)", systemImage: "moon.zzz.fill")
                    .foregroundStyle(.indigo)
                    .font(.body.weight(.medium))
                Spacer()
                Button("Cancel Timer", role: .destructive) {
                    sleepTimer.cancel()
                }
                .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([10, 20, 30, 60], id: \.self) { mins in
                        Button("\(mins)m") {
                            sleepTimer.start(minutes: mins)
                        }
                        .controlSize(.small)
                    }
                }
                HStack(spacing: 12) {
                    Stepper("Custom: \(customSleepMinutes) min", value: $customSleepMinutes, in: 1...360, step: 5)
                    Button("Start") {
                        sleepTimer.start(minutes: customSleepMinutes)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Text("When the timer expires, all audio and video playback on your Mac will pause automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ device: DeviceState) -> some View {
        let iconName = MenuBarIcon.symbolForDevice(name: device.name)
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
        MenuBarIcon.symbolForDevice(name: device.name)
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
            Image(systemName: MenuBarIcon.symbolForDevice(name: device.name))
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
    @ObservedObject private var sleepTimer = SleepTimerManager.shared
    @State private var customSleepMinutes: Int = 45

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

            Section("Sleep Timer") {
                if sleepTimer.isActive {
                    HStack {
                        Label("Pausing playback in \(sleepTimer.formattedRemaining)", systemImage: "moon.zzz.fill")
                            .foregroundStyle(.indigo)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button("Cancel Timer", role: .destructive) {
                            sleepTimer.cancel()
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach([10, 20, 30, 60], id: \.self) { mins in
                                Button("\(mins)m") {
                                    sleepTimer.start(minutes: mins)
                                }
                                .controlSize(.small)
                            }
                        }
                        HStack(spacing: 12) {
                            Stepper("Custom: \(customSleepMinutes) min", value: $customSleepMinutes, in: 1...360, step: 5)
                            Button("Start") {
                                sleepTimer.start(minutes: customSleepMinutes)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        Text("When the timer expires, all audio, music, and browser playback will pause automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
    @State private var isDownloading = false

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
                HStack(spacing: 12) {
                    Button {
                        checkForUpdates()
                    } label: {
                        Label(isDownloading ? "Updating…" : (isCheckingUpdates ? "Checking…" : "Check for Updates…"),
                              systemImage: isDownloading ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                    }
                    .disabled(isCheckingUpdates || isDownloading)

                    if isCheckingUpdates || isDownloading {
                        ProgressView().controlSize(.small)
                    }

                    if let updateStatus = updateStatus {
                        Text(updateStatus)
                            .font(.caption)
                            .foregroundStyle(updateStatus.contains("up to date") ? .green : .secondary)
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
                Text("UnifiedBuds checks GitHub releases directly and updates itself in-place without needing Terminal commands.")
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
        updateStatus = "Checking GitHub for updates…"
        let url = URL(string: "https://api.github.com/repos/amitdeb9/unifiedbuds-macos/releases/latest?t=\(Int(Date().timeIntervalSince1970))")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isCheckingUpdates = false
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"

                var latestTag: String?
                var downloadURL: URL?

                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    latestTag = tagName
                    if let assets = json["assets"] as? [[String: Any]] {
                        for asset in assets {
                            if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                               let dlStr = asset["browser_download_url"] as? String,
                               let dlUrl = URL(string: dlStr) {
                                downloadURL = dlUrl
                                break
                            }
                        }
                    }
                }

                guard let tagName = latestTag else {
                    self.updateStatus = "Could not check GitHub releases."
                    return
                }

                let cleanLatest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let isNewer = cleanLatest.compare(current, options: .numeric) == .orderedDescending

                if isNewer {
                    let zipURL = downloadURL ?? URL(string: "https://github.com/amitdeb9/unifiedbuds-macos/releases/download/\(tagName)/UnifiedBuds.zip")!
                    self.updateStatus = "New version v\(cleanLatest) found! Starting auto-update…"
                    self.performAutoUpdate(downloadURL: zipURL, newVersion: cleanLatest)
                } else {
                    self.updateStatus = "UnifiedBuds is up to date (v\(current))"
                }
            }
        }.resume()
    }

    private func performAutoUpdate(downloadURL: URL, newVersion: String) {
        isDownloading = true
        updateStatus = "Downloading v\(newVersion)…"

        URLSession.shared.downloadTask(with: downloadURL) { localURL, _, error in
            DispatchQueue.main.async {
                guard let localURL = localURL, error == nil else {
                    self.isDownloading = false
                    self.updateStatus = "Download failed: \(error?.localizedDescription ?? "Network error")"
                    return
                }

                self.updateStatus = "Installing v\(newVersion) and relaunching…"

                let pid = ProcessInfo.processInfo.processIdentifier
                let destPath = "/Applications/UnifiedBuds.app"
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let downloadedZip = tempDir.appendingPathComponent("UnifiedBuds.zip")
                    try FileManager.default.copyItem(at: localURL, to: downloadedZip)

                    let scriptContent = """
                    #!/bin/bash
                    while kill -0 \(pid) 2>/dev/null; do
                        sleep 0.2
                    done
                    /usr/bin/ditto -x -k "\(downloadedZip.path)" "\(tempDir.path)"
                    if [ -d "\(tempDir.path)/UnifiedBuds.app" ]; then
                        rm -rf "\(destPath)"
                        /usr/bin/ditto "\(tempDir.path)/UnifiedBuds.app" "\(destPath)"
                        xattr -dr com.apple.quarantine "\(destPath)" 2>/dev/null || true
                        open "\(destPath)"
                    fi
                    rm -rf "\(tempDir.path)"
                    """

                    let scriptPath = tempDir.appendingPathComponent("install_update.sh")
                    try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

                    var permissions = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
                    permissions[.posixPermissions] = 0o755
                    try FileManager.default.setAttributes(permissions, ofItemAtPath: scriptPath.path)

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = [scriptPath.path]
                    try process.run()

                    NSApplication.shared.terminate(nil)
                } catch {
                    self.isDownloading = false
                    self.updateStatus = "Update failed: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
