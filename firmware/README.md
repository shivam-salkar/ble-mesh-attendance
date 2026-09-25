# Firmware — BLE Mesh Attendance

ESP32-S3 gateway firmware for the BLE Mesh Attendance classroom system.

## Directory Structure

```
firmware/
├── esp32-gateway-arduino/   ← ACTIVE (Phase 1, Arduino IDE)
│   ├── esp32-gateway-arduino.ino    # Main gateway firmware
│   └── README.md                     # Build/flash/test instructions
│
├── test-beacon-arduino/     ← Testing tool
│   └── test-beacon-arduino.ino      # Simulates student BLE packets
│
└── esp32-gateway/           ← ARCHIVED (ESP-IDF, for future use)
    ├── main/main.c
    ├── CMakeLists.txt
    └── sdkconfig.defaults
```

## Current Status

| Component | Status | Framework |
|-----------|--------|-----------|
| **Gateway (Arduino)** | ✅ Compiles, ready to flash | Arduino Core 3.3.x |
| **Test Beacon (Arduino)** | ✅ Compiles, ready to flash | Arduino Core 3.3.x |
| **Gateway (ESP-IDF)** | ⏸ Archived | ESP-IDF 5.x |

### Why Arduino instead of ESP-IDF?

ESP-IDF toolchain had environment configuration issues on the development machine. For **Phase 1** (BLE hardware validation and initial testing), the Arduino framework provides:

- Simpler build/flash workflow via Arduino IDE
- Same underlying ESP32 BLE stack (NimBLE)
- Easier debugging with Serial Monitor
- No loss of functionality for BLE advertisement/scan operations

The ESP-IDF version is preserved in `esp32-gateway/` for potential future migration when advanced features (custom partitions, OTA, etc.) are needed.

## Quick Start

See [`esp32-gateway-arduino/README.md`](esp32-gateway-arduino/README.md) for detailed build, flash, and testing instructions.

### TL;DR

1. Open `esp32-gateway-arduino.ino` in Arduino IDE
2. Select board: **ESP32S3 Dev Module**
3. Set: USB CDC On Boot = Enabled, Flash Size = 16MB, PSRAM = OPI
4. Upload → Open Serial Monitor at 115200 baud
