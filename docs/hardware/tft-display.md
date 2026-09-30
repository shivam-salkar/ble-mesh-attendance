# 1.8" TFT SPI Display Specification & Hardware Guide

> **Project:** BLE Mesh Attendance — ESP32-S3 Classroom Gateway  
> **Status:** Phase 4 Implementation  
> **Target MCU:** ESP32-S3-WROOM-1 (ESP32-S3-N16R8)

---

## 1. Hardware Overview

| Specification | Value | Notes |
|---|---|---|
| **Display Model** | 1.8-inch TFT SPI Display Module (V1.1) | Standard hobbyist SPI breakout |
| **Controller IC** | Sitronix **ST7735** (ST7735S / ST7735R) | ST7789 compatible variant exists |
| **Resolution** | 128 × 160 pixels | RGB 16-bit color (5-6-5) |
| **Active Display Area** | ~28.03 mm × 35.04 mm | Diagonal 1.8" |
| **Bus Interface** | 4-Wire SPI (Hardware SPI) + Command/Data | Max SPI clock ~20 MHz |
| **Operating Voltage** | 3.3V – 5.0V (VCC has on-board 3.3V regulator) | Logic levels must be 3.3V |
| **Current Consumption** | ~50 mA (with backlight active) | Powered via ESP32 3.3V rail |

---

## 2. Pinout & ESP32-S3 Wiring

> [!IMPORTANT]
> The ESP32-S3-N16R8 uses **Octal SPI** for its 16MB Flash and 8MB PSRAM. GPIOs 33–37 are internally dedicated to the Octal memory bus and **MUST NOT** be used for external SPI peripherals.
> The wiring below uses FSPI (SPI2) free GPIOs.

| Module Pin | Label | ESP32-S3 Pin | Function | Configuration Macro in Firmware |
|---|---|---|---|---|
| 1 | **GND** | GND | Power Ground | System GND |
| 2 | **VCC** | 3.3V (or 5V) | Module Power Supply | Board Power |
| 3 | **SCL / SCK** | **GPIO 12** | SPI Clock | `TFT_SCLK` |
| 4 | **SDA / MOSI** | **GPIO 11** | SPI Master Out Slave In | `TFT_MOSI` |
| 5 | **RES / RST** | **GPIO 9** | Hardware Reset (Active Low) | `TFT_RST` |
| 6 | **DC / A0** | **GPIO 8** | Data (High) / Command (Low) | `TFT_DC` |
| 7 | **CS** | **GPIO 10** | Chip Select (Active Low) | `TFT_CS` |
| 8 | **BLK / LED** | 3.3V (or GPIO 7) | Backlight LED Anode | Tied to 3.3V or PWM control |

### Firmware Pin Mapping Definition

In [firmware/esp32-gateway-arduino/esp32-gateway-arduino.ino](file:///c:/Projects/ble-mesh-attendance/firmware/esp32-gateway-arduino/esp32-gateway-arduino.ino):

```cpp
#define TFT_ENABLED 1

#if TFT_ENABLED
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>
#include <SPI.h>

#define TFT_CS    10   // Chip Select
#define TFT_DC     8   // Data/Command (A0/RS)
#define TFT_RST    9   // Reset (-1 if tied to MCU EN)
#define TFT_MOSI  11   // SPI MOSI (DIN/SDA)
#define TFT_SCLK  12   // SPI Clock (SCK/SCL)

Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
#endif
```

---

## 3. Libraries & Dependencies

The firmware uses the following standard Arduino libraries:
1. **`Adafruit GFX Library`** (`Adafruit_GFX.h`) — Core 2D graphics engine and font rendering.
2. **`Adafruit ST7735 and ST7789 Library`** (`Adafruit_ST7735.h`) — Display controller hardware driver.
3. **`SPI.h`** — Hardware SPI peripheral driver for ESP32.

---

## 4. Initialization Sequence

```cpp
void setupTft() {
#if TFT_ENABLED
  tft.initR(INITR_BLACKTAB);         // Initialize ST7735S chip, black tab variant
  tft.setRotation(1);                // Landscape orientation (160x128)
  tft.fillScreen(ST77XX_BLACK);
  tft.setTextWrap(false);
  tft.setTextColor(ST77XX_WHITE);
  tft.setTextSize(1);                // Compact 6x8 font to maximize information density
#endif
}
```

---

## 5. UI Layout & State Machine

The display functions strictly as a **Status Monitor** utilizing a compact monospace 6×8 font to display maximum diagnostic telemetry across the 160×128 landscape resolution.

### Screen Layout Specification

```
┌──────────────────────────────────────────────┐
│ BLE GATEWAY                     STATUS: READY│  <-- Header (Yellow / Green)
├──────────────────────────────────────────────┤
│ BLE: ADV ACTIVE      PEERS: 0                │  <-- Connection State & Clients
│ RX PKTS: 14          ACK SENT: 14            │  <-- Throughput Counters
│ DUPLICATES: 2        DROPPED: 0              │  <-- Suppression Stats
├──────────────────────────────────────────────┤
│ LAST PACKET:                                 │
│ ID:     A1B2C3D4   HOPS: 2   TTL: 1          │  <-- Last Packet Identifiers
│ ORIGIN: IOS-A1B2   PLAT: ios                 │  <-- Origin & Source OS
│ MSG:    HELLO-FROM-IP1                       │  <-- Verified Application Payload
├──────────────────────────────────────────────┤
│ ACK: SENT -> A1B2C3D4 [RECEIVED]             │  <-- ACK Feedback Channel
└──────────────────────────────────────────────┘
```

### Supported Monitor States

1. **`BOOTING`**: System power-on, flash & PSRAM verification, GPIO initialization.
2. **`BLE READY`**: NimBLE initialized, BLE service registered, advertisement active.
3. **`BLE CONNECTED`**: Central node (phone/relay) established GATT link.
4. **`RECEIVING`**: Active characteristic write detected on GATT or BLE scan.
5. **`PROCESSING`**: Deduplication check, JSON validation, and field extraction.
6. **`ACK SENT`**: Notification dispatched to client via ACK characteristic.
7. **`DUPLICATE`**: Packet ignored due to matching seen packet ID cache.
8. **`ERROR`**: Malformed payload, TTL expired, or GATT write failure.

---

## 6. Known Hardware Quirks & Troubleshooting

1. **Color Inversion / Offsets:**
   - Some 1.8" clone panels use different tab configurations (`INITR_REDTAB`, `INITR_GREENTAB`, or `INITR_18BLACKTAB`).
   - If colors are inverted (black appears white), call `tft.invertDisplay(true);`.
   - If a 1-2 pixel border offset appears on the left/top edges, switch between `INITR_BLACKTAB` and `INITR_REDTAB`.

2. **Octal SPI Bus Collision:**
   - ESP32-S3 boards with 16MB Flash / 8MB OPI PSRAM use high-speed Octal SPI on GPIO 33-37. Connecting any display line to these pins causes instant boot loops or memory corruption. Always keep display pins on GPIO 8–12.

3. **Backlight Power Stability:**
   - The backlight LED draws substantial current when turned on. If the 3.3V rail sags during simultaneous BLE TX bursts and backlight activation, add a 100µF decoupling capacitor across VCC and GND near the display header.
