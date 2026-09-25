# BLE Mesh Attendance

A decentralized, hardware-assisted classroom attendance system leveraging application-level Bluetooth Low Energy (BLE) peer-to-peer relaying and physical ESP32-S3 classroom gateways.

## Project Status

Early development — repository initialization phase.

## Overview

BLE Mesh Attendance is designed for classroom environments where dense student populations frequently encounter congested cellular data networks or unreliable campus Wi-Fi. At the conclusion of a lecture, students open the Flutter mobile app and explicitly trigger their attendance confirmation.

Instead of requiring every mobile device to hold a concurrent active internet connection, student devices form an application-level peer-to-peer BLE relay network. Attendance packets propagate hop-by-hop across peer smartphones until reaching the classroom's dedicated ESP32-S3 gateway. The gateway validates packet integrity and forwards batched attendance submissions over Wi-Fi to a Supabase PostgreSQL backend. On-device face verification will subsequently be introduced as an identity authentication layer.

## Architecture

```text
Student Mobile App (Flutter)
            ↓
     Phone BLE Layer
            ↓
Application-Level Peer Relay (Multi-hop BLE)
            ↓
  ESP32-S3 Classroom Gateway
            ↓
          Wi-Fi
            ↓
    Backend / Supabase
            ↓
   PostgreSQL Database
```

## Repository Structure

```
ble-mesh-attendance/
├── apps/               # Client applications (Flutter mobile app for Android & iOS)
│   └── mobile/
├── backend/            # Supabase configuration, SQL migrations, seed scripts, & Edge Functions
├── firmware/           # Microcontroller firmware for physical classroom gateways
│   └── esp32-gateway/  # ESP-IDF project targeting ESP32-S3
├── protocol/           # Authoritative packet definitions, schemas, and protocol versioning
├── docs/               # System architecture, development guides, security, and references
│   ├── architecture/
│   ├── development/
│   ├── security/
│   └── references/
├── tests/              # Protocol verification and end-to-end integration tests
│   ├── protocol/
│   └── integration/
├── .github/            # GitHub Actions workflows, issue templates, and PR templates
├── .gitignore          # Comprehensive monorepo ignore rules
├── README.md           # Root repository overview
├── LICENSE             # Proprietary license (All Rights Reserved)
├── CONTRIBUTING.md     # Contribution guidelines and intellectual property policies
└── SECURITY.md         # Vulnerability reporting and security requirements
```

## Technology Stack

- **Mobile Client:** Flutter, Dart (targeting Android & iOS)
- **Backend & Database:** Supabase, PostgreSQL, Row Level Security (RLS), Edge Functions
- **Firmware:** ESP32-S3, ESP-IDF (C/C++), FreeRTOS, NimBLE
- **Networking & Wireless:** BLE (GATT/GAP), Wi-Fi (802.11 b/g/n)
- **Mesh Topology:** Application-level BLE peer-to-peer networking

## Current Development Phase

Repository initialization.

### Next Hardware Milestone:
```text
ESP32-S3 boot verification
            ↓
    BLE advertisement
            ↓
   Phone detects gateway
            ↓
Phone ↔ ESP32 communication
```

## Important Architecture Note

This project is inspired by decentralized BLE peer networking concepts (such as those demonstrated by BitChat), but it is **NOT** a BitChat clone. It implements a domain-specific attendance protocol featuring ephemeral student tokens, classroom gateway ingestion, cryptographic session signatures, and anti-replay constraints.

Furthermore, this system does **NOT** use Bluetooth SIG Mesh (or ESP-BLE-MESH) on student phones. It operates as an application-level BLE peer relay utilizing standard BLE GATT and GAP primitives supported across consumer iOS and Android devices.

## References

Comprehensive documentation and references for BitChat, ESP-IDF, Apple Core Bluetooth, Android BLE, and Espressif documentation are cataloged in [docs/references/README.md](file:///c:/Projects/ble-mesh-attendance/docs/references/README.md).

## License

Proprietary — All Rights Reserved. See [LICENSE](file:///c:/Projects/ble-mesh-attendance/LICENSE) for full details.
