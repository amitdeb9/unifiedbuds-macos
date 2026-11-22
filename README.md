# UnifiedBuds

A lightweight macOS menu bar app for **QCY, Nothing / CMF, realme, OnePlus, boAt, Anker Soundcore, Samsung Galaxy Buds, Sony WF/WH, and Xiaomi / Redmi** earbuds: live menu bar battery %, noise control (Off / Transparency / ANC / Adaptive), custom EQ profiles, gaming low-latency mode, wear detection, multipoint, find my buds, global hotkeys, and per-app automation.

```
 ┌──────────────────────────────────────────────┐
 │  🎧 UnifiedBuds                       ⚙      │
 ├──────────────────────────────────────────────┤
 │  QCY MeloBuds N20              🔄 Reconnect  │
 │  QCY · Connected                             │
 ├──────────────────────────────────────────────┤
 │     [ 85% ]        [ 85% ]        [ 90% ]    │
 │        L              R             Case     │
 ├──────────────────────────────────────────────┤
 │  Sound output:   [ Earbuds ]  [ Mac Speakers]│
 ├──────────────────────────────────────────────┤
 │  Noise control:  [ Off ] [ Transparency ]    │
 │                  [   ANC   ] [  Adaptive   ] │
 │  Strength:       [ Low ]  [ Medium ] [ High ]│
 ├──────────────────────────────────────────────┤
 │  Equalizer:      [ Bass Boost          ▾ ]   │
 │  Custom EQ:      [ Podcast ] [ Focus ] [ + ] │
 ├──────────────────────────────────────────────┤
 │  Features:       Gaming Mode [ Toggle ]      │
 │  Find My Buds:   [ Ring L ]     [ Ring R ]   │
 └──────────────────────────────────────────────┘
```

| Brand | Battery (L / R / Case) | Noise Control | EQ Presets & Custom Curves | Gaming & Features |
|---|---|---|---|---|
| **QCY** (JieLi models, e.g. MeloBuds N20) | ✓ (L/R) | ✓ (ANC / Transp / Adapt) | ✓ (8-band factory curve + custom dB) | ✓ (Touch, Gaming, Find My) |
| **QCY** (Classic BLE A001 models) | ✓ (L/R/Case) | ✓ | ✓ (10-band client EQ) | |
| **Nothing / CMF** (Ear, Ear (a), CMF Pro) | ✓ (L/R/Case) | ✓ | ✓ (Dirac Opteo / Balanced) | ✓ (Gaming, Wear, Multipoint, Ring) |
| **realme, OPPO, OnePlus** (HeyMelody) | ✓ (L/R/Case) | ✓ | ✓ | ✓ (Gaming, Wear, Multipoint, Neckband) |
| **Anker Soundcore** (Liberty, Space, Life) | ✓ | ✓ | ✓ (Signature, Acoustic, Custom) | ✓ (Gaming, Wear, Multipoint) |
| **Samsung Galaxy Buds** (Buds2, Pro, FE, 3) | ✓ | ✓ | ✓ (Normal, Bass Boost, Dynamic) | ✓ (Gaming, Wear, Find My chime) |
| **Sony** (WF/WH-1000XM4/XM5, LinkBuds) | ✓ | ✓ | ✓ (Bright, Excited, Bass Boost) | ✓ (Gaming, Wear, Multipoint) |
| **Xiaomi / Redmi Buds** (Pro series) | ✓ | ✓ | ✓ (Standard, Enhance Bass, Custom)| ✓ (Gaming, Wear, Find My) |
| **boAt** (Airdopes, Rockerz, Nirvana) | ✓ (HFP status) | | | Sound output & connection |

Requires macOS 13+ (Ventura, Sonoma, Sequoia).

---

## Installation

### 1. Homebrew Cask (Recommended)

```sh
brew tap amitdeb9/tap
brew install --cask unifiedbuds
```

### 2. Download Installer DMG

**[Download UnifiedBuds.dmg](https://github.com/amitdeb9/unifiedbuds-macos/releases/latest/download/UnifiedBuds.dmg)**, open it and drag UnifiedBuds into `/Applications`.

### 3. One-line Terminal Command

```sh
curl -fsSL https://raw.githubusercontent.com/amitdeb9/unifiedbuds-macos/main/install.sh | bash
```

To update an existing installation:
```sh
curl -fsSL https://raw.githubusercontent.com/amitdeb9/unifiedbuds-macos/main/install.sh | bash -s -- --update
```

---

## Key Features

### 🎧 Menu Bar & UI Polish
- **Live Battery % in the Menu Bar**: Optional toggle to display the lowest earbud battery directly in your menu bar (`🎧 85%`).
- **Dynamic State Icons**: Menu bar icon dynamically indicates whether ANC is active, Transparency is on, or earbuds are charging.
- **Device-Specific Icons**: Distinct icons for true wireless earbuds, neckband models (e.g. realme Buds Wireless 5 ANC), and over-ear headphones.
- **Low-Battery Notifications**: Native macOS notification alerts when any earbud drops below 10%, 15%, 20%, or 25%.
- **Clean Interface**: Unsupported controls automatically hide cleanly rather than showing empty or disabled rows.

### ⚡ Audio & Earbud Controls
- **Global Keyboard Shortcuts**:
  - `⌘⇧A`: Cycle Noise Control Mode (Off → Transparency → ANC → Adaptive) from anywhere in macOS.
  - `⌘⇧G`: Toggle Low-Latency / Gaming Mode on the fly.
- **Prevent Bluetooth HFP Mic Downgrade**: Automatically prevents macOS from switching your input mic to low-bandwidth Bluetooth Hands-Free, preserving 48kHz stereo output quality during calls.
- **Auto-Switch Audio Output**: Seamlessly switches macOS default audio to your earbuds the moment they connect.
- **Find My Buds**: Trigger an audible chime on your left or right earbud to locate them quickly.
- **Custom EQ Profiles**: Save custom bass/mid/treble curves per genre or activity (e.g., *Podcast*, *Bass Boost*, *Focus*).
- **Per-App ANC Automation**: Automatically switch to ANC when Spotify or Apple Music is active, and switch to Transparency during Zoom, Teams, or FaceTime calls.

### 🤖 Apple Shortcuts & CLI Support

UnifiedBuds includes a built-in CLI for automation:

```sh
# Change ANC mode from Terminal or Apple Shortcuts
/Applications/UnifiedBuds.app/Contents/MacOS/UnifiedBuds --anc transparency
/Applications/UnifiedBuds.app/Contents/MacOS/UnifiedBuds --anc anc

# Toggle Gaming mode
/Applications/UnifiedBuds.app/Contents/MacOS/UnifiedBuds --gaming on

# Check battery status
/Applications/UnifiedBuds.app/Contents/MacOS/UnifiedBuds --battery

# Dump diagnostic report for bug reporting
/Applications/UnifiedBuds.app/Contents/MacOS/UnifiedBuds --diagnostics
```

You can also send distributed notifications from AppleScript or Swift:
```applescript
tell application "System Events"
    -- Trigger ANC change
end tell
```

---

## Layout

```
Sources/UnifiedBuds/
  App/UnifiedBudsApp.swift          MenuBarExtra and CLI argument dispatcher
  UI/MenuPopoverView.swift          Quick popover (battery, ANC, EQ, Gaming, Find My)
  UI/MainWindowView.swift           Settings window (features, shortcuts, per-app rules)
  UI/MenuBarIcon.swift              Dynamic template glyph generator
  Core/EarbudDriver.swift           Shared driver protocol and state definitions
  Core/BudsManager.swift            Bluetooth watcher, driver factory, sleep/wake reconnect
  Core/Preferences.swift            Persistent user preferences
  Core/NotificationManager.swift    Native low-battery notifications
  Core/KeyboardShortcutManager.swift Global hotkeys (⌘⇧A, ⌘⇧G)
  Core/AppAutomationManager.swift   Per-app ANC automation observer
  Core/AudioOutput.swift            CoreAudio routing & HFP quality protection
  Core/DeviceHistory.swift          Recent device connection history
  Core/LaunchAtLogin.swift          SMAppService login helper
  Transport/RFCOMMTransport.swift   IOBluetooth RFCOMM channel abstraction
  Drivers/QCYDriver.swift           CoreBluetooth GATT service A001 driver
  Drivers/QCYJieLiDriver.swift      RFCOMM JL_SPP, JieLi RCSP protocol driver
  Drivers/NothingDriver.swift       RFCOMM 0x55 + CRC-16/MODBUS driver
  Drivers/RealmeDriver.swift        RFCOMM HeyMelody 0xAA driver
  Drivers/SoundcoreDriver.swift     Anker Soundcore series driver
  Drivers/GalaxyBudsDriver.swift    Samsung Galaxy Buds protocol driver
  Drivers/SonyDriver.swift          Sony WF/WH series driver
  Drivers/XiaomiDriver.swift        Xiaomi / Redmi Buds driver
  Drivers/GenericDriver.swift       Hands-Free Profile fallback driver
Casks/unifiedbuds.rb                Homebrew cask tap formula
PROTOCOLS.md                        Deep reverse-engineered protocol specifications
```

---

## Protocol Specifications

Detailed packet structures, hex byte formats, opcodes, and CRC algorithms are documented in [PROTOCOLS.md](PROTOCOLS.md).

<details>
<summary><b>Known Hardware Details (click to expand)</b></summary>

- **QCY JieLi Models (e.g. MeloBuds N20):** Connects over RFCOMM `JL_SPP`. Case battery is not broadcast over BLE advertising on some firmware versions. Touch control table setting is `0x2B`; Gaming mode is `0x24`.
- **Nothing / CMF:** Packets use `0x55` header with CRC-16/MODBUS. Listening modes on CMF models use opcode `0xF01D` and `0xC050`. Gaming mode is `0xF018`.
- **realme / OnePlus:** Packets use `0xAA` header with LEB128 length prefix. Gaming mode is `0x0406`.
- **Control Connection Lock:** If the control channel refuses to open, force-close the manufacturer's mobile app on your phone (Nothing X, realme Link, QCY), as earbuds typically accept only one active RFCOMM control channel at a time.

</details>

---

## Build from Source

```sh
scripts/build-app.sh          # -> build/UnifiedBuds.noindex/UnifiedBuds.app (ad-hoc signed)
scripts/make-dmg.sh           # -> build/UnifiedBuds.dmg (installer image)
```

## License

MIT © [Amit Debnath](https://github.com/amitdeb9). See [LICENSE](LICENSE).
