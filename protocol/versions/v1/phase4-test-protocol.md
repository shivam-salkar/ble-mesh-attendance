# Phase 4 — Interoperability Test Protocol

> **Status:** Development / Testing only
> **Version:** 1
> **Scope:** Phase 4 cross-platform BLE relay testing
>
> **This is NOT a production protocol.** It is a temporary test format designed
> to prove cross-platform BLE relay interoperability between iOS, Android, and
> the ESP32-S3 gateway.

---

## 1. Overview

Phase 4 introduces a JSON-based test packet that travels over BLE GATT
(characteristic writes). This packet proves that a message can originate on
one phone, relay through a second phone, and arrive intact at the ESP32
gateway.

The existing Phase 1 binary attendance packet (42 bytes, manufacturer-specific
data) continues to work unchanged. The ESP32 gateway accepts both formats.

---

## 2. Transport

### Phone ↔ Phone (Relay)

| Property | Value |
|----------|-------|
| Service UUID | `a1b2c3d4-e5f6-7890-abcd-ef1234567893` |
| Relay RX Characteristic (WRITE) | `a1b2c3d4-e5f6-7890-abcd-ef1234567894` |
| Relay TX Characteristic (NOTIFY) | `a1b2c3d4-e5f6-7890-abcd-ef1234567895` |

The relay service is hosted by phones acting as BLE Peripherals. Other phones
(acting as BLE Centrals) discover it, connect, and write relay packets to the
RX characteristic. ACKs are sent back via NOTIFY on the TX characteristic.

### Phone → ESP32 Gateway

Reuses the existing Phase 1 GATT service:

| Property | Value |
|----------|-------|
| Service UUID | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| Attendance Characteristic (WRITE) | `a1b2c3d4-e5f6-7890-abcd-ef1234567892` |
| Relay ACK Characteristic (NOTIFY) | `a1b2c3d4-e5f6-7890-abcd-ef1234567896` |

The gateway detects Phase 4 packets by checking if the first byte is `{`
(0x7B). Binary packets (first bytes `0xAA 0x55`) continue to use the existing
Phase 1 parser.

---

## 3. Packet Format

### 3.1 Test Relay Packet

```json
{
  "v": 1,
  "t": "TEST_RELAY",
  "pid": "A1B2C3D4",
  "oid": "IOS-A1B2",
  "sp": "ios",
  "p": "HELLO-FROM-IP1",
  "ttl": 3,
  "hc": 0
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `v` | integer | yes | Protocol version. Must be `1`. |
| `t` | string | yes | Packet type. Must be `"TEST_RELAY"`. |
| `pid` | string | yes | Unique packet ID (8-char hex). Generated once at origin. |
| `oid` | string | yes | Origin device ID (e.g., `"IOS-A1B2"`, `"ANDROID-C3D4"`). |
| `sp` | string | yes | Source platform: `"ios"` or `"android"`. |
| `p` | string | yes | Payload message. Must survive relay unchanged. |
| `ttl` | integer | yes | Time-to-live. Decremented by each relay. Drop when ≤ 0. |
| `hc` | integer | yes | Hop count. Incremented by each relay. Starts at 0. |

### 3.2 ACK Packet

```json
{
  "v": 1,
  "t": "ACK",
  "pid": "A1B2C3D4",
  "gid": "BMA-Gateway-01",
  "s": "RECEIVED"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `v` | integer | Protocol version. |
| `t` | string | `"ACK"` |
| `pid` | string | Packet ID being acknowledged. |
| `gid` | string | Gateway or device ID that generated the ACK. |
| `s` | string | Status: `"RECEIVED"`, `"DUPLICATE"`, `"REJECTED"`, `"INVALID"` |

---

## 4. Relay Algorithm

```
receive(packet):

  if packet.pid already in seenCache:
      log "DUPLICATE"
      return

  if packet.ttl <= 0:
      log "TTL_EXPIRED"
      return

  add packet.pid to seenCache

  packet.hc += 1
  packet.ttl -= 1

  if ESP32 gateway is reachable:
      forward to gateway via GATT write
  else:
      forward to nearby relay peers via GATT write
```

---

## 5. Device Identifiers

Phones generate a random application-level device ID on first launch:

- Format: `{PLATFORM}-{4 hex chars}` (e.g., `IOS-A1B2`, `ANDROID-C3D4`)
- Persisted in local storage (SharedPreferences / NSUserDefaults)
- Does NOT use the phone's hardware Bluetooth MAC address

**Privacy note:** This ID is ephemeral and application-scoped. It does not
contain personally identifiable information. In production, device IDs will
be replaced with cryptographic session tokens.

---

## 6. Duplicate Suppression

Each device maintains a bounded in-memory cache of seen packet IDs:

- Maximum entries: 128
- Expiry: 5 minutes
- Eviction: oldest-first when full

---

## 7. Compatibility with Phase 1

The ESP32 gateway differentiates packets by inspecting the first byte:

| First byte | Format | Handler |
|-----------|--------|---------|
| `0x7B` (`{`) | Phase 4 JSON | JSON parser |
| `0xAA` | Phase 1 binary | Existing binary parser |
| Other | Invalid | Rejected |

Phase 1 functionality (binary attendance packets via advertisement scanning
and GATT writes) is fully preserved.

---

## 8. Security Notice

> Phase 4 interoperability protocol is a development test protocol and is NOT
> production-secure. It does not include cryptographic signatures, session
> binding, or replay protection beyond basic packet ID deduplication.
> Production security will be implemented in Phase 5.
