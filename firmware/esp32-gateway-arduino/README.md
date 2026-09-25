# ESP32-S3 Gateway Firmware — Arduino (Phase 1)

BLE Mesh Attendance classroom gateway firmware for **ESP32-S3-N16R8**.

> **Phase 1 Scope:** BLE advertisement + scan only. No Wi-Fi backend integration yet. No mesh relay on ESP32 side.

## Hardware

| Spec | Value |
|------|-------|
| **MCU** | ESP32-S3 |
| **Module** | ESP32-S3-WROOM-1 (N16R8) |
| **Flash** | 16 MB |
| **PSRAM** | 8 MB (Octal SPI) |
| **BLE** | Bluetooth 5.0 LE |
| **LED** | WS2812 RGB on GPIO 48 |

## Firmware Overview

### `esp32-gateway-arduino/` — Classroom Gateway

The main gateway firmware that:
- **Advertises** a custom BLE service UUID so student phones can discover it
- **Scans** for BLE advertisements containing attendance packets
- **Parses** the attendance protocol packet format
- **Deduplicates** packets using an in-memory packet ID cache (256 entries, 5-minute expiry)
- **Logs** all received packets with full field breakdown to Serial Monitor

### `test-beacon-arduino/` — Test Beacon (Student Simulator)

A helper sketch that simulates a student phone:
- Generates valid attendance packets with random IDs
- Broadcasts them as BLE manufacturer-specific data
- Sends a new packet every 5 seconds
- Supports serial commands for duplicate/burst testing

## Protocol: BLE Attendance Packet

Packets are sent as **BLE manufacturer-specific advertisement data** (AD type `0xFF`):

```
Offset  Size   Field             Description
──────  ────   ─────             ───────────
0       2      Magic bytes       [0xAA, 0x55] — identifies our packets
2       1      Version           Protocol version (0x01)
3       1      Packet type       0x01 = ATTENDANCE
4       4      Packet ID         Random uint32, for deduplication
8       4      Session ID        From backend, identifies the lecture
12      4      Timestamp         Unix seconds (lower 32 bits)
16      1      TTL               Starts at 5, decremented per hop
17      1      Hop count         Starts at 0, incremented per hop
18      16     Student token     Truncated HMAC or temporary token
34      8      Signature         Truncated digital signature
───────────────────────────────────────────────────────────────
Total: 42 bytes (fits in BLE advertisement payload)
```

> **Note:** The 42-byte payload is within the BLE 5.0 extended advertising limit. Classic BLE 4.x advertisements allow ~31 bytes total (including headers), but ESP32-S3 supports BLE 5.0 extended advertisements.

## BLE Service UUID

```
Gateway Service:  a1b2c3d4-e5f6-7890-abcd-ef1234567890
Status Char:      a1b2c3d4-e5f6-7890-abcd-ef1234567891  (READ)
Attendance Char:  a1b2c3d4-e5f6-7890-abcd-ef1234567892  (WRITE)
```

Student phones scan for the service UUID to discover the gateway, then can either:
1. Send attendance via **BLE advertisements** (passive, scanned by gateway)
2. Connect via **GATT** and write to the attendance characteristic (active, future)

---

## Build & Flash Instructions

### Prerequisites

1. **Arduino IDE 2.x** installed
2. **ESP32 Arduino Core** installed via Board Manager:
   - In Arduino IDE: `File → Preferences → Additional Board Manager URLs`
   - Add: `https://espressif.github.io/arduino-esp32/package_esp32_index.json`
   - Then: `Tools → Board → Board Manager → Search "esp32" → Install`

### Board Settings

| Setting | Value |
|---------|-------|
| **Board** | `ESP32S3 Dev Module` |
| **USB CDC On Boot** | `Enabled` |
| **USB Mode** | `Hardware CDC and JTAG` |
| **Flash Size** | `16MB (128Mb)` |
| **Partition Scheme** | `Default 4MB with spiffs` or `16M Flash (3MB APP/9.9MB FATFS)` |
| **PSRAM** | `OPI PSRAM` |
| **Upload Speed** | `921600` |
| **Port** | Your ESP32's COM port (e.g., `COM3`) |

### Flash the Gateway

1. Open `firmware/esp32-gateway-arduino/esp32-gateway-arduino.ino` in Arduino IDE
2. Select board settings as above
3. Connect ESP32-S3 via USB
4. If the board isn't detected:
   - Hold the **BOOT** button
   - Press and release **RESET** while holding BOOT
   - Release BOOT after 1 second
   - The board should appear as a COM port
5. Click **Upload** (→ button)
6. Open **Serial Monitor** at `115200` baud

### Flash the Test Beacon (Optional)

If you have a **second ESP32**:

1. Open `firmware/test-beacon-arduino/test-beacon-arduino.ino`
2. Flash to the second board
3. Power it on near the gateway
4. Watch the gateway Serial Monitor for received packets

---

## Testing Without a Second ESP32

### Option 1: nRF Connect (Android/iOS)

1. Install [nRF Connect](https://www.nordicsemi.no/Products/Development-tools/nrf-connect-for-mobile) on your phone
2. Go to **Advertiser** tab
3. Create a new advertisement packet:
   - Add **Manufacturer Specific Data**
   - Company ID: `0xFFFF`
   - Data (hex): `AA 55 01 01 DE AD BE EF 78 56 34 12 00 00 00 00 05 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 AA BB CC DD EE FF 00 11`
4. Start advertising
5. The gateway should detect and parse the packet

### Option 2: Serial Monitor Commands

On the gateway, send these characters via Serial Monitor:

| Key | Action |
|-----|--------|
| `d` | Print diagnostics (uptime, counters, memory) |
| `r` | Reset all counters |
| `s` | Restart BLE scan |
| `h` | Show help |

On the test beacon:

| Key | Action |
|-----|--------|
| `d` | Send duplicate packet (tests dedup) |
| `b` | Send burst of 5 rapid packets |
| `h` | Show help |

---

## Expected Serial Output (Gateway)

```
═══════════════════════════════════════════════════════
  BLE Mesh Attendance — Classroom Gateway
  Phase 1: BLE Advertisement + Scan
  Board: ESP32-S3-N16R8
  Framework: Arduino + NimBLE
═══════════════════════════════════════════════════════

[INIT] Initializing NimBLE...
[INIT] Device address: AA:BB:CC:DD:EE:FF
[INIT] Creating BLE server...
[INIT] Configuring BLE advertising...
[INIT] ✓ Gateway is now advertising
[INIT] ✓ Service UUID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
[INIT] Configuring BLE scanner...
[INIT] ✓ Scanner configured

═══════════════════════════════════════════════════════
  GATEWAY READY — Scanning for attendance packets...
═══════════════════════════════════════════════════════

╔══════════════════════════════════════════════════════╗
║         ATTENDANCE PACKET RECEIVED                  ║
╚══════════════════════════════════════════════════════╝
  Source:      11:22:33:44:55:66
  RSSI:        -42 dBm
  Version:     1
  Packet ID:   0xDEADBEEF
  Session ID:  0x12345678
  Timestamp:   1234567890
  TTL:         5
  Hop Count:   0
  Token:       0102030405060708090A0B0C0D0E0F10
  Signature:   AABBCCDDEEFF0011
  Raw (42 bytes): AA 55 01 01 EF BE AD DE 78 56 34 12 ...
──────────────────────────────────────────────────────
```

---

## LED Status Indicators

| Color | Pattern | Meaning |
|-------|---------|---------|
| 🔵 Blue | Solid | Initializing |
| 🟢 Green | Brief flash | Ready / Packet received |
| 🔵 Blue | Brief pulse | Heartbeat (every 30s) |
| 🟠 Orange | Blink | Test beacon transmitting |

---

## Troubleshooting

### Board not detected (no COM port)

1. Try a different USB cable (must support data, not charge-only)
2. Try the **other USB port** on the ESP32-S3 (if it has two)
3. Put the board in **download mode**: Hold BOOT → Press RESET → Release BOOT
4. Install [ESP32-S3 USB driver](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/get-started/establish-serial-connection.html) if needed
5. Check Device Manager for unknown devices under "Ports" or "Other devices"

### Compilation errors

- Ensure ESP32 Arduino Core **v3.x+** is installed (NimBLE is built-in)
- If `NimBLEDevice.h` not found: update to latest ESP32 Arduino Core
- Select `ESP32S3 Dev Module` as the board (not generic ESP32)

### No packets received

- Ensure test beacon and gateway are within BLE range (~10m indoors)
- Verify both sketches use the same magic bytes (`0xAA, 0x55`)
- Check the test beacon's Serial Monitor for TX confirmations
- Try `s` command on gateway to restart scanning

---

## Architecture (Phase 1)

```
┌─────────────────────┐          BLE Adv         ┌─────────────────────┐
│   Test Beacon       │ ──────────────────────── │   ESP32-S3 Gateway  │
│   (or Student Phone)│     Manufacturer Data     │                     │
│                     │     [0xAA 0x55 ...]       │   Scan + Parse      │
│   Advertise packet  │                           │   Dedup             │
│   every 5 seconds   │                           │   Serial log        │
└─────────────────────┘                           └─────────────────────┘
                                                          │
                                                    Serial Monitor
                                                    (115200 baud)
```

## Next Steps (Phase 2+)

- [ ] Wi-Fi connection and HTTP POST to backend
- [ ] GATT-based packet delivery (connection mode)
- [ ] Phone → Phone → ESP32 multi-hop relay
- [ ] Session management from backend
- [ ] OTA firmware updates
- [ ] Multiple gateway support
