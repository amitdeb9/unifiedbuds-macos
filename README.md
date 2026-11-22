# UnifiedBuds

A lightweight macOS menu bar app for QCY, Nothing / CMF and realme earbuds: battery (L / R / case), noise control (Off / Transparency / ANC / Adaptive), EQ presets, connect / disconnect, and a list of every supported device seen on this Mac with its last battery levels.

Requires macOS 13+.

## Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/amitdeb9/unifiedbuds-macos/main/install.sh | bash
```

It downloads the latest release into `/Applications` and opens it. Allow Bluetooth access when macOS asks.

## Update

```sh
curl -fsSL https://raw.githubusercontent.com/amitdeb9/unifiedbuds-macos/main/install.sh | bash -s -- --update
```

This does nothing if you already have the latest version.

## Build

```sh
scripts/build-app.sh          # -> build/UnifiedBuds.app (universal, ad-hoc signed)
scripts/make-dmg.sh           # -> build/UnifiedBuds.dmg (needs `brew install create-dmg`)
```

To publish a release (used by the install command), bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, then run `scripts/release.sh`.

Set `SIGN_IDENTITY="Developer ID Application: …"` to sign for distribution. Ad-hoc builds get a new code identity each time, so macOS asks for Bluetooth permission again after every rebuild; until it's allowed the app sees no devices. Launch at login needs approval in System Settings › General › Login Items. Without a Developer ID, users approve the first launch in System Settings › Privacy & Security › Open Anyway.

To work in Xcode, open `Package.swift`. Running from Xcode skips the bundle's `Info.plist`, so the Bluetooth permission prompt and `LSUIElement` only apply to the app built by the script.

## Layout

```
Sources/UnifiedBuds/
  App/UnifiedBudsApp.swift        MenuBarExtra (window style)
  UI/MenuPopoverView.swift        battery, noise control, EQ, launch at login
  Core/EarbudDriver.swift         shared driver protocol and state model
  Core/BudsManager.swift          watches connected devices, picks a driver by name
  Core/LaunchAtLogin.swift        SMAppService
  Core/DeviceHistory.swift        known devices, persisted in UserDefaults
  Transport/RFCOMMTransport.swift IOBluetooth RFCOMM channel found through SDP
  Drivers/QCYDriver.swift         CoreBluetooth, service A001
  Drivers/QCYJieLiDriver.swift    RFCOMM JL_SPP, JieLi RCSP frames (FE DC BA … EF)
  Drivers/NothingDriver.swift     RFCOMM aeac4a03-…, 0x55 frames with CRC-16/MODBUS
  Drivers/RealmeDriver.swift      RFCOMM HeyMelody, 0xAA frames
Resources/Info.plist              LSUIElement, NSBluetoothAlwaysUsageDescription
Resources/UnifiedBuds.entitlements  no App Sandbox (it blocks RFCOMM)
```

To add a brand, implement `EarbudDriver`, add a name match in `Brand.detect(name:)` and a case in `BudsManager.makeDriver`.

## Protocol sources

| Brand | References |
|---|---|
| QCY | qcy-control-macos (Muyubu1), QCYBar (joaoianuci), h3-control (tsnery) for JieLi models |
| Nothing / CMF | ear-web, nothing-x-macos, Gadgetbridge `Ear1Support` |
| realme | BudsControl (amarsakore), Gadgetbridge `oppo` |

## Known gaps (need testing on hardware)

- **QCY:** classic models use BLE service A001. JieLi-based models (SDP records named `JL_*`, e.g. MeloBuds N20) use RCSP over SPP; battery, noise control and EQ are verified on the N20. EQ presets (including Extra Bass and a Custom bass/mid/treble preset) are offsets on the N20's factory 8-band curve (captured from the buds) and only appear on buds reporting that layout. ANC strength (low/medium/high) is selectable. Touch controls use setting 0x2B, a list of `<gesture> <action>` pairs (odd gesture ids = left bud, even = right; 1/2 single, 3/4 double, 5/6 triple, 7/8 quadruple, 9/10 long press). The N20 also reports pairs 0x41–0x4A (all 0x80) of unknown meaning; the app writes the whole table back unchanged apart from the edited pair. The N20 never reports case battery (0 in every reply, no BLE broadcast), so the app shows N/A. The N20's ANC read-back doesn't follow writes, so the app remembers the last mode per device. A001 EQ writes a 10-band gain curve to characteristic 000B; models without it get no EQ picker.
- **CMF EQ:** "Dirac Opteo" is id 0 in ear-web and 7 in Gadgetbridge. The app sends 0 and accepts both when reading.
- **realme EQ:** the buds don't report preset ids and no source documents them, so EQ is hidden for realme. Adaptive ANC appears once the buds report it.
- **Nothing:** the per-model ANC lists follow Gadgetbridge and nothing-x-macos.

If the control channel won't open, force-close the brand's phone app (Nothing X, realme Link, QCY). Most earbuds allow only one control connection at a time.

Use PacketLogger (Additional Tools for Xcode) or an Android HCI snoop log to check bytes against the official apps.

## License

MIT, see [LICENSE](LICENSE).
