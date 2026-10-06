/**
 * ═══════════════════════════════════════════════════════════════════
 *  BLE Mesh Attendance — ESP32-S3 Classroom Gateway (Arduino)
 *  Phase 1 + Phase 4: BLE Advertisement + Scan + Relay + TFT
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
 *   6. [Phase 4] Accepts JSON relay test packets over GATT.
 *   7. [Phase 4] Sends ACK notifications back to connected clients.
 *   8. [Phase 4] Displays gateway status on TFT (if connected).
 *
 *  Phase 1 scope:
 *   - Direct phone → ESP32 BLE communication (no mesh relay yet)
 *   - Serial output only (no Wi-Fi backend yet)
 *   - Duplicate suppression via in-memory packet ID cache
 *
 *  Phase 4 additions:
 *   - JSON test relay packet support (detected by first byte '{')
 *   - ACK characteristic (NOTIFY) for relay acknowledgement
 *   - TFT status display (ST7735/ST7789, 128x160)
 *   - Connected client tracking
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
#include <BLE2902.h>

// ─── TFT Display (optional — compile with TFT_ENABLED) ─────────
// Set to 1 if you have a TFT connected (requires Adafruit GFX + ST7735 libraries), 0 to disable
#define TFT_ENABLED 0

#if TFT_ENABLED
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>
#include <SPI.h>

// ═══════════════════════════════════════════════════════════════
//  TFT PIN CONFIGURATION — VERIFY YOUR WIRING!
// ═══════════════════════════════════════════════════════════════
//
//  These pins are common defaults for ESP32-S3 boards with SPI TFT.
//  If your display does not work, check your board's pinout diagram
//  and update these values accordingly.
//
//  Display: 1.8" TFT SPI, 128x160, V1.1
//  Likely controller: ST7735 (could also be ST7789 for some modules)
//
#define TFT_CS    10   // Chip Select
#define TFT_DC     8   // Data/Command (A0/RS)
#define TFT_RST    9   // Reset (-1 if connected to ESP32 RST)
#define TFT_MOSI  11   // SPI MOSI (DIN/SDA)
#define TFT_SCLK  12   // SPI Clock (SCK/SCL)
// Backlight: Usually connected to VCC (always on) or a GPIO for dimming

Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
#endif

// ─── Wi-Fi & Supabase Realtime Gateway Sync (Step 2) ─────────────
// Set to 1 to enable Wi-Fi sync with Supabase backend; 0 for offline BLE-only mode
#define WIFI_ENABLED 0

#if WIFI_ENABLED
#include <WiFi.h>
#include <HTTPClient.h>

const char* WIFI_SSID       = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD   = "YOUR_WIFI_PASSWORD";
const char* SUPABASE_URL    = "https://hiqmayrqlqgvxqsaxdkm.supabase.co";
const char* SUPABASE_KEY    = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhpcW1heXJxbHFndnhxc2F4ZGttIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyMTM2OTMsImV4cCI6MjEwNjc4OTY5M30.bq3IEkjLRbCStJybuyGv9KMVbtvUY3tglOlIXyWyumw";
const char* GATEWAY_DB_ID   = "ESP32_GATEWAY_405";
#endif

// ─── Configuration ───────────────────────────────────────────────

// Custom 128-bit service UUID for the BLE Mesh Attendance Gateway
// Student phones will scan for this UUID to discover the gateway
#define GATEWAY_SERVICE_UUID        "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
#define GATEWAY_STATUS_CHAR_UUID    "a1b2c3d4-e5f6-7890-abcd-ef1234567891"
#define GATEWAY_ATTENDANCE_CHAR_UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567892"

// Phase 4: ACK characteristic — gateway sends ACK notifications here
#define GATEWAY_ACK_CHAR_UUID       "a1b2c3d4-e5f6-7890-abcd-ef1234567896"

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
// PHASE 1 — Manufacturer-specific data layout (inside BLE advertisement):
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
// PHASE 4 — JSON test relay packets (over GATT write):
//
// Detected by first byte being '{' (0x7B).
// Format: {"v":1,"t":"TEST_RELAY","pid":"...","oid":"...","sp":"...","p":"...","ttl":N,"hc":N}
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
    char packetId[16];     // String-based ID (supports both binary hex and Phase 4 IDs)
    unsigned long seenAt;  // millis() timestamp
};

// ─── Global State ────────────────────────────────────────────────

BLEServer*      pServer      = nullptr;
BLEService*     pService     = nullptr;
BLEAdvertising* pAdvertising = nullptr;
BLEScan*        pBLEScan     = nullptr;

// Phase 4: ACK characteristic for notifications
BLECharacteristic* pAckChar    = nullptr;
// Status characteristic — updated with connected client count
BLECharacteristic* pStatusChar = nullptr;

// Duplicate suppression cache
CachedPacketId packetCache[MAX_CACHED_PACKET_IDS];
int packetCacheCount = 0;

// Counters for diagnostics
uint32_t totalPacketsReceived   = 0;
uint32_t validPacketsReceived   = 0;
uint32_t duplicatePacketsCount  = 0;
uint32_t invalidPacketsCount    = 0;
uint32_t phase4PacketsReceived  = 0;
uint32_t acksGenerated          = 0;

// Connection tracking
int connectedClients = 0;

// Display settings
bool showUnnamedDevices         = true;  // Toggle with 'u' in serial monitor

// Phase 4: Last received packet info (for TFT display)
char lastOriginId[16] = "";
char lastPlatform[12] = "";
char lastPayload[32]  = "";
char lastPacketId[16] = "";
int  lastHopCount     = 0;
int  lastTtl          = 0;

// TFT display state
enum GatewayState {
    STATE_BOOTING,
    STATE_BLE_READY,
    STATE_BLE_CONNECTED,
    STATE_RECEIVING,
    STATE_PROCESSING,
    STATE_ACK_SENT,
    STATE_ERROR
};
GatewayState currentState = STATE_BOOTING;

// ─── Classroom Lecture Attendance Roster ──────────────────────────

struct AttendeeRecord {
    char name[32];
    char studentId[24];
    char mac[20];
    char originId[16];
    char platform[12];
    unsigned long timestamp;
    int hopCount;
};

#define MAX_ATTENDEES 100
AttendeeRecord lectureRoster[MAX_ATTENDEES];
int lectureAttendeeCount = 0;

// ─── Forward Declarations ────────────────────────────────────────

bool isPacketIdDuplicate(const char* packetId);
void cachePacketIdStr(const char* packetId);
bool isPacketDuplicate(uint32_t packetId);
void cachePacketId(uint32_t packetId);
void cleanExpiredCache();
void processAttendancePacket(const uint8_t* data, size_t length, int rssi, BLEAddress addr);
void processPhase4Packet(const uint8_t* data, size_t length);
void sendAck(const char* packetId, const char* status, int count = 0, bool syncedOnline = false);
bool syncAttendanceWithSupabase(const char* sessionId, const char* studentId, const char* studentName, const char* mac, int hopCount);
void printAttendanceRoster();
void updateGatewayStatusChar();
void printPacketHex(const uint8_t* data, size_t length);
void blinkLed(uint8_t r, uint8_t g, uint8_t b, int times, int delayMs);
void printDiagnostics();
void updateTftDisplay();
void tftShowState(GatewayState state);

// ─── Simple JSON Parser Helpers ─────────────────────────────────
// Minimal parser for our known-format Phase 4 JSON packets.
// Avoids pulling in a full JSON library (ArduinoJson) for this test protocol.

bool jsonExtractString(const char* json, const char* key, char* out, size_t outLen) {
    char searchKey[32];
    snprintf(searchKey, sizeof(searchKey), "\"%s\":\"", key);
    const char* start = strstr(json, searchKey);
    if (!start) {
        // Try with space after colon
        snprintf(searchKey, sizeof(searchKey), "\"%s\": \"", key);
        start = strstr(json, searchKey);
    }
    if (!start) return false;

    start = strchr(start, ':');
    if (!start) return false;
    start++; // skip ':'
    while (*start == ' ') start++; // skip spaces
    if (*start != '"') return false;
    start++; // skip opening quote

    const char* end = strchr(start, '"');
    if (!end) return false;

    size_t len = end - start;
    if (len >= outLen) len = outLen - 1;
    strncpy(out, start, len);
    out[len] = '\0';
    return true;
}

int jsonExtractInt(const char* json, const char* key, int defaultVal) {
    char searchKey[32];
    snprintf(searchKey, sizeof(searchKey), "\"%s\":", key);
    const char* start = strstr(json, searchKey);
    if (!start) return defaultVal;

    start = strchr(start, ':');
    if (!start) return defaultVal;
    start++; // skip ':'
    while (*start == ' ') start++; // skip spaces

    return atoi(start);
}

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

void updateGatewayStatusChar() {
    if (pStatusChar != nullptr) {
        char statusJson[96];
        snprintf(statusJson, sizeof(statusJson),
            "{\"clients\":%d,\"attendees\":%d,\"uptime\":%lu}",
            connectedClients, lectureAttendeeCount, millis() / 1000);
        pStatusChar->setValue(statusJson);
        pStatusChar->notify();
    }
}

class GatewayServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        connectedClients++;
        Serial.printf("[BLE] Connected (clients: %d)\n", connectedClients);
        blinkLed(0, 20, 0, 2, 100);
        currentState = STATE_BLE_CONNECTED;
        updateGatewayStatusChar();
        updateTftDisplay();
        // Restart advertising so other devices can discover us
        BLEDevice::startAdvertising();
    }

    void onDisconnect(BLEServer* pServer) override {
        connectedClients--;
        if (connectedClients < 0) connectedClients = 0;
        Serial.printf("[BLE] Disconnected (clients: %d)\n", connectedClients);
        currentState = (connectedClients > 0) ? STATE_BLE_CONNECTED : STATE_BLE_READY;
        updateGatewayStatusChar();
        updateTftDisplay();
        // Restart advertising after disconnect
        BLEDevice::startAdvertising();
    }
};

// ─── GATT Attendance Characteristic Callback ─────────────────────

class AttendanceCharCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) override {
        String value = pCharacteristic->getValue();
        size_t len = value.length();

        if (len < 2) {
            Serial.printf("[GATT] Received write too short: %d bytes\n", (int)len);
            return;
        }

        const uint8_t* data = (const uint8_t*)value.c_str();

        // Skip any leading whitespace if present
        size_t startIdx = 0;
        while (startIdx < len && (data[startIdx] == ' ' || data[startIdx] == '\t' || data[startIdx] == '\r' || data[startIdx] == '\n')) {
            startIdx++;
        }

        // Phase 4: Detect JSON packets (first non-whitespace byte is '{' / 0x7B)
        if (startIdx < len && data[startIdx] == 0x7B) {  // '{'
            Serial.printf("[GATT] Received Phase 4 JSON packet: %d bytes\n", (int)(len - startIdx));
            processPhase4Packet(data + startIdx, len - startIdx);
            return;
        }

        // Phase 1: Binary attendance packet
        if (len < 6) {
            Serial.printf("[GATT] Received binary write too short: %d bytes (first byte: 0x%02X)\n", (int)len, data[0]);
            return;
        }

        // Check magic bytes
        if (data[0] != ATTENDANCE_MAGIC_BYTE_0 || data[1] != ATTENDANCE_MAGIC_BYTE_1) {
            Serial.printf("[GATT] Invalid magic bytes in write: 0x%02X 0x%02X (expected 0x%02X 0x%02X, len=%d)\n",
                          data[0], data[1], ATTENDANCE_MAGIC_BYTE_0, ATTENDANCE_MAGIC_BYTE_1, (int)len);
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

// ─── Supabase Gateway Sync Implementation ──────────────────────────

bool syncAttendanceWithSupabase(const char* sessionId, const char* studentId, const char* studentName, const char* mac, int hopCount) {
#if WIFI_ENABLED
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("  [WiFi] Offline. Attendance cached locally in gateway roster.");
        return false;
    }

    if (strlen(sessionId) == 0 || strlen(studentId) == 0) {
        Serial.println("  [Supabase] Skip sync: missing sessionId or studentId");
        return false;
    }

    HTTPClient http;
    char endpoint[256];
    snprintf(endpoint, sizeof(endpoint), "%s/rest/v1/attendance_records", SUPABASE_URL);

    http.begin(endpoint);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("apikey", SUPABASE_KEY);
    http.addHeader("Authorization", String("Bearer ") + SUPABASE_KEY);
    http.addHeader("Prefer", "resolution=merge-duplicates,return=minimal");

    char postBody[384];
    snprintf(postBody, sizeof(postBody),
        "{\"session_id\":\"%s\",\"student_id\":\"%s\",\"status\":\"PRESENT\","
        "\"gateway_id\":\"%s\",\"verification_method\":\"BLE_GATEWAY\","
        "\"gateway_verified\":true,\"mac_address\":\"%s\",\"hop_count\":%d}",
        sessionId, studentId, GATEWAY_DB_ID, mac, hopCount);

    int httpCode = http.POST(postBody);
    bool success = (httpCode >= 200 && httpCode < 300);

    if (success) {
        Serial.printf("  [Supabase] Synced online! (HTTP %d)\n", httpCode);
    } else {
        Serial.printf("  [Supabase] Sync returned HTTP %d: %s\n", httpCode, http.getString().c_str());
    }

    http.end();
    return success;
#else
    (void)sessionId;
    (void)studentId;
    (void)studentName;
    (void)mac;
    (void)hopCount;
    return false;
#endif
}

// ─── Phase 4 JSON Packet Processing ─────────────────────────────

void processPhase4Packet(const uint8_t* data, size_t length) {
    totalPacketsReceived++;
    phase4PacketsReceived++;

    currentState = STATE_RECEIVING;
    updateTftDisplay();

    // Null-terminate the JSON string for parsing (512 bytes buffer for session and nonce)
    char jsonBuf[512];
    size_t copyLen = (length < sizeof(jsonBuf) - 1) ? length : sizeof(jsonBuf) - 1;
    memcpy(jsonBuf, data, copyLen);
    jsonBuf[copyLen] = '\0';

    // Extract fields
    char packetType[16]   = "";
    char packetId[16]     = "";
    char originId[16]     = "";
    char platform[12]     = "";
    char payload[64]      = "";
    char studentName[32]  = "";
    char studentId[40]    = "";
    char deviceMac[20]    = "";
    char sessionId[40]    = "";
    char sessionNonce[40] = "";

    int version  = jsonExtractInt(jsonBuf, "v", -1);
    jsonExtractString(jsonBuf, "t", packetType, sizeof(packetType));
    jsonExtractString(jsonBuf, "pid", packetId, sizeof(packetId));
    jsonExtractString(jsonBuf, "oid", originId, sizeof(originId));
    jsonExtractString(jsonBuf, "sp", platform, sizeof(platform));
    jsonExtractString(jsonBuf, "p", payload, sizeof(payload));
    jsonExtractString(jsonBuf, "sname", studentName, sizeof(studentName));
    jsonExtractString(jsonBuf, "sid", studentId, sizeof(studentId));
    jsonExtractString(jsonBuf, "mac", deviceMac, sizeof(deviceMac));
    jsonExtractString(jsonBuf, "sess", sessionId, sizeof(sessionId));
    jsonExtractString(jsonBuf, "nonce", sessionNonce, sizeof(sessionNonce));
    int ttl      = jsonExtractInt(jsonBuf, "ttl", -1);
    int hopCount = jsonExtractInt(jsonBuf, "hc", -1);

    // Validate required fields
    if (version != 1) {
        Serial.printf("[RX] Invalid version: %d\n", version);
        invalidPacketsCount++;
        sendAck(packetId, "INVALID", lectureAttendeeCount);
        return;
    }

    bool isAttendance = (strcmp(packetType, "ATTENDANCE") == 0);
    bool isTestRelay  = (strcmp(packetType, "TEST_RELAY") == 0);

    if (!isAttendance && !isTestRelay) {
        Serial.printf("[RX] Unknown packet type: %s\n", packetType);
        invalidPacketsCount++;
        sendAck(packetId, "INVALID", lectureAttendeeCount);
        return;
    }

    if (strlen(packetId) == 0) {
        Serial.println("[RX] Missing packet ID");
        invalidPacketsCount++;
        sendAck("", "INVALID", lectureAttendeeCount);
        return;
    }

    // Duplicate packet check (packet ID level)
    if (isPacketIdDuplicate(packetId)) {
        duplicatePacketsCount++;
        Serial.printf("[RX] DUPLICATE packet: %s (suppressed)\n", packetId);
        sendAck(packetId, "DUPLICATE", lectureAttendeeCount);
        return;
    }

    // Cache the packet ID
    cachePacketIdStr(packetId);

    // TTL check
    if (ttl <= 0) {
        Serial.printf("[RX] TTL expired for packet: %s\n", packetId);
        sendAck(packetId, "REJECTED", lectureAttendeeCount);
        return;
    }

    // Populate defaults for name, ID, and MAC if not explicitly set
    if (strlen(studentName) == 0 && strlen(payload) > 0) {
        strncpy(studentName, payload, sizeof(studentName) - 1);
    } else if (strlen(studentName) == 0) {
        snprintf(studentName, sizeof(studentName), "Student (%s)", originId);
    }

    if (strlen(studentId) == 0) {
        snprintf(studentId, sizeof(studentId), "STU-%s", originId);
    }

    if (strlen(deviceMac) == 0) {
        strncpy(deviceMac, originId, sizeof(deviceMac) - 1);
    }

    // Check if this student is already in the lecture roster (by MAC or Student ID)
    int existingIdx = -1;
    for (int i = 0; i < lectureAttendeeCount; i++) {
        if ((strlen(deviceMac) > 0 && strcmp(lectureRoster[i].mac, deviceMac) == 0) ||
            (strlen(studentId) > 0 && strcmp(lectureRoster[i].studentId, studentId) == 0)) {
            existingIdx = i;
            break;
        }
    }

    bool isNewAttendee = (existingIdx == -1);
    if (isNewAttendee) {
        if (lectureAttendeeCount < MAX_ATTENDEES) {
            strncpy(lectureRoster[lectureAttendeeCount].name, studentName, sizeof(lectureRoster[lectureAttendeeCount].name) - 1);
            strncpy(lectureRoster[lectureAttendeeCount].studentId, studentId, sizeof(lectureRoster[lectureAttendeeCount].studentId) - 1);
            strncpy(lectureRoster[lectureAttendeeCount].mac, deviceMac, sizeof(lectureRoster[lectureAttendeeCount].mac) - 1);
            strncpy(lectureRoster[lectureAttendeeCount].originId, originId, sizeof(lectureRoster[lectureAttendeeCount].originId) - 1);
            strncpy(lectureRoster[lectureAttendeeCount].platform, platform, sizeof(lectureRoster[lectureAttendeeCount].platform) - 1);
            lectureRoster[lectureAttendeeCount].timestamp = millis() / 1000;
            lectureRoster[lectureAttendeeCount].hopCount = hopCount;
            lectureAttendeeCount++;
        }
    } else {
        // Update hop count if shorter path
        if (hopCount < lectureRoster[existingIdx].hopCount) {
            lectureRoster[existingIdx].hopCount = hopCount;
        }
    }

    // Valid packet — process it
    validPacketsReceived++;
    currentState = STATE_PROCESSING;
    updateTftDisplay();

    // Update last packet info for TFT display
    strncpy(lastOriginId, originId, sizeof(lastOriginId) - 1);
    strncpy(lastPlatform, platform, sizeof(lastPlatform) - 1);
    strncpy(lastPayload, studentName, sizeof(lastPayload) - 1);
    strncpy(lastPacketId, packetId, sizeof(lastPacketId) - 1);
    lastHopCount = hopCount;
    lastTtl = ttl;

    // Log to Serial with clear student banner
    Serial.println();
    Serial.println("╔══════════════════════════════════════════════════════════════════════════════════════╗");
    if (isAttendance) {
        Serial.printf ("║                    ★ ATTENDANCE RECORDED FOR STUDENT ★                               ║\n");
    } else {
        Serial.printf ("║                    PHASE 4 — TEST RELAY PACKET RECEIVED                              ║\n");
    }
    Serial.println("╠═════════════════╦════════════════════════════════════════════════════════════════════╣");
    Serial.printf ("║ Student Name    ║ %-66.66s ║\n", studentName);
    Serial.printf ("║ Student Roll ID ║ %-66.66s ║\n", studentId);
    Serial.printf ("║ Device MAC      ║ %-66.66s ║\n", deviceMac);
    Serial.printf ("║ Origin Device   ║ %-16.16s (platform: %-8.8s)                             ║\n", originId, platform);
    Serial.printf ("║ Network Path    ║ %-12.12s (hopCount: %d, ttl: %d)                                ║\n",
                   (hopCount == 0) ? "Direct BLE" : "Mesh Relayed", hopCount, ttl);
    Serial.printf ("║ Status          ║ %-66.66s ║\n",
                   isNewAttendee ? "VERIFIED & ADDED TO LECTURE ROSTER" : "CONFIRMED (ALREADY IN ROSTER)");
    Serial.printf ("║ Total Attendees ║ %2d attendee(s) currently marked present in this lecture           ║\n", lectureAttendeeCount);
    Serial.println("╚═════════════════╩════════════════════════════════════════════════════════════════════╝");

    // Print current full classroom roster
    printAttendanceRoster();

    // Check and trigger online Supabase sync if Wi-Fi enabled and session is present
    bool syncedOnline = false;
    if (isAttendance && strlen(sessionId) > 0) {
        syncedOnline = syncAttendanceWithSupabase(sessionId, studentId, studentName, deviceMac, hopCount);
    }

    // Send ACK back to the client
    const char* ackStatus = isNewAttendee 
        ? (syncedOnline ? "VERIFIED_ONLINE" : "RECORDED") 
        : "ALREADY_RECORDED";
    sendAck(packetId, ackStatus, lectureAttendeeCount, syncedOnline);
    acksGenerated++;

    // Update status characteristic so other clients receive updated count
    updateGatewayStatusChar();

    currentState = STATE_ACK_SENT;
    updateTftDisplay();

    // Visual feedback — cyan flash for packets
    blinkLed(0, 15, 20, 3, 80);

    // After short delay, return to connected/ready state
    delay(400);
    currentState = (connectedClients > 0) ? STATE_BLE_CONNECTED : STATE_BLE_READY;
    updateTftDisplay();
}

// ─── Print Attendance Roster Table ───────────────────────────────

void printAttendanceRoster() {
    Serial.println();
    Serial.println("═══════════════════════════ LECTURE ATTENDANCE ROSTER ═══════════════════════════════");
    Serial.printf ("  Session Gateway: %s  |  Total Attendees Present: %d\n", GATEWAY_DEVICE_NAME, lectureAttendeeCount);
    Serial.println("  +----+------------------------+----------------+-------------------+------+-----------+");
    Serial.println("  | #  | Student Name           | Student ID     | MAC Address       | Hops | Path      |");
    Serial.println("  +----+------------------------+----------------+-------------------+------+-----------+");

    if (lectureAttendeeCount == 0) {
        Serial.println("  |    | (No students marked present yet for this lecture session)                     |");
    } else {
        for (int i = 0; i < lectureAttendeeCount; i++) {
            const char* pathStr = (lectureRoster[i].hopCount == 0) ? "Direct" : "Relayed";
            Serial.printf("  | %02d | %-22.22s | %-14.14s | %-17.17s | %4d | %-9.9s |\n",
                          i + 1,
                          lectureRoster[i].name,
                          lectureRoster[i].studentId,
                          lectureRoster[i].mac,
                          lectureRoster[i].hopCount,
                          pathStr);
        }
    }
    Serial.println("  +----+------------------------+----------------+-------------------+------+-----------+");
    Serial.println("  [Tip] Type 'a' + Enter to view roster anytime. Type 'c' + Enter to clear roster.");
    Serial.println();
}

// ─── ACK Generation ─────────────────────────────────────────────

void sendAck(const char* packetId, const char* status, int count, bool syncedOnline) {
    // Build ACK JSON with attendee count and online sync status
    char ackJson[192];
    snprintf(ackJson, sizeof(ackJson),
        "{\"v\":1,\"t\":\"ACK\",\"pid\":\"%s\",\"gid\":\"%s\",\"s\":\"%s\",\"count\":%d,\"sync\":%s}",
        packetId, GATEWAY_DEVICE_NAME, status, count, syncedOnline ? "true" : "false");

    Serial.printf("  [ACK] %s → %s (attendees: %d, sync: %s)\n",
                  packetId, status, count, syncedOnline ? "ONLINE" : "LOCAL");

    // Send via NOTIFY if clients are subscribed
    if (pAckChar != nullptr && connectedClients > 0) {
        pAckChar->setValue(ackJson);
        pAckChar->notify();
    }
}

// ─── Phase 1 Packet Processing (unchanged) ──────────────────────

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

    // Update TFT for Phase 1 packets too
    snprintf(lastPacketId, sizeof(lastPacketId), "%08X", packetId);
    strncpy(lastOriginId, addr.toString().c_str(), sizeof(lastOriginId) - 1);
    strncpy(lastPlatform, "binary", sizeof(lastPlatform) - 1);
    strncpy(lastPayload, "(P1 binary)", sizeof(lastPayload) - 1);
    lastHopCount = (length >= 18) ? data[17] : 0;
    lastTtl = (length >= 17) ? data[16] : 0;
    currentState = STATE_PROCESSING;
    updateTftDisplay();
    delay(300);
    currentState = (connectedClients > 0) ? STATE_BLE_CONNECTED : STATE_BLE_READY;
    updateTftDisplay();
}

// ─── Duplicate Suppression ───────────────────────────────────────

// String-based duplicate check (Phase 4)
bool isPacketIdDuplicate(const char* packetId) {
    unsigned long now = millis();
    for (int i = 0; i < packetCacheCount; i++) {
        if (strcmp(packetCache[i].packetId, packetId) == 0) {
            if ((now - packetCache[i].seenAt) < PACKET_CACHE_EXPIRY_MS) {
                return true;
            }
        }
    }
    return false;
}

void cachePacketIdStr(const char* packetId) {
    cleanExpiredCache();

    if (packetCacheCount < MAX_CACHED_PACKET_IDS) {
        strncpy(packetCache[packetCacheCount].packetId, packetId, 15);
        packetCache[packetCacheCount].packetId[15] = '\0';
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
        strncpy(packetCache[oldestIdx].packetId, packetId, 15);
        packetCache[oldestIdx].packetId[15] = '\0';
        packetCache[oldestIdx].seenAt = millis();
    }
}

// Binary duplicate check (Phase 1 backward compatibility)
bool isPacketDuplicate(uint32_t packetId) {
    char idStr[16];
    snprintf(idStr, sizeof(idStr), "%08X", packetId);
    return isPacketIdDuplicate(idStr);
}

void cachePacketId(uint32_t packetId) {
    char idStr[16];
    snprintf(idStr, sizeof(idStr), "%08X", packetId);
    cachePacketIdStr(idStr);
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
    Serial.printf("| Phase 4 (JSON):   %u packets\n", phase4PacketsReceived);
    Serial.printf("| Duplicates:       %u packets\n", duplicatePacketsCount);
    Serial.printf("| Invalid:          %u packets\n", invalidPacketsCount);
    Serial.printf("| ACKs sent:        %u\n", acksGenerated);
    Serial.printf("| Connected clients: %d\n", connectedClients);
    Serial.printf("| Cache entries:    %d / %d\n", packetCacheCount, MAX_CACHED_PACKET_IDS);
    Serial.printf("| Free heap:        %u bytes\n", ESP.getFreeHeap());
    Serial.printf("| Free PSRAM:       %u bytes\n", ESP.getFreePsram());
    Serial.println("+-----------------------------------------------------+");
    Serial.println();
}

// ─── TFT Display Functions ──────────────────────────────────────

#if TFT_ENABLED
void tftInit() {
    // Try ST7735S initialization (most common for 1.8" 128x160 modules)
    tft.initR(INITR_BLACKTAB);
    tft.setRotation(0);  // Portrait
    tft.fillScreen(ST77XX_BLACK);
    tft.setTextWrap(true);
}

void tftClear() {
    tft.fillScreen(ST77XX_BLACK);
    tft.setCursor(0, 0);
}

void tftHeader() {
    tft.setTextSize(1);
    tft.setTextColor(ST77XX_CYAN);
    tft.println("BLE GATEWAY");
    tft.setTextColor(ST77XX_WHITE);
    tft.println("----------------");
}
#endif

void tftShowState(GatewayState state) {
#if TFT_ENABLED
    tftClear();
    tftHeader();

    tft.setTextSize(1);

    switch (state) {
        case STATE_BOOTING:
            tft.setTextColor(ST77XX_YELLOW);
            tft.println("STATUS: BOOTING");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.println("Initializing...");
            break;

        case STATE_BLE_READY:
            tft.setTextColor(ST77XX_GREEN);
            tft.println("STATUS: READY");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.println("BLE: ADVERTISING");
            tft.printf("CLIENTS: %d\n", connectedClients);
            tft.println();
            tft.printf("RX: %u\n", totalPacketsReceived);
            tft.printf("VALID: %u\n", validPacketsReceived);
            tft.printf("P4: %u\n", phase4PacketsReceived);
            tft.printf("DUP: %u\n", duplicatePacketsCount);
            tft.printf("ACK: %u\n", acksGenerated);
            if (strlen(lastPacketId) > 0) {
                tft.println();
                tft.setTextColor(ST77XX_YELLOW);
                tft.println("LAST:");
                tft.setTextColor(ST77XX_WHITE);
                tft.println(lastOriginId);
                tft.printf("MSG: %.16s\n", lastPayload);
                tft.printf("HOP: %d TTL: %d\n", lastHopCount, lastTtl);
            }
            break;

        case STATE_BLE_CONNECTED:
            tft.setTextColor(ST77XX_GREEN);
            tft.println("STATUS: CONNECTED");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.printf("CLIENTS: %d\n", connectedClients);
            tft.println();
            tft.printf("RX: %u\n", totalPacketsReceived);
            tft.printf("VALID: %u\n", validPacketsReceived);
            tft.printf("P4: %u\n", phase4PacketsReceived);
            tft.printf("DUP: %u\n", duplicatePacketsCount);
            tft.printf("ACK: %u\n", acksGenerated);
            if (strlen(lastPacketId) > 0) {
                tft.println();
                tft.setTextColor(ST77XX_YELLOW);
                tft.println("LAST:");
                tft.setTextColor(ST77XX_WHITE);
                tft.println(lastOriginId);
                tft.printf("MSG: %.16s\n", lastPayload);
                tft.printf("HOP: %d TTL: %d\n", lastHopCount, lastTtl);
            }
            break;

        case STATE_RECEIVING:
            tft.setTextColor(ST77XX_BLUE);
            tft.println("STATUS: RECEIVING");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.println("RX PACKET...");
            break;

        case STATE_PROCESSING:
            tft.setTextColor(ST77XX_MAGENTA);
            tft.println("STATUS: PROCESSING");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.printf("ID: %s\n", lastPacketId);
            tft.printf("FROM: %s\n", lastOriginId);
            tft.printf("PLAT: %s\n", lastPlatform);
            tft.printf("MSG: %.16s\n", lastPayload);
            tft.printf("HOP: %d TTL: %d\n", lastHopCount, lastTtl);
            break;

        case STATE_ACK_SENT:
            tft.setTextColor(ST77XX_GREEN);
            tft.println("STATUS: ACK SENT");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.printf("PID: %s\n", lastPacketId);
            tft.printf("FROM: %s\n", lastOriginId);
            tft.printf("MSG: %.16s\n", lastPayload);
            break;

        case STATE_ERROR:
            tft.setTextColor(ST77XX_RED);
            tft.println("STATUS: ERROR");
            tft.setTextColor(ST77XX_WHITE);
            tft.println();
            tft.printf("INV: %u\n", invalidPacketsCount);
            break;
    }

    // Footer: WiFi status (placeholder for future)
    tft.println();
    tft.setTextColor(0x7BEF);  // Gray
    tft.println("WiFi: N/A");
    tft.println("Backend: N/A");
#endif
}

void updateTftDisplay() {
    tftShowState(currentState);
}

// ─── Scan Complete Callback ──────────────────────────────────────

void scanCompleteCB(BLEScanResults results) {
    int count = results.getCount();
    int namedCount = 0;

    Serial.println();
    Serial.printf("[SCAN] Cycle complete — %d devices detected:\n", count);
    Serial.println("  +----+--------------------------+-------------------+----------+");
    Serial.println("  | #  | Device Name              | MAC Address       | Signal   |");
    Serial.println("  +----+--------------------------+-------------------+----------+");

    for (int i = 0; i < count; i++) {
        BLEAdvertisedDevice dev = results.getDevice(i);
        String name = dev.haveName() ? dev.getName() : "";
        bool hasName = (name.length() > 0);

        if (hasName) {
            namedCount++;
        }

        if (hasName || showUnnamedDevices) {
            const char* displayName = hasName ? name.c_str() : "(unnamed)";
            Serial.printf("  | %02d | %-24.24s | %s | %4d dBm |\n",
                          i + 1, displayName, dev.getAddress().toString().c_str(), dev.getRSSI());
        }
    }
    Serial.println("  +----+--------------------------+-------------------+----------+");
    Serial.printf("  Summary: %d named, %d unnamed (Total: %d)\n", namedCount, count - namedCount, count);
    if (!showUnnamedDevices && (count - namedCount > 0)) {
        Serial.printf("  [Tip] %d unnamed devices hidden. Type 'u' + Enter to show all.\n", count - namedCount);
    }
    Serial.println();
}

// ─── Setup ───────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(1000);  // Wait for serial monitor to attach

    Serial.println();
    Serial.println("=======================================================");
    Serial.println("  BLE Mesh Attendance — Classroom Gateway");
    Serial.println("  Phase 1 + Phase 4: BLE + Relay + TFT");
    Serial.println("  Board: ESP32-S3-N16R8");
    Serial.println("  Framework: Arduino Core 3.3.x");
    Serial.println("=======================================================");
    Serial.println();

    // Initialize LED — blue = initializing
    neopixelWrite(STATUS_LED_PIN, 0, 0, 20);
    delay(500);

    // ─── Initialize TFT ───
#if TFT_ENABLED
    Serial.println("[INIT] Initializing TFT display...");
    tftInit();
    currentState = STATE_BOOTING;
    tftShowState(currentState);
    Serial.println("[INIT] > TFT initialized (ST7735 128x160)");
#else
    Serial.println("[INIT] TFT display disabled (TFT_ENABLED=0)");
#endif

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
    pService = pServer->createService(BLEUUID(GATEWAY_SERVICE_UUID), 20);  // 20 handles for more characteristics

    // Status characteristic — readable + notify by phones to see gateway state
    pStatusChar = pService->createCharacteristic(
        GATEWAY_STATUS_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pStatusChar->addDescriptor(new BLE2902());
    pStatusChar->setValue("{\"clients\":0,\"uptime\":0}");

    // Attendance characteristic — writable by phones to submit attendance via GATT
    // Accepts both Phase 1 binary and Phase 4 JSON packets
    BLECharacteristic* pAttendanceChar = pService->createCharacteristic(
        GATEWAY_ATTENDANCE_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pAttendanceChar->setCallbacks(new AttendanceCharCallbacks());

    // Phase 4: ACK characteristic — gateway notifies connected clients with ACK
    pAckChar = pService->createCharacteristic(
        GATEWAY_ACK_CHAR_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pAckChar->addDescriptor(new BLE2902());  // Client Characteristic Configuration Descriptor

    pService->start();

    // ─── Configure Advertising ───
    Serial.println("[INIT] Configuring BLE advertising...");
    pAdvertising = BLEDevice::getAdvertising();

    // Add our gateway service UUID so phones can discover us
    pAdvertising->addServiceUUID(GATEWAY_SERVICE_UUID);

    // Configure advertising parameters
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x12);  // Min connection interval: 22.5ms
    pAdvertising->setMaxPreferred(0x40);  // Max connection interval: 80ms (more reliable)

    // Start advertising
    BLEDevice::startAdvertising();
    Serial.println("[INIT] > Gateway is now advertising");
    Serial.printf("[INIT] > Service UUID: %s\n", GATEWAY_SERVICE_UUID);
    Serial.printf("[INIT] > ACK UUID:     %s\n", GATEWAY_ACK_CHAR_UUID);

    // ─── Configure BLE Scanning ───
    Serial.println("[INIT] Configuring BLE scanner...");
    pBLEScan = BLEDevice::getScan();
    pBLEScan->setAdvertisedDeviceCallbacks(new GatewayScanCallbacks(), true);  // true = wantDuplicates
    pBLEScan->setActiveScan(true);     // Active scan gets scan responses
    // NOTE: Scan window/interval are in units of 0.625ms.
    // Use moderate duty cycle to leave radio time for GATT connections.
    pBLEScan->setInterval(160);        // 100ms scan interval
    pBLEScan->setWindow(48);           // 30ms scan window (~30% duty cycle)

    Serial.println("[INIT] > Scanner configured");

    // ─── Initialize Wi-Fi (Step 2) ───
#if WIFI_ENABLED
    Serial.print("[INIT] Connecting to Wi-Fi: ");
    Serial.println(WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int wifiWait = 0;
    while (WiFi.status() != WL_CONNECTED && wifiWait < 15) {
        delay(400);
        Serial.print(".");
        wifiWait++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n[INIT] > Wi-Fi Connected! Gateway IP: %s\n", WiFi.localIP().toString().c_str());
        Serial.printf("[INIT] > Supabase Backend: %s\n", SUPABASE_URL);
    } else {
        Serial.println("\n[INIT] > Wi-Fi offline or timed out. Operating in offline BLE mode.");
    }
#else
    Serial.println("[INIT] Wi-Fi sync disabled (WIFI_ENABLED=0). Operating in local BLE mode.");
#endif

    // Initialization complete — green flash
    neopixelWrite(STATUS_LED_PIN, 0, 20, 0);
    delay(500);
    neopixelWrite(STATUS_LED_PIN, 0, 0, 0);

    currentState = STATE_BLE_READY;
    updateTftDisplay();

    Serial.println();
    Serial.println("=======================================================");
    Serial.println("  GATEWAY READY — Scanning for attendance packets...");
    Serial.println("  Phase 4: JSON relay packets supported");
    Serial.println("  Serial commands: d=diagnostics r=reset s=scan h=help");
    Serial.println("=======================================================");
    Serial.println();

    // Start first scan cycle (non-blocking with callback)
    pBLEScan->start(SCAN_DURATION_SECS, scanCompleteCB, false);
}

// ─── Main Loop ───────────────────────────────────────────────────

unsigned long lastDiagnosticTime = 0;
unsigned long lastScanRestart   = 0;
unsigned long lastTftRefresh    = 0;
const unsigned long DIAGNOSTIC_INTERVAL_MS = 30000;  // Print diagnostics every 30s
const unsigned long SCAN_RESTART_MS        = 6000;    // Restart scan every 6s
const unsigned long TFT_REFRESH_MS         = 10000;   // Refresh TFT every 10s

void loop() {
    unsigned long now = millis();

    // ─── Restart scanning if needed ───
    // When clients are connected, scan less aggressively to avoid
    // starving the BLE radio of time to service GATT connections.
    unsigned long effectiveScanRestart = (connectedClients > 0) ? 10000 : SCAN_RESTART_MS;
    int effectiveScanDuration = (connectedClients > 0) ? 3 : SCAN_DURATION_SECS;

    if (!pBLEScan->isScanning() && (now - lastScanRestart > effectiveScanRestart)) {
        // Reduce scan duty cycle further when clients are connected
        if (connectedClients > 0) {
            pBLEScan->setInterval(320);   // 200ms interval when connected
            pBLEScan->setWindow(32);      // 20ms window (~10% duty)
        } else {
            pBLEScan->setInterval(160);   // 100ms interval default
            pBLEScan->setWindow(48);      // 30ms window (~30% duty)
        }
        pBLEScan->clearResults();  // Free memory from previous scan
        pBLEScan->start(effectiveScanDuration, scanCompleteCB, false);
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

    // ─── Periodic TFT refresh ───
    if (now - lastTftRefresh > TFT_REFRESH_MS) {
        updateTftDisplay();
        lastTftRefresh = now;
    }

    // ─── Handle serial commands ───
    if (Serial.available()) {
        char cmd = Serial.read();
        switch (cmd) {
            case 'a':
            case 'A':
                printAttendanceRoster();
                break;
            case 'c':
            case 'C':
                lectureAttendeeCount = 0;
                Serial.println("[CMD] Lecture attendance roster cleared for next session.");
                updateGatewayStatusChar();
                break;
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
                phase4PacketsReceived = 0;
                acksGenerated = 0;
                packetCacheCount = 0;
                lastOriginId[0] = '\0';
                lastPlatform[0] = '\0';
                lastPayload[0] = '\0';
                lastPacketId[0] = '\0';
                lastHopCount = 0;
                lastTtl = 0;
                updateTftDisplay();
                break;
            case 's':
            case 'S':
                Serial.println("[CMD] Restarting scan...");
                pBLEScan->stop();
                delay(100);
                pBLEScan->clearResults();
                pBLEScan->start(SCAN_DURATION_SECS, scanCompleteCB, false);
                break;
            case 'u':
            case 'U':
                showUnnamedDevices = !showUnnamedDevices;
                Serial.printf("[CMD] Show unnamed devices: %s\n",
                              showUnnamedDevices ? "ENABLED (showing all)" : "DISABLED (showing named only)");
                break;
            case 'h':
            case 'H':
            case '?':
                Serial.println();
                Serial.println("--- Gateway Commands ---");
                Serial.println("  a — Print lecture attendance roster (students & MACs)");
                Serial.println("  c — Clear lecture attendance roster for next session");
                Serial.println("  d — Print diagnostics");
                Serial.println("  u — Toggle unnamed devices in scan output");
                Serial.println("  r — Reset counters");
                Serial.println("  s — Restart BLE scan");
                Serial.println("  h — Show this help");
                Serial.println("------------------------");
                break;
        }
    }

    delay(10);  // Small yield
}
