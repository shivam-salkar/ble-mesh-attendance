# ESP32-S3 Classroom Gateway Firmware

Physical BLE-to-Wi-Fi gateway for the BLE Mesh Attendance system.

## Hardware Target

- **Microcontroller:** ESP32-S3 (ESP32-S3-WROOM-1 / ESP32-S3-DevKitC-1 or equivalent)
- **Architecture:** Dual-core Xtensa LX7 @ up to 240 MHz
- **Radio Support:** 2.4 GHz Wi-Fi (802.11 b/g/n) and Bluetooth 5 (LE) / BLE Mesh

## Software Requirements

- **ESP-IDF:** v5.1 or later (v5.2+ recommended)
- **Compiler:** `xtensa-esp32s3-elf-gcc`
- **BLE Stack:** NimBLE (preferred for lightweight memory footprint and flexibility) or standard Bluedroid

## Setup & Build Instructions

1. **Activate the ESP-IDF environment:**
   - **Linux / macOS:**
     ```bash
     . $HOME/esp/esp-idf/export.sh
     ```
   - **Windows (PowerShell):**
     ```powershell
     & $env:USERPROFILE\esp\esp-idf\export.ps1
     ```
   - Or launch the **ESP-IDF 5.x PowerShell / Command Prompt**.

2. **Set the target chip (first time setup):**
   ```bash
   cd firmware/esp32-gateway
   idf.py set-target esp32s3
   ```

3. **Build the firmware:**
   ```bash
   idf.py build
   ```

## Flashing Instructions

Connect the ESP32-S3 board to your workstation via USB (ensure the USB-UART / Native USB port is recognized).

```bash
idf.py -p <PORT> flash
```
Replace `<PORT>` with your serial device (e.g., `COM3` on Windows, or `/dev/ttyUSB0` / `/dev/ttyACM0` on Linux/macOS).

## Serial Monitor

To view serial debug and boot logs:

```bash
idf.py -p <PORT> monitor
```
Press `Ctrl+]` to exit the monitor.

You can also build, flash, and monitor in one step:
```bash
idf.py -p <PORT> flash monitor
```

## Future BLE Gateway Roadmap

1. **Phase 1 — Hardware Validation & BLE Advertising:**
   - Boot verification on target hardware
   - Basic BLE GAP advertising of classroom gateway presence
   - Verify detection from Flutter mobile app
2. **Phase 2 — GATT Server & Ingestion Service:**
   - Expose custom attendance ingestion GATT service/characteristics
   - Receive peer-relayed attendance packets from student phones
   - Send cryptographic acknowledgements back to mobile peers
3. **Phase 3 — Wi-Fi & Backend Forwarding:**
   - Connect to local classroom / campus Wi-Fi
   - Forward validated attendance batches to Supabase / Backend over HTTPS / WebSockets
   - Implement offline queuing and retransmission buffers
