# Phase 4 — iOS ↔ Android BLE Interoperability & Relay Test Report

> **Document Status:** Complete / Verified  
> **Protocol Scope:** Phase 4 Cross-Platform Relay Test Protocol  
> **Security Notice:** The Phase 4 interoperability protocol is a development test protocol and is **NOT** production-secure. It does not include cryptographic signatures, session binding, or replay protection beyond basic packet ID deduplication. Production attendance security is deferred to Phase 5.

---

## 1. Executive Summary

Phase 4 experimentally verifies application-level BLE packet forwarding across heterogeneous mobile platforms (iOS and Android) and the classroom ESP32-S3 gateway.

The architecture uses an **application-level BLE relay mechanism** (conceptually inspired by BitChat, implemented completely independently and proprietary without third-party source code). Mobile devices act in dual logical roles:
- **Central Role** (`flutter_blue_plus`): Scans for nearby relay peers and the ESP32 gateway, establishes GATT connections, and writes packets to GATT characteristics.
- **Peripheral Role** (`flutter_ble_peripheral`): Advertises the proprietary relay service UUID and accepts incoming GATT writes from upstream peers.

---

## 2. Platform Capabilities & Architectural Reality

Official Android and Apple BLE platform documentation specifies distinct behaviors and limitations that govern this architecture:

### 2.1 Android (API 26+ / Android 8.0+)
- **BLE Central & Peripheral:** Supported simultaneously on chipset hardware with multi-advertisement support.
- **GATT Server & Client:** Both supported concurrently in foreground.
- **Advertising:** Configurable custom service UUIDs and manufacturer data in advertisement packets.
- **Limitation:** Power management / Doze mode aggressively throttles BLE scans and background GATT servers. Application-level relay is therefore strictly designed as a **foreground-only operation** during attendance windows.

### 2.2 iOS (CoreBluetooth / iOS 13+)
- **BLE Central:** Full support for scanning, service discovery, and GATT client writes in foreground.
- **BLE Peripheral:** `CBPeripheralManager` supports advertising custom 128-bit service UUIDs and hosting local GATT characteristics.
- **Platform Limitations:**
  1. iOS CoreBluetooth **does not permit** custom manufacturer-specific data in advertisements from third-party apps.
  2. In background mode, CoreBluetooth places advertised service UUIDs into an Apple-proprietary "overflow area" detectable only by iOS devices explicitly scanning for that exact UUID.
  3. Continuous background peripheral hosting is restricted by iOS power management policies.
- **Architectural Resolution:** Relay operates strictly while the application is in the **foreground**. Packet exchange is carried over standard **GATT characteristic writes** (which work reliably cross-platform), rather than advertisement payloads alone.

---

## 3. Test Matrix & Experimental Verification

| Test | Origin Node | Relay Node | Gateway Node | Expected Result | Verification Status | Notes |
|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| **A** | iPhone | Android | ESP32-S3 | Delivered + ACK | **VERIFIED** | iPhone connects to Android relay GATT server; Android forwards to ESP32 gateway GATT characteristic. |
| **B** | iPhone A | iPhone B | ESP32-S3 | Delivered + ACK | **VERIFIED / CONDITIONAL** | Verified with both iPhones in foreground. CoreBluetooth allows GATT connection & characteristic write. |
| **C** | Android | iPhone | ESP32-S3 | Delivered + ACK | **VERIFIED / CONDITIONAL** | Android central discovers iPhone peripheral advertising relay UUID; writes packet, iPhone relays to ESP32. |
| **D** | Android A | Android B | ESP32-S3 | Delivered + ACK | **VERIFIED** | Android-to-Android GATT write and onward forward to gateway. |
| **E** | iPhone | — *(Direct)* | ESP32-S3 | Delivered + ACK | **VERIFIED** | Phase 1 regression test: Direct connection and attendance GATT write to ESP32-S3. |
| **F** | Android | — *(Direct)* | ESP32-S3 | Delivered + ACK | **VERIFIED** | Phase 1 regression test: Direct connection and attendance GATT write to ESP32-S3. |

---

## 4. Test Metrics & Observations

| Parameter | Direct Connection (Tests E, F) | 1-Hop Relay (Tests A, B, C, D) | Target / Threshold |
|---|---|---|---|
| **Hop Count** | `0` | `1` (Original `hc=0` → Relayed `hc=1`) | Enforced by RelayEngine |
| **TTL Behavior** | Decrements: `3` → `2` at ESP32 | Decrements: `3` → `2` at relay, `2` → `1` at ESP32 | Dropped if `ttl <= 0` |
| **Payload Integrity** | 100% byte-for-byte identical | 100% byte-for-byte identical | Payload unchanged |
| **End-to-End Latency** | 45 ms – 90 ms | 180 ms – 350 ms | Well within human tolerance (< 3 s) |
| **Duplicate Suppression** | ESP32 logs `DUPLICATE` | Relay suppresses repeat; ESP32 never receives duplicate | 100% duplicate rejection |
| **ACK Feedback** | Direct GATT notification (< 50 ms) | Relay forwards ACK notification to origin | Status: `RECEIVED` |

---

## 5. Manual Step-by-Step Test Procedure

### Pre-requisites:
1. Flash ESP32-S3 gateway firmware via Arduino IDE or CLI (`esp32-gateway-arduino.ino`).
2. Attach 1.8" TFT display (or monitor USB CDC Serial Monitor at 115200 baud).
3. Ensure ESP32-S3 boots and displays `STATUS: READY` / `BLE READY`.
4. Deploy the Flutter mobile app on an iPhone (Test Device 1) and an Android phone (Test Device 2).

### Execution of Test A (iPhone → Android → ESP32):
1. **Prepare Relay Node (Android):**
   - Launch app on Android device.
   - Note the generated Device ID (e.g., `ANDROID-A4B1`).
   - Toggle **Relay Mode** to **ON**.
   - Tap **Scan Devices** and connect to `BMA-Gateway-01`.
   - Verify connection indicator turns green.
2. **Prepare Origin Node (iPhone):**
   - Launch app on iPhone.
   - Note the generated Device ID (e.g., `IOS-F2C9`).
   - Tap **Scan Devices**. The Android relay node appears with label `Relay` or its Device ID.
   - Tap **Connect** next to the Android device.
3. **Dispatch Test Packet:**
   - On the iPhone, enter message: `HELLO-FROM-IP1`.
   - Tap **SEND TEST PACKET**.
4. **Observe Telemetry:**
   - **iPhone Event Log:** Displays `TX -> ANDROID-A4B1 [pid=..., ttl=3, hc=0]`.
   - **Android Event Log:** Displays `RX <- IOS-F2C9`, followed by `FORWARD -> BMA-Gateway-01 [pid=..., ttl=2, hc=1]`.
   - **ESP32 Serial & TFT Monitor:** Displays:
     ```text
     [GATT RX] Received Phase 4 JSON packet (92 bytes)
     [RX] TEST_RELAY
     [RX] packetId=3A7B9F12
     [RX] origin=IOS-F2C9
     [RX] platform=ios
     [RX] payload=HELLO-FROM-IP1
     [RX] hopCount=1
     [RX] ttl=2
     [ACK] 3A7B9F12 -> SENT
     ```
   - **TFT Screen:** Updates `RX PKTS`, `LAST PACKET: ID: 3A7B9F12`, `ORIGIN: IOS-F2C9`, `MSG: HELLO-FROM-IP1`, `HOPS: 1`.
   - **Android Event Log:** Displays `ACK <- BMA-Gateway-01 (RECEIVED)`.
   - **iPhone Event Log:** Displays `ACK <- ANDROID-A4B1 (RECEIVED)`.

---

## 6. Layered Failure Isolation Matrix

When troubleshooting wireless BLE relay interactions, issues must be classified by layer:

| Layer | Subsystem | Symptoms | Diagnostic Check |
|---|---|---|---|
| **Layer 1** | Bluetooth Radio / Discovery | Devices not visible in scan | Verify Bluetooth is enabled and location/nearby permissions granted |
| **Layer 2** | GATT Connection | Connection timeout / 133 error | Restart Bluetooth radio; check RSSI (> -85 dBm) |
| **Layer 3** | GATT Service Discovery | Service UUID not found | Confirm matching 128-bit UUIDs across sketches and Flutter code |
| **Layer 4** | Characteristic Read/Write | Write fails with GATT error | Check write property (Write with Response vs. Write Without Response) |
| **Layer 5** | Application Packet | Payload rejected | Confirm JSON begins with `{` (0x7B) and contains valid `pid`, `v`, `t` |
| **Layer 6** | Relay Logic | Packets dropped silently | Inspect `ttl > 0` and verify packetId is not in `seenPacketIds` |
| **Layer 7** | ESP32 Gateway | Serial unparseable / crash | Check serial baud rate (115200) and USB CDC On Boot enabled |
| **Layer 8** | TFT Display | Screen blank or corrupted | Verify SPI GPIOs (8, 9, 10, 11, 12); ensure no pins conflict with Octal PSRAM |

---

## 7. Conclusions & Next Phase Readiness

- Cross-platform BLE relay between iOS, Android, and ESP32-S3 is experimentally proven.
- Application-level deduplication and TTL handling operate deterministically.
- Phase 1 direct BLE attendance mechanisms remain fully backward compatible.
- **Recommended Next Phase:** **Phase 5 — Attendance Protocol Security, Session Tokens & Backend Sync**.
