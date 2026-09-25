/**
 * ═══════════════════════════════════════════════════════════════════
 *  BLE Mesh Attendance — Test Beacon (Attendance Packet Simulator)
 *  Phase 1: Hardware Testing
 * ═══════════════════════════════════════════════════════════════════
 *
 *  PURPOSE:
 *    Simulates a student phone sending attendance packets via BLE
 *    advertisements. Upload to a SECOND ESP32 to test the gateway.
 *
 *  Board:  Any ESP32 / ESP32-S3
 *  Framework: Arduino + ESP32 Arduino Core 3.3.x
 *
 *  HOW TO TEST:
 *    1. Flash esp32-gateway-arduino.ino to your GATEWAY ESP32-S3
 *    2. Flash this sketch to a SECOND ESP32 board
 *    3. Open Serial Monitor on the gateway — you should see packets
 *
 *  If you only have ONE ESP32:
 *    Use the nRF Connect mobile app to send test advertisements
 *    (see README.md for instructions)
 *
 * ═══════════════════════════════════════════════════════════════════
 */

#include <BLEDevice.h>
#include <BLEAdvertising.h>
#include <BLEUtils.h>

// ─── Must match gateway configuration ────────────────────────────

#define ATTENDANCE_MFG_ID       0xFFFF
#define ATTENDANCE_MAGIC_BYTE_0 0xAA
#define ATTENDANCE_MAGIC_BYTE_1 0x55
#define PROTOCOL_VERSION        0x01
#define PKT_TYPE_ATTENDANCE     0x01

// ─── Test Configuration ─────────────────────────────────────────

// How often to send a new attendance packet (milliseconds)
#define SEND_INTERVAL_MS 5000

// Simulated session ID (would come from backend in real system)
#define TEST_SESSION_ID 0x12345678

// Starting TTL for packets
#define DEFAULT_TTL 5

// LED pin (ESP32-S3 RGB LED on GPIO 48)
#define STATUS_LED_PIN 48

// Device name
#define BEACON_DEVICE_NAME "BMA-TestStudent"

// ─── Global State ────────────────────────────────────────────────

BLEAdvertising* pAdvertising = nullptr;
uint32_t packetCounter = 0;
uint32_t basePacketId  = 0;

// ─── Build Attendance Packet ────────────────────────────────────

/**
 * Constructs a manufacturer-specific data payload containing the
 * attendance packet. This includes the 2-byte manufacturer ID prefix
 * followed by our 42-byte custom payload.
 *
 * Total: 44 bytes (2 MFG ID + 42 payload)
 */
String buildMfgDataWithPacket() {
    uint8_t fullData[44];

    // Manufacturer ID (little-endian)
    fullData[0] = (ATTENDANCE_MFG_ID & 0xFF);
    fullData[1] = ((ATTENDANCE_MFG_ID >> 8) & 0xFF);

    // Our payload starts at index 2
    uint8_t* pkt = fullData + 2;

    // Magic bytes
    pkt[0] = ATTENDANCE_MAGIC_BYTE_0;
    pkt[1] = ATTENDANCE_MAGIC_BYTE_1;

    // Protocol version
    pkt[2] = PROTOCOL_VERSION;

    // Packet type
    pkt[3] = PKT_TYPE_ATTENDANCE;

    // Packet ID (random base + counter for uniqueness)
    uint32_t packetId = basePacketId + packetCounter;
    pkt[4] = (packetId >> 0)  & 0xFF;
    pkt[5] = (packetId >> 8)  & 0xFF;
    pkt[6] = (packetId >> 16) & 0xFF;
    pkt[7] = (packetId >> 24) & 0xFF;

    // Session ID
    uint32_t sessionId = TEST_SESSION_ID;
    pkt[8]  = (sessionId >> 0)  & 0xFF;
    pkt[9]  = (sessionId >> 8)  & 0xFF;
    pkt[10] = (sessionId >> 16) & 0xFF;
    pkt[11] = (sessionId >> 24) & 0xFF;

    // Timestamp (current uptime seconds as stand-in)
    uint32_t timestamp = (uint32_t)(millis() / 1000);
    pkt[12] = (timestamp >> 0)  & 0xFF;
    pkt[13] = (timestamp >> 8)  & 0xFF;
    pkt[14] = (timestamp >> 16) & 0xFF;
    pkt[15] = (timestamp >> 24) & 0xFF;

    // TTL
    pkt[16] = DEFAULT_TTL;

    // Hop count (0 = direct, no relay)
    pkt[17] = 0;

    // Student token (random bytes for testing)
    for (int i = 18; i < 34; i++) {
        pkt[i] = (uint8_t)esp_random();
    }

    // Signature (random bytes for testing — real system uses HMAC)
    for (int i = 34; i < 42; i++) {
        pkt[i] = (uint8_t)esp_random();
    }

    // Convert to Arduino String (binary safe via constructor)
    return String((char*)fullData, 44);
}

// ─── Utility ────────────────────────────────────────────────────

void blinkLed(uint8_t r, uint8_t g, uint8_t b, int times, int delayMs) {
    for (int i = 0; i < times; i++) {
        neopixelWrite(STATUS_LED_PIN, r, g, b);
        delay(delayMs);
        neopixelWrite(STATUS_LED_PIN, 0, 0, 0);
        delay(delayMs);
    }
}

void sendCurrentPacket() {
    // Build new manufacturer data with attendance packet
    String mfgData = buildMfgDataWithPacket();

    // Stop current advertising to update data
    pAdvertising->stop();

    // Configure advertisement data
    BLEAdvertisementData advData;
    advData.setName(BEACON_DEVICE_NAME);
    advData.setManufacturerData(mfgData);

    pAdvertising->setAdvertisementData(advData);
    pAdvertising->start();

    uint32_t currentPktId = basePacketId + packetCounter;
    Serial.printf("[TX] Packet #%u sent — ID: 0x%08X, Session: 0x%08X\n",
                  packetCounter, currentPktId, TEST_SESSION_ID);

    // Visual feedback: orange blink
    blinkLed(20, 10, 0, 1, 150);
}

// ─── Setup ───────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println();
    Serial.println("=======================================================");
    Serial.println("  BLE Mesh Attendance — Test Beacon");
    Serial.println("  Simulates student phone sending attendance packets");
    Serial.println("=======================================================");
    Serial.println();

    // Generate random base packet ID
    basePacketId = esp_random();
    Serial.printf("[INIT] Base packet ID: 0x%08X\n", basePacketId);
    Serial.printf("[INIT] Test session ID: 0x%08X\n", TEST_SESSION_ID);

    // Initialize BLE
    Serial.println("[INIT] Initializing BLE...");
    BLEDevice::init(BEACON_DEVICE_NAME);
    BLEDevice::setPower(ESP_PWR_LVL_P9);

    Serial.printf("[INIT] Device address: %s\n",
                  BLEDevice::getAddress().toString().c_str());

    pAdvertising = BLEDevice::getAdvertising();

    // LED: ready
    neopixelWrite(STATUS_LED_PIN, 0, 20, 0);
    delay(300);
    neopixelWrite(STATUS_LED_PIN, 0, 0, 0);

    Serial.println("[INIT] > Test beacon ready");
    Serial.printf("[INIT] > Will send a new packet every %d ms\n", SEND_INTERVAL_MS);
    Serial.println("[INIT] > Commands: d=duplicate b=burst h=help");
    Serial.println();
}

// ─── Main Loop ───────────────────────────────────────────────────

void loop() {
    packetCounter++;
    sendCurrentPacket();

    // ─── Handle serial commands ───
    if (Serial.available()) {
        char cmd = Serial.read();
        switch (cmd) {
            case 'd':
                // Send duplicate (same packet ID — tests dedup on gateway)
                Serial.println("[CMD] Sending DUPLICATE packet (same ID)...");
                packetCounter--;  // Reuse same ID
                delay(500);
                sendCurrentPacket();
                break;
            case 'b':
                // Send burst of 5 rapid packets
                Serial.println("[CMD] Sending burst of 5 packets...");
                for (int i = 0; i < 4; i++) {
                    delay(200);
                    packetCounter++;
                    sendCurrentPacket();
                }
                break;
            case 'h':
            case '?':
                Serial.println();
                Serial.println("--- Test Beacon Commands ---");
                Serial.println("  d — Send duplicate packet");
                Serial.println("  b — Send burst of 5 packets");
                Serial.println("  h — Show this help");
                Serial.println("----------------------------");
                break;
        }
    }

    delay(SEND_INTERVAL_MS);
}
