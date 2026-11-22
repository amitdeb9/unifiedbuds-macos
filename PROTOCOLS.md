# UnifiedBuds Protocol Documentation

Technical reference and byte specifications for wireless earbud control channels on macOS (RFCOMM, BLE GATT, and SPP).

---

## Brand Architecture Matrix

| Brand | Status | Primary Transport | Framing Protocol | Noise Control | Battery Source | Custom Features |
|---|---|---|---|---|---|---|
| **QCY (JieLi RCSP)** | ✓ Verified | RFCOMM (SPP `JL_SPP`) | RCSP (`FE DC BA ... EF`) | Setting `0x17` | Setting `0x2F` & Adv `0xC2` | 8-band EQ (`0x22`), Touch (`0x2B`), Game mode (`0x24`), Find My (`0x30`) |
| **QCY (Legacy BLE)** | ✓ Verified | CoreBluetooth GATT | Service `A001` / Char `1001` | TLV `0x17` | Char `0008` & TLV `0x2F` | 10-band client EQ curve (Char `000B`) |
| **Nothing / CMF** | ✓ Verified | RFCOMM `AEAC4A03-...` | `0x55` + CRC-16/MODBUS | Cmd `0xF00F` / `0xC01E` | Cmd `0xC007` & Push `0xE001` | EQ (`0xF010`/`0xF01D`), Game Mode (`0xF018`), Wear (`0xF011`), Ring (`0xF003`) |
| **realme / OnePlus / OPPO** | ✓ Verified | RFCOMM HeyMelody | `0xAA` + LEB128 len | Cmd `0x0404` / Query `0x010C` | Cmd `0x0106` & Push `0x0204` | Game mode (`0x0406`), Wear (`0x0408`), Multipoint (`0x041A`), Find My (`0x0410`) |
| **Anker Soundcore** | 🧪 Beta | RFCOMM / BLE | Multi-format SPP / HFP | Query/Set Category | Hands-Free Profile (KVC) | EQ Presets, Game Mode, In-Ear, Multipoint |
| **Samsung Galaxy Buds** | 🧪 Beta | RFCOMM (Galaxy Buds Protocol) | `FD <len> <id> <data> <crc>` | Msg `SET_ANC` | Msg `BATTERY_STATUS` | Ambient sound level, Game mode, Find My ringing chime |
| **Sony WF / WH** | 🧪 Beta | RFCOMM SPP | Sony Headphone Protocol | Cmd category `0x0E` | Battery report bytes | 8-band EQ presets, LDAC toggles, Speak-to-chat |
| **Xiaomi / Redmi** | 🧪 Beta | RFCOMM / BLE | Mi Buds Protocol | Packet header `0xA5` | Broadcast & Query | ANC modes, Game mode, Dual connection |
| **boAt** | 🧪 Beta | Bluetooth Classic HFP | Apple HFP Battery AT commands | N/A | `batteryPercentLeft/Right/Combined` | Sound output switching, connect/disconnect |

---

## 1. QCY JieLi RCSP (e.g. MeloBuds N20, HT05, T13 ANC)

JieLi-based QCY earbuds expose an RFCOMM service named `JL_SPP` (`00001101-0000-1000-8000-00805F9B34FB`).

### Frame Format
```
FE DC BA <flag> <opcode> <length_hi> <length_lo> <body> EF
```
- **Host Request**: flag `0xC0`, body: `<sequence: u8> <payload>`
- **Device Push**: flag `0x80`, body: `<sequence: u8> <payload>`
- **Device Reply**: flag `0x00`, body: `<status: 0x00> <sequence: u8> <payload>`

<details>
<summary><b>Click to expand: QCY JieLi TLV Settings</b></summary>

Settings ride on custom opcode `0xFF`:
```
FE DC BA C0 FF <len_hi> <len_lo> <seq> <setting_id> <data_len> <data> EF
```

| Setting ID | Purpose | Payload |
|---|---|---|
| `0x17` | Noise Control | `[mode: 1=ANC, 2=Off, 3=Transparency, scene: 1=Indoor/Noisy, 5=Adaptive, level: 0..2]` |
| `0x22` | Equalizer | `<preset_id> <master_gain: s16 LE> (<freq: u16 LE> <gain: s16 LE> <q: u16 LE> <type: u8>)*8` |
| `0x24` | Gaming Mode | `[0x01 = On, 0x00 = Off]` |
| `0x26` | In-Ear Detection | `[0x01 = On, 0x00 = Off]` |
| `0x2B` | Touch Table | Pairs of `<gesture_id> <action_id>` (odd = Left bud, even = Right bud) |
| `0x2F` | Battery Query | Returns `[L: u8, R: u8, Case: u8]` (bit 7 set = charging) |
| `0x30` | Find My Buds | `[bud: 1=Left, 2=Right, state: 1=Chime, 0=Stop]` |
| `0xFE` | Read Request | `[target_setting_id]` |

</details>

---

## 2. Nothing & CMF (Nothing Ear, Ear (2), Ear (a), CMF Buds Pro)

Control channel connects to RFCOMM service UUID `AEAC4A03-DFF5-498F-843A-34487CF133EB` (fallback channel 15).

### Frame Format (Little-Endian)
```
55 <control: u16> <command: u16> <length: u16> <operation_id: u8> <payload> <crc16: u16>
```
- CRC is `CRC-16/MODBUS` (reflected polynomial `0xA001`, initial value `0xFFFF`).
- Included when `control & 0x20 != 0`.

<details>
<summary><b>Click to expand: Nothing / CMF Command IDs</b></summary>

| Command ID | Direction | Purpose | Description |
|---|---|---|---|
| `0xC007` | Query | Battery | Requests battery status |
| `0xE001` | Push | Battery | `[count, (id: 2=L, 3=R, 4=Case, val: level \| 0x80 charging)...]` |
| `0xC01E` | Query | Noise Control | Read current ANC mode |
| `0xF00F` | Set | Noise Control | `[0x01, mode: 1=High ANC, 4=Adaptive, 5=Off, 7=Transparency, 0x00]` |
| `0xE003` | Push | Noise Control | Pushed when ANC button is pressed on earbud stem |
| `0xC01F` | Query | Equalizer | Standard Nothing EQ preset |
| `0xF010` | Set | Equalizer | Preset index (0=Balanced, 1=Voice, 2=Treble, 3=Bass) |
| `0xC050` | Query | Listening Mode | CMF Dirac Opteo / EQ presets |
| `0xF01D` | Set | Listening Mode | CMF preset index (0=Dirac Opteo, 1=Rock, 2=Electronic, etc.) |
| `0xF018` | Set | Gaming Mode | `[0x01 = Low Latency On, 0x00 = Off]` |
| `0xF011` | Set | In-Ear Detection | `[0x01 = Wear Detection On, 0x00 = Off]` |
| `0xF020` | Set | Multipoint | `[0x01 = Dual Connect On, 0x00 = Off]` |
| `0xF003` | Set | Find My Buds | `[left_chime: 0/1, right_chime: 0/1]` |

</details>

---

## 3. realme, OnePlus & OPPO (HeyMelody Protocol)

Uses HeyMelody RFCOMM services:
- `0000079A-D102-11E1-9B23-00025B00A5A5`
- `00001107-D102-11E1-9B23-00025B00A5A5`
- `00001101-0000-1000-8000-00805F9B34FB` (fallback channel 15)

### Frame Format
```
AA <length: LEB128> 00 00 <command: u16 LE> <seq: u8> <payload_len: u16 LE> <payload>
```
- No packet checksum.
- Response command IDs use `command | 0x8000`.

<details>
<summary><b>Click to expand: HeyMelody Command IDs & Bitmasks</b></summary>

| Command ID | Purpose | Payload & Details |
|---|---|---|
| `0x0100` | Hello / Handshake | Sent immediately after channel open |
| `0x0205` | Subscribe | `[0x03, 0x01 (Battery), 0x02 (Wear), 0x03 (ANC)]` |
| `0x0106` | Battery Query | Returns `<status> <count> (<id: 1=L, 2=R, 3=Case> <level \| 0x80 charging>)*` |
| `0x010C` | ANC Query | Returns active ANC mask |
| `0x0404` | ANC Set | `[0x01, 0x01, mask: u8]` |
| `0x0204` | Status Push | Asynchronous event pushed from earbuds |
| `0x0406` | Gaming Mode | `[0x01, 0x01 = On, 0x00 = Off]` |
| `0x0408` | In-Ear Detection | `[0x01, 0x01 = On, 0x00 = Off]` |
| `0x041A` | Multipoint | `[0x01, 0x01 = On, 0x00 = Off]` |
| `0x0410` | Ring Earbud | `[bud: 1=Left, 2=Right, chime: 0/1]` |

**ANC Bitmasks:**
- `0x01`: Off
- `0x02`: Transparency
- `0x08`: Max / High ANC
- `0x20`: Smart / Adaptive ANC

</details>

---

## 4. Samsung Galaxy Buds (Galaxy Buds Protocol)

Galaxy Buds communicate over Bluetooth RFCOMM using the Galaxy Buds Protocol (GBP).

### Frame Format
```
FD <length: u16 LE> <msg_id: u8> <payload> <crc16: u16 LE>
```
- **Start Byte**: `0xFD`
- **Supported Models**: Buds, Buds+, Buds Live, Buds Pro, Buds2, Buds2 Pro, Buds FE, Buds3, Buds3 Pro.
- **Find My Buds**: Ring left/right command sends a high-frequency beeping tone directly via audio DSP firmware.

---

## 5. Sony WF / WH Series

Sony uses command-response frames over RFCOMM Serial Port Profile.
- Models: WH-1000XM4/XM5, WF-1000XM4/XM5, LinkBuds, LinkBuds S.
- Categories: ANC mode switching (`0x0E`), Ambient sound slider (`0..20`), Custom Equalizer (8-band + Clear Bass), Voice passthrough focus, Speak-to-chat toggle.

---

## 6. Anker Soundcore Series

Models: Liberty 4 NC, Liberty 3 Pro, Space Q45, Space A40, Life P3, Life Q30.
- Transports: Bluetooth Classic RFCOMM and BLE custom services.
- Profiles: Custom Soundcore signature curves, gaming low-latency mode, hearID custom frequency response.
