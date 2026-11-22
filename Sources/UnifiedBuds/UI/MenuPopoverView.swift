import AppKit
import SwiftUI

/// Native macOS Visual Effect view for Control Center-style backdrop vibrancy blur
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Frosted Glass Card wrapper matching macOS Control Center aesthetic
struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
    }
}

struct MenuPopoverView: View {
    @EnvironmentObject private var manager: BudsManager
    @ObservedObject private var sleepTimer = SleepTimerManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let device = manager.selected {
                DeviceHeader(device: device)
                if sleepTimer.isActive {
                    ActiveSleepTimerPill(sleepTimer: sleepTimer)
                }
                DeviceControls(device: device)
            } else {
                emptyState
            }

            if !manager.history.isEmpty {
                Divider().opacity(0.3)
                DeviceHistoryList()
            }

            Divider().opacity(0.3)
            footer
        }
        .padding(12)
        .frame(width: 310)
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow, state: .active))
        .modifier(NoFocusRing())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text("No Earbuds Connected")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
                HeaderActionPill()
            }
            Text("Pair your QCY, Nothing, realme, OnePlus or boAt earbuds in macOS Bluetooth settings to control them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
    }

    private var footer: some View {
        HStack {
            Text("UnifiedBuds")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 2)
    }
}

/// Header containing Device Name, live glowing connection status dot, and glass action pill.
/// App icon and app name have been completely removed per user request.
struct DeviceHeader: View {
    @EnvironmentObject private var manager: BudsManager
    let device: DeviceState

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                // Live status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.8), radius: isConnected ? 3 : 1)

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
                        Text(device.name)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                    }
                    Text(statusText(device))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HeaderActionPill()
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var isConnected: Bool {
        device.connection == .connected
    }

    private var statusColor: Color {
        switch device.connection {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary.opacity(0.5)
        case .failed: return .red
        }
    }

    private func statusText(_ device: DeviceState) -> String {
        switch device.connection {
        case .connected: return "\(device.brand.rawValue) · Connected"
        case .connecting: return "\(device.brand.rawValue) · Connecting…"
        case .disconnected: return "\(device.brand.rawValue) · Not connected"
        case .failed(let message): return message
        }
    }
}

/// Elegant capsule containing Reconnect and Settings actions
private struct HeaderActionPill: View {
    @EnvironmentObject private var manager: BudsManager

    var body: some View {
        HStack(spacing: 4) {
            Button {
                manager.reconnectSelected()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reconnect control channel")

            Divider()
                .frame(height: 12)
                .opacity(0.3)

            Button {
                AppDelegate.shared?.showWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
        }
    }
}

/// Floating glass banner shown when a sleep timer is actively counting down
private struct ActiveSleepTimerPill: View {
    @ObservedObject var sleepTimer: SleepTimerManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.caption)
                .foregroundStyle(.indigo)
            Text("Sleep timer: \(sleepTimer.formattedRemaining)")
                .font(.caption.weight(.medium).monospacedDigit())
            Spacer()
            Button("Cancel") {
                sleepTimer.cancel()
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.indigo.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.indigo.opacity(0.25), lineWidth: 0.75)
                }
        }
    }
}

struct DeviceControls: View {
    @EnvironmentObject private var manager: BudsManager
    @EnvironmentObject private var audio: AudioOutput
    let device: DeviceState

    private var enabled: Bool { device.connection == .connected }

    private var budSymbol: String {
        MenuBarIcon.symbolForDevice(name: device.name)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Glass Battery Card
            GlassCard {
                HStack(spacing: 0) {
                    if let combined = device.battery.combined, device.battery.left == nil, device.battery.right == nil {
                        BatteryCell(label: "Earbuds", symbol: budSymbol, battery: combined)
                    } else {
                        BatteryCell(label: "L", symbol: budSymbol, battery: device.battery.left)
                        BatteryCell(label: "R", symbol: budSymbol, battery: device.battery.right)
                    }
                    BatteryCell(label: "Case", symbol: "earbuds.case", battery: device.battery.caseBattery,
                                unavailable: !device.reportsCaseBattery)
                }
            }

            // Sound Output Card (Cleanly hidden if audio devices unavailable)
            if let buds = audio.device(named: device.name), let mac = audio.builtInDevice {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOUND OUTPUT")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            soundOutputButton(title: "Earbuds", icon: budSymbol, isSelected: audio.defaultDeviceID == buds.id) {
                                withAnimation(.snappy) { audio.select(buds) }
                            }
                            soundOutputButton(title: "Mac Speakers", icon: "laptopcomputer", isSelected: audio.defaultDeviceID == mac.id) {
                                withAnimation(.snappy) { audio.select(mac) }
                            }
                        }
                    }
                }
            }

            // Control Center-Style Noise Control Card (Cleanly hidden if unsupported)
            if !device.supportedANCModes.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOISE CONTROL")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            ForEach(device.supportedANCModes) { mode in
                                let isSelected = device.ancMode == mode
                                Button {
                                    withAnimation(.snappy) {
                                        manager.setANCMode(mode)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: iconForMode(mode))
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(shortName(for: mode))
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                                            }
                                    }
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if device.ancMode == .noiseCancellation, !device.ancLevels.isEmpty {
                            HStack {
                                Text("Strength").font(.caption2).foregroundStyle(.secondary)
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
                            .padding(.top, 2)
                        }
                    }
                }
            }

            // Equalizer Card (Cleanly hidden if unsupported)
            if !device.supportedEQPresets.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EQUALIZER")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
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
        }
        .disabled(!enabled)
    }

    private func soundOutputButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func iconForMode(_ mode: ANCMode) -> String {
        switch mode {
        case .off: return "slash.circle"
        case .transparency: return "wave.3.forward"
        case .noiseCancellation: return "shield.fill"
        case .adaptive: return "a.circle.fill"
        }
    }

    private func shortName(for mode: ANCMode) -> String {
        switch mode {
        case .off: return "Off"
        case .transparency: return "Transp."
        case .noiseCancellation: return "ANC"
        case .adaptive: return "Adaptive"
        }
    }
}

private struct BatteryCell: View {
    let label: String
    let symbol: String
    let battery: BudBattery?
    var unavailable = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(height: 22)

            HStack(spacing: 2) {
                if battery?.charging == true {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 9))
                }
                Text(battery.map { "\($0.percent)%" } ?? (unavailable ? "N/A" : "—"))
                    .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(textColor)
            }

            // Modern mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)
                    if let percent = battery?.percent {
                        Capsule()
                            .fill(progressColor(percent))
                            .frame(width: max(4, geo.size.width * CGFloat(min(percent, 100)) / 100.0), height: 4)
                    }
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 12)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(unavailable && battery == nil ? "These earbuds don't report the case battery to a Mac." : "")
    }

    private var iconColor: Color {
        guard let battery else { return .secondary }
        if battery.charging { return .green }
        return battery.percent <= 15 ? .red : .primary
    }

    private var textColor: Color {
        guard let battery else { return .secondary }
        return battery.percent <= 15 ? .red : .primary
    }

    private func progressColor(_ percent: Int) -> Color {
        if battery?.charging == true { return .green }
        return percent <= 15 ? .red : .accentColor
    }
}

/// Every supported device seen on this Mac, with connect / disconnect.
struct DeviceHistoryList: View {
    @EnvironmentObject private var manager: BudsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OTHER DEVICES")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

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

    private var iconName: String {
        MenuBarIcon.symbolForDevice(name: device.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(connected ? Color.accentColor : .secondary)
                .frame(width: 18)
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
        .padding(.vertical, 2)
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

/// Left, right and case battery with a level bar under each.
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
            if let current = map[gesture], TouchAction(rawValue: current) == nil {
                Text("Other (\(current))").tag(current)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 104)
    }
}

/// Bass / mid / treble sliders for the Custom EQ preset.
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
