/**
 * ═══════════════════════════════════════════════════════════════════
 *  BLE Mesh Attendance — ESP32-S3 Classroom Gateway (Arduino)
 *  Phase 1: BLE Advertisement + Scan
 * ═══════════════════════════════════════════════════════════════════
 *
 *  Board:  ESP32-S3-N16R8 (ESP32-S3-WROOM-1, 16MB Flash, 8MB PSRAM)
 *  Framework: Arduino + ESP32 Arduino Core 3.3.x
 *  BLE Stack: NimBLE (via built-in BLE library)
 *
 *  This firmware:
 *   1. Advertises the gateway using a custom 128-bit BLE service UUID
 *      so student phones can discover the classroom gateway.
 *   2. Simultaneously scans for BLE advertisements from student phones
 *      carrying attendance data in manufacturer-specific data fields.
 *   3. Parses received attendance packets and logs them to Serial.
 *   4. Tracks seen packet IDs to suppress duplicates.
 *   5. Blinks the onboard RGB LED to indicate status.
 *
 *  Phase 1 scope:
 *   - Direct phone → ESP32 BLE communication (no mesh relay yet)
 *   - Serial output only (no Wi-Fi backend yet)
 *   - Duplicate suppression via in-memory packet ID cache
 *
 *  Arduino IDE Board Settings:
 *   - Board: ESP32S3 Dev Module
 *   - USB CDC On Boot: Enabled
 *   - USB Mode: Hardware CDC and JTAG
 *   - Flash Size: 16MB (128Mb)
 *   - PSRAM: OPI PSRAM
 *
 * ═══════════════════════════════════════════════════════════════════
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>
#include <BLEUtils.h>

// ─── Configuration ───────────────────────────────────────────────

// Custom 128-bit service UUID for the BLE Mesh Attendance Gateway
// Student phones will scan for this UUID to discover the gateway
#define GATEWAY_SERVICE_UUID        "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
#define GATEWAY_STATUS_CHAR_UUID    "a1b2c3d4-e5f6-7890-abcd-ef1234567891"
#define GATEWAY_ATTENDANCE_CHAR_UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567892"

// Manufacturer ID for our custom attendance packets
// Using 0xFFFF (reserved/test) — replace with registered ID in production
#define ATTENDANCE_MFG_ID 0xFFFF

// Attendance packet magic bytes (first 2 bytes after manufacturer ID)
// Used to distinguish our packets from other BLE traffic
#define ATTENDANCE_MAGIC_BYTE_0 0xAA
#define ATTENDANCE_MAGIC_BYTE_1 0x55

// Protocol version
#define PROTOCOL_VERSION 0x01

// Maximum number of cached packet IDs for duplicate suppression
#define MAX_CACHED_PACKET_IDS 256

// How long to cache packet IDs before expiry (milliseconds)
#define PACKET_CACHE_EXPIRY_MS 300000  // 5 minutes

// Scan duration per cycle (seconds)
#define SCAN_DURATION_SECS 5

// LED pin for status indication (ESP32-S3 built-in RGB LED is on GPIO 48)
#define STATUS_LED_PIN 48

// Gateway device name shown in BLE advertisements
#define GATEWAY_DEVICE_NAME "BMA-Gateway-01"

// ─── Packet Structure ────────────────────────────────────────────
//
// Manufacturer-specific data layout (inside BLE advertisement):
//
// The manufacturer ID (2 bytes, 0xFFFF) is prepended automatically
// by the BLE stack. Our custom payload starts right after:
//
// Offset  Size   Field
// ──────  ────   ─────
// 0       2      Magic bytes [0xAA, 0x55]
// 2       1      Protocol version (0x01)
// 3       1      Packet type (0x01 = ATTENDANCE)
// 4       4      Packet ID (random, for dedup)
// 8       4      Session ID (from backend)
// 12      4      Timestamp (unix seconds, lower 32 bits)
// 16      1      TTL (starts at 5, decremented per hop)
// 17      1      Hop count (starts at 0, incremented per hop)
// 18      16     Student token (truncated HMAC or random token)
// 34      8      Signature (truncated Ed25519 or HMAC)
// ──────────────────────────────────────────────────────────────────
// Total: 42 bytes payload (+ 2 bytes MFG ID = 44 bytes in adv data)
//

// Packet type constants
#define PKT_TYPE_ATTENDANCE 0x01
#define PKT_TYPE_HEARTBEAT  0x02
#define PKT_TYPE_ACK        0x03

// Minimum valid attendance packet size (magic + version + type + packetId + sessionId)
#define MIN_ATTENDANCE_PKT_SIZE 12

// Full attendance packet size (our payload, excluding manufacturer ID)
#define FULL_ATTENDANCE_PKT_SIZE 42

// ─── Data Structures ────────────────────────────────────────────

struct CachedPacketId {
    uint32_t packetId;
    unsigned long seenAt;  // millis() timestamp
};

// ─── Global State ────────────────────────────────────────────────

BLEServer*      pServer      = nullptr;
BLEService*     pService     = nullptr;
BLEAdvertising* pAdvertising = nullptr;
BLEScan*        pBLEScan     = nullptr;

// Duplicate suppression cache
CachedPacketId packetCache[MAX_CACHED_PACKET_IDS];
int packetCacheCount = 0;

// Counters for diagnostics
uint32_t totalPacketsReceived   = 0;
uint32_t validPacketsReceived   = 0;
uint32_t duplicatePacketsCount  = 0;
uint32_t invalidPacketsCount    = 0;

// ─── Forward Declarations ────────────────────────────────────────

bool isPacketDuplicate(uint32_t packetId);
void cachePacketId(uint32_t packetId);
void cleanExpiredCache();
void processAttendancePacket(const uint8_t* data, size_t length, int rssi, BLEAddress addr);
void printPacketHex(const uint8_t* data, size_t length);
void blinkLed(uint8_t r, uint8_t g, uint8_t b, int times, int delayMs);
void printDiagnostics();

// ─── BLE Scan Callbacks ─────────────────────────────────────────

class GatewayScanCallbacks : public BLEAdvertisedDeviceCallbacks {
    void onResult(BLEAdvertisedDevice advertisedDevice) override {
        // Check if this advertisement has manufacturer-specific data
        if (!advertisedDevice.haveManufacturerData()) {
            return;
        }

        String mfgDataStr = advertisedDevice.getManufacturerData();
        size_t mfgLen = mfgDataStr.length();

        // Minimum check: MFG ID (2 bytes) + magic (2 bytes) + version (1) + type (1) = 6 bytes
        if (mfgLen < 6) {
            return;
        }

        const uint8_t* data = (const uint8_t*)mfgDataStr.c_str();

        // First 2 bytes are the manufacturer ID (little-endian, added by BLE stack)
        // Bytes 2,3 should be our magic bytes
        if (data[2] != ATTENDANCE_MAGIC_BYTE_0 || data[3] != ATTENDANCE_MAGIC_BYTE_1) {
            return;  // Not our packet
        }

        totalPacketsReceived++;

        // Pass the payload (after manufacturer ID) for processing
        processAttendancePacket(
            data + 2,              // Skip manufacturer ID (2 bytes)
            mfgLen - 2,            // Adjusted length
            advertisedDevice.getRSSI(),
            advertisedDevice.getAddress()
        );
    }
};

// ─── BLE Server Callbacks ────────────────────────────────────────

class GatewayServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        Serial.println("[CONN] Device connected");
        blinkLed(0, 20, 0, 2, 100);
        // Restart advertising so other devices can discover us
        BLEDevice::startAdvertising();
    }

    void onDisconnect(BLEServer* pServer) override {
        Serial.println("[CONN] Device disconnected");
        // Restart advertising after disconnect
        BLEDevice::startAdvertising();
    }
};

// ─── GATT Attendance Characteristic Callback ─────────────────────

class AttendanceCharCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) override {
        String value = pCharacteristic->getValue();
        size_t len = value.length();

        if (len < 6) {
            Serial.printf("[GATT] Received write too short: %d bytes\n", (int)len);
            return;
        }

        const uint8_t* data = (const uint8_t*)value.c_str();

        // Check magic bytes
        if (data[0] != ATTENDANCE_MAGIC_BYTE_0 || data[1] != ATTENDANCE_MAGIC_BYTE_1) {
            Serial.println("[GATT] Invalid magic bytes in write");
            invalidPacketsCount++;
            return;
        }

        totalPacketsReceived++;
        Serial.printf("[GATT] Received attendance write: %d bytes\n", (int)len);

        // Process using same pipeline as advertisement-based packets
        // Use a placeholder address for GATT writes
        BLEAddress gattAddr("00:00:00:00:00:00");
        processAttendancePacket(data, len, 0, gattAddr);
    }
};

// ─── Packet Processing ──────────────────────────────────────────

void processAttendancePacket(const uint8_t* data, size_t length, int rssi, BLEAddress addr) {
    // Validate magic bytes
    if (data[0] != ATTENDANCE_MAGIC_BYTE_0 || data[1] != ATTENDANCE_MAGIC_BYTE_1) {
        invalidPacketsCount++;
        return;
    }

    // Validate version
    uint8_t version = data[2];
    if (version != PROTOCOL_VERSION) {
        Serial.printf("[PKT] Warning: Unknown protocol version: %d (expected %d)\n",
                      version, PROTOCOL_VERSION);
        invalidPacketsCount++;
        return;
    }

    // Validate packet type
    uint8_t packetType = data[3];
    if (packetType != PKT_TYPE_ATTENDANCE) {
        Serial.printf("[PKT] Info: Non-attendance packet type: 0x%02X\n", packetType);
        return;
    }

    // Extract packet ID (bytes 4-7, little-endian)
    uint32_t packetId = 0;
    if (length >= 8) {
        packetId = (uint32_t)data[4]
                 | ((uint32_t)data[5] << 8)
                 | ((uint32_t)data[6] << 16)
                 | ((uint32_t)data[7] << 24);
    }

    // Duplicate check
    if (isPacketDuplicate(packetId)) {
        duplicatePacketsCount++;
        Serial.printf("[PKT] Duplicate packet ID: 0x%08X (suppressed)\n", packetId);
        return;
    }

    // Cache the packet ID
    cachePacketId(packetId);
    validPacketsReceived++;

    // ─── Log full packet details ───
    Serial.println();
    Serial.println("======================================================");
    Serial.println("         ATTENDANCE PACKET RECEIVED");
    Serial.println("======================================================");

    Serial.printf("  Source:      %s\n", addr.toString().c_str());
    if (rssi != 0) {
        Serial.printf("  RSSI:        %d dBm\n", rssi);
    }
    Serial.printf("  Version:     %d\n", version);
    Serial.printf("  Packet ID:   0x%08X\n", packetId);

    if (length >= MIN_ATTENDANCE_PKT_SIZE) {
        uint32_t sessionId = (uint32_t)data[8]
                           | ((uint32_t)data[9] << 8)
                           | ((uint32_t)data[10] << 16)
                           | ((uint32_t)data[11] << 24);
        Serial.printf("  Session ID:  0x%08X\n", sessionId);
    }

    if (length >= 16) {
        uint32_t timestamp = (uint32_t)data[12]
                           | ((uint32_t)data[13] << 8)
                           | ((uint32_t)data[14] << 16)
                           | ((uint32_t)data[15] << 24);
        Serial.printf("  Timestamp:   %u\n", timestamp);
    }

    if (length >= 17) {
        Serial.printf("  TTL:         %d\n", data[16]);
    }

    if (length >= 18) {
        Serial.printf("  Hop Count:   %d\n", data[17]);
    }

    if (length >= 34) {
        Serial.print("  Token:       ");
        for (int i = 18; i < 34; i++) {
            Serial.printf("%02X", data[i]);
        }
        Serial.println();
    }

    if (length >= FULL_ATTENDANCE_PKT_SIZE) {
        Serial.print("  Signature:   ");
        for (int i = 34; i < 42; i++) {
            Serial.printf("%02X", data[i]);
        }
        Serial.println();
    }

    Serial.printf("  Raw (%d bytes): ", (int)length);
    printPacketHex(data, length);
    Serial.println("------------------------------------------------------");

    // Visual feedback — green flash
    blinkLed(0, 20, 0, 3, 80);
}

// ─── Duplicate Suppression ───────────────────────────────────────

bool isPacketDuplicate(uint32_t packetId) {
    unsigned long now = millis();
    for (int i = 0; i < packetCacheCount; i++) {
        if (packetCache[i].packetId == packetId) {
            if ((now - packetCache[i].seenAt) < PACKET_CACHE_EXPIRY_MS) {
                return true;
            }
        }
    }
    return false;
}

void cachePacketId(uint32_t packetId) {
    cleanExpiredCache();

    if (packetCacheCount < MAX_CACHED_PACKET_IDS) {
        packetCache[packetCacheCount].packetId = packetId;
        packetCache[packetCacheCount].seenAt = millis();
        packetCacheCount++;
    } else {
        // Overwrite oldest entry
        int oldestIdx = 0;
        unsigned long oldestTime = packetCache[0].seenAt;
        for (int i = 1; i < MAX_CACHED_PACKET_IDS; i++) {
            if (packetCache[i].seenAt < oldestTime) {
                oldestTime = packetCache[i].seenAt;
                oldestIdx = i;
            }
        }
        packetCache[oldestIdx].packetId = packetId;
        packetCache[oldestIdx].seenAt = millis();
    }
}

void cleanExpiredCache() {
    unsigned long now = millis();
    int writeIdx = 0;
    for (int readIdx = 0; readIdx < packetCacheCount; readIdx++) {
        if ((now - packetCache[readIdx].seenAt) < PACKET_CACHE_EXPIRY_MS) {
            if (writeIdx != readIdx) {
                packetCache[writeIdx] = packetCache[readIdx];
            }
            writeIdx++;
        }
    }
    packetCacheCount = writeIdx;
}

// ─── Utility Functions ──────────────────────────────────────────

void printPacketHex(const uint8_t* data, size_t length) {
    for (size_t i = 0; i < length; i++) {
        Serial.printf("%02X ", data[i]);
    }
    Serial.println();
}

void blinkLed(uint8_t r, uint8_t g, uint8_t b, int times, int delayMs) {
    for (int i = 0; i < times; i++) {
        neopixelWrite(STATUS_LED_PIN, r, g, b);
        delay(delayMs);
        neopixelWrite(STATUS_LED_PIN, 0, 0, 0);
        delay(delayMs);
    }
}

void printDiagnostics() {
    Serial.println();
    Serial.println("+---------------- GATEWAY DIAGNOSTICS ----------------+");
    Serial.printf("| Uptime:           %lu seconds\n", millis() / 1000);
    Serial.printf("| Total received:   %u packets\n", totalPacketsReceived);
    Serial.printf("| Valid:            %u packets\n", validPacketsReceived);
    Serial.printf("| Duplicates:       %u packets\n", duplicatePacketsCount);
    Serial.printf("| Invalid:          %u packets\n", invalidPacketsCount);
    Serial.printf("| Cache entries:    %d / %d\n", packetCacheCount, MAX_CACHED_PACKET_IDS);
    Serial.printf("| Free heap:        %u bytes\n", ESP.getFreeHeap());
    Serial.printf("| Free PSRAM:       %u bytes\n", ESP.getFreePsram());
    Serial.println("+-----------------------------------------------------+");
    Serial.println();
}

// ─── Scan Complete Callback ──────────────────────────────────────

void scanCompleteCB(BLEScanResults results) {
    Serial.printf("[SCAN] Cycle complete — %d devices seen\n", results.getCount());
}

// ─── Setup ───────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(1000);  // Wait for serial monitor to attach

    Serial.println();
    Serial.println("=======================================================");
    Serial.println("  BLE Mesh Attendance — Classroom Gateway");
    Serial.println("  Phase 1: BLE Advertisement + Scan");
    Serial.println("  Board: ESP32-S3-N16R8");
    Serial.println("  Framework: Arduino Core 3.3.x");
    Serial.println("=======================================================");
    Serial.println();

    // Initialize LED — blue = initializing
    neopixelWrite(STATUS_LED_PIN, 0, 0, 20);
    delay(500);

    // ─── Initialize BLE ───
    Serial.println("[INIT] Initializing BLE...");
    BLEDevice::init(GATEWAY_DEVICE_NAME);

    // Set transmit power to maximum for better range in classroom
    BLEDevice::setPower(ESP_PWR_LVL_P9);

    Serial.printf("[INIT] Device address: %s\n",
                  BLEDevice::getAddress().toString().c_str());

    // ─── Create BLE Server ───
    Serial.println("[INIT] Creating BLE server...");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new GatewayServerCallbacks());

    // Create our gateway service
    pService = pServer->createService(GATEWAY_SERVICE_UUID);

    // Status characteristic — readable by phones to confirm gateway is active
    BLECharacteristic* pStatusChar = pService->createCharacteristic(
        GATEWAY_STATUS_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ
    );
    pStatusChar->setValue("GATEWAY_ACTIVE_v1");

    // Attendance characteristic — writable by phones to submit attendance via GATT
    BLECharacteristic* pAttendanceChar = pService->createCharacteristic(
        GATEWAY_ATTENDANCE_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pAttendanceChar->setCallbacks(new AttendanceCharCallbacks());

    pService->start();

    // ─── Configure Advertising ───
    Serial.println("[INIT] Configuring BLE advertising...");
    pAdvertising = BLEDevice::getAdvertising();

    // Add our gateway service UUID so phones can discover us
    pAdvertising->addServiceUUID(GATEWAY_SERVICE_UUID);

    // Configure advertising parameters
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // Connection interval hints
    pAdvertising->setMaxPreferred(0x12);

    // Start advertising
    BLEDevice::startAdvertising();
    Serial.println("[INIT] > Gateway is now advertising");
    Serial.printf("[INIT] > Service UUID: %s\n", GATEWAY_SERVICE_UUID);

    // ─── Configure BLE Scanning ───
    Serial.println("[INIT] Configuring BLE scanner...");
    pBLEScan = BLEDevice::getScan();
    pBLEScan->setAdvertisedDeviceCallbacks(new GatewayScanCallbacks(), true);  // true = wantDuplicates
    pBLEScan->setActiveScan(true);     // Active scan gets scan responses
    pBLEScan->setInterval(100);        // Scan interval (in 0.625ms units = 62.5ms)
    pBLEScan->setWindow(99);           // Scan window (in 0.625ms units) — near-continuous

    Serial.println("[INIT] > Scanner configured");

    // Initialization complete — green flash
    neopixelWrite(STATUS_LED_PIN, 0, 20, 0);
    delay(500);
    neopixelWrite(STATUS_LED_PIN, 0, 0, 0);

    Serial.println();
    Serial.println("=======================================================");
    Serial.println("  GATEWAY READY — Scanning for attendance packets...");
    Serial.println("  Serial commands: d=diagnostics r=reset s=scan h=help");
    Serial.println("=======================================================");
    Serial.println();

    // Start first scan cycle (non-blocking with callback)
    pBLEScan->start(SCAN_DURATION_SECS, scanCompleteCB, false);
}

// ─── Main Loop ───────────────────────────────────────────────────

unsigned long lastDiagnosticTime = 0;
unsigned long lastScanRestart   = 0;
const unsigned long DIAGNOSTIC_INTERVAL_MS = 30000;  // Print diagnostics every 30s
const unsigned long SCAN_RESTART_MS        = 6000;    // Restart scan every 6s

void loop() {
    unsigned long now = millis();

    // ─── Restart scanning if needed ───
    if (!pBLEScan->isScanning() && (now - lastScanRestart > SCAN_RESTART_MS)) {
        pBLEScan->clearResults();  // Free memory from previous scan
        pBLEScan->start(SCAN_DURATION_SECS, scanCompleteCB, false);
        lastScanRestart = now;
    }

    // ─── Periodic diagnostics ───
    if (now - lastDiagnosticTime > DIAGNOSTIC_INTERVAL_MS) {
        printDiagnostics();
        cleanExpiredCache();
        lastDiagnosticTime = now;

        // Heartbeat LED blink (blue)
        neopixelWrite(STATUS_LED_PIN, 0, 0, 10);
        delay(100);
        neopixelWrite(STATUS_LED_PIN, 0, 0, 0);
    }

    // ─── Handle serial commands ───
    if (Serial.available()) {
        char cmd = Serial.read();
        switch (cmd) {
            case 'd':
            case 'D':
                printDiagnostics();
                break;
            case 'r':
            case 'R':
                Serial.println("[CMD] Resetting counters...");
                totalPacketsReceived = 0;
                validPacketsReceived = 0;
                duplicatePacketsCount = 0;
                invalidPacketsCount = 0;
                packetCacheCount = 0;
                break;
            case 's':
            case 'S':
                Serial.println("[CMD] Restarting scan...");
                pBLEScan->stop();
                delay(100);
                pBLEScan->clearResults();
                pBLEScan->start(SCAN_DURATION_SECS, scanCompleteCB, false);
                break;
            case 'h':
            case 'H':
            case '?':
                Serial.println();
                Serial.println("--- Gateway Commands ---");
                Serial.println("  d — Print diagnostics");
                Serial.println("  r — Reset counters");
                Serial.println("  s — Restart BLE scan");
                Serial.println("  h — Show this help");
                Serial.println("------------------------");
                break;
        }
    }

    delay(10);  // Small yield
}
