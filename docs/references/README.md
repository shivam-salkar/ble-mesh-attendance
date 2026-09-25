# External References & Architecture Research

This document compiles authoritative references, research materials, and inspiration repositories for building the BLE Mesh Attendance system.

---

### 1. BitChat Repository
- **URL:** [https://github.com/permissionlesstech/bitchat](https://github.com/permissionlesstech/bitchat)
- **Purpose:** Primary architectural and conceptual reference for studying application-level BLE peer-to-peer networking.
- **Key Concepts to Study:**
  - Peer discovery mechanics
  - BLE central and peripheral simultaneous/interleaved behavior
  - Packet forwarding and relay routing
  - Time-To-Live (TTL) mechanics
  - Duplicate suppression and bloom filters / seen-cache
  - Multi-hop networking over consumer Bluetooth
  - Compact binary packet encoding
- **Important Note:** Do not copy BitChat blindly. Study the implementation and adapt concepts to our attendance-specific protocol. Before copying any code, inspect the exact license of the relevant repository/version and comply with its terms.

---

### 2. BitChat Android
- **URL:** [https://github.com/permissionlesstech/bitchat-android](https://github.com/permissionlesstech/bitchat-android)
- **Purpose:** Reference for Android BLE implementation, background service considerations, and cross-platform protocol ideas.

---

### 3. BitChat ESP32 Reference
- **URL:** [https://github.com/hackerhouse-opensource/bitchat-esp32](https://github.com/hackerhouse-opensource/bitchat-esp32)
- **Purpose:** Reference for ESP32-side BLE interoperability, GATT server/client configurations, and gateway experimentation.
- **Important Note:** Inspect its license before using any code or adapting patterns.

---

### 4. ESP-IDF Documentation
- **URL:** [https://docs.espressif.com/projects/esp-idf/](https://docs.espressif.com/projects/esp-idf/)
- **Purpose:** Official Espressif IoT Development Framework documentation, APIs, FreeRTOS tasks, build systems, and best practices.

---

### 5. ESP32-S3 BLE Documentation
- **URL:** [Espressif ESP32-S3 Bluetooth LE Documentation](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/bluetooth/index.html)
- **Purpose:** Official documentation for BLE Controller, Host (NimBLE / Bluedroid), GAP, and GATT implementations on ESP32-S3.

---

### 6. ESP-BLE-MESH Documentation
- **URL:** [Espressif ESP-BLE-MESH Documentation](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/bluetooth/esp-ble-mesh.html)
- **Purpose:** Reference for Bluetooth SIG Mesh concepts and Espressif's BLE Mesh stack implementation.
- **Important Distinction:** ESP-BLE-MESH implements the Bluetooth SIG standard, which is **not** the same architecture as our intended phone mesh. Standard consumer smartphones do not participate directly in Bluetooth SIG Mesh without root or proprietary stacks. Our project uses an application-level BLE peer relay.

---

### 7. Apple Core Bluetooth
- **URL:** [https://developer.apple.com/documentation/corebluetooth](https://developer.apple.com/documentation/corebluetooth)
- **Purpose:** Official iOS reference for `CBCentralManager`, `CBPeripheralManager`, background execution modes, and iOS BLE constraints.

---

### 8. Android Bluetooth / BLE Documentation
- **URL:** [Android Bluetooth Low Energy Overview](https://developer.android.com/develop/connectivity/bluetooth/ble)
- **Purpose:** Official Android developer guide covering BLE scanning (`BluetoothLeScanner`), advertising (`BluetoothLeAdvertiser`), GATT server/client APIs, and Android 12+ runtime permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`).

---

### 9. Educational ESP32 BLE Mesh Video Tutorial
- **URL:** [Build a BLE Mesh Network with ESP32 using ESP-IDF! (YouTube)](https://youtu.be/DbrN5ONz3O4?si=Fe1copWS3j64vPfE)
- **Title:** "Build a BLE Mesh Network with ESP32 using ESP-IDF!"
- **Purpose:** Educational tutorial supplied by the project owner for learning ESP32 BLE Mesh and ESP-IDF development concepts.
