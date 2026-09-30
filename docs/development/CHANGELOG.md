# Changelog

All notable changes to the `ble-mesh-attendance` project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added - Phase 4 (Cross-Platform BLE Relay & Interoperability)
- **Mobile (Flutter):**
  - Application-level BLE relay engine with duplicate packet suppression (`seenPacketIds` bounded cache with 5-minute expiry) and TTL management.
  - Ephemeral application-scoped device ID generation (`{PLATFORM}-{HEX}`) without hardware MAC tracking.
  - Dual BLE Central (`flutter_blue_plus`) and Peripheral (`flutter_ble_peripheral`) support for multi-role operation.
  - Diagnostic test screen (`BleTestScreen`) showing device telemetry, scanner, connection manager, relay toggle, payload dispatch, and live color-coded event log.
  - Complete unit test suite for packet serialization, forwarding, duplicate suppression, and widget testing (`flutter test` passing 8/8).
  - Android BLE permissions (Bluetooth Scan, Connect, Advertise, Fine Location) in `AndroidManifest.xml`.
  - iOS CoreBluetooth usage strings and peripheral background modes in `Info.plist`.
- **Firmware (ESP32-S3 Gateway):**
  - JSON test relay packet parser for Phase 4 packets (`TEST_RELAY` detected by `{` byte).
  - Full backward compatibility for Phase 1 binary attendance packets (`0xAA 0x55`).
  - Dedicated ACK GATT characteristic (`a1b2c3d4-e5f6-7890-abcd-ef1234567896`) with BLE notifications.
  - 1.8" TFT SPI (ST7735, 128x160) real-time status monitor displaying gateway state, client connections, packet throughput, last packet ID, origin, and verified payload.
  - Safe GPIO pin mapping (GPIO 8–12) avoiding Octal Flash/PSRAM bus lines on ESP32-S3-N16R8.
- **Protocol & Documentation:**
  - `protocol/versions/v1/phase4-test-protocol.md`: Test relay packet format, ACK schema, and relay algorithm specification.
  - `docs/hardware/tft-display.md`: Complete wiring specification, SPI configuration, state machine, and hardware troubleshooting notes.
  - `docs/development/phase-4-ios-interoperability.md`: Cross-platform test matrix (Tests A–F), manual test procedure, platform limitations, and layered failure isolation guide.

### Added - Phase 1 (ESP32 Gateway Firmware & Hardware Verification)
- ESP32-S3 Arduino sketch (`esp32-gateway-arduino.ino`) supporting BLE advertisement and passive scanning.
- In-memory duplicate suppression cache (256 entries).
- Custom 128-bit service UUID advertisement.
- RGB status LED indicator on GPIO 48.
