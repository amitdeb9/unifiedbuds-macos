import SwiftUI

struct MenuPopoverView: View {
    @EnvironmentObject private var manager: BudsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandBar
            if let device = manager.selected {
                DeviceHeader(device: device)
                DeviceControls(device: device)
            } else {
                emptyState
            }
            if !manager.history.isEmpty {
                Divider()
                DeviceHistoryList()
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .modifier(NoFocusRing())
    }

    private var emptyState: some View {
        NoDevicesView()
    }

    /// The app logo and name across the top of the popover, with the settings button.
    private var brandBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            Text("UnifiedBuds").font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            // Plain tappable image, like reload, so it never draws a focus box.
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture { AppDelegate.shared?.showWindow() }
                .help("Open UnifiedBuds settings")
                .accessibilityLabel("Settings")
                .accessibilityAddTraits(.isButton)
        }
    }

    /// Touch controls and launch at login live in the settings window (gear button).
    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}

/// Device name (or a picker when several are connected), status, and reload.
struct DeviceHeader: View {
    @EnvironmentObject private var manager: BudsManager
    let device: DeviceState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if manager.devices.count > 1 {
                    Picker("", selection: Binding(
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
                    Text(device.name).font(.headline)
                }
                Text(statusText(device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // A plain tappable image rather than a Button: as the first control in the
            // panel a Button takes keyboard focus and macOS draws a highlight box on it.
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture { manager.reconnectSelected() }
                .help("Reconnect control channel")
                .accessibilityLabel("Reconnect")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func statusText(_ device: DeviceState) -> String {
        switch device.connection {
        case .connected: return device.brand.rawValue
        case .connecting: return "\(device.brand.rawValue) · Connecting…"
        case .disconnected: return "\(device.brand.rawValue) · Not connected"
        case .failed(let message): return message
        }
    }
}

struct NoDevicesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No supported earbuds connected").font(.headline)
            Text("Pair QCY, Nothing / CMF, realme, OnePlus or boAt earbuds in System Settings › Bluetooth and connect them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Launch-at-login checkbox that shows the real login-item state, including when
/// macOS still needs the user's approval.
struct LaunchAtLoginControl: View {
    /// The menu bar panel uses small text; the settings window uses the system size.
    var compact = true
    @State private var enabled = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    error = LaunchAtLogin.set(newValue)
                    sync()
                }
            ))
            .toggleStyle(.checkbox)
            .font(compact ? .caption : .body)
            if needsApproval {
                HStack(spacing: 4) {
                    Text("Allow UnifiedBuds in Login Items to finish.")
                    Button("Open Settings") { LaunchAtLogin.openLoginItemsSettings() }
                        .buttonStyle(.link)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: sync)
    }

    private func sync() {
        enabled = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
        needsApproval = LaunchAtLogin.needsApproval
    }
}

/// Every supported device seen on this Mac, with connect / disconnect.
struct DeviceHistoryList: View {
    @EnvironmentObject private var manager: BudsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices").font(.caption).foregroundStyle(.secondary)
            ForEach(manager.history) { device in
                DeviceRow(device: device,
                          connected: manager.isConnected(device.address),
                          pending: manager.pendingAddresses.contains(device.address))
            }
        }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var manager: BudsManager
    let device: KnownDevice
    let connected: Bool
    let pending: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "earbuds")
                .foregroundStyle(connected ? Color.accentColor : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.callout).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if pending {
                ProgressView().controlSize(.small)
            } else if connected {
                Button("Disconnect") { manager.disconnectDevice(address: device.address) }
                    .controlSize(.small)
            } else {
                Button("Connect") { manager.connectDevice(address: device.address) }
                    .controlSize(.small)
            }
        }
        .contextMenu {
            if !connected {
                Button("Remove from list") { manager.forget(address: device.address) }
            }
        }
    }

    private var subtitle: String {
        var parts = [connected ? "Connected" : lastUsed]
        let levels = [("Battery", device.combined), ("L", device.left), ("R", device.right), ("Case", device.caseBattery)]
            .compactMap { label, value in value.map { "\(label) \($0)%" } }
        if !levels.isEmpty { parts.append(levels.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    private var lastUsed: String {
        guard device.lastConnected > .distantPast else { return "Paired" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last used " + formatter.localizedString(for: device.lastConnected, relativeTo: Date())
    }
}

struct DeviceControls: View {
    @EnvironmentObject private var manager: BudsManager
    @EnvironmentObject private var audio: AudioOutput
    let device: DeviceState

    private var enabled: Bool { device.connection == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                if let combined = device.battery.combined, device.battery.left == nil, device.battery.right == nil {
                    BatteryCell(label: "Earbuds", symbol: "earbuds", battery: combined)
                } else {
                    BatteryCell(label: "L", symbol: "earbuds", battery: device.battery.left)
                    BatteryCell(label: "R", symbol: "earbuds", battery: device.battery.right)
                }
                BatteryCell(label: "Case", symbol: "earbuds.case", battery: device.battery.caseBattery,
                            unavailable: !device.reportsCaseBattery)
            }

            if let buds = audio.device(named: device.name), let mac = audio.builtInDevice {
                section("Sound output") {
                    Picker("", selection: Binding(
                        get: { audio.defaultDeviceID },
                        set: { id in
                            if let target = [buds, mac].first(where: { $0.id == id }) { audio.select(target) }
                        }
                    )) {
                        Label("Earbuds", systemImage: "earbuds").tag(buds.id)
                        Label("Mac Speakers", systemImage: "laptopcomputer").tag(mac.id)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if !device.supportedANCModes.isEmpty {
                section("Noise control") {
                    Picker("", selection: Binding(
                        get: { device.ancMode },
                        set: { if let mode = $0 { manager.setANCMode(mode) } }
                    )) {
                        ForEach(device.supportedANCModes) { mode in
                            Text(mode.rawValue).tag(Optional(mode))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if device.ancMode == .noiseCancellation, !device.ancLevels.isEmpty {
                        HStack {
                            Text("Strength").font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { device.ancLevel ?? device.ancLevels.count - 1 },
                                set: { manager.setANCLevel($0) }
                            )) {
                                ForEach(Array(device.ancLevels.enumerated()), id: \.offset) { index, name in
                                    Text(name).tag(index)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                }
            }

            if !device.supportedEQPresets.isEmpty {
                section("Equalizer") {
                    Picker("", selection: Binding(
                        get: { device.eqPreset },
                        set: { if let preset = $0 { manager.setEQ(preset) } }
                    )) {
                        if device.eqPreset == nil { Text("—").tag(EQPreset?.none) }
                        ForEach(device.supportedEQPresets) { preset in
                            Text(preset.name).tag(Optional(preset))
                        }
                    }
                    .labelsHidden()
                    if device.eqPreset == .custom, let custom = device.customEQ {
                        CustomEQSliders(initial: custom) { manager.setCustomEQ($0) }
                    }
                }
            }

        }
        .disabled(!enabled)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Left / right action menus for each touch gesture, collapsed by default.
struct TouchControls: View {
    let map: [UInt8: UInt8]
    var collapsible = true
    let set: (_ action: UInt8, _ gesture: UInt8) -> Void
    @State private var expanded = false

    var body: some View {
        if collapsible {
            DisclosureGroup(isExpanded: $expanded) {
                table.padding(.top, 4)
            } label: {
                Text("Touch controls").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            table
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("")
                Text("Left").font(.caption2).foregroundStyle(.secondary)
                Text("Right").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(TouchGesture.allCases) { gesture in
                GridRow {
                    Text(gesture.name).font(.caption)
                    menu(for: gesture.leftID)
                    menu(for: gesture.rightID)
                }
            }
        }
    }

    private func menu(for gesture: UInt8) -> some View {
        Picker("", selection: Binding(
            get: { map[gesture] ?? 0 },
            set: { set($0, gesture) }
        )) {
            ForEach(TouchAction.allCases) { action in
                Text(action.name).tag(action.rawValue)
            }
            // Keep a value the app doesn't know selectable rather than showing it as None.
            if let current = map[gesture], TouchAction(rawValue: current) == nil {
                Text("Other (\(current))").tag(current)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 104)
    }
}

/// Bass / mid / treble sliders for the Custom EQ preset. Changes are sent when a
/// slider is released, not on every step.
struct CustomEQSliders: View {
    @State private var eq: CustomEQ
    let initial: CustomEQ
    let apply: (CustomEQ) -> Void

    init(initial: CustomEQ, apply: @escaping (CustomEQ) -> Void) {
        _eq = State(initialValue: initial)
        self.initial = initial
        self.apply = apply
    }

    var body: some View {
        VStack(spacing: 4) {
            row("Bass", \.bass, range: -6...12)
            row("Mid", \.mid, range: -6...6)
            row("Treble", \.treble, range: -6...8)
        }
        .padding(.top, 4)
        // Another window or a device switch can change the values; don't keep stale ones.
        .onChange(of: initial) { eq = $0 }
    }

    private func row(_ title: String, _ keyPath: WritableKeyPath<CustomEQ, Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).frame(width: 42, alignment: .leading)
            Slider(value: Binding(
                get: { Double(eq[keyPath: keyPath]) },
                set: { eq[keyPath: keyPath] = Int($0.rounded()) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                if !editing { apply(eq) }
            }
            Text(String(format: "%+d dB", eq[keyPath: keyPath]))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}

private struct BatteryCell: View {
    let label: String
    let symbol: String
    let battery: BudBattery?
    var unavailable = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(height: 26)
            HStack(spacing: 2) {
                if battery?.charging == true {
                    Image(systemName: "bolt.fill").foregroundStyle(.green).font(.caption2)
                }
                Text(battery.map { "\($0.percent)%" } ?? (unavailable ? "N/A" : "—"))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(unavailable && battery == nil ? "These earbuds don't report the case's battery to a Mac." : "")
    }

    private var color: Color {
        guard let battery else { return .secondary }
        if battery.charging { return .primary }
        return battery.percent <= 15 ? .red : .primary
    }
}

/// Hides the keyboard-focus box macOS draws around the first button in a window.
struct NoFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}
